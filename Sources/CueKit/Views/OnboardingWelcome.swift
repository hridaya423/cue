import SwiftUI

extension OnboardingView {
    /// The hero: the mark, the film's line, and one action, sitting just above centre on the dawn field. Nothing else.
    var hero: some View {
        WelcomeHero(lean: lean, markReplay: markReplay, primary: primarySpec)
    }
}

private let cobaltInk = Color(red: 0.02, green: 0.08, blue: 0.35)
private let rise = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.8)

struct WelcomeHero: View {
    var lean: CGFloat
    var markReplay: Int
    var primary: OBPrimary
    @State private var shown = false

    var body: some View {
        ZStack {
            light
            VStack(spacing: 0) {
                Wordmark(height: 84, lean: lean, loops: true, replay: markReplay, color: .white)
                    .shadow(color: cobaltInk.opacity(0.35), radius: 24, y: 10)
                Text("A better instinct for paste.")
                    .font(.system(size: 60, weight: .bold))
                    .tracking(-2)
                    .foregroundStyle(.white)
                    .shadow(color: cobaltInk.opacity(0.3), radius: 18, y: 6)
                    .padding(.top, 30)
                    .reveal(shown, delay: 0.15, dy: 14)
                OBStagePrimary(title: primary.title, enabled: primary.enabled, action: primary.action)
                    .padding(.top, 36)
                    .reveal(shown, delay: 0.28, dy: 10)
            }
            .offset(y: -OBLayout.footerHeight / 2)
        }
        .frame(width: OBLayout.window.width, height: OBLayout.window.height)
        .clipped()
        .task { shown = true }
    }

    /// A soft bloom behind the mark. No vignette: navy over the field's ice light reads grey.
    private var light: some View {
        RadialGradient(colors: [.white.opacity(0.16), .clear], center: .init(x: 0.5, y: 0.34), startRadius: 0, endRadius: 360)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension View {
    /// Rises into place after `delay`; with Reduce Motion it is simply there.
    func reveal(_ shown: Bool, delay: Double, dy: CGFloat) -> some View {
        modifier(Reveal(shown: shown, delay: delay, dy: dy))
    }
}

private struct Reveal: ViewModifier {
    let shown: Bool, delay: Double, dy: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : dy)
            .animation(rise.delay(delay), value: shown)
    }
}
