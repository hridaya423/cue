import Carbon
import SwiftUI

/// Window geometry for the first-run flow: a split layout (copy and controls on the canvas, a live
/// cobalt stage on the right) and a hero layout where the stage fills the window.
enum OBLayout {
    static let window = CGSize(width: 920, height: 620)
    static let stageWidth: CGFloat = 452
    static var columnWidth: CGFloat { window.width - stageWidth }
    static let margin: CGFloat = 48
    static let footerHeight: CGFloat = 76
}

/// The film's cobalt as a slow dawn: deep ink overhead so white type holds, light rising from the lower
/// right with ice at its core and indigo in the shadows. Neighbouring hues, held off full saturation and
/// blended perceptually so the middle never goes grey. A 4×4 mesh whose inner points drift on unrelated
/// periods, with film grain so the gradient never bands. One field sits behind every screen.
struct CobaltField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let colors: [Color] = [
        .init(red: 0.05, green: 0.06, blue: 0.27), .init(red: 0.07, green: 0.10, blue: 0.42), .init(red: 0.09, green: 0.17, blue: 0.56), .init(red: 0.13, green: 0.26, blue: 0.68),
        .init(red: 0.07, green: 0.09, blue: 0.40), .init(red: 0.11, green: 0.21, blue: 0.70), .init(red: 0.17, green: 0.36, blue: 0.88), .init(red: 0.27, green: 0.50, blue: 0.95),
        .init(red: 0.08, green: 0.12, blue: 0.50), .init(red: 0.15, green: 0.33, blue: 0.88), .init(red: 0.30, green: 0.54, blue: 0.97), .init(red: 0.56, green: 0.74, blue: 0.99),
        .init(red: 0.06, green: 0.08, blue: 0.38), .init(red: 0.14, green: 0.31, blue: 0.84), .init(red: 0.42, green: 0.65, blue: 0.98), .init(red: 0.84, green: 0.90, blue: 1.00),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            let t = Float(tl.date.timeIntervalSince(start))
            MeshGradient(width: 4, height: 4, points: Self.points(t), colors: Self.colors, colorSpace: .perceptual)
                .visualEffect { view, proxy in
                    view.colorEffect(ShaderLibrary.bundle(.module).cobaltGrain(.float2(proxy.size), .float(t)))
                }
        }
    }

    private static func points(_ t: Float) -> [SIMD2<Float>] {
        func w(_ f: Float, _ p: Float, _ a: Float) -> Float { a * sin(t * f + p) }
        let e: Float = 1 / 3, f: Float = 2 / 3
        return [
            [0, 0], [e + w(0.11, 0, 0.06), 0], [f + w(0.09, 1, 0.06), 0], [1, 0],
            [0, e + w(0.10, 2, 0.05)], [e + w(0.13, 0.5, 0.07), e + w(0.08, 1.7, 0.06)],
            [f + w(0.07, 2.4, 0.08), e + w(0.12, 0.3, 0.06)], [1, e + w(0.09, 1.1, 0.05)],
            [0, f + w(0.08, 0.9, 0.05)], [e + w(0.10, 3.1, 0.07), f + w(0.11, 2.2, 0.06)],
            [f + w(0.12, 1.4, 0.07), f + w(0.09, 0.6, 0.06)], [1, f + w(0.11, 2.8, 0.05)],
            [0, 1], [e + w(0.12, 1.9, 0.06), 1], [f + w(0.10, 0.2, 0.06), 1], [1, 1],
        ]
    }
}

/// Three spring speeds for the whole flow, no bounce: the bigger the thing that moves, the slower the
/// spring. `land` is the one settle a scene gets when something arrives.
enum OBMotion {
    static let fast = Animation.spring(duration: 0.2, bounce: 0)
    static let moderate = Animation.spring(duration: 0.35, bounce: 0)
    static let slow = Animation.spring(duration: 0.6, bounce: 0)
    static let land = Animation.spring(duration: 0.45, bounce: 0.12)
    static let exit = Animation.easeIn(duration: 0.2)
}

/// Footer progress: one segment per screen on this user's route, the current one long.
struct OBProgress: View {
    let count: Int
    let index: Int
    var onStage = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i == index ? active : inactive)
                    .frame(width: i == index ? 26 : 10, height: 3)
            }
        }
        .animation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.4), value: index)
        .accessibilityElement()
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }

    private var active: Color { onStage ? .white : OBTheme.action }
    private var inactive: Color { onStage ? .white.opacity(0.3) : OBTheme.textTertiary.opacity(0.3) }
}

/// The one forward action: a white pill on the cobalt stage with the Return key shown inside it.
struct OBStagePrimary: View {
    let title: String
    var enabled = true
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text("↩")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 18)
                    .background(OBTheme.action.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .foregroundStyle(OBTheme.action)
            .padding(.leading, 18)
            .padding(.trailing, 10)
            .frame(height: 38)
            .background(.white, in: Capsule())
            .shadow(color: .black.opacity(hovered ? 0.22 : 0.14), radius: hovered ? 14 : 8, y: hovered ? 6 : 3)
            .offset(y: hovered ? -1 : 0)
            .contentShape(Capsule())
        }
        .buttonStyle(OBPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
        .keyboardShortcut(.defaultAction)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovered = h } }
    }
}

/// Back as a quiet round chevron, the way the Mac's own setup screens do it.
struct OBRoundBack: View {
    var onStage = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(onStage ? .white : OBTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background((onStage ? Color.white : OBTheme.textPrimary).opacity(hovered ? 0.14 : 0.07), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(OBPressStyle())
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovered = h } }
        .accessibilityLabel("Back")
    }
}

struct OBPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Text on the stage: white, with the cobalt's own shadow so it lifts off the moving field.
struct OBStageCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .environment(\.colorScheme, .light)
            .shadow(color: Color(red: 0.02, green: 0.08, blue: 0.35).opacity(0.35), radius: 24, y: 12)
    }
}
