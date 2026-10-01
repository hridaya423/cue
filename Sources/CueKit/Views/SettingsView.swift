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

public struct SettingsView: View {
    var model: AppModel
    @State private var loginError: String?

    public var body: some View {
        @Bindable var settings = model.settings

        Form {
            Section("Decision model") {
                ProviderPicker(model: model)
                if model.providerStatus.state == .unreachable {
                    Label("Provider unreachable — pastes pass through normally",
                          systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }

            Section("Privacy") {
                Picker("PII redaction", selection: redactionBinding) {
                    Text("Auto").tag(Bool?.none)
                    Text("On").tag(Bool?.some(true))
                    Text("Off").tag(Bool?.some(false))
                }
                Text("Auto means: on for cloud providers, off for local models — scrubbing traffic that never leaves the device only costs latency. Only the scrubbed preview reaches the model; the real clip is what pastes.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                redactorStatus
            }

            Section("Trigger") {
                Picker("Smart paste runs on", selection: triggerBinding) {
                    Text("Its own hotkey").tag(false)
                    Text("Intercepting ⌘V").tag(true)
                }
                ForEach(HotkeyManager.Action.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        HotkeyRecorder(value: settings.hotkey(for: action.rawValue)) { hk in
                            settings.setHotkey(hk, for: action.rawValue)
                            model.hotkeys.reregister()
                        }
                    }
                }
            }

            Section("Behavior") {
                LabeledContent("Confidence threshold: \(Int(settings.confidenceThreshold * 100))%") {
                    Slider(value: $settings.confidenceThreshold, in: 0.4...0.95, step: 0.05)
                        .frame(width: 160)
                }
                Picker("When unsure", selection: $settings.lowConfidenceMode) {
                    ForEach(AppSettings.LowConfidenceMode.allCases, id: \.self) {
                        Text($0.rawValue).tag($0)
                    }
                }
                Toggle("Show pasted confirmation", isOn: $settings.showStatusToast)
                Toggle("Queue mode (FIFO pastes)", isOn: queueBinding)
            }

            Section("History") {
                LabeledContent("Keep up to") {
                    TextField("items", value: $settings.historyCap, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                LabeledContent("Never capture from") {
                    TextField("bundle IDs, comma-separated", text: excludedBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: loginBinding)
                if let loginError {
                    Text(loginError).font(.system(size: 11)).foregroundStyle(.red)
                }
                HStack {
                    Button("Reset learned rankings") { model.feedback.reset() }
                    Spacer()
                    Button("Run onboarding again") { model.open(id: "onboarding") }
                }
                LabeledContent("Self-check") {
                    HStack(spacing: 8) {
                        if let result = model.selfCheckResult {
                            Text(result)
                                .font(.system(size: 11))
                                .foregroundStyle(result.hasPrefix("PASS") ? Color.secondary : Color.red)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Button("Run") { Task { await model.runSelfCheck() } }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
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
    private var excludedBinding: Binding<String> {
        Binding(get: { model.settings.excludedBundleIDs.joined(separator: ", ") },
                set: { model.settings.excludedBundleIDs = $0
                    .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty } })
    }
    private var loginBinding: Binding<Bool> {
        Binding(get: { model.settings.launchAtLogin }, set: { v in
            model.settings.launchAtLogin = v
            do {
                if v { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
                loginError = nil
            } catch {
                loginError = "Launch at login needs the app installed as a .app — run Scripts/bundle.sh first."
                model.settings.launchAtLogin = false
            }
        })
    }

}
