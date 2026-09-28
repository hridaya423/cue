import AppKit
import SwiftUI

/// The object graph + window management. One instance for the app's lifetime.
@MainActor @Observable
public final class AppModel {
    public static let shared = AppModel()

    public let settings = AppSettings.shared
    public let store: ClipStore
    public let monitor: ClipboardMonitor
    public let hotkeys: HotkeyManager
    public let executor: PasteExecutor
    public let feedback: FeedbackTracker
    public let hud: HUDController
    public let redactor: PIIRedactor
    public let models: ModelManager
    public let providerStatus: ProviderStatus
    public let controller: SmartPasteController

    public var selfCheckResult: String?
    public var trusted: Bool { ContextCaptor.isTrusted }

    /// The active guided-paste session (onboarding's practice screen). When
    /// set it gets first refusal on the smart-paste trigger; nil = normal.
    public var practice: OnboardingPractice?

    private var windows: [String: NSWindow] = [:]

    public init() {
        store = ClipStore(capacity: self.settings.historyCap)
        monitor = ClipboardMonitor(store: store, settings: settings)
        hotkeys = HotkeyManager(settings: settings)
        executor = PasteExecutor(monitor: monitor, hotkeys: hotkeys)
        feedback = FeedbackTracker()
        hud = HUDController()
        redactor = PIIRedactor()
        models = ModelManager()
        providerStatus = ProviderStatus()
        controller = SmartPasteController(
            store: store, settings: settings,
            executor: executor, feedback: feedback, hud: hud, redactor: redactor
        ) { [settings, providerStatus] timeout in
            settings.providerClient(timeout: timeout).map { StatusTrackingProvider($0, status: providerStatus) }
        }

        hotkeys.interceptCmdV = settings.triggerMode == .intercept
        hotkeys.reregister()
        hotkeys.on(.smartPaste) { [weak self] in
            // Practice gets first refusal: it consumes the trigger only while
            // its own field is focused; everything else is normal dispatch.
            if self?.practice?.handleTrigger() == true { return }
            self?.controller.smartPaste()
        }
        hotkeys.on(.picker) { [weak self] in self?.controller.showPicker() }
        hotkeys.on(.rawPaste) { [weak self] in self?.controller.pasteLatest() }
        hotkeys.on(.queueToggle) { [weak self] in self?.toggleQueue() }
        hotkeys.on(.settings) { [weak self] in self?.open(id: "settings") }

        monitor.start()
        // Warm the redaction model in the background so the first paste
        // doesn't pay the download latency.
        if settings.effectivePIIRedaction { Task { await redactor.prepare() } }
        // Auto-start the selected local model server if it's installed.
        if settings.provider == .local, let r = selectedLocal {
            Task { await models.start(r) }
        }
        // No orphaned model servers: they stop when the app does.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [models] _ in
            Task { @MainActor in models.stop() }
        }
        if !settings.onboardingDone {
            Task { @MainActor in self.open(id: "onboarding") }
        }
    }

    /// The catalog pair for the current local-model selection, if any.
    public var selectedLocal: ModelSpec.Resolved? {
        ModelCatalog.variant(modelID: settings.localModelID, variantID: settings.localVariantID)
    }

    public func makeProvider(timeout: TimeInterval = 10) -> (any DecisionProvider)? {
        settings.providerClient(timeout: timeout)
    }

    /// Typed connection check — onboarding gates Continue on this without
    /// parsing UI strings. Settings' formatted status stays on testProvider().
    public enum ProviderConnectionResult: Sendable, Equatable {
        case connected(model: String)
        case failed(message: String)
    }

    public func testConnection() async -> ProviderConnectionResult {
        guard let provider = settings.providerClient() else {
            return .failed(message: settings.provider == .off ? "Model is off"
                : settings.provider.needsAPIKey ? "No API key set" : "Check the endpoint URL")
        }
        do {
            let resp = try await provider.evaluate(
                state: .string("The user clicked test."),
                questions: ["ok": .noul(instructions: "Did the request succeed?")]
            )
            return .connected(model: resp.model)
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    /// Round-trips a trivial question so Settings/onboarding can verify keys.
    public func testProvider() async -> String {
        switch await testConnection() {
        case .connected(let model): "Connected — \(model)"
        case .failed(let message): "Failed: \(message)"
        }
    }

    public func close(id: String) {
        windows[id]?.close()
    }

    /// History action: close our window, let focus return to the previous
    /// app, then paste the chosen clip into it.
    public func pasteIntoFrontApp(_ clip: Clip) {
        close(id: "history")
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            controller.pasteClip(clip)
        }
    }

    /// Cheap endpoint reachability check for the endpoint-field status dot.
    /// A refused connection means nothing is listening; any HTTP response
    /// (even 404) counts as up.
    public func endpointReachable(_ base: String) async -> Bool {
        guard var comps = URLComponents(string: base.contains("://") ? base : "http://" + base),
              let url = comps.url else { return false }
        comps.path = "/"
        var req = URLRequest(url: comps.url ?? url)
        req.timeoutInterval = 1.5
        do {
            _ = try await URLSession.shared.data(for: req)
            return true
        } catch {
            return false
        }
    }

    public func toggleQueue() {
        settings.queueMode.toggle()
        if !settings.queueMode { store.clearQueue() }
        hud.showStatus(settings.queueMode ? "Queue mode on" : "Queue mode off")
    }

    /// Window management, kept manual: reliable under LSUIElement (no Dock/app menu).
    public func open(id: String) {
        let win = windows[id] ?? makeWindow(id: id)
        windows[id] = win
        NSApp.activate(ignoringOtherApps: true)
        win.center()
        win.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(id: String) -> NSWindow {
        let view: AnyView = switch id {
        case "history": AnyView(HistoryView(model: self))
        case "settings": AnyView(SettingsView(model: self))
        default: AnyView(OnboardingView(model: self))
        }
        let win = NSWindow(contentViewController: NSHostingController(rootView: view))
        if id == "onboarding" {
            // Native chrome: transparent titlebar, hidden title, real traffic
            // lights. AppKit owns the window shadow; not resizable — the
            // content column scrolls internally at larger text sizes.
            win.styleMask = [.titled, .closable, .fullSizeContentView]
            win.titlebarAppearsTransparent = true
            win.titleVisibility = .hidden
            win.isMovableByWindowBackground = false
            win.appearance = nil
            #if DEBUG
            if let appearance = ProcessInfo.processInfo.environment["OB_APPEARANCE"] {
                win.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
            }
            #endif
            win.isOpaque = true
            win.backgroundColor = OBTheme.canvasNS
        } else {
            win.styleMask = [.titled, .closable, .resizable]
        }
        win.title = switch id {
        case "history": "Clipboard History"
        case "settings": "Settings"
        default: "Welcome to Cue"
        }
        win.isReleasedWhenClosed = false
        let size: NSSize = switch id {
        case "history": NSSize(width: 480, height: 420)
        case "settings": NSSize(width: 480, height: 560)
        default: NSSize(width: 760, height: 580)
        }
        win.setContentSize(size)
        return win
    }

    public func runSelfCheck() async {
        selfCheckResult = "running…"
        selfCheckResult = await SelfCheck.run(model: self)
    }
}

@MainActor
public struct CueApp: App {
    public init() {}

    public var body: some Scene {
        MenuBarExtra("Cue", systemImage: "paperclip") {
            // First access happens inside body evaluation (MainActor),
            // which is where AppModel builds the whole object graph.
            MenuBarView(model: AppModel.shared)
        }
    }
}
