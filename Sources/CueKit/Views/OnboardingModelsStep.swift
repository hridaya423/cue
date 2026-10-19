import SwiftUI

extension OnboardingView {
    var modelsControls: some View {
        OnboardingModels(model: model, primary: $stepPrimary) {
            advance()
        }
    }

    /// The chosen model at work: one copied message, three empty fields, the chooser ranking the clips
    /// for each and the decision landing. The badge follows the picker's live selection.
    var modelsStage: some View {
        ModelsStageScene(pick: ModelsStageChoice.shared.pick)
    }
}

/// The picker's live choice, published for the stage beside it.
@MainActor @Observable
final class ModelsStageChoice {
    static let shared = ModelsStageChoice()
    var pick = ModelsStageScene.Pick(name: ModelCatalog.featured.first?.title ?? "On-device model",
                                     detail: "On this Mac · private", symbol: "lock.fill")
}

struct ModelsStageScene: View {
    struct Pick: Equatable {
        var name: String
        var detail: String
        var symbol: String
    }

    private enum Phase { case idle, asking, ranked }

    private struct Row: Identifiable {
        let id: Int
        let app: App
        let text: String
        let age: String
    }

    private enum App {
        case messages, mail, notes
        var symbol: String { switch self { case .messages: "message.fill"; case .mail: "envelope.fill"; case .notes: "note.text" } }
        var tint: Color {
            switch self {
            case .messages: Color(red: 0.19, green: 0.78, blue: 0.35)
            case .mail: Color(red: 0.16, green: 0.50, blue: 1.0)
            case .notes: Color(red: 0.98, green: 0.76, blue: 0.16)
            }
        }
    }

    private struct Beat {
        let label: String
        let value: String
        let hit: Int
        let rows: [Row]
    }

    private static let whole = "Reach Mira at mira@northwind.co or +44 7700 900123 …"
    private static let beats: [Beat] = [
        Beat(label: "Email", value: "mira@northwind.co", hit: 2, rows: [
            Row(id: 0, app: .messages, text: whole, age: "Messages · 2m"),
            Row(id: 1, app: .mail, text: "j.okafor@lumen.io", age: "Mail · 1h"),
            Row(id: 2, app: .messages, text: "mira@northwind.co", age: "Messages · 2m"),
        ]),
        Beat(label: "Phone", value: "+44 7700 900123", hit: 1, rows: [
            Row(id: 0, app: .notes, text: "Order #A-20417 · shipped Tue", age: "Notes · 1d"),
            Row(id: 1, app: .messages, text: "+44 7700 900123", age: "Messages · 2m"),
            Row(id: 2, app: .messages, text: whole, age: "Messages · 2m"),
        ]),
        Beat(label: "Website", value: "northwind.co/mira", hit: 2, rows: [
            Row(id: 0, app: .mail, text: "j.okafor@lumen.io", age: "Mail · 1h"),
            Row(id: 1, app: .notes, text: "Order #A-20417 · shipped Tue", age: "Notes · 1d"),
            Row(id: 2, app: .messages, text: "northwind.co/mira", age: "Messages · 2m"),
        ]),
    ]

    let pick: Pick
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var focus: Int? = 0
    @State private var filled = 0
    @State private var phase: Phase = .idle

    var body: some View {
        ZStack(alignment: .topLeading) {
            source.offset(x: 22, y: 0)
            window.offset(x: 44, y: 134)
            badge.frame(width: 452).offset(y: 100)
            if let i = focus, phase != .idle {
                chooser(i)
                    .id(i)
                    .offset(x: 60, y: 338)
                    .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }
        }
        .frame(width: 452, height: 560, alignment: .topLeading)
        .accessibilityHidden(true)
        .task(id: reduceMotion) {
            guard !reduceMotion else {
                (focus, filled, phase) = (2, 2, .ranked)
                return
            }
            (focus, filled, phase) = (0, 0, .idle)
            while !Task.isCancelled {
                for i in Self.beats.indices {
                    await go(500) { focus = i }
                    await go(900) { phase = .asking }
                    await go(1100) { phase = .ranked }
                    await go(500) { phase = .idle; filled = i + 1 }
                }
                await go(1800) { focus = nil }
                await go(500) { filled = 0 }
            }
        }
    }

    private func go(_ ms: Int, _ change: () -> Void) async {
        withAnimation(.spring(duration: 0.4, bounce: 0.1), change)
        try? await Task.sleep(for: .milliseconds(ms))
    }

    // MARK: Source clip

    private var source: some View {
        let active = phase == .ranked ? focus : nil
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                tile(.messages, 20)
                Text("Mira Okonkwo")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("Copied 2m ago")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Text(message(active: active))
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 360, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 0.5))
        .shadow(color: shadow.opacity(0.3), radius: 18, y: 10)
    }

    private func message(active: Int?) -> AttributedString {
        let parts: [(String, Int?)] = [
            ("Reach Mira at ", nil), ("mira@northwind.co", 0), (" or call ", nil),
            ("+44 7700 900123", 1), (" — site: ", nil), ("northwind.co/mira", 2),
        ]
        var out = AttributedString()
        for (s, span) in parts {
            var a = AttributedString(s)
            if let span, span == active {
                a.backgroundColor = OBTheme.highlight
                a.foregroundColor = OBTheme.highlightText
            }
            out += a
        }
        return out
    }

    // MARK: Target window

    private var window: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.79, blue: 0.26)], id: \.self) {
                    Circle().fill($0).frame(width: 10, height: 10)
                }
                Spacer()
                Text("New contact")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(OBTheme.textSecondary)
                Spacer()
                Color.clear.frame(width: 46, height: 1)
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            VStack(spacing: 9) {
                ForEach(Array(Self.beats.enumerated()), id: \.offset) { i, beat in field(i, beat) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            Spacer(minLength: 0)
        }
        .frame(width: 384, height: 192)
        .background(OBTheme.canvas, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(OBTheme.separator, lineWidth: 0.5))
        .shadow(color: shadow.opacity(0.45), radius: 28, y: 16)
    }

    private func field(_ i: Int, _ beat: Beat) -> some View {
        let focused = focus == i
        let done = i < filled
        return HStack(spacing: 10) {
            Text(beat.label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OBTheme.textTertiary)
                .frame(width: 58, alignment: .leading)
            ZStack(alignment: .leading) {
                if done {
                    Text(beat.value)
                        .font(.system(size: 13.5))
                        .foregroundStyle(OBTheme.textPrimary)
                        .transition(.opacity.combined(with: .offset(y: 5)))
                } else if focused {
                    Capsule().fill(OBTheme.action).frame(width: 1.5, height: 16)
                }
            }
            Spacer(minLength: 0)
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(red: 0.19, green: 0.7, blue: 0.4))
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(OBTheme.inputFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(focused ? OBTheme.action : OBTheme.inputStroke.opacity(0.45), lineWidth: focused ? 1.5 : 0.5))
        .shadow(color: OBTheme.action.opacity(focused ? 0.3 : 0), radius: 6)
    }

    // MARK: The chooser, as the HUD draws it

    private func chooser(_ i: Int) -> some View {
        let beat = Self.beats[i]
        let ranked = phase == .ranked
        let rows = ranked ? [beat.rows[beat.hit]] + beat.rows.filter { $0.id != beat.hit } : beat.rows
        return VStack(alignment: .leading, spacing: 0) {
                Text("Paste into \(beat.label)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
                VStack(spacing: 2) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { n, r in row(n, r, selected: ranked && n == 0) }
                }
                .padding(.horizontal, 6)
                Divider().opacity(0.5).padding(.top, 4)
                HStack(spacing: 4) {
                    keycap("↩"); Text("paste")
                    keycap("esc").padding(.leading, 6); Text("plain paste")
                    Spacer()
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }
            .frame(width: 352)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(OBTheme.canvas.opacity(0.95))
            }
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(OBTheme.separator.opacity(0.8), lineWidth: 0.5))
            .shadow(color: shadow.opacity(0.4), radius: 22, y: 12)
    }

    private func row(_ n: Int, _ r: Row, selected: Bool) -> some View {
        HStack(spacing: 9) {
            tile(r.app, 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? .white : OBTheme.textPrimary)
                    .lineLimit(1)
                Text(r.age)
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? .white.opacity(0.8) : OBTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Text("\(n + 1)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? .white : OBTheme.textSecondary)
                .frame(width: 18, height: 18)
                .background(selected ? .white.opacity(0.22) : OBTheme.textPrimary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(selected ? OBTheme.action : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var badge: some View {
        HStack(spacing: 7) {
            Image(systemName: pick.symbol).font(.system(size: 10, weight: .semibold))
            Text(pick.name).font(.system(size: 12, weight: .semibold))
            Text(pick.detail).font(.system(size: 11)).opacity(0.7)
            Group {
                if phase == .ranked {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                } else if phase == .asking {
                    Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold))
                        .symbolEffect(.variableColor.iterative, isActive: phase == .asking)
                }
            }
            .frame(width: 14)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background(.white.opacity(0.18), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5))
    }

    // MARK: Pieces

    private var shadow: Color { Color(red: 0.02, green: 0.07, blue: 0.32) }

    private func tile(_ app: App, _ size: CGFloat) -> some View {
        Image(systemName: app.symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(app.tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }

    private func keycap(_ s: String) -> some View {
        Text(s)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 3.5, style: .continuous))
    }
}
