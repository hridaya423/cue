import SwiftUI

public struct OnboardingView: View {
    var model: AppModel

    @State private var step = 0
    @State private var pollTimer: Timer?
    @State private var trusted = false

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 6) {
                Text("Cue")
                    .font(.system(size: 20, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 22)
            .padding(.bottom, 16)

            // Steps
            Group {
                switch step {
                case 0: permissionsStep
                case 1: triggerStep
                case 2: providerStep
                default: privacyStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Footer
            HStack(spacing: 10) {
                stepDots
                Spacer()
                if step > 0 {
                    Button("Back") { step -= 1 }
                }
                if step < 3 {
                    Button("Continue") { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .disabled(step == 0 && !trusted)
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Done") {
                        model.settings.onboardingDone = true
                        model.close(id: "onboarding")
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 480, height: 560)
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

    private var stepDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var subtitle: String {
        switch step {
        case 0: "Step 1 of 4 — permission"
        case 1: "Step 2 of 4 — trigger"
        case 2: "Step 3 of 4 — decision model"
        default: "Step 4 of 4 — privacy"
        }
    }

    // MARK: - Step 1: permission

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Accessibility access", systemImage: trusted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(trusted ? .green : .orange)
            Text("Cue reads the focused field's label and posts the paste keystroke into the app you're in. macOS requires Accessibility permission for both.")
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
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Step 2: trigger

    private var triggerStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            card(
                title: "Smart hotkey",
                detail: "⌃⌥V smart-pastes; ⌘V stays normal.",
                selected: model.settings.triggerMode == .hotkey
            ) { setTrigger(.hotkey) }
            card(
                title: "Intercept ⌘V",
                detail: "Every ⌘V runs the smart check — when a different clip clearly fits, it's pasted instead; otherwise ⌘V behaves normally.",
                selected: model.settings.triggerMode == .intercept
            ) { setTrigger(.intercept) }
            Text("All hotkeys are rebindable in Settings.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Step 3: provider

    private var providerStep: some View {
        ScrollView {
            ProviderPicker(model: model)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
    }

    // MARK: - Step 4: privacy

    private var privacyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            card(
                title: "Redact PII before cloud calls",
                detail: "An on-device model (≈12 MB, Core ML) masks names, emails, phones, cards and IDs in clip text before anything reaches a remote endpoint. Auto by default: on for cloud providers, off for local models — the model only ever sees the scrubbed preview; the real clip is what pastes.",
                selected: model.settings.effectivePIIRedaction
            ) {
                // Tapping flips the effective state into an explicit override.
                model.settings.piiRedaction = !model.settings.effectivePIIRedaction
                kickDownload()
            }
            Text(model.settings.piiRedaction == nil
                 ? "Auto — \(model.settings.provider.mayBeRemote ? "on (remote provider)" : "off (local provider)")"
                 : (model.settings.effectivePIIRedaction ? "On — override" : "Off — override"))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

            redactorStatus
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var redactorStatus: some View {
        switch model.redactor.status {
        case .idle:
            if model.settings.effectivePIIRedaction {
                Button("Download redaction model (~12 MB)") { kickDownload() }
            }
        case .downloading(let f):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: f)
                Text("Downloading model… \(Int(f * 100))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .ready:
            Label("Model downloaded — redaction active", systemImage: "checkmark.shield.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 6) {
                Text("Download failed: \(msg)")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Button("Retry") { kickDownload() }
            }
        }
    }

    // MARK: - shared bits

    private func card(title: String, detail: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Spacer()
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    private func kickDownload() {
        if model.settings.effectivePIIRedaction && model.redactor.needsDownload {
            Task { await model.redactor.prepare() }
        }
    }

    private func setTrigger(_ mode: AppSettings.TriggerMode) {
        model.settings.triggerMode = mode
        model.hotkeys.interceptCmdV = mode == .intercept
    }
}
