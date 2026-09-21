import AppKit
import Carbon
import ServiceManagement
import SwiftUI

/// Records a single hotkey: click, press the combo, done. Esc cancels.
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

        override func draw(_ dirtyRect: NSRect) {
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            (recording ? NSColor.controlAccentColor.withAlphaComponent(0.2) : NSColor.controlBackgroundColor).setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.stroke()
            let str = NSAttributedString(
                string: recording ? "press keys…" : label,
                attributes: [.font: NSFont.systemFont(ofSize: 11),
                             .foregroundColor: NSColor.labelColor]
            )
            let size = str.size()
            str.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        }

        override func mouseDown(with event: NSEvent) {
            recording = true
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { return super.keyDown(with: event) }
            if Int(event.keyCode) == kVK_Escape { // Esc cancels
                recording = false
                window?.makeFirstResponder(nil)
                return
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isEmpty else { return } // require a modifier
            onRecord?(AppSettings.Hotkey(keyCode: UInt32(event.keyCode),
                                         modifiers: AppSettings.Hotkey.carbonModifiers(mods)))
            recording = false
            window?.makeFirstResponder(nil)
        }
    }
}

public struct SettingsView: View {
    var model: AppModel
    @State private var testResult: String?
    @State private var testing = false
    @State private var loginError: String?
    @State private var endpointUp: Bool?

    public var body: some View {
        @Bindable var settings = model.settings

        Form {
            Section("Provider") {
                Picker("Decision model", selection: $settings.provider) {
                    ForEach(AppSettings.Provider.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if settings.provider.needsAPIKey {
                    SecureField("API key", text: apiKeyBinding)
                        .textFieldStyle(.roundedBorder)
                }
                if settings.provider.isEndpointBased {
                    LabeledContent("Endpoint") {
                        HStack(spacing: 6) {
                            TextField("http://127.0.0.1:8009", text: endpointBinding)
                                .textFieldStyle(.roundedBorder)
                            Circle()
                                .fill(endpointUp == true ? Color.green
                                    : endpointUp == false ? Color.red
                                    : Color.secondary.opacity(0.3))
                                .frame(width: 7, height: 7)
                                .help(endpointUp == true ? "reachable" : "not responding")
                        }
                    }
                    .task(id: currentEndpoint) {
                        endpointUp = await model.endpointReachable(currentEndpoint)
                    }
                    if settings.provider == .custom {
                        SecureField("Bearer key (optional)", text: customKeyBinding)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                if settings.provider != .none {
                    LabeledContent("Model") {
                        TextField("model", text: modelBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 160)
                    }
                    HStack {
                        Button(testing ? "Testing…" : "Test connection") { Task { await testJev() } }
                            .disabled(testing)
                        if let testResult {
                            Text(testResult).font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("No provider — smart paste uses local heuristics until a key or endpoint is set.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Privacy") {
                Toggle("Redact PII before cloud calls", isOn: $settings.piiRedaction)
                redactorStatus
                Text("Names, emails, phones, cards and IDs are masked on-device before clip text reaches a remote model. Loopback endpoints (Kev, Laya, localhost) skip redaction — that data stays on the device anyway.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
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
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }

    @ViewBuilder
    private var redactorStatus: some View {
        switch model.redactor.status {
        case .idle:
            if model.settings.piiRedaction && model.redactor.needsDownload {
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

    private var apiKeyBinding: Binding<String> {
        Binding(
            get: { model.settings.provider == .jevGateway
                ? model.settings.gatewayKey ?? ""
                : model.settings.apiKey ?? "" },
            set: { if model.settings.provider == .jevGateway {
                model.settings.gatewayKey = $0.isEmpty ? nil : $0
            } else {
                model.settings.apiKey = $0.isEmpty ? nil : $0
            } }
        )
    }
    private var customKeyBinding: Binding<String> {
        Binding(get: { model.settings.customKey ?? "" },
                set: { model.settings.customKey = $0.isEmpty ? nil : $0 })
    }
    private var currentEndpoint: String {
        switch model.settings.provider {
        case .kev: model.settings.kevURL
        case .laya: model.settings.layaURL
        default: model.settings.customURL
        }
    }
    private var endpointBinding: Binding<String> {
        Binding(get: { currentEndpoint }, set: {
            switch model.settings.provider {
            case .kev: model.settings.kevURL = $0
            case .laya: model.settings.layaURL = $0
            default: model.settings.customURL = $0
            }
        })
    }
    private var modelBinding: Binding<String> {
        Binding(get: { model.settings.model }, set: { model.settings.model = $0 })
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

    private func testJev() async {
        testing = true
        defer { testing = false }
        testResult = await model.testProvider()
    }
}
