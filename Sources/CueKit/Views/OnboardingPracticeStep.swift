import SwiftUI

extension OnboardingView {
    var practiceControls: some View {
        Group {
            if let practice { PracticeScreen(practice: practice) }
        }
    }

    var practiceStage: some View {
        VStack(spacing: 20) {
            if let practice {
                OBKeycap(keys: practice.triggerHint).scaleEffect(2.2)
                Text("Press it in the field").font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 30)
            }
        }
    }

    var practicePrimary: OBPrimary {
        guard let p = practice else { return OBPrimary(title: "Continue", enabled: false) }
        switch p.phase {
        case .intro, .armed, .deciding:
            return .none
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
            // No model yet: the way forward is setting one up, not leaving.
            return OBPrimary(title: "Set up a model") {
                forward = false
                step = .models
                stepPrimary = nil
                leavePractice()
            }
        }
    }

    func enterPractice() {
        let p = OnboardingPractice(model: model)
        p.target = .email
        practice = p
        model.practice = p
    }

    func leavePractice() {
        practice?.cancel()
        model.practice = nil
        practice = nil
    }
}

// MARK: - Practice screen

/// The guided first paste. The field is a real NSTextField; the sample copy
/// is a real pasteboard write; the trigger is the user's real binding.
private struct PracticeScreen: View {
    var practice: OnboardingPractice

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var succeeded: Bool { if case .succeeded = practice.phase { return true }; return false }

    var body: some View {
        FoldOut {
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
                    fontSize: 15, width: 336)
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
                            if succeeded {
                                Label("\(practice.target.rawValue.capitalized) pasted", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.green)
                                    .padding(.trailing, 10)
                                    .transition(reduceMotion ? .opacity
                                                : .scale(scale: 0.85, anchor: .trailing).combined(with: .opacity))
                            }
                        }
                        .animation(.spring(duration: 0.35, bounce: 0.25), value: succeeded)
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
            HStack(spacing: 8) {
                Text("Now press")
                OBKeycap(keys: practice.triggerHint)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OBTheme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
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
