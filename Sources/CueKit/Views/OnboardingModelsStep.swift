import SwiftUI

extension OnboardingView {
    var modelsControls: some View {
        OnboardingModels(model: model, primary: $stepPrimary) {
            advance()
        }
    }

    /// The chosen model at work: one copied message, and the phone number in it landing in the Phone
    /// field. The pill follows the picker's live selection.
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

    private enum Phase { case rest, asking, landed }

    private static let phone = "+44 7700 900123"
    private static let phoneInMessage = phone.replacingOccurrences(of: " ", with: "\u{00A0}")

    let pick: Pick
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Phase = .landed

    private var still: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OB_STILL"] != nil { return true }
        #endif
        return reduceMotion
    }

    var body: some View {
        VStack(spacing: 18) {
            source
            badge
            window
        }
        .frame(width: 372)
        .offset(y: -24)
        .accessibilityHidden(true)
        .task(id: still) {
            guard !still else { phase = .landed; return }
            phase = .rest
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1300))
                await go(OBMotion.moderate, 800) { phase = .asking }
                await go(OBMotion.land, 3200) { phase = .landed }
                await go(OBMotion.exit, 0) { phase = .rest }
            }
        }
    }

    private func go(_ animation: Animation, _ ms: Int, _ change: () -> Void) async {
        withAnimation(animation, change)
        try? await Task.sleep(for: .milliseconds(ms))
    }

    private static let ink = Color(red: 0.01, green: 0.05, blue: 0.3)

    /// A solid white card on the cobalt, lifted by the stage ink: the same card the other steps use.
    private func lifted<S: Shape>(_ shape: S) -> some View {
        shape.fill(.white)
            .shadow(color: Self.ink.opacity(0.28), radius: 3, y: 2)
            .shadow(color: Self.ink.opacity(0.32), radius: 28, y: 16)
    }

    // MARK: Source clip

    private var source: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "message.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color(red: 0.19, green: 0.78, blue: 0.35).gradient,
                                in: RoundedRectangle(cornerRadius: 5.2, style: .continuous))
                Text("Mira Okonkwo")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("Copied 2m ago")
                    .font(.system(size: 11))
                    .foregroundStyle(OBTheme.textTertiary)
            }
            Text(message)
                .font(.system(size: 13.5))
                .foregroundStyle(OBTheme.textPrimary)
                .lineSpacing(3)
                .contentTransition(.opacity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 372, alignment: .leading)
        .background { lifted(RoundedRectangle(cornerRadius: 16, style: .continuous)) }
        .environment(\.colorScheme, .light)
    }

    private var message: AttributedString {
        let lead = AttributedString("Reach Mira at mira@northwind.co or call ")
        var number = AttributedString(Self.phoneInMessage)
        if phase != .rest {
            number.backgroundColor = OBTheme.highlight
            number.foregroundColor = OBTheme.highlightText
        }
        return lead + number + AttributedString(". Site: northwind.co/mira")
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
            VStack(spacing: 8) {
                field("Email", value: "mira@northwind.co", focused: false)
                field("Phone", value: phase == .landed ? Self.phone : nil, focused: true)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            Spacer(minLength: 0)
        }
        .frame(width: 372, height: 146)
        .background { lifted(RoundedRectangle(cornerRadius: 16, style: .continuous)) }
        .environment(\.colorScheme, .light)
    }

    private func field(_ label: String, value: String?, focused: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(OBTheme.textTertiary)
                .frame(width: 58, alignment: .leading)
            ZStack(alignment: .leading) {
                if let value {
                    Text(value)
                        .font(.system(size: 13.5))
                        .foregroundStyle(OBTheme.textPrimary)
                        .transition(.opacity.combined(with: .offset(y: 5)))
                } else if focused {
                    Capsule().fill(OBTheme.action).frame(width: 1.5, height: 16)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(focused ? Color.white : OBTheme.insetFill, in: shape)
        .overlay(shape.strokeBorder(focused ? OBTheme.action : OBTheme.separator, lineWidth: focused ? 1.5 : 0.5))
        .shadow(color: OBTheme.action.opacity(focused ? 0.3 : 0), radius: 6)
    }

    // MARK: Model pill

    private var badge: some View {
        HStack(spacing: 7) {
            Image(systemName: pick.symbol).font(.system(size: 10, weight: .semibold))
            Text(pick.name).font(.system(size: 12, weight: .semibold))
            Text(pick.detail).font(.system(size: 11)).opacity(0.75)
            Group {
                switch phase {
                case .rest: Color.clear
                case .asking:
                    Image(systemName: "ellipsis").font(.system(size: 11, weight: .bold))
                        .symbolEffect(.variableColor.iterative)
                case .landed: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                }
            }
            .frame(width: 14)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background(.white.opacity(0.2), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.4), lineWidth: 0.5))
    }
}
