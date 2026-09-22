import AppKit
import Foundation

/// Learns from undos: a ⌘Z within 2.5s of our paste means the pick was wrong.
/// Outcomes persist as `{contextKey: {clipID: netScore}}` and re-enter future
/// rankings as probability multipliers.
@MainActor @Observable
public final class FeedbackTracker {
    private var stats: [String: [String: Int]] = [:] // contextKey -> clipID -> net (+good/-bad)
    private struct PendingOutcome: Equatable {
        var clipID: String
        var contextKey: String
        var deadline: Date
    }

    private var pending: PendingOutcome?
    private var undoMonitor: Any?
    private let fileURL: URL

    public init(fileURL: URL = FeedbackTracker.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    /// Global ⌘Z monitor, created lazily — it only delivers events once the
    /// app is Accessibility-trusted, which may happen after init.
    private func ensureMonitor() {
        guard undoMonitor == nil else { return }
        undoMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard e.modifierFlags.contains(.command),
                  e.charactersIgnoringModifiers?.lowercased() == "z" else { return }
            Task { @MainActor in self?.registerUndo() }
        }
    }

    public static var defaultFileURL: URL {
        ClipStore.defaultFileURL.deletingLastPathComponent().appendingPathComponent("feedback.json")
    }

    static func contextKey(bundleID: String, fieldLabel: String) -> String {
        let label = fieldLabel.lowercased().components(separatedBy: .whitespaces).joined()
        return "\(bundleID)|\(label)"
    }

    /// Call right after we paste a clip on the user's behalf.
    public func expectOutcome(clipID: String, context: ContextSnapshot) {
        ensureMonitor()
        let p = PendingOutcome(
            clipID: clipID,
            contextKey: Self.contextKey(bundleID: context.bundleID, fieldLabel: context.field.label),
            deadline: Date().addingTimeInterval(2.5)
        )
        pending = p
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            self?.resolve(p, undone: false)
        }
    }

    private func registerUndo() {
        guard let p = pending, Date() <= p.deadline else { return }
        resolve(p, undone: true)
    }

    /// Identity-checked resolve: a newer pending paste makes older timers no-ops.
    private func resolve(_ p: PendingOutcome, undone: Bool) {
        guard pending == p else { return }
        stats[p.contextKey, default: [:]][p.clipID, default: 0] += undone ? -1 : 1
        pending = nil
        save()
    }

    /// clipID → multiplier for the decision engine.
    public func multipliers(for context: ContextSnapshot) -> [String: Double] {
        let key = Self.contextKey(bundleID: context.bundleID, fieldLabel: context.field.label)
        return stats[key, default: [:]].mapValues { net in
            min(1.5, max(0.1, 1 + 0.25 * Double(net)))
        }
    }

    public func reset() {
        stats = [:]
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stats) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let s = try? JSONDecoder().decode([String: [String: Int]].self, from: data) else { return }
        stats = s
    }
}

/// The orchestrator. Hotkey in → paste or HUD out. Owns the form-fill loop.
@MainActor @Observable
public final class SmartPasteController {
    public private(set) var busy = false
    /// One-line record of the most recent outcome — the menu bar shows it so
    /// a silent fallback is never mysterious ("plain paste · model unreachable").
    public private(set) var lastAction: String?

    private let store: ClipStore
    private let settings: AppSettings
    private let executor: PasteExecutor
    private let feedback: FeedbackTracker
    private let hud: HUDController
    private let redactor: (any Redacting)?
    private let makeProvider: () -> (any DecisionProvider)?
    private var formFiller: FormFiller?

    public init(store: ClipStore, settings: AppSettings,
                executor: PasteExecutor, feedback: FeedbackTracker, hud: HUDController,
                redactor: (any Redacting)?,
                makeProvider: @escaping () -> (any DecisionProvider)?) {
        self.store = store
        self.settings = settings
        self.executor = executor
        self.feedback = feedback
        self.hud = hud
        self.redactor = redactor
        self.makeProvider = makeProvider
        // Assigned last: the closure weak-captures self, legal once every
        // stored property above is initialized.
        self.formFiller = FormFiller(executor: executor) { [weak self] ctx in
            guard let self else { return nil }
            return await self.decisionForFormField(ctx)
        }
    }

    /// Entry point for the smart-paste hotkey (and ⌘V when intercepting).
    public func smartPaste() {
        let intercepted = settings.triggerMode == .intercept
        // Intercept contract: the real keystroke was already eaten — every
        // exit must produce a paste. Hotkey mode ate nothing, so a bail just
        // informs instead.
        func bail(_ action: String, toast: String? = nil) {
            lastAction = action
            if let toast { hud.showStatus(toast) }
            if intercepted { pasteLatest() }
        }

        if busy || hud.isShowing {
            // HUD up → this press belongs to it; treat as "none of these".
            if hud.isShowing { hud.dismiss() }
            bail("plain paste · busy", toast: intercepted ? nil : "Still deciding…")
            return
        }
        guard ContextCaptor.isTrusted else {
            ContextCaptor.requestTrust()
            // Untrusted shouldn't intercept at all (the hotkey isn't
            // registered) — a race can still land here; repost is a no-op
            // if CGEvent is also untrusted, so the toast carries the info.
            bail("plain paste · needs Accessibility",
                 toast: "Accessibility permission needed — check System Settings")
            return
        }
        let ctx = ContextCaptor.capture()

        // Image/file on the pasteboard → the user wants that, not a text pick.
        if PasteboardGate.shouldPassThrough() {
            lastAction = "plain paste · image/file on clipboard"
            pasteLatest()
            return
        }
        // Never think about password fields: plain paste, no API call.
        if ctx.field.isSecure {
            lastAction = "plain paste · secure field"
            pasteLatest()
            return
        }
        // Queue mode: deterministic FIFO, no model call.
        if settings.queueMode, let clip = store.popQueue() {
            lastAction = "queued paste · \"\(clip.preview)\""
            paste(clip.text, clip: clip, ctx: ctx)
            return
        }
        guard !store.clips.isEmpty else {
            bail("plain paste · history empty",
                 toast: intercepted ? nil : "Clipboard history is empty")
            return
        }

        busy = true
        Task {
            let indicator = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let self, self.busy else { return }
                self.hud.showStatus("Deciding…")
            }
            defer {
                indicator.cancel()
                busy = false
            }
            let engine = makeEngine()
            let mode: DecisionEngine.Mode = settings.triggerMode == .intercept ? .intercept : .hotkey
            let outcome = await engine.decide(
                context: ctx,
                candidates: store.candidates(),
                mode: mode,
                feedback: feedback.multipliers(for: ctx)
            )
            await handle(outcome, ctx: ctx)
        }
    }

    /// Raw-paste hotkey / .pasteLatest fallthrough: send ⌘V for whatever is
    /// on the pasteboard right now — not our store's possibly-stale view.
    /// No toast, no feedback tracking: this is the user's normal paste.
    public func pasteLatest() {
        executor.pasteCurrent()
    }

    /// History-window/menu action: paste a specific clip into whatever app
    /// had focus. The caller is responsible for restoring focus first.
    public func pasteClip(_ clip: Clip) {
        paste(clip.text, clip: clip, ctx: nil)
    }

    /// Manual picker hotkey — always shows the picker, no model call.
    public func showPicker() {
        let candidates = store.candidates().map {
            ScoredCandidate(clip: $0, probability: 0, confidence: 0)
        }
        guard !candidates.isEmpty else { return }
        hud.showPicker(candidates: candidates, near: ContextCaptor.capture().fieldRect) { [weak self] pick in
            guard let self else { return }
            guard let pick else { self.pasteLatest(); return }
            self.paste(pick.clip.text, clip: pick.clip, ctx: nil)
        }
    }

    private func handle(_ outcome: PasteOutcome, ctx: ContextSnapshot) async {
        switch outcome {
        case .paste(let d):
            let note = d.transform == .asIs ? nil : d.transform.rawValue.replacing("_", with: " ")
            lastAction = "pasted \"\(d.clip.preview)\"" + (note.map { " · \($0)" } ?? "")
            paste(d.text, clip: d.clip, ctx: ctx, note: note)
            if d.isForm { await formFiller?.run() }
        case .top3(let cands):
            lastAction = "showed top 3"
            hud.showTop3(candidates: cands, near: ctx.fieldRect) { [weak self] pick in
                guard let self else { return }
                // Esc/⌘V means "plain paste" — the toast promises it.
                guard let pick else { self.lastAction = "plain paste · declined options"; self.pasteLatest(); return }
                self.lastAction = "pasted \"\(pick.clip.preview)\" · picked"
                self.paste(pick.clip.text, clip: pick.clip, ctx: ctx)
            }
        case .picker(let cands):
            lastAction = "showed picker"
            hud.showPicker(candidates: cands, near: ctx.fieldRect) { [weak self] pick in
                guard let self else { return }
                guard let pick else { self.lastAction = "plain paste · declined options"; self.pasteLatest(); return }
                self.lastAction = "pasted \"\(pick.clip.preview)\" · picked"
                self.paste(pick.clip.text, clip: pick.clip, ctx: ctx)
            }
        case .pasteLatest(let reason):
            lastAction = "plain paste · \(reason.label)"
            pasteLatest()
        }
    }

    /// The form-fill loop's per-field decision. Returns nil to stop.
    private func decisionForFormField(_ ctx: ContextSnapshot) async -> Decision? {
        let engine = makeEngine()
        let outcome = await engine.decide(
            context: ctx,
            candidates: store.candidates(),
            mode: .formFill,
            feedback: feedback.multipliers(for: ctx)
        )
        guard case .paste(let d) = outcome else { return nil }
        store.markPasted(d.clip)
        feedback.expectOutcome(clipID: d.clip.id, context: ctx)
        return d
    }

    private func paste(_ text: String, clip: Clip, ctx: ContextSnapshot?, note: String? = nil) {
        executor.paste(text)
        store.markPasted(clip)
        if let ctx { feedback.expectOutcome(clipID: clip.id, context: ctx) }
        if settings.showStatusToast {
            hud.showStatus("Pasted “\(clip.preview)”" + (note.map { " · \($0)" } ?? ""))
        }
    }

    /// Internal: the practice session builds its engine through the same path.
    func makeEngine() -> DecisionEngine {
        var engine = DecisionEngine(
            provider: makeProvider(),
            redactor: settings.effectivePIIRedaction ? redactor : nil
        )
        engine.confidenceThreshold = settings.confidenceThreshold
        engine.lowConfidenceMode = settings.lowConfidenceMode
        return engine
    }
}
