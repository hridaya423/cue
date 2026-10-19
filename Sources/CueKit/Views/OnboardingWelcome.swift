import SwiftUI

extension OnboardingView {
    /// The hero: the mark, the film's line, one action, and one paste happening on its own.
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
                Text("Copy it all. Cue pastes just the part that fits the field.")
                    .font(.system(size: 18))
                    .foregroundStyle(.white.opacity(0.82))
                    .padding(.top, 12)
                    .reveal(shown, delay: 0.25, dy: 12)
                OBStagePrimary(title: primary.title, enabled: primary.enabled, action: primary.action)
                    .padding(.top, 24)
                    .reveal(shown, delay: 0.35, dy: 10)
                PasteMoment(lean: lean)
                    .frame(width: 600, height: 250, alignment: .top)
                    .padding(.top, 30)
                    .reveal(shown, delay: 0.45, dy: 40)
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
            RadialGradient(colors: [.white.opacity(0.28), .clear], center: .init(x: 0.5, y: 0.2), startRadius: 0, endRadius: 360)
            RadialGradient(colors: [.clear, cobaltInk.opacity(0.55)], center: .init(x: 0.5, y: 0.45), startRadius: 260, endRadius: 640)
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

/// A copied message above a contact form. The email lifts out of the message as a chip, flies across
/// and lands in the Email field. Loops; never touches the clipboard. Idle between steps: the animation
/// is a handful of state changes, no frame clock.
struct PasteMoment: View {
    var lean: CGFloat = 0
    @State private var phase = Phase.rest
    @State private var source = CGRect.zero
    @State private var target = CGRect.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Phase: Int { case rest, picked, lifted, flying, landed }

    private static let email = "mira@example.com"
    private static let chipPad: CGFloat = 4

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
        VStack(alignment: .leading, spacing: 8) {
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
                        .opacity(phase.rawValue >= Phase.picked.rawValue ? 0 : 1)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(demoSpace)) } action: { source = $0 }
                }
                Text("or +44 7700 900123.")
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.black.opacity(phase == .landed ? 0.32 : 0.86))
            .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(width: 336, height: 112, alignment: .leading)
        .cardSurface(radius: 18)
        .scaleEffect(phase == .landed ? 0.975 : 1, anchor: .bottomLeading)
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
                field("Email", value: nil, focused: true)
                field("Phone", value: nil, focused: false)
                field("Company", value: nil, focused: false)
            }
            .padding(16)
        }
        .frame(width: 294, alignment: .topLeading)
        .cardSurface(radius: 18)
        .scaleEffect(phase == .landed ? 1.015 : 1, anchor: .center)
    }

    private func field(_ label: String, value: String?, focused: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.black.opacity(0.45))
            Text(value ?? " ")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.86))
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(OBTheme.action.opacity(phase == .landed ? 1 : 0.55), lineWidth: phase == .landed ? 2 : 1.5)
                            .shadow(color: OBTheme.action.opacity(phase == .landed ? 0.4 : 0), radius: 6)
                    }
                }
                .overlay(alignment: .trailing) {
                    if focused, phase == .landed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(OBTheme.action)
                            .padding(.trailing, 9)
                            .transition(.scale(scale: 0.5).combined(with: .opacity))
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(demoSpace)) } action: { if focused { target = $0 } }
        }
    }

    private var keycap: some View {
        HStack(spacing: 4) {
            key("⌘")
            key("V")
        }
        .scaleEffect(phase == .flying ? 0.9 : 1)
        .opacity(phase == .rest ? 0.7 : 1)
    }

    private func key(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 22)
            .background(.white.opacity(phase == .flying ? 0.34 : 0.16), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.3)))
    }

    // MARK: Chip

    /// The email as a selection pill: it sits over its place in the message, lifts, flies to the field
    /// and dissolves into the field's own text.
    private var chip: some View {
        let pad = Self.chipPad
        let landed = phase == .landed
        let flying = phase == .flying
        let to = CGPoint(x: target.minX + 11 + source.width / 2, y: target.midY)
        let at = flying || landed ? to : CGPoint(x: source.midX, y: source.midY)
        return Text(Self.email)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(landed ? Color.black.opacity(0.86) : chipInk)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, pad)
            .padding(.vertical, 3)
            .background(.white.opacity(landed ? 0 : 1), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(OBTheme.action.opacity(landed || phase == .rest ? 0 : 0.35)))
            .shadow(color: cobaltInk.opacity(phase == .lifted || flying ? 0.4 : 0), radius: phase == .lifted || flying ? 16 : 0, y: phase == .lifted || flying ? 10 : 0)
            .scaleEffect(phase == .lifted ? 1.08 : flying ? 1.04 : 1)
            .position(at)
            .opacity(phase == .rest || source == .zero ? 0 : 1)
    }

    // MARK: Timeline

    private func step(_ p: Phase, _ a: Animation) { withAnimation(a) { phase = p } }

    private func run() async {
        guard !reduceMotion else { phase = .landed; return }
        let snap = Animation.timingCurve(0.23, 1, 0.32, 1, duration: 0.35)
        while !Task.isCancelled {
            phase = .rest
            try? await Task.sleep(for: .seconds(1.4))
            step(.picked, snap)
            try? await Task.sleep(for: .seconds(0.7))
            step(.lifted, .spring(duration: 0.4, bounce: 0.3))
            try? await Task.sleep(for: .seconds(0.35))
            step(.flying, .timingCurve(0.65, 0, 0.2, 1, duration: 0.7))
            try? await Task.sleep(for: .seconds(0.7))
            step(.landed, .spring(duration: 0.5, bounce: 0.25))
            try? await Task.sleep(for: .seconds(3.4))
            step(.rest, .easeInOut(duration: 0.5))
            try? await Task.sleep(for: .seconds(0.7))
        }
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
