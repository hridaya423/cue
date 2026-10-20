import SwiftUI

extension OnboardingView {
    /// The hero: the mark, the film's line, one action, and one paste happening on its own. Nothing else.
    var hero: some View {
        WelcomeHero(lean: lean, markReplay: markReplay, primary: primarySpec)
    }
}

private let cobaltInk = Color(red: 0.02, green: 0.08, blue: 0.35)
private let chipInk = Color(red: 0.06, green: 0.2, blue: 0.6)
private let demoSpace = "demo"
private let rise = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.8)

struct WelcomeHero: View {
    var lean: CGFloat
    var markReplay: Int
    var primary: OBPrimary
    @State private var shown = false

    var body: some View {
        ZStack(alignment: .top) {
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
                    .padding(.top, 28)
                    .reveal(shown, delay: 0.28, dy: 10)
                PasteMoment(lean: lean)
                    .frame(width: 600, height: 250, alignment: .top)
                    .padding(.top, 40)
                    .reveal(shown, delay: 0.42, dy: 40)
            }
            .padding(.top, 44)
        }
        .frame(width: OBLayout.window.width, height: OBLayout.window.height, alignment: .top)
        .clipped()
        .task { shown = true }
    }

    /// Depth on the field: a bloom behind the mark and a vignette that pulls the corners down.
    private var light: some View {
        ZStack {
            RadialGradient(colors: [.white.opacity(0.16), .clear], center: .init(x: 0.5, y: 0.18), startRadius: 0, endRadius: 340)
            RadialGradient(colors: [.clear, cobaltInk.opacity(0.35)], center: .init(x: 0.5, y: 0.45), startRadius: 300, endRadius: 680)
        }
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

/// A copied message beside a contact form. ⌘V goes down, Cue selects the email in the message, a copy
/// lifts off it, arcs over to the Email field and settles in as the field's own text. Then the field
/// clears and it plays again. Never touches the clipboard. Idle between beats: a handful of state changes,
/// no frame clock.
struct PasteMoment: View {
    var lean: CGFloat = 0
    @State private var phase = Phase.rest
    @State private var source = CGRect.zero
    @State private var target = CGRect.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Int, Comparable {
        case rest, pressed, picked, lifted, flying, landed, clearing
        static func < (a: Phase, b: Phase) -> Bool { a.rawValue < b.rawValue }
    }

    private static let email = "mira@example.com"
    private static let chipPad: CGFloat = 3
    private static let fieldInset: CGFloat = 11

    var body: some View {
        ZStack(alignment: .topLeading) {
            messageCard
                .offset(x: -lean * 6, y: 0)
            formCard
                .offset(x: 306 + lean * 9, y: 40)
            keycap
                .offset(x: 232 + lean * 4, y: 150)
            chip
        }
        .coordinateSpace(name: demoSpace)
        .accessibilityElement()
        .accessibilityLabel("A copied message with an email in it. Cue pastes just the email into the Email field.")
        .task { await run() }
    }

    // MARK: Cards

    private var messageCard: some View {
        let selected = phase >= .picked && phase < .landed
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.74, blue: 0.5), Color(red: 0.96, green: 0.48, blue: 0.42)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 22, height: 22)
                    .overlay(Text("D").font(.system(size: 11, weight: .bold)).foregroundStyle(.white))
                Text("Dan")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.78))
                Text("Copied")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(chipInk)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(chipInk.opacity(0.1), in: Capsule())
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 0) {
                    Text("Reach Mira at ").padding(.trailing, 3)
                    Text(Self.email)
                        .foregroundStyle(selected ? chipInk : Color.black.opacity(0.86))
                        .background {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(OBTheme.action.opacity(0.14))
                                .padding(.horizontal, -Self.chipPad)
                                .padding(.vertical, -1)
                                .opacity(selected ? 1 : 0)
                        }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(demoSpace)) } action: { source = $0 }
                }
                Text("or +44 7700 900123.")
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.black.opacity(0.86))
            .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(width: 336, height: 112, alignment: .leading)
        .cardSurface(radius: 18)
    }

    private var formCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(Color.black.opacity(0.12)).frame(width: 9, height: 9) }
                Spacer()
                Text("New contact").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.black.opacity(0.4))
                Spacer()
                Color.clear.frame(width: 39, height: 1)
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            Divider().overlay(Color.black.opacity(0.05))
            VStack(alignment: .leading, spacing: 12) {
                field("Email", focused: true)
                field("Phone", focused: false)
                field("Company", focused: false)
            }
            .padding(16)
        }
        .frame(width: 294, alignment: .topLeading)
        .cardSurface(radius: 18)
    }

    private func field(_ label: String, focused: Bool) -> some View {
        let filled = focused && phase == .landed
        return VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.black.opacity(0.45))
            Color.clear
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(alignment: .leading) {
                    if focused {
                        Capsule().fill(OBTheme.action)
                            .frame(width: 1.5, height: 18)
                            .padding(.leading, Self.fieldInset)
                            .opacity(phase < .flying || phase == .clearing ? 1 : 0)
                    }
                }
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(OBTheme.action.opacity(filled ? 1 : 0.55), lineWidth: filled ? 2 : 1.5)
                            .shadow(color: OBTheme.action.opacity(filled ? 0.4 : 0), radius: 6)
                    }
                }
                .overlay(alignment: .trailing) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(OBTheme.action)
                        .padding(.trailing, 9)
                        .scaleEffect(filled ? 1 : 0.5)
                        .opacity(filled ? 1 : 0)
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(demoSpace)) } action: { if focused { target = $0 } }
        }
    }

    private var keycap: some View {
        let down = phase == .pressed
        return HStack(spacing: 4) {
            key("⌘", down: down)
            key("V", down: down)
        }
        .opacity(phase == .rest || phase >= .landed ? 0.7 : 1)
    }

    private func key(_ s: String, down: Bool) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 22)
            .background(.white.opacity(down ? 0.4 : 0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(down ? 0.6 : 0.3)))
            .scaleEffect(down ? 0.9 : 1)
            .offset(y: down ? 1.5 : 0)
    }

    // MARK: Chip

    /// A copy of the email as a selection pill: it rises off the message, arcs to the field and drops its
    /// pill to become the field's text.
    private var chip: some View {
        let landed = phase >= .landed
        let airborne = phase == .lifted || phase == .flying
        let to = CGPoint(x: target.minX + Self.fieldInset + source.width / 2, y: target.midY)
        let from = CGPoint(x: source.midX, y: source.midY)
        return Text(Self.email)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(landed ? Color.black.opacity(0.86) : chipInk)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Self.chipPad)
            .padding(.vertical, 3)
            .background(.white.opacity(landed ? 0 : 1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(OBTheme.action.opacity(landed ? 0 : 0.35)))
            .shadow(color: cobaltInk.opacity(airborne ? 0.38 : 0), radius: airborne ? 14 : 0, y: airborne ? 9 : 0)
            .scaleEffect(airborne ? 1.03 : 1)
            .offset(y: phase == .lifted ? -5 : 0)
            .position(from)
            .modifier(Arc(travel: phase >= .flying ? 1 : 0, delta: CGSize(width: to.x - from.x, height: to.y - from.y)))
            .opacity(phase < .lifted || phase == .clearing || source == .zero ? 0 : 1)
    }

    // MARK: Timeline

    private func step(_ p: Phase, _ a: Animation) { withAnimation(a) { phase = p } }

    private func run() async {
        guard !reduceMotion else { phase = .landed; return }
        while !Task.isCancelled {
            phase = .rest
            try? await Task.sleep(for: .seconds(1.2))
            step(.pressed, OBMotion.fast)
            try? await Task.sleep(for: .seconds(0.18))
            step(.picked, OBMotion.moderate)
            try? await Task.sleep(for: .seconds(0.45))
            step(.lifted, OBMotion.moderate)
            try? await Task.sleep(for: .seconds(0.3))
            step(.flying, .timingCurve(0.5, 0, 0.2, 1, duration: 0.7))
            try? await Task.sleep(for: .seconds(0.62))
            step(.landed, OBMotion.land)
            try? await Task.sleep(for: .seconds(2.8))
            step(.clearing, .easeIn(duration: 0.3))
            try? await Task.sleep(for: .seconds(0.5))
        }
    }
}

/// Moves a view along a quadratic arc that peaks above both ends, so the copy lifts over the cards
/// instead of sliding across them.
private struct Arc: GeometryEffect {
    var travel: CGFloat
    var delta: CGSize

    var animatableData: CGFloat {
        get { travel }
        set { travel = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let t = travel, u = 1 - t
        let control = CGPoint(x: delta.width * 0.45, y: min(0, delta.height) - 70)
        let x = 2 * u * t * control.x + t * t * delta.width
        let y = 2 * u * t * control.y + t * t * delta.height
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}

private extension View {
    /// A white card floating over the cobalt: a tinted soft shadow for height, a tight one for contact,
    /// and a 1 pt top light.
    func cardSurface(radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background(.white, in: shape)
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white, .white.opacity(0.3)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: cobaltInk.opacity(0.5), radius: 36, y: 22)
            .shadow(color: cobaltInk.opacity(0.3), radius: 5, y: 3)
            .environment(\.colorScheme, .light)
    }
}
