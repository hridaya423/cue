import SwiftUI

extension OnboardingView {
    /// The hero: the mark, the film's line, and one paste happening on its own.
    var hero: some View {
        VStack(spacing: 0) {
            Wordmark(height: 64, lean: lean, loops: true, replay: markReplay, color: .white)
            Text("A better instinct for paste.")
                .font(.system(size: 44, weight: .bold))
                .tracking(-1.2)
                .foregroundStyle(.white)
                .padding(.top, 40)
            Text("Copy it all. Cue pastes just the part that fits the field.")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.78))
                .padding(.top, 14)
            PasteMoment()
                .frame(width: 520)
                .padding(.top, 44)
        }
        .frame(width: OBLayout.window.width, height: OBLayout.window.height - OBLayout.footerHeight + 20)
    }
}

/// One copied message; the email lifts out of it and lands in a field. Loops; never touches the clipboard.
struct PasteMoment: View {
    @State private var phase = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let before = "Reach Mira at "
    private static let email = "mira@example.com"
    private static let after = " or +44 7700 900123."

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            message
                .padding(.horizontal, 18)
                .frame(height: 50)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.18)))
            HStack(spacing: 12) {
                Text("Email")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 44, alignment: .leading)
                Text(phase >= 3 ? Self.email : " ")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(red: 0.06, green: 0.2, blue: 0.6))
                    .contentTransition(.opacity)
                    .padding(.horizontal, 14)
                    .frame(height: 44)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(alignment: .trailing) {
                        if phase >= 3 {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(OBTheme.action)
                                .padding(.trailing, 12)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .shadow(color: .black.opacity(phase >= 3 ? 0.25 : 0.12), radius: phase >= 3 ? 18 : 8, y: 6)
            }
        }
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.5), value: phase)
        .accessibilityElement()
        .accessibilityLabel("A copied message with an email in it. Cue pastes just the email into the Email field.")
        .task {
            guard !reduceMotion else { phase = 3; return }
            while !Task.isCancelled {
                for (p, wait) in [(0, 1.1), (1, 0.8), (2, 0.6), (3, 3.2)] {
                    phase = p
                    try? await Task.sleep(for: .seconds(wait))
                }
            }
        }
    }

    private var message: some View {
        HStack(spacing: 0) {
            Text(Self.before).opacity(phase >= 2 ? 0.35 : 1)
            Text(Self.email)
                .foregroundStyle(phase >= 1 ? Color(red: 0.06, green: 0.2, blue: 0.6) : .white)
                .padding(.horizontal, phase >= 1 ? 4 : 0)
                .background(.white.opacity(phase >= 1 ? 1 : 0), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(Self.after).opacity(phase >= 2 ? 0.35 : 1)
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(.white)
        .lineLimit(1)
    }
}
