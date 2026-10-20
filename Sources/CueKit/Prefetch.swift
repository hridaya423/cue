import AppKit
import ApplicationServices
import Foundation

extension DecisionEngine.Mode: Equatable {}

/// What a warmed answer depends on: the field's identity and the clipboard's.
/// The field's current value and caret are deliberately out — they move with
/// every keystroke and would make the cache unreachable.
public struct PrefetchKey: Equatable, Sendable {
    public var bundleID = ""
    public var windowTitle = ""
    public var role = ""
    public var label = ""
    public var placeholder = ""
    public var webHost = ""
    public var clipIDs: [String] = []

    public init(context: ContextSnapshot, candidates: [Clip]) {
        bundleID = context.bundleID
        windowTitle = context.windowTitle
        role = context.field.role
        label = context.field.label
        placeholder = context.field.placeholder
        webHost = context.webHost
        clipIDs = OptionBuilder.inScope(candidates).map(\.id)
    }
}

/// Asks the model while the user is still reaching for the keys. Holds one
/// answer — in flight or finished — for the current key; a key change cancels
/// the loser. ⌘V and the hotkey both fold their policy over the same answer.
@MainActor
public final class DecisionPrefetch {
    private var key: PrefetchKey?
    private var task: Task<JevResponse, Error>?

    public init() {}

    public func warm(context: ContextSnapshot, candidates: [Clip], engine: DecisionEngine) {
        let k = PrefetchKey(context: context, candidates: candidates)
        guard k != key else { return }
        task?.cancel()
        key = k
        task = Task { [weak self] in
            do { return try await engine.fetch(context: context, candidates: candidates) } catch {
                if self?.key == k { self?.key = nil }
                throw error
            }
        }
    }

    /// Waits for the warm-up to finish, used or not — a benchmark must not let it bleed into the next step.
    public func settle() async { _ = try? await task?.value }

    /// The outcome for this paste, from the warmed answer when the key matches
    /// (awaiting it if still in flight), otherwise asked live.
    public func outcome(context: ContextSnapshot, candidates: [Clip],
                        mode: DecisionEngine.Mode,
                        engine: DecisionEngine) async -> PasteOutcome {
        guard mode != .formFill, let task,
              PrefetchKey(context: context, candidates: candidates) == key else {
            // A stale warm-up would hold the model while this paste waits for it.
            task?.cancel(); task = nil; key = nil
            return await engine.decide(context: context, candidates: candidates,
                                       mode: mode)
        }
        return await engine.decide(context: context, candidates: candidates, mode: mode,
                                   answer: { try await task.value })
    }
}

/// Event-driven warm-up for ⌘V and the hotkey: frontmost-app switches, focus
/// changes inside that app (AXObserver), and new clips each start a warm.
/// At most one warm per 100 ms; no timers, so idle cost is zero.
@MainActor
public final class PrefetchTriggers {
    private let store: ClipStore
    private let settings: AppSettings
    private let prefetch: DecisionPrefetch
    private let makeEngine: @MainActor () -> DecisionEngine

    private var focusObserver: AXObserver?
    private var observedPID: pid_t = 0
    private var activationNote: NSObjectProtocol?
    private var lastWarm: ContinuousClock.Instant?
    private var warmScheduled = false

    public init(store: ClipStore, settings: AppSettings,
                prefetch: DecisionPrefetch,
                makeEngine: @escaping @MainActor () -> DecisionEngine) {
        self.store = store
        self.settings = settings
        self.prefetch = prefetch
        self.makeEngine = makeEngine
    }

    public func start(monitor: ClipboardMonitor) {
        monitor.onClipAdded = { [weak self] in self?.requestWarm() }
        activationNote = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.activated() }
        }
        activated()
    }

    public func stop() {
        if let note = activationNote {
            NSWorkspace.shared.notificationCenter.removeObserver(note)
            activationNote = nil
        }
        if let focusObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(focusObserver), .defaultMode)
        }
        focusObserver = nil
        observedPID = 0
    }

    /// The frontmost app changed: move the focus observer to it and warm —
    /// whatever field has the caret there is the next likely ⌘V target.
    private func activated() {
        if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            ContextCaptor.enableWebAccessibility(pid: pid)
            observeFocus(pid: pid)
        }
        requestWarm()
    }

    private func observeFocus(pid: pid_t) {
        guard pid != observedPID else { return }
        if let focusObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(),
                                  AXObserverGetRunLoopSource(focusObserver), .defaultMode)
            self.focusObserver = nil
            observedPID = 0
        }
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, _, _, refcon in
            guard let refcon else { return }
            let triggers = Unmanaged<PrefetchTriggers>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { triggers.requestWarm() }
        }, &observer) == .success, let observer else { return }
        let app = AXUIElementCreateApplication(pid)
        guard AXObserverAddNotification(
            observer, app, kAXFocusedUIElementChangedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()) == .success else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        focusObserver = observer
        observedPID = pid
    }

    /// Coalesce bursts: warm immediately when the last warm is ≥100 ms ago,
    /// else queue one trailing warm. It captures context at fire time, so
    /// dropped middle events lose nothing.
    private func requestWarm() {
        guard ContextCaptor.isTrusted,
              settings.provider != .off,
              !settings.queueMode else { return }
        let now = ContinuousClock.now
        let elapsed = lastWarm.map { now - $0 } ?? .milliseconds(100)
        guard elapsed < .milliseconds(100) else {
            lastWarm = now
            warmNow()
            return
        }
        guard !warmScheduled else { return }
        warmScheduled = true
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(100) - elapsed)
            guard let self else { return }
            warmScheduled = false
            requestWarm()
        }
    }

    private func warmNow() {
        let engine = makeEngine()
        // Warming sends the clipboard to the model before the user has pasted anything: on-device only.
        guard let provider = engine.provider, !provider.isRemote else { return }
        let ctx = ContextCaptor.capture()
        guard ctx.field.isTextual,
              !PasteboardGate.shouldPassThrough(),
              !store.clips.isEmpty else { return }
        prefetch.warm(context: ctx, candidates: store.clips, engine: engine)
    }
}
