import AppKit
import Carbon
import SwiftUI

/// First-run flow in a native window: welcome → accessibility → trigger → models → privacy → practice.
/// Welcome is a hero on the living cobalt field; every later screen splits into copy and controls on the
/// canvas and a live stage on the right. The field never leaves: it slides from full width to the stage.
/// Each step's controls and stage live in their own file (`Onboarding<Step>.swift`).
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

    @State var step: Step = .welcome
    @State var trusted = ContextCaptor.isTrusted
    /// The models/practice screens publish their footer action up here.
    @State var stepPrimary: OBPrimary?
    @State var practice: OnboardingPractice?
    @State var escMonitor: Any?
    @State var openedPermissionSettings = false
    /// Which way the last step change went: content slides in from the side it's travelling to.
    @State var forward = true
    @State var lean: CGFloat = 0
    @State var markReplay = 0
    @State var recorderConflict: String?
    @State var redactedSample: String?
    /// Route fixed when the flow starts, so the progress count doesn't jump as the user grants access.
    @State var startedTrusted = ContextCaptor.isTrusted
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    public init(model: AppModel) { self.model = model }

    var settings: AppSettings { model.settings }
    var isHero: Bool { step == .welcome }

    var practiceSucceeded: Bool {
        if let p = practice, case .succeeded = p.phase { return true }
        return false
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            OBTheme.canvas

            CobaltField()
                .frame(width: isHero ? OBLayout.window.width : OBLayout.stageWidth, height: OBLayout.window.height)
                .offset(x: isHero ? 0 : OBLayout.columnWidth)
                .accessibilityHidden(true)

            if isHero {
                hero.transition(.opacity)
            } else {
                column
                    .frame(width: OBLayout.columnWidth, height: OBLayout.window.height, alignment: .topLeading)
                    .transition(.opacity)
                stage
                    .frame(width: OBLayout.stageWidth, height: OBLayout.window.height)
                    .offset(x: OBLayout.columnWidth)
                    .transition(.opacity)
            }

            footer
                .frame(width: OBLayout.window.width, height: OBLayout.footerHeight)
                .offset(y: OBLayout.window.height - OBLayout.footerHeight)
        }
        .frame(width: OBLayout.window.width, height: OBLayout.window.height)
        .ignoresSafeArea()
        .onContinuousHover { phase in
            guard !reduceMotion, case .active(let at) = phase else { return }
            withAnimation(.spring(duration: 0.6, bounce: 0)) { lean = max(-1, min(1, (at.x - 460) / 460)) }
        }
        .onChange(of: practiceSucceeded) { _, done in if done { markReplay += 1 } }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .timingCurve(0.65, 0, 0.35, 1, duration: 0.7), value: isHero)
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: reduceMotion ? 0.15 : 0.35), value: step)
        .onAppear {
            trusted = ContextCaptor.isTrusted
            startedTrusted = trusted
            #if DEBUG
            debugJump()
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

    // MARK: - Layout

    private var column: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                Wordmark(height: 26, lean: lean, replay: markReplay)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(.system(size: 34, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(OBTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 28)
                    Text(support)
                        .font(.system(size: 15))
                        .lineSpacing(3)
                        .foregroundStyle(OBTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                    controls
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 28)
                }
                .id(step)
                .transition(stepTransition)
            }
            .padding(.horizontal, OBLayout.margin)
            .padding(.vertical, 24)
        }
        .scrollIndicators(.never)
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center, for: .alignment)
        .padding(.top, 28)
        .padding(.bottom, OBLayout.footerHeight)
    }

    @ViewBuilder private var controls: some View {
        switch step {
        case .welcome: EmptyView()
        case .accessibility: permissionControls
        case .trigger: triggerControls
        case .models: modelsControls
        case .privacy: privacyControls
        case .practice: practiceControls
        }
    }

    private var stage: some View {
        ZStack {
            switch step {
            case .welcome: EmptyView()
            case .accessibility: permissionStage
            case .trigger: triggerStage
            case .models: modelsStage
            case .privacy: privacyStage
            case .practice: practiceStage
            }
        }
        .id(step)
        .transition(stepTransition)
        .padding(.horizontal, 40)
        .padding(.top, 40)
        .padding(.bottom, OBLayout.footerHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            if step.previous(trusted: trusted, remote: privacyIsRemote) != nil {
                OBRoundBack(onStage: isHero) { goBack() }
            }
            OBProgress(count: route.count, index: route.firstIndex(of: step) ?? 0, onStage: isHero)
            Spacer()
            if step != .welcome && step != .models { OBModelProgress(model: model) }
            if showsFinishLater {
                Button("Finish later") { finishLater() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
            if !primarySpec.title.isEmpty {
                OBStagePrimary(title: primarySpec.title, enabled: primarySpec.enabled, action: primarySpec.action)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 8)
    }

    /// This user's screens in order, from the trust and provider they started with.
    var route: [Step] {
        var out: [Step] = [], s: Step? = .welcome
        while let cur = s {
            out.append(cur)
            s = cur.next(trusted: startedTrusted, remote: privacyIsRemote)
        }
        if !out.contains(step), let i = Step.allCases.firstIndex(of: step) {
            out.insert(step, at: min(i, out.count))
        }
        return out
    }

    // MARK: - Copy

    private var title: String {
        switch step {
        case .welcome: "A better instinct for paste."
        case .accessibility: "Let Cue see the field."
        case .trigger: "Make it your shortcut."
        case .models: "Choose your model."
        case .privacy: "Choose what leaves your Mac."
        case .practice:
            practiceSucceeded ? "That\u{2019}s your first smart paste." : "Try your first smart paste."
        }
    }

    private var support: String {
        switch step {
        case .welcome: "Copy it all. Cue pastes just the part that fits the field."
        case .accessibility: "Cue reads a field\u{2019}s label to know what belongs there. Turn it on once in System Settings."
        case .trigger: "Choose when Cue steps in."
        case .models: "Cue runs best with a model on your Mac. It downloads while you finish setup."
        case .privacy: "Mask personal details before Cue sends text to a hosted model."
        case .practice:
            if practiceSucceeded {
                "One copied message. Just the detail you needed."
            } else if let p = practice, p.target == .website {
                "We copied a message for you. Paste just the link."
            } else {
                "We copied a message for you. Paste just the email."
            }
        }
    }

    // MARK: - Primary

    /// The footer primary per route/state — the single action per screen.
    var primarySpec: OBPrimary {
        if let stepPrimary { return stepPrimary }
        switch step {
        case .welcome:
            return OBPrimary(title: "Get started") { advance() }
        case .trigger, .models:
            return OBPrimary(title: "Continue") { advance() }
        case .accessibility:
            if trusted {
                return OBPrimary(title: "Continue") { advance() }
            }
            return OBPrimary(title: "Open System Settings") { grantAccessibility() }
        case .privacy:
            return privacyPrimary
        case .practice:
            return practicePrimary
        }
    }

    /// Quiet and truthful, only where setup can be unavailable: models and practice.
    private var showsFinishLater: Bool {
        if primarySpec.title == "Finish setup later" { return false }
        switch step {
        case .models: return settings.provider == .custom
        case .practice: return true
        default: return false
        }
    }

    /// Forward slides left, Back slides right; Reduce Motion keeps only the crossfade.
    var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let d: CGFloat = forward ? 22 : -22
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: d)),
                           removal: .opacity.combined(with: .offset(x: -d)))
    }

    // MARK: - Navigation

    func advance() {
        trusted = ContextCaptor.isTrusted
        guard let next = step.next(trusted: trusted, remote: privacyIsRemote) else { return }
        forward = true
        step = next
        stepPrimary = nil
        if step == .practice { enterPractice() }
    }

    func goBack() {
        trusted = ContextCaptor.isTrusted
        guard let previous = step.previous(trusted: trusted, remote: privacyIsRemote) else { return }
        forward = false
        step = previous
        stepPrimary = nil
        if step != .practice { leavePractice() }
    }

    func finishLater() {
        model.settings.onboardingDone = true
        leavePractice()
        model.close(id: "onboarding")
    }

    func closeWindow() {
        leavePractice()
        model.close(id: "onboarding")
    }

    #if DEBUG
    private func debugJump() {
        guard let s = ProcessInfo.processInfo.environment["OB_STEP"],
              let i = Int(s), Step.allCases.indices.contains(i) else { return }
        step = Step.allCases[i]
        guard step == .practice else { return }
        enterPractice()
        if ProcessInfo.processInfo.environment["OB_PRACTICE"] == "another" {
            practice?.tryAnother()
        }
    }
    #endif
}
