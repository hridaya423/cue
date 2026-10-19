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

/// The film's cobalt as a slow, living field: a 3×3 mesh whose inner points drift, with film grain
/// so the gradient never bands. One field sits behind every screen; only its frame changes.
struct CobaltField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private static let colors: [Color] = [
        .init(red: 0.05, green: 0.20, blue: 0.72), .init(red: 0.08, green: 0.32, blue: 0.88), .init(red: 0.12, green: 0.42, blue: 0.95),
        .init(red: 0.07, green: 0.30, blue: 0.86), .init(red: 0.10, green: 0.42, blue: 0.97), .init(red: 0.30, green: 0.55, blue: 1.00),
        .init(red: 0.04, green: 0.17, blue: 0.62), .init(red: 0.09, green: 0.33, blue: 0.90), .init(red: 0.17, green: 0.46, blue: 0.98),
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { tl in
            let t = Float(tl.date.timeIntervalSince(start))
            MeshGradient(width: 3, height: 3, points: Self.points(t), colors: Self.colors)
                .visualEffect { view, proxy in
                    view.colorEffect(ShaderLibrary.bundle(.module).cobaltGrain(.float2(proxy.size), .float(t)))
                }
        }
    }

    private static func points(_ t: Float) -> [SIMD2<Float>] {
        let a = 0.08 * sin(t * 0.21), b = 0.07 * cos(t * 0.17), c = 0.06 * sin(t * 0.13 + 1)
        return [
            [0, 0], [0.5 + a, 0], [1, 0],
            [0, 0.5 + b], [0.5 + c, 0.5 + a], [1, 0.5 - c],
            [0, 1], [0.5 - b, 1], [1, 1],
        ]
    }
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
