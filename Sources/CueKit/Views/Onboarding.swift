import AppKit
import Carbon
import SwiftUI

/// First-run flow in a native window: welcome → accessibility → trigger →
/// models → privacy → practice. One idea per screen, the fold-out surface
/// carries the content, the footer's primary is the single action.
/// See docs/design/onboarding/SPEC.md.
public struct OnboardingView: View {
    var model: AppModel

    enum Step: CaseIterable {
        case welcome, accessibility, trigger, models, privacy, practice

        func next(trusted: Bool, remote: Bool) -> Step? {
            switch self {
            case .welcome: trusted ? .trigger : .accessibility
            case .accessibility: .trigger
            case .trigger: .models
            case .models: remote ? .privacy : .practice
            case .privacy: .practice
            case .practice: nil
            }
        }

        func previous(trusted: Bool, remote: Bool) -> Step? {
            switch self {
            case .welcome: nil
            case .accessibility: .welcome
            case .trigger: trusted ? .welcome : .accessibility
            case .models: .trigger
            case .privacy: .models
            case .practice: remote ? .privacy : .models
            }
        }
    }

    @State private var step: Step = .welcome
    @State private var trusted = ContextCaptor.isTrusted
    /// The models/practice screens publish their footer action up here.
    @State private var stepPrimary: OBPrimary?
    @State private var practice: OnboardingPractice?
    @State private var escMonitor: Any?
    @State private var openedPermissionSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(model: AppModel) { self.model = model }

    private var settings: AppSettings { model.settings }

    public var body: some View {
        ZStack {
            OBTheme.canvas.ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Cue")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(OBTheme.textPrimary)
                    .padding(.top, 24)

                Text(title)
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.4)
                    .foregroundStyle(OBTheme.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 680)
                    .padding(.top, 21)

                Text(support)
                    .font(.system(size: 16))
                    .foregroundStyle(OBTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 680)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)

                // Content column: 600 wide, top-anchored at y≈166. The
                // window is fixed — a route that grows scrolls inside,
                // it never resizes the window.
                ScrollView(.vertical) {
                    ZStack {
                        switch step {
                        case .welcome: welcomeStep.transition(.opacity)
                        case .accessibility: permissionStep.transition(.opacity)
                        case .trigger: triggerStep.transition(.opacity)
                        case .models: modelsStep.transition(.opacity)
                        case .privacy: privacyStep.transition(.opacity)
                        case .practice: practiceStep.transition(.opacity)
                        }
                    }
                    .padding(.vertical, 12)
                    .frame(width: 600, alignment: .top)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, step == .models ? 4 : 16)

                footer
            }
        }
        .frame(width: 760, height: 580)
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: step)
        .onAppear {
            trusted = ContextCaptor.isTrusted
            #if DEBUG
            if let s = ProcessInfo.processInfo.environment["OB_STEP"],
               let i = Int(s), Step.allCases.indices.contains(i) {
                step = Step.allCases[i]
                if step == .practice {
                    enterPractice()
                    if ProcessInfo.processInfo.environment["OB_PRACTICE"] == "another" {
                        practice?.tryAnother()
                    }
                }
            }
            #endif
            escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                // Escape closes without completing — unless the hotkey
                // recorder owns it (it cancels recording first).
                guard Int(e.keyCode) == kVK_Escape,
                      e.window?.title == "Welcome to Cue",
                      !(e.window?.firstResponder is HotkeyRecorder.RecorderView)
                else { return e }
                Task { @MainActor in self.closeWindow() }
                return nil
            }
        }
        .onDisappear {
            if let escMonitor { NSEvent.removeMonitor(escMonitor) }
            leavePractice()
        }
    }

    // MARK: - Shell

    private var title: String {
        switch step {
        case .welcome: "Copy it all. Paste just what fits."
        case .accessibility: "Allow Accessibility access"
        case .trigger: "Make it your shortcut."
        case .models: "Choose your model."
        case .privacy: "Choose what leaves your Mac"
        case .practice:
            if let p = practice, case .succeeded = p.phase {
                "That's your first smart paste."
            } else {
                "Try your first smart paste."
            }
        }
    }

    private var support: String {
        switch step {
        case .welcome: "Cue finds the right detail in your copied text."
        case .accessibility: "Cue needs permission to read field labels and paste into your apps."
        case .trigger: "Choose when Cue steps in."
        case .models: "Run a model on your Mac or connect a hosted service."
        case .privacy: "Mask personal details before Cue sends text to a hosted model."
        case .practice:
            if let p = practice, case .succeeded = p.phase {
                "One copied message. Just the detail you needed."
            } else if let p = practice, p.target == .website {
                "We copied a message. Paste just the link."
            } else {
                "We copied a message. Paste just the email."
            }
        }
    }

    /// The references put the footer inside the lower sheet on Accessibility
    /// (primary, centered) and Models (Back left, primary right); every other
    /// screen keeps Back + centered primary outside the panels.
    private var footerInsideSheet: Bool { step == .accessibility || step == .models }

    /// Refs 02/04/05 draw "‹ Back"; 03/06 a plain "Back".
    private var backChevron: Bool { step == .accessibility || step == .privacy }

    private var footer: some View {
        ZStack {
            if !footerInsideSheet {
                HStack { primaryCluster }.frame(maxWidth: .infinity)
            }
            HStack {
                if step != .welcome && step != .models {
                    OBBackButton(chevron: backChevron, action: goBack)
                }
                Spacer()
                if showsFinishLater {
                    Button("Finish setup later") { finishLater() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(OBTheme.textTertiary)
                        .padding(.trailing, 24)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private var primaryCluster: some View {
        let p = primarySpec
        return OBPrimaryButton(title: p.title, enabled: p.enabled, action: p.action)
    }

    /// The footer primary per route/state — the single action per screen.
    private var primarySpec: OBPrimary {
        if let stepPrimary { return stepPrimary }
        switch step {
        case .welcome, .trigger:
            return OBPrimary(title: "Continue") { advance() }
        case .accessibility:
            if trusted {
                return OBPrimary(title: "Continue") { advance() }
            }
            return OBPrimary(title: "Open System Settings") { grantAccessibility() }
        case .models:
            return OBPrimary(title: "Continue") { advance() }
        case .privacy:
            return privacyPrimary
        case .practice:
            return practicePrimary
        }
    }

    /// "Finish setup later" is quiet, truthful, and only where setup can be
    /// unavailable — models and practice. Hidden when the primary already
    /// carries that label (e.g. no provider configured).
    private var showsFinishLater: Bool {
        if primarySpec.title == "Finish setup later" { return false }
        switch step {
        case .models:
            return settings.provider == .off || settings.provider == .custom
        case .practice:
            return true
        default:
            return false
        }
    }

    private func advance() {
        trusted = ContextCaptor.isTrusted
        guard let next = step.next(trusted: trusted, remote: privacyIsRemote) else { return }
        step = next
        stepPrimary = nil
        if step == .practice { enterPractice() }
    }

    private func goBack() {
        trusted = ContextCaptor.isTrusted
        guard let previous = step.previous(trusted: trusted, remote: privacyIsRemote) else { return }
        step = previous
        stepPrimary = nil
        if step != .practice { leavePractice() }
    }

    private func finishLater() {
        model.settings.onboardingDone = true
        leavePractice()
        model.close(id: "onboarding")
    }

    private func closeWindow() {
        leavePractice()
        model.close(id: "onboarding")
    }

    // MARK: - Screen 1: Welcome

    private var welcomeStep: some View {
        WelcomeDemo()
    }

    // MARK: - Screen 2: Accessibility

    private var permissionStep: some View {
        FoldOut(verticalPadding: 16, lowerTopPadding: 14) {
            VStack(alignment: .leading, spacing: 0) {
                OBCaption("In System Settings")
                Text("Privacy & Security › Accessibility")
                    .font(.system(size: 17))
                    .foregroundStyle(OBTheme.textPrimary)
                    .padding(.top, 12)
                HStack(spacing: 12) {
                    Group {
                        if let icon = NSApp.applicationIconImage {
                            Image(nsImage: icon).resizable().scaledToFit()
                        } else {
                            Image(systemName: "paperclip")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(OBTheme.textSecondary)
                        }
                    }
                    .frame(width: 32, height: 32)
                    Text("Cue").font(.system(size: 15)).foregroundStyle(OBTheme.textPrimary)
                    Spacer()
                    PermissionSwitchDemo(granted: trusted)
                }
                .padding(.horizontal, 14)
                .frame(height: 54)
                .background(OBTheme.insetFill, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(OBTheme.separator, lineWidth: 0.7))
                .padding(.top, 12)
            }
        } lower: {
            VStack(alignment: .leading, spacing: 0) {
                instruction(1, "Open System Settings below.")
                instruction(2, "Turn on Cue under Accessibility.")
                Text("Cue will bring you back when access is enabled.")
                    .font(.system(size: 12))
                    .foregroundStyle(OBTheme.textSecondary)
                    .padding(.leading, 40)
                    .padding(.top, 6)
                HStack(spacing: 8) {
                    if trusted {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Access granted")
                    } else {
                        Image(systemName: "circle").foregroundStyle(OBTheme.textTertiary)
                        Text("Access not yet granted")
                    }
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(trusted ? .green : OBTheme.textTertiary)
                .padding(.top, 10)
                .frame(maxWidth: .infinity)
                // Ref 02: the primary lives inside the lower sheet, centered.
                OBPrimaryButton(title: primarySpec.title, enabled: primarySpec.enabled,
                                action: primarySpec.action)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
            }
            .frame(maxWidth: .infinity)
        }
        .task(id: step == .accessibility) {
            guard step == .accessibility else { return }
            while !Task.isCancelled && step == .accessibility {
                trusted = ContextCaptor.isTrusted
                if trusted {
                    if openedPermissionSettings { model.open(id: "onboarding") }
                    openedPermissionSettings = false
                    advance()
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func instruction(_ n: Int, _ text: String) -> some View {
        HStack(spacing: 12) {
            Text("\(n)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OBTheme.textPrimary)
                .frame(width: 28, height: 28)
                .background(OBTheme.textTertiary.opacity(0.1), in: Circle())
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(OBTheme.textPrimary)
        }
        .padding(.vertical, 4)
    }

    private func grantAccessibility() {
        openedPermissionSettings = true
        ContextCaptor.requestTrust()
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    // MARK: - Screen 3: Trigger

    @State private var recorderConflict: String?

    private var triggerStep: some View {
        FoldOut(verticalPadding: 16, lowerTopPadding: 16) {
            VStack(alignment: .leading, spacing: 0) {
                triggerRow(
                    title: "Dedicated shortcut",
                    detail: "Use Cue when you choose. ⌘V stays unchanged.",
                    selected: settings.triggerMode == .hotkey
                ) {
                    setTrigger(.hotkey)
                } accessory: {
                    VStack(spacing: 4) {
                        HotkeyRecorder(
                            value: settings.hotkey(for: HotkeyManager.Action.smartPaste.rawValue)
                                ?? HotkeyManager.Action.smartPaste.default
                        ) { hk in recordSmartPaste(hk) }
                        .frame(width: 116, height: 34)
                        Text("Click to record")
                            .font(.system(size: 11))
                            .foregroundStyle(OBTheme.textTertiary)
                    }
                    .disabled(settings.triggerMode == .intercept)
                    .opacity(settings.triggerMode == .intercept ? 0.4 : 1)
                }
                Divider().padding(.leading, 68).padding(.vertical, 4)
                triggerRow(
                    title: "Use ⌘V",
                    detail: "Let Cue choose the relevant text when you paste.",
                    selected: settings.triggerMode == .intercept
                ) {
                    setTrigger(.intercept)
                } accessory: {
                    EmptyView()
                }
            }
        } lower: {
            VStack(spacing: 10) {
                OBCaption("Your shortcut pastes the part that fits the focused field.")
                    .frame(maxWidth: .infinity)
                if let recorderConflict {
                    Text(recorderConflict)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Caption above the grey inset box (ref 03).
                        Text("Copied message")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(OBTheme.textTertiary)
                        HighlightedParagraph(
                            text: "Reach Mira at mira@example.com or +44 7700 900123.",
                            highlights: [OnboardingSample.Target.email.expected],
                            fontSize: 12, width: 200)
                            .padding(10)
                            .background(OBTheme.insetFill,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(OBTheme.separator, lineWidth: 0.5))
                    }
                    .frame(width: 224, alignment: .leading)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(OBTheme.textTertiary)
                        .fixedSize()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Email")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(OBTheme.textTertiary)
                        Text(OnboardingSample.Target.email.expected)
                            .font(.system(size: 13))
                            .foregroundStyle(OBTheme.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, 10).frame(height: 30)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(OBTheme.inputFill,
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(OBTheme.inputStroke, lineWidth: 0.5))
                    }
                }
            }
        }
    }

    private func triggerRow<Accessory: View>(
        title: String, detail: String, selected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    OBRadio(selected: selected)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 15, weight: .medium))
                            .foregroundStyle(OBTheme.textPrimary)
                        Text(detail).font(.system(size: 13))
                            .foregroundStyle(OBTheme.textSecondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Spacer()
            accessory()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 72)
    }

    private func setTrigger(_ mode: AppSettings.TriggerMode) {
        settings.triggerMode = mode
        model.hotkeys.interceptCmdV = mode == .intercept
    }

    /// Reject bindings that collide with another Cue action — the recorder
    /// keeps its prior value when we refuse to persist.
    private func recordSmartPaste(_ hk: AppSettings.Hotkey) {
        for action in HotkeyManager.Action.allCases where action != .smartPaste {
            let other = settings.hotkey(for: action.rawValue) ?? action.default
            if other.keyCode == hk.keyCode && other.modifiers == hk.modifiers {
                recorderConflict = "That shortcut is already \(action.title)."
                return
            }
        }
        recorderConflict = nil
        settings.setHotkey(hk, for: HotkeyManager.Action.smartPaste.rawValue)
        model.hotkeys.reregister()
    }

    // MARK: - Screen 4: Models

    private var modelsStep: some View {
        OnboardingModels(model: model, primary: $stepPrimary,
                         onBack: { goBack() }) {
            advance()
        }
    }

    // MARK: - Screen 5: Privacy

    /// Locality from the real endpoint, not the conservative mayBeRemote —
    /// a loopback custom endpoint is local.
    private var privacyIsRemote: Bool {
        switch settings.provider {
        case .jevDirect, .jevGateway: true
        case .local, .off: false
        case .custom: model.makeProvider()?.isRemote ?? false
        }
    }

    @State private var redactedSample: String?

    private var privacyStep: some View {
        remotePrivacy
    }

    @State private var privacyRects: [CGRect] = []

    private var remotePrivacy: some View {
        VStack(alignment: .leading, spacing: 14) {
            FoldOut(arrowX: privacyRects.first.map { 24 + $0.midX }) {
                VStack(alignment: .leading, spacing: 8) {
                    OBCaption("Example copied text")
                    HighlightedParagraph(
                        text: "Send the launch brief to Mira at mira@example.com.",
                        highlights: ["Mira", "mira@example.com"],
                        fontSize: 16, width: 552) { rects in
                        privacyRects = rects
                    }
                }
            } lower: {
                VStack(alignment: .leading, spacing: 8) {
                    OBCaption(settings.effectivePIIRedaction
                              ? "Example sent to the model" : "Example sent without redaction")
                    // [NAME]/[EMAIL] style tokens render as coral chips, in
                    // the static example or live redactor output alike.
                    HighlightedParagraph(
                        text: scrubbedSample,
                        highlights: Self.placeholderTokens(in: scrubbedSample),
                        fontSize: 16, width: 552)
                }
            }

            VStack(spacing: 8) {
                Toggle("Redact personal details", isOn: redactionToggle)
                    .toggleStyle(.switch)
                    .font(.system(size: 15))
                    .fixedSize()
                Text("The detail you paste keeps its original text.")
                    .font(.system(size: 12))
                    .foregroundStyle(OBTheme.textTertiary)
                if settings.piiRedaction != nil {
                    Button("Use automatic setting") { settings.piiRedaction = nil }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(OBTheme.textTertiary)
                }
                redactorLine
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 6) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 11))
                Text("Redaction uses a small model on your Mac.")
                    .font(.system(size: 12))
            }
            .foregroundStyle(OBTheme.textTertiary)
            .frame(maxWidth: .infinity)
        }
        .task(id: model.redactor.status) {
            // Live preview once the redactor is ready — real output only.
            if model.redactor.status == .ready {
                redactedSample = try? await model.redactor.redact(
                    "Send the launch brief to Mira at mira@example.com.")
            }
        }
    }

    /// Bracketed placeholders like `[NAME]`/`[EMAIL_1]` — whatever the real
    /// redactor emits, plus the static example's tokens.
    private static func placeholderTokens(in text: String) -> [String] {
        var out: [String] = []
        for m in text.matches(of: /\[[A-Z0-9_]+\]/) {
            let t = String(m.output)
            if !out.contains(t) { out.append(t) }
        }
        return out
    }

    /// Live redactor output when ready, else the labeled static example.
    private var scrubbedSample: String {
        settings.effectivePIIRedaction
            ? redactedSample ?? "Send the launch brief to [NAME] at [EMAIL]."
            : "Send the launch brief to Mira at mira@example.com."
    }

    @ViewBuilder
    private var redactorLine: some View {
        switch model.redactor.status {
        case .idle:
            EmptyView()
        case .downloading(let f):
            VStack(spacing: 6) {
                ProgressView(value: f)
                Text("Downloading… \(Int(f * 100))%")
                    .font(.system(size: 12)).foregroundStyle(OBTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
        case .ready:
            Label("Redaction ready", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundStyle(.green)
                .frame(maxWidth: .infinity)
        case .failed(let msg):
            Label("Download failed — \(msg)", systemImage: "xmark.circle")
                .font(.system(size: 12)).foregroundStyle(.red)
                .frame(maxWidth: .infinity)
        }
    }


    /// The tri-state: toggling writes an explicit override; auto is shown as
    /// the current effective value.
    private var redactionToggle: Binding<Bool> {
        Binding(
            get: { settings.effectivePIIRedaction },
            set: { settings.piiRedaction = $0 }
        )
    }

    /// Privacy primary: remote + redaction-on-but-model-missing gates on
    /// "Set up redaction" / "Downloading…" / "Retry download".
    private var privacyPrimary: OBPrimary {
        guard privacyIsRemote, settings.effectivePIIRedaction else {
            return OBPrimary(title: "Continue") { advance() }
        }
        switch model.redactor.status {
        case .ready:
            return OBPrimary(title: "Continue") { advance() }
        case .downloading:
            return OBPrimary(title: "Downloading…", enabled: false)
        case .failed:
            return OBPrimary(title: "Retry download") {
                Task { await model.redactor.prepare() }
            }
        case .idle:
            return OBPrimary(title: "Set up redaction") {
                Task { await model.redactor.prepare() }
            }
        }
    }

    // MARK: - Screen 6: Practice

    private var practiceStep: some View {
        Group {
            if let practice {
                PracticeScreen(practice: practice)
            }
        }
    }

    private var practicePrimary: OBPrimary {
        guard let p = practice else { return OBPrimary(title: "Continue", enabled: false) }
        switch p.phase {
        case .intro:
            return OBPrimary(title: "Preparing sample…", enabled: false)
        case .armed:
            return OBPrimary(title: "Waiting for \(p.triggerHint)…", enabled: false)
        case .deciding:
            return OBPrimary(title: "Deciding…", enabled: false)
        case .succeeded:
            return OBPrimary(title: "Start using Cue") {
                model.settings.onboardingDone = true
                closeWindow()
            }
        case .ordinaryPaste, .uncertain, .failed:
            return OBPrimary(title: "Try again") { p.reset(target: nil) }
        case .lostPermission:
            return OBPrimary(title: "Grant access") { step = .accessibility; leavePractice() }
        case .unavailable:
            return OBPrimary(title: "Finish setup later") { finishLater() }
        }
    }

    private func enterPractice() {
        let p = OnboardingPractice(model: model)
        p.target = .email
        practice = p
        model.practice = p
    }

    private func leavePractice() {
        practice?.cancel()
        model.practice = nil
        practice = nil
    }
}

// MARK: - Welcome demo

/// One copied message, one highlighted detail, one destination preview.
/// Pointer/keyboard on the segmented control retargets the highlight and
/// sends a coral chip through the fold to the field. Never touches the real
/// clipboard, never calls a model.
private struct WelcomeDemo: View {
    @State private var target = OnboardingSample.Target.email
    /// Paragraph-local rects + the paragraph's frame in demo space.
    @State private var paragraphLocalRects: [CGRect] = []
    @State private var paragraphRect: CGRect = .zero
    /// Field anchor for the chip's destination.
    @State private var fieldRect: CGRect = .zero
    @State private var chip: ChipFlight?
    @State private var chipTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct ChipFlight {
        var from: CGRect
        var to: CGRect
        var text: String
        var progress: CGFloat = 0
    }

    var body: some View {
        FoldOut(arrowX: arrowX) {
            VStack(alignment: .leading, spacing: 16) {
                OBCaption("Example copied message")
                HighlightedParagraph(
                    text: OnboardingSample.message,
                    highlights: [span],
                    width: 552
                ) { rects in
                    paragraphLocalRects = rects
                }
                .background(
                    GeometryReader { g in
                        Color.clear.preference(key: ParaAnchorKey.self,
                                               value: g.frame(in: .named("demo")))
                    }
                )
            }
        } lower: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(target.rawValue)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(OBTheme.textPrimary)
                    Spacer()
                    Text("Try a different field:")
                        .font(.system(size: 11))
                        .foregroundStyle(OBTheme.textSecondary)
                    OBSegmented(items: OnboardingSample.Target.allCases.map { ($0, $0.rawValue) },
                                selection: $target)
                        .frame(width: 150)
                }
                OBFieldPreview(label: target.rawValue, value: shownValue)
                    .background(
                        GeometryReader { g in
                            Color.clear.preference(key: FieldAnchorKey.self,
                                                   value: g.frame(in: .named("demo")))
                        }
                    )
            }
        }
        .coordinateSpace(name: "demo")
        .onPreferenceChange(FieldAnchorKey.self) { fieldRect = $0 }
        .onPreferenceChange(ParaAnchorKey.self) { paragraphRect = $0 }
        .onChange(of: target) { _, _ in retarget() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Demo: Cue picks the fitting detail from one copied message")
        .overlay {
            if let chip {
                ChipView(chip: chip)
            }
        }
    }

    private var span: String { target.expected }

    private var arrowX: CGFloat? {
        paragraphLocalRects.first.map { 24 + $0.midX }
    }

    /// The field shows the extracted value — after the chip lands during a
    /// retarget animation, immediately otherwise.
    private var shownValue: String { chip == nil ? target.expected : "" }

    /// The highlighted span's rect in demo coordinates.
    private var spanRectInDemo: CGRect? {
        paragraphLocalRects.first.map {
            $0.offsetBy(dx: paragraphRect.minX, dy: paragraphRect.minY)
        }
    }

    private func retarget() {
        chipTask?.cancel()
        guard !reduceMotion, let from = spanRectInDemo, !fieldRect.isEmpty else {
            chip = nil
            return
        }
        chip = ChipFlight(from: from, to: fieldRect, text: target.expected)
        withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.4)) {
            chip?.progress = 1
        }
        chipTask = Task {
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            chip = nil // field value appears
        }
    }

    private struct FieldAnchorKey: PreferenceKey {
        static let defaultValue: CGRect = .zero
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
    }

    private struct ParaAnchorKey: PreferenceKey {
        static let defaultValue: CGRect = .zero
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
    }

    /// The coral chip that travels from the highlighted span to the field.
    private struct ChipView: View {
        var chip: ChipFlight
        var body: some View {
            let t = chip.progress
            let x = chip.from.midX + (chip.to.midX - chip.from.midX) * t
            let y = chip.from.midY + (chip.to.midY - chip.from.midY) * t - 3 * sin(t * .pi)
            Text(chip.text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OBTheme.highlightText)
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(OBTheme.highlight, in: RoundedRectangle(cornerRadius: 4))
                .position(x: x, y: y)
                .opacity(t < 0.85 ? 1 : 0)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Practice screen

/// The guided first paste. The field is a real NSTextField; the sample copy
/// is a real pasteboard write; the trigger is the user's real binding.
private struct PracticeScreen: View {
    var practice: OnboardingPractice

    @State private var paraRects: [CGRect] = []

    var body: some View {
        FoldOut(arrowX: paraRects.first.map { 24 + $0.midX }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    OBCaption("Sample copied message")
                    Spacer()
                    Label("Copied for you", systemImage: "checkmark")
                        .font(.system(size: 12))
                        .foregroundStyle(OBTheme.textSecondary)
                }
                HighlightedParagraph(
                    text: practice.sampleText,
                    highlights: [practice.expected],
                    fontSize: 16, width: 552) { rects in
                    paraRects = rects
                }
            }
        } lower: {
            VStack(alignment: .leading, spacing: 10) {
                Text(practice.fieldLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(OBTheme.textPrimary)
                HStack(spacing: 10) {
                    PracticeField(label: practice.fieldLabel,
                                  placeholder: practice.target == .email
                                    ? "name@example.com" : "https://…",
                                  practice: practice)
                        .frame(height: 36)
                        .overlay(alignment: .trailing) {
                            // Ref 06: the confirmation sits inside the field.
                            if case .succeeded = practice.phase {
                                Text("✓ \(practice.target.rawValue) pasted")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.green)
                                    .padding(.trailing, 10)
                            }
                        }
                    if case .succeeded = practice.phase, practice.round == 0 {
                        OBBorderedButton(
                            title: practice.target == .website ? "Try Email" : "Try Website"
                        ) {
                            practice.reset(target: practice.target == .website ? .email : .website)
                        }
                        OBBorderedButton(title: "Try another") { practice.tryAnother() }
                    }
                }
                statusLine
            }
        }
        .task {
            practice.copySample()
            await Task.yield()
            practice.focus()
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch practice.phase {
        case .intro:
            Text("Preparing your sample…")
                .font(.system(size: 12)).foregroundStyle(OBTheme.textTertiary)
        case .armed:
            Text("Now press \(practice.triggerHint)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OBTheme.textSecondary)
        case .deciding:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Deciding…").font(.system(size: 12))
                    .foregroundStyle(OBTheme.textSecondary)
            }
        case .succeeded:
            Text(practice.elapsedMilliseconds.map { "Pasted in \($0) ms · Find Cue in your Mac's menu bar." }
                 ?? "Find Cue in your Mac's menu bar.")
                .font(.system(size: 12))
                .foregroundStyle(OBTheme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        case .ordinaryPaste(let observed):
            VStack(alignment: .leading, spacing: 6) {
                Text("Cue used ordinary paste this time.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.orange)
                if !observed.isEmpty, observed != practice.expected {
                    Text("The field got the whole message, not the \(practice.target.rawValue.lowercased()).")
                        .font(.system(size: 11)).foregroundStyle(OBTheme.textTertiary)
                }
            }
        case .uncertain:
            Text("Cue wasn't sure which detail to paste.")
                .font(.system(size: 12)).foregroundStyle(OBTheme.textSecondary)
        case .failed(let msg):
            Text(msg).font(.system(size: 12)).foregroundStyle(.red)
        case .lostPermission:
            Text("Accessibility access is needed to try this.")
                .font(.system(size: 12)).foregroundStyle(.orange)
        case .unavailable:
            Text("Smart paste needs a working model — configure one in Settings anytime.")
                .font(.system(size: 12)).foregroundStyle(OBTheme.textSecondary)
        }
    }
}
