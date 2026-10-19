import AppKit
import Carbon
import ServiceManagement
import SwiftUI

/// Records a single hotkey: click, press the combo, done. Esc cancels.
/// Tab-reachable, Enter/Space arms recording, VoiceOver gets a real label.
struct HotkeyRecorder: NSViewRepresentable {
    var value: AppSettings.Hotkey?
    var onChange: (AppSettings.Hotkey) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let v = RecorderView()
        v.onRecord = { hk in onChange(hk) }
        return v
    }

    func updateNSView(_ v: RecorderView, context: Context) {
        v.label = value?.displayString ?? "Record"
    }

    final class RecorderView: NSView {
        var label = "Record" { didSet { needsDisplay = true } }
        var onRecord: ((AppSettings.Hotkey) -> Void)?
        private var recording = false { didSet { needsDisplay = true } }

        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize { NSSize(width: 96, height: 22) }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            // The onboarding reference shows no ring until the recorder is
            // armed; AppKit's automatic ring would fire on first focus.
            focusRingType = .none
        }
        required init?(coder: NSCoder) { fatalError() }

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            (recording ? NSColor.controlAccentColor.withAlphaComponent(0.2) : NSColor.controlBackgroundColor).setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            // Ring only while armed — a passive focus must not light it up.
            if recording {
                NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
                let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: -2.5, dy: -2.5), xRadius: 7, yRadius: 7)
                ring.lineWidth = 2
                ring.stroke()
            }
            let str = NSAttributedString(
                string: recording ? "press keys…" : label,
                attributes: [.font: NSFont.systemFont(ofSize: 11),
                             .foregroundColor: NSColor.labelColor]
            )
            let size = str.size()
            str.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        }

        override func becomeFirstResponder() -> Bool { needsDisplay = true; return true }
        override func resignFirstResponder() -> Bool { needsDisplay = true; return true }

        override func mouseDown(with event: NSEvent) {
            recording = true
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            // Enter/Space arms recording — keyboard parity with the click.
            if !recording, Int(event.keyCode) == kVK_Return || Int(event.keyCode) == kVK_Space {
                recording = true
                return
            }
            guard recording else { return super.keyDown(with: event) }
            if Int(event.keyCode) == kVK_Escape { // Esc cancels, restores prior value
                recording = false
                return // keep firstResponder: Escape restores focus state
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return } // require a modifier
            onRecord?(AppSettings.Hotkey(keyCode: UInt32(event.keyCode),
                                         modifiers: AppSettings.Hotkey.carbonModifiers(mods)))
            recording = false
            window?.makeFirstResponder(nil)
        }

        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func accessibilityTitle() -> String? {
            recording ? "Recording shortcut — press keys, Escape cancels" : "Shortcut: \(label)"
        }
        override func accessibilityPerformPress() -> Bool {
            recording = true
            window?.makeFirstResponder(self)
            return true
        }
    }
}

/// One pane of the Settings window; the window's toolbar switches between them (CueApp.makeWindow).
public enum SettingsTab: String, CaseIterable {
    case general = "General", shortcuts = "Shortcuts", model = "Model", privacy = "Privacy"

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        case .model: "cpu"
        case .privacy: "hand.raised"
        }
    }
}

public struct SettingsView: View {
    var model: AppModel
    var tab: SettingsTab
    @State private var loginError: String?
    @State private var confirmClear = false

    public var body: some View {
        Form {
            switch tab {
            case .general: general
            case .shortcuts: shortcuts
            case .model: modelPane
            case .privacy: privacy
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        // The model list is long: a fixed pane that scrolls, not a window taller than the screen.
        .frame(height: tab == .model ? 560 : nil)
        .fixedSize(horizontal: false, vertical: tab != .model)
    }

    @ViewBuilder private var general: some View {
        @Bindable var settings = model.settings
        Section {
            Toggle("Open Cue at login", isOn: loginBinding)
            if let loginError {
                Text(loginError).font(.callout).foregroundStyle(.red)
            }
            Toggle("Show a note when Cue picks for you", isOn: $settings.showStatusToast)
            Toggle("Paste in the order I copied (queue)", isOn: queueBinding)
        } footer: {
            Text("Queue: each ⌘V pastes the next clip you copied, oldest first, until the queue is empty.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section("Advanced") {
            LabeledContent("Onboarding") {
                Button("Show Again") { model.open(id: "onboarding") }
            }
            LabeledContent("Self-check") {
                HStack(spacing: 8) {
                    if let result = model.selfCheckResult {
                        Text(result)
                            .font(.callout)
                            .foregroundStyle(result.hasPrefix("PASS") ? Color.secondary : Color.red)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Run") { Task { await model.runSelfCheck() } }
                }
            }
        }
    }

    @ViewBuilder private var shortcuts: some View {
        @Bindable var settings = model.settings
        Section {
            Picker("When you press ⌘V", selection: triggerBinding) {
                Text("Paste what fits the field").tag(true)
                Text("Paste the latest clip, as usual").tag(false)
            }
            .pickerStyle(.radioGroup)
        } footer: {
            Text("Either way, the Show choices shortcut lists what you copied.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section {
            ForEach(HotkeyManager.Action.allCases, id: \.self) { action in
                // A plain row: LabeledContent stacks the AppKit recorder under its label.
                HStack {
                    Text(action.title)
                    Spacer()
                    // Unset means the built-in shortcut is live, so show that, not "Record".
                    HotkeyRecorder(value: settings.hotkey(for: action.rawValue) ?? action.default) { hk in
                        settings.setHotkey(hk, for: action.rawValue)
                        model.hotkeys.reregister()
                    }
                    .frame(width: 110, height: 24)
                }
            }
        } footer: {
            Text("Click a shortcut, then press the new keys. Esc cancels.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var modelPane: some View {
        Section {
            ProviderPicker(model: model)
            if model.providerStatus.state == .unreachable {
                Label("Can’t reach the model. Pastes work normally until it’s back.",
                      systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder private var privacy: some View {
        @Bindable var settings = model.settings
        Section {
            Picker("Hide names and emails from the model", selection: redactionBinding) {
                Text("Hosted models only").tag(Bool?.none)
                Text("Always").tag(Bool?.some(true))
                Text("Never").tag(Bool?.some(false))
            }
            redactorStatus
        } footer: {
            Text("Only what the model reads is masked. What you paste is always your original text.")
                .font(.callout).foregroundStyle(.secondary)
        }
        Section("History") {
            LabeledContent("Keep up to") {
                HStack(spacing: 6) {
                    TextField("", value: $settings.historyCap, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                    Text("clips").foregroundStyle(.secondary)
                }
            }
            LabeledContent("Ignore copies from") {
                VStack(alignment: .trailing, spacing: 6) {
                    ForEach(settings.excludedBundleIDs, id: \.self) { id in
                        HStack(spacing: 6) {
                            if let icon = SourceAppIcon.image(for: id) {
                                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                            }
                            Text(Self.appName(id))
                            Button {
                                settings.excludedBundleIDs.removeAll { $0 == id }
                            } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Stop ignoring \(Self.appName(id))")
                        }
                    }
                    Button("Add App…") { addExcludedApp() }
                }
            }
            LabeledContent("Saved history") {
                Button("Clear History…", role: .destructive) { confirmClear = true }
            }
        }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { model.store.clearUnpinned() }
        } message: {
            Text("Every clip except pinned ones is deleted from this Mac. This can’t be undone.")
        }
    }

    private static func appName(_ bundleID: String) -> String {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
            ?? bundleID
    }

    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Ignore"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier,
              !model.settings.excludedBundleIDs.contains(id) else { return }
        model.settings.excludedBundleIDs.append(id)
    }

    @ViewBuilder
    private var redactorStatus: some View {
        switch model.redactor.status {
        case .idle:
            if model.settings.effectivePIIRedaction && model.redactor.needsDownload {
                Button("Download redaction model (~12 MB)") {
                    Task { await model.redactor.prepare() }
                }
            }
        case .downloading(let f):
            LabeledContent("Redaction model") {
                ProgressView(value: f).frame(width: 140)
            }
        case .ready:
            LabeledContent("Redaction model") {
                Text("downloaded").foregroundStyle(.secondary)
            }
        case .failed(let msg):
            LabeledContent("Redaction model") {
                Text("failed — \(msg)").foregroundStyle(.red).lineLimit(1)
            }
        }
    }

    private var redactionBinding: Binding<Bool?> {
        Binding(get: { model.settings.piiRedaction },
                set: { model.settings.piiRedaction = $0 })
    }
    private var triggerBinding: Binding<Bool> {
        Binding(get: { model.settings.triggerMode == .intercept },
                set: { v in
                    model.settings.triggerMode = v ? .intercept : .hotkey
                    model.hotkeys.interceptCmdV = v
                })
    }
    private var queueBinding: Binding<Bool> {
        Binding(get: { model.settings.queueMode },
                set: { v in
                    model.settings.queueMode = v
                    if !v { model.store.clearQueue() }
                })
    }
    private var loginBinding: Binding<Bool> {
        Binding(get: { model.settings.launchAtLogin }, set: { v in
            model.settings.launchAtLogin = v
            do {
                if v { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch {
                loginError = "Move Cue to your Applications folder to open it at login."
                model.settings.launchAtLogin = false
            }
        })
    }

}
