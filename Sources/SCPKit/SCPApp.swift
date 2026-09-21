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
    public let controller: SmartPasteController

    public var selfCheckResult: String?
    public var trusted: Bool { ContextCaptor.isTrusted }

    private var windows: [String: NSWindow] = [:]

    public init() {
        store = ClipStore(capacity: self.settings.historyCap)
        monitor = ClipboardMonitor(store: store, settings: settings)
        hotkeys = HotkeyManager(settings: settings)
        executor = PasteExecutor(monitor: monitor, hotkeys: hotkeys)
        feedback = FeedbackTracker()
        hud = HUDController()
        redactor = PIIRedactor()
        controller = SmartPasteController(
            store: store, settings: settings,
            executor: executor, feedback: feedback, hud: hud, redactor: redactor
        ) { [settings] in settings.providerClient() }

        hotkeys.interceptCmdV = settings.triggerMode == .intercept
        hotkeys.reregister()
        hotkeys.on(.smartPaste) { [weak self] in self?.controller.smartPaste() }
        hotkeys.on(.picker) { [weak self] in self?.controller.showPicker() }
        hotkeys.on(.rawPaste) { [weak self] in self?.controller.pasteLatest() }
        hotkeys.on(.queueToggle) { [weak self] in self?.toggleQueue() }
        hotkeys.on(.settings) { [weak self] in self?.open(id: "settings") }

        monitor.start()
        // Warm the redaction model in the background so the first paste
        // doesn't pay the download latency.
        if settings.piiRedaction { Task { await redactor.prepare() } }
        if !settings.onboardingDone {
            Task { @MainActor in self.open(id: "onboarding") }
        }
    }

    public func makeProvider() -> (any DecisionProvider)? {
        settings.providerClient()
    }

    /// Round-trips a trivial question so Settings/onboarding can verify keys.
    public func testProvider() async -> String {
        guard let provider = settings.providerClient() else {
            return settings.provider == .none ? "No provider selected"
                : settings.provider.needsAPIKey ? "No API key set" : "Check the endpoint URL"
        }
        do {
            let resp = try await provider.evaluate(
                state: .string("The user clicked test."),
                questions: ["ok": .noul(instructions: "Did the request succeed?")]
            )
            return "Connected — \(resp.model), \(resp.inputTokens) tokens in"
        } catch {
            return "Failed: \(error.localizedDescription)"
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
        win.title = switch id {
        case "history": "Clipboard History"
        case "settings": "Settings"
        default: "Welcome"
        }
        win.styleMask = [.titled, .closable, .resizable]
        win.isReleasedWhenClosed = false
        let size: NSSize = switch id {
        case "history": NSSize(width: 480, height: 420)
        case "settings": NSSize(width: 480, height: 560)
        default: NSSize(width: 480, height: 560)
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
public struct SCPApp: App {
    public init() {}

    public var body: some Scene {
        MenuBarExtra("SmartCopyPaste", systemImage: "doc.on.clipboard") {
            // First access happens inside body evaluation (MainActor),
            // which is where AppModel builds the whole object graph.
            MenuBarView(model: AppModel.shared)
        }
    }
}
