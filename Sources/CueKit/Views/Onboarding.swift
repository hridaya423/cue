import SwiftUI

/// First-run flow in a borderless dark card: welcome (with a live demo of a
/// clip landing in a field) → permission → trigger → model → privacy → done.
/// One idea per screen, one primary action, Return advances.
public struct OnboardingView: View {
    var model: AppModel

    @State private var step = 0
    /// +1 forward / -1 back; drives the direction-aware step transition.
    @State private var direction = 1
    @State private var pollTimer: Timer?
    @State private var trusted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let stepCount = 6

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        ZStack {
            // Card surface: material darkened to a locked dark theme, hairline
            // ring, continuous corners. The window itself is transparent.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.5))
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.09), lineWidth: 0.5)

            VStack(spacing: 0) {
                ZStack {
                    if step == 0 { welcomeStep.transition(stepTransition) }
                    if step == 1 { permissionStep.transition(stepTransition) }
                    if step == 2 { triggerStep.transition(stepTransition) }
                    if step == 3 { modelStep.transition(stepTransition) }
                    if step == 4 { privacyStep.transition(stepTransition) }
                    if step == 5 { doneStep.transition(stepTransition) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
            }
        }
        .environment(\.colorScheme, .dark)
        .padding(14) // shadow room
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: step)
        .onAppear {
            trusted = ContextCaptor.isTrusted
            pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                Task { @MainActor in
                    let now = ContextCaptor.isTrusted
                    if now != trusted {
                        trusted = now
                        // Granted while on the permission step → move on.
                        // Re-check after the beat: the user may have gone Back.
                        if now, step == 1 {
                            try? await Task.sleep(for: .milliseconds(400))
                            if step == 1 { advance() }
                        }
                    }
                    if now { pollTimer?.invalidate() }
                }
            }
        }
        .onDisappear { pollTimer?.invalidate() }
    }

    /// Direction-aware: forward steps enter from trailing, exits to leading.
    private var stepTransition: AnyTransition {
        let enter: Edge = direction > 0 ? .trailing : .leading
        let exit: Edge = direction > 0 ? .leading : .trailing
        return .asymmetric(
            insertion: .move(edge: enter).combined(with: .opacity),
            removal: .move(edge: exit).combined(with: .opacity)
        )
    }

    private func advance() {
        direction = 1
        step = min(step + 1, stepCount - 1)
    }

    private func back() {
        direction = -1
        step = max(step - 1, 0)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            dots
            Spacer()
            if step > 0 && step < stepCount - 1 {
                Button("Back", action: back)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            primaryButton
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    /// The active dot stretches into a capsule — one moving element, not six
    /// blinking dots. matchedGeometryEffect carries it between positions.
    @Namespace private var dotSpace

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<stepCount, id: \.self) { i in
                if i == step {
                    Capsule()
                        .fill(.white)
                        .frame(width: 16, height: 5)
                        .matchedGeometryEffect(id: "dot", in: dotSpace)
                } else {
                    Circle()
                        .fill(.white.opacity(0.25))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.15), value: step)
    }

    private var primaryButton: some View {
        Button(step == 0 ? "Get started" : step == stepCount - 1 ? "Start using Cue" : "Continue") {
            if step == stepCount - 1 {
                model.settings.onboardingDone = true
                model.close(id: "onboarding")
            } else {
                advance()
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
        .disabled(step == 1 && !trusted)
    }

    // MARK: - Step chrome

    /// Headline + one support line; the job of the screen in plain language.
    private func stepHeader(_ title: String, _ support: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
            Text(support)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 380)
        }
        .padding(.top, 26)
        .padding(.bottom, 20)
    }

    private func stepIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 26, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .frame(width: 56, height: 56)
            .background(Color.accentColor.opacity(0.12), in: Circle())
    }

    // MARK: - Step 0: welcome

    private var welcomeStep: some View {
        VStack(spacing: 0) {
            Text("Cue")
                .font(.system(size: 34, weight: .semibold))
            Text("Copy anything. Cue pastes the right clip.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            WelcomeDemo()
                .padding(.top, 30)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Step 1: permission

    private var permissionStep: some View {
        VStack(spacing: 0) {
            stepIcon("viewfinder")
            stepHeader(
                "Let Cue see where you're pasting",
                "Cue reads the focused field's label to pick the right clip, and posts the paste keystroke for you. macOS asks once."
            )
            if trusted {
                Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.green)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                VStack(spacing: 10) {
                    Button("Grant in System Settings") {
                        ContextCaptor.requestTrust()
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    Text("Waiting for permission…")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
        .animation(.easeOut(duration: 0.2), value: trusted)
    }

    // MARK: - Step 2: trigger

    private var triggerStep: some View {
        VStack(spacing: 0) {
            stepIcon("keyboard")
            stepHeader(
                "Choose your trigger",
                "Same ⌘V muscle memory, or a dedicated hotkey. Rebindable later in Settings."
            )
            VStack(spacing: 10) {
                triggerCard(
                    keys: "⌃⌥V",
                    title: "Smart hotkey",
                    detail: "Press ⌃⌥V for a smart pick. ⌘V stays exactly what it is.",
                    selected: model.settings.triggerMode == .hotkey
                ) { setTrigger(.hotkey) }
                triggerCard(
                    keys: "⌘V",
                    title: "Intercept ⌘V",
                    detail: "Every paste runs the check. When another clip clearly fits, Cue swaps it in.",
                    selected: model.settings.triggerMode == .intercept
                ) { setTrigger(.intercept) }
            }
            .padding(.horizontal, 60)
        }
        .frame(maxWidth: .infinity)
    }

    private func triggerCard(keys: String?, title: String, detail: String,
                             selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let keys {
                    Text(keys)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .frame(width: 44, height: 30)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(.white.opacity(0.14), lineWidth: 0.5))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(12)
            .background(.white.opacity(selected ? 0.09 : 0.05),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? Color.accentColor : .white.opacity(0.08),
                        lineWidth: selected ? 1.5 : 0.5))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Step 3: model

    private var modelStep: some View {
        VStack(spacing: 0) {
            stepHeader(
                "Pick a decision model",
                "Hosted Jev or a local on-device model. Change anytime in Settings."
            )
            ScrollView {
                ProviderPicker(model: model)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Step 4: privacy

    private var privacyStep: some View {
        VStack(spacing: 0) {
            stepIcon("lock.shield")
            stepHeader(
                "Keep it private",
                "An on-device model (~12 MB, Core ML) masks names, emails, phones, and cards in clip previews before anything reaches a remote endpoint."
            )
            VStack(alignment: .leading, spacing: 10) {
                triggerCard(
                    keys: nil,
                    title: "Redact PII before cloud calls",
                    detail: "Auto: on for remote providers, off for local models. Only the scrubbed preview leaves; the real clip is what pastes.",
                    selected: model.settings.effectivePIIRedaction
                ) {
                    model.settings.piiRedaction = !model.settings.effectivePIIRedaction
                    kickDownload()
                }
                Text(model.settings.piiRedaction == nil
                     ? "Auto · \(model.settings.provider.mayBeRemote ? "on, remote provider" : "off, local provider")"
                     : (model.settings.effectivePIIRedaction ? "On · override" : "Off · override"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                redactorStatus
            }
            .padding(.horizontal, 60)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var redactorStatus: some View {
        switch model.redactor.status {
        case .idle:
            if model.settings.effectivePIIRedaction {
                Button("Download redaction model (~12 MB)") { kickDownload() }
                    .controlSize(.small)
            }
        case .downloading(let f):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: f)
                Text("Downloading model… \(Int(f * 100))%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        case .ready:
            Label("Redaction model ready", systemImage: "checkmark.shield.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
        case .failed(let msg):
            VStack(alignment: .leading, spacing: 6) {
                Text("Download failed: \(msg)")
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                Button("Retry") { kickDownload() }
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Step 5: done

    private var doneStep: some View {
        VStack(spacing: 0) {
            stepIcon("checkmark.circle")
            stepHeader(
                "You're set.",
                "Cue is watching the clipboard in the background."
            )
            VStack(alignment: .leading, spacing: 12) {
                tip("keyboard", "\(hotkeyHint) smart-pastes wherever the caret is")
                tip("menubar.rectangle", "Find Cue in the menu bar: history, queue, settings")
                tip("command", "⌘V during a pick keeps your normal paste")
            }
            .padding(.horizontal, 90)
        }
        .frame(maxWidth: .infinity)
    }

    private var hotkeyHint: String {
        (model.settings.hotkey(for: HotkeyManager.Action.smartPaste.rawValue)
            ?? HotkeyManager.Action.smartPaste.default).displayString
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - shared

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

/// The product in miniature: clip chips cycle, and each lands transformed in
/// a mock To: field. Pure decoration — a 2-second answer to "what does this
/// do?" Honors reduce-motion by holding on the first frame.
private struct WelcomeDemo: View {
    @State private var index = 0
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// (clip on the clipboard, what Cue would paste)
    private let beats: [(clip: String, pasted: String)] = [
        ("hridya agrawal hridayahoney@gmail.com", "hridayahoney@gmail.com"),
        ("x.com/post/4821?utm_source=share", "x.com/post/4821"),
        ("Call +1 (415) 555-0132 anytime", "+1 (415) 555-0132"),
    ]

    var body: some View {
        VStack(spacing: 14) {
            // The clipboard
            VStack(spacing: 4) {
                ForEach(beats.indices, id: \.self) { i in
                    Text(beats[i].clip)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(i == index ? .primary : .tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 300, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(i == index ? Color.accentColor.opacity(0.14) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(8)
            .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 0.5))

            // The field it lands in
            HStack(spacing: 8) {
                Text("To:")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text(beats[index].pasted)
                    .font(.system(size: 11, weight: .medium))
                    .contentTransition(.interpolate)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: index)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: 316)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.4), lineWidth: 1))
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4).delay(0.15)) {
                appeared = true
            }
        }
        .onReceive(Timer.publish(every: 1.6, on: .main, in: .common).autoconnect()) { _ in
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                index = (index + 1) % beats.count
            }
        }
    }
}
