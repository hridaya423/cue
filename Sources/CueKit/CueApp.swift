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
    public let hud: HUDController
    public let redactor: PIIRedactor
    public let models: ModelManager
    public let providerStatus: ProviderStatus
    public let prefetch: DecisionPrefetch
    public let prefetcher: PrefetchTriggers
    public let controller: SmartPasteController

    public var selfCheckResult: String?
    public var trusted: Bool { ContextCaptor.isTrusted }

    /// The active guided-paste session (onboarding's practice screen). When
    /// set it gets first refusal on the smart-paste trigger; nil = normal.
    public var practice: OnboardingPractice?

    private var windows: [String: NSWindow] = [:]

    /// `live: false` builds the graph without side effects (no hotkeys, clipboard monitor, model servers or saved
    /// history) so windows can be drawn off-screen.
    public init(live: Bool = true) {
        store = live ? ClipStore(capacity: self.settings.historyCap)
            : ClipStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("cue-preview-\(UUID().uuidString).json"))
        monitor = ClipboardMonitor(store: store, settings: settings)
        hotkeys = HotkeyManager(settings: settings)
        executor = PasteExecutor(monitor: monitor, hotkeys: hotkeys)
        hud = HUDController()
        redactor = PIIRedactor()
        models = ModelManager()
        providerStatus = ProviderStatus()
        prefetch = DecisionPrefetch()
        let ctl = SmartPasteController(
            store: store, settings: settings,
            executor: executor, hud: hud, redactor: redactor,
            prefetch: prefetch
        ) { [settings, providerStatus] timeout in
            settings.providerClient(timeout: timeout).map { StatusTrackingProvider($0, status: providerStatus) }
        }
        controller = ctl
        prefetcher = PrefetchTriggers(
            store: store, settings: settings, prefetch: prefetch
        ) { [ctl] in ctl.makeEngine() }

        guard live else { return }
        hotkeys.interceptCmdV = settings.triggerMode == .intercept
        hotkeys.reregister()
        hotkeys.on(.smartPaste) { [weak self] in
            // Practice gets first refusal: it consumes the trigger only while
            // its own field is focused; everything else is normal dispatch.
            if self?.practice?.handleTrigger() == true { return }
            self?.controller.smartPaste(intercepted: false)
        }
        hotkeys.onIntercept { [weak self] in
            if self?.practice?.handleTrigger() == true { return }
            self?.controller.smartPaste(intercepted: true)
        }
        hotkeys.on(.picker) { [weak self] in self?.controller.showPicker() }
        hotkeys.on(.rawPaste) { [weak self] in self?.controller.pasteLatest() }
        hotkeys.on(.queueToggle) { [weak self] in self?.toggleQueue() }
        hotkeys.on(.settings) { [weak self] in self?.open(id: "settings") }

        monitor.start()
        prefetcher.start(monitor: monitor)
        #if DEBUG
        // `CUE_DEMO_WINDOW=history|settings` opens that window at launch —
        // a visual-verification hook alongside CUE_DEMO_CHOOSER.
        if let w = ProcessInfo.processInfo.environment["CUE_DEMO_WINDOW"], !w.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self.open(id: w)
            }
        }
        // `CUE_DEMO_PICKER=1` shows the full picker once — same purpose.
        if ProcessInfo.processInfo.environment["CUE_DEMO_PICKER"] != nil {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                let cands = ["Standup moved to 10", "mira@example.com",
                             "https://typesafe.ai/docs", "call me at +1 415 555 0117",
                             "invoice approved"].enumerated().map { i, t in
                    ScoredCandidate(clip: Clip(text: t, kind: .text,
                                               sourceApp: ["Slack", "Mail", "Safari", "Messages", "Notes"][i],
                                               copiedAt: Date().addingTimeInterval(-300.0 * Double(i + 1)),
                                               pinned: i == 4),
                                    probability: 0, confidence: 0)
                }
                hud.showPicker(candidates: cands, near: nil) { _ in }
            }
        }
        // `CUE_DEMO_CHOOSER=1` shows the chooser once near the mouse — a
        // visual-verification hook; practice exercises the same view.
        if ProcessInfo.processInfo.environment["CUE_DEMO_CHOOSER"] != nil {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                let loc = NSEvent.mouseLocation
                let clips = [
                    Clip(text: "mira@example.com", kind: .text, sourceApp: "Mail", sourceBundleID: "com.apple.mail",
                         copiedAt: Date().addingTimeInterval(-420)),
                    Clip(text: "priya@acme.com", kind: .text, sourceApp: "Safari", sourceBundleID: "com.apple.Safari",
                         copiedAt: Date().addingTimeInterval(-3600)),
                    Clip(text: "hello@work.dev", kind: .text, sourceApp: "Notes", sourceBundleID: "com.apple.Notes",
                         copiedAt: Date().addingTimeInterval(-7200)),
                ]
                let opts = clips.enumerated().map { i, c in
                    ScoredOption(option: PasteOption(
                        id: "demo-\(i)", text: c.text, kind: .email,
                        clip: c, snippet: c.text),
                        probability: [0.45, 0.35, 0.2][i], confidence: 0.6)
                }
                hud.showChooser(options: opts,
                                near: CGRect(origin: loc, size: CGSize(width: 2, height: 18)),
                                fieldLabel: "Email") { _ in }
            }
        }
        #endif
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

    /// History/menu action: close our surfaces and return focus to the
    /// previous app, then paste the chosen clip into it.
    public func pasteIntoFrontApp(_ clip: Clip) {
        close(id: "history")
        NSApp.hide(nil)
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

    /// A Mac settings window: toolbar tabs that switch panes, the window resizing to each one.
    private func makeSettingsWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.canPropagateSelectedChildViewControllerTitle = true
        for tab in SettingsTab.allCases {
            let host = NSHostingController(rootView: SettingsView(model: self, tab: tab))
            host.sizingOptions = .preferredContentSize
            host.title = tab.rawValue
            let item = NSTabViewItem(viewController: host)
            item.label = tab.rawValue
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.rawValue)
            tabs.addTabViewItem(item)
        }
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["CUE_SETTINGS_TAB"], let i = Int(s) {
            tabs.selectedTabViewItemIndex = i
        }
        #endif
        let win = NSWindow(contentViewController: tabs)
        win.styleMask = [.titled, .closable]
        win.toolbarStyle = .preference
        win.isReleasedWhenClosed = false
        return win
    }

    private func makeWindow(id: String) -> NSWindow {
        if id == "settings" { return makeSettingsWindow() }
        let view: AnyView = switch id {
        case "history": AnyView(HistoryView(model: self))
        default: AnyView(OnboardingView(model: self))
        }
        let host = NSHostingController(rootView: view)
        if id == "onboarding" { host.sizingOptions = [] }
        let win = NSWindow(contentViewController: host)
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
        win.title = id == "history" ? "Clipboard History" : "Welcome to Cue"
        win.isReleasedWhenClosed = false
        let size = id == "history" ? NSSize(width: 760, height: 500) : OBLayout.window
        if id == "onboarding" {
            win.setFrame(NSRect(origin: win.frame.origin, size: size), display: false)
        } else {
            win.setContentSize(size)
        }
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
        MenuBarExtra("Cue", systemImage: "doc.on.clipboard") {
            // First access happens inside body evaluation (MainActor),
            // which is where AppModel builds the whole object graph.
            MenuBarView(model: AppModel.shared)
        }
        .menuBarExtraStyle(.window)
    }
}
