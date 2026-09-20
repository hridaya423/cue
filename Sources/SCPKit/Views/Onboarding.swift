import SwiftUI

public struct OnboardingView: View {
    var model: AppModel

    @State private var step = 0
    @State private var pollTimer: Timer?
    @State private var trusted = false
    @State private var testResult: String?
    @State private var testing = false

    public var body: some View {
        VStack(spacing: 20) {
            Text("SmartCopyPaste")
                .font(.system(size: 22, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Group {
                switch step {
                case 0: permissionsStep
                case 1: triggerStep
                default: providerStep
                }
            }
            .frame(maxWidth: .infinity)

            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                if step < 2 {
                    Button("Continue") { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .disabled(step == 0 && !trusted)
                } else {
                    Button("Done") {
                        model.settings.onboardingDone = true
                        model.close(id: "onboarding")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 420)
        .onAppear {
            trusted = ContextCaptor.isTrusted
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    let now = ContextCaptor.isTrusted
                    if now != trusted { trusted = now }
                    if now { pollTimer?.invalidate() }
                }
            }
        }
        .onDisappear { pollTimer?.invalidate() }
    }

    private var subtitle: String {
        switch step {
        case 0: "Step 1 of 3 — permission"
        case 1: "Step 2 of 3 — trigger"
        default: "Step 3 of 3 — model"
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Accessibility access", systemImage: trusted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(trusted ? .green : .orange)
            Text("SmartCopyPaste reads the focused field's label and posts the paste keystroke into the app you're in. macOS requires Accessibility permission for both.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !trusted {
                Button("Grant in System Settings") {
                    ContextCaptor.requestTrust()
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            } else {
                Text("Granted.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private var triggerStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            triggerCard(
                title: "Smart hotkey",
                detail: "⌃⌥V smart-pastes; ⌘V stays normal.",
                selected: model.settings.triggerMode == .hotkey
            ) { setTrigger(.hotkey) }
            triggerCard(
                title: "Intercept ⌘V",
                detail: "Every ⌘V runs the smart check — when a different clip clearly fits, it's pasted instead; otherwise ⌘V behaves normally. Rebindable later.",
                selected: model.settings.triggerMode == .intercept
            ) { setTrigger(.intercept) }
        }
    }

    private func triggerCard(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private var providerStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Jev via", selection: providerBinding) {
                ForEach(AppSettings.Provider.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if model.settings.provider == .none {
                Text("Skipped — the app still works with local heuristics. Add a key in Settings anytime.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                SecureField("API key", text: keyBinding)
                    .textFieldStyle(.roundedBorder)
                Text(model.settings.provider == .gateway
                     ? "AI_GATEWAY_API_KEY — used against ai-gateway.vercel.sh/typesafe"
                     : "TYPESAFE_API_KEY — used against api.typesafe.ai")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                HStack {
                    Button(testing ? "Testing…" : "Test connection") { Task { await test() } }
                        .disabled(testing)
                    if let testResult {
                        Text(testResult).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
    }

    private func setTrigger(_ mode: AppSettings.TriggerMode) {
        model.settings.triggerMode = mode
        model.hotkeys.interceptCmdV = mode == .intercept
    }

    private var providerBinding: Binding<AppSettings.Provider> {
        Binding(get: { model.settings.provider }, set: { model.settings.provider = $0 })
    }
    private var keyBinding: Binding<String> {
        Binding(
            get: { model.settings.provider == .gateway
                ? model.settings.gatewayKey ?? "" : model.settings.apiKey ?? "" },
            set: { if model.settings.provider == .gateway {
                model.settings.gatewayKey = $0.isEmpty ? nil : $0
            } else {
                model.settings.apiKey = $0.isEmpty ? nil : $0
            } }
        )
    }

    private func test() async {
        testing = true
        defer { testing = false }
        testResult = await model.testProvider()
    }
}
