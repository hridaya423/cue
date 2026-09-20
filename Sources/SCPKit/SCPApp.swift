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
        controller = SmartPasteController(
            store: store, settings: settings,
            executor: executor, feedback: feedback, hud: hud
        ) { [settings] in settings.jevProvider() }

        hotkeys.interceptCmdV = settings.triggerMode == .intercept
        hotkeys.reregister()
        hotkeys.on(.smartPaste) { [weak self] in self?.controller.smartPaste() }
        hotkeys.on(.picker) { [weak self] in self?.controller.showPicker() }
        hotkeys.on(.rawPaste) { [weak self] in self?.controller.pasteLatest() }
        hotkeys.on(.queueToggle) { [weak self] in self?.toggleQueue() }
        hotkeys.on(.settings) { [weak self] in self?.open(id: "settings") }

        monitor.start()
        if !settings.onboardingDone {
            Task { @MainActor in self.open(id: "onboarding") }
        }
    }

    public func makeProvider() -> (any DecisionProvider)? {
        settings.jevProvider()
    }

    /// Round-trips a trivial question so Settings/onboarding can verify keys.
    public func testProvider() async -> String {
        guard let provider = settings.jevProvider() else { return "No API key set" }
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
        default: NSSize(width: 460, height: 380)
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
