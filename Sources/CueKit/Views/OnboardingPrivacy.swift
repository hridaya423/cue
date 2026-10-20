import SwiftUI

extension OnboardingView {
    /// Locality from the real endpoint, not the conservative mayBeRemote —
    /// a loopback custom endpoint is local.
    var privacyIsRemote: Bool {
        switch settings.provider {
        case .jevDirect, .jevGateway: true
        case .local, .off: false
        case .custom: model.makeProvider()?.isRemote ?? false
        }
    }

    var privacyControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            PrivacyCard(on: redactionToggle, tokens: privacyTokens, status: { redactorLine })
            if settings.piiRedaction != nil {
                Button("Use automatic setting") { settings.piiRedaction = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(OBTheme.textTertiary)
            }
        }
        .task(id: model.redactor.status) {
            if model.redactor.status == .ready {
                redactedSample = try? await model.redactor.redact(Self.privacySample)
            }
        }
    }

    /// The real redactor's placeholders when it has run, else the labeled static pair.
    var privacyTokens: [String] { Self.orderedPlaceholders(in: redactedSample, count: 2) ?? ["[GIVEN_NAME_1]", "[EMAIL_1]"] }

    static let privacySample = "Send the launch brief to Mira at mira@example.com."

    var privacyStage: some View {
        PrivacyDemo(masked: settings.effectivePIIRedaction, tokens: privacyTokens, lean: lean)
    }

    /// Placeholders in reading order, only when the sample yields exactly `count` of them.
    static func orderedPlaceholders(in text: String?, count: Int) -> [String]? {
        guard let text else { return nil }
        let found = text.matches(of: /\[[A-Z0-9_]+\]/).map { String($0.output) }
        return found.count == count ? found : nil
    }

    @ViewBuilder
    var redactorLine: some View {
        switch model.redactor.status {
        case .idle:
            EmptyView()
        case .downloading(let f):
            HStack(spacing: 10) {
                ProgressView(value: f).frame(width: 120)
                Text("Getting the redaction model… \(Int(f * 100))%")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(OBTheme.textSecondary)
                    .monospacedDigit()
            }
        case .ready:
            Label("Redaction ready", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.green)
        case .failed(let msg):
            Label("Download failed — \(msg)", systemImage: "xmark.circle.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.red)
        }
    }

    /// The tri-state: toggling writes an explicit override; auto is shown as
    /// the current effective value.
    var redactionToggle: Binding<Bool> {
        Binding(
            get: { settings.effectivePIIRedaction },
            set: { settings.piiRedaction = $0 }
        )
    }

    /// Privacy primary: remote + redaction-on-but-model-missing gates on
    /// "Set up redaction" / "Downloading…" / "Retry download".
    var privacyPrimary: OBPrimary {
        guard privacyIsRemote, settings.effectivePIIRedaction else {
            return OBPrimary(title: "Continue") { advance() }
        }
        switch model.redactor.status {
        case .ready:
            return OBPrimary(title: "Continue") { advance() }
        case .downloading:
            return OBPrimary(title: "Downloading…", enabled: false)
        case .failed:
            return OBPrimary(title: "Retry download") {
                Task { await model.redactor.prepare() }
            }
        case .idle:
            return OBPrimary(title: "Set up redaction") {
                Task { await model.redactor.prepare() }
            }
        }
    }

}


// MARK: - Hero toggle card

/// The one decision on this screen, as the left column's hero: a large switch, a blue "on" state, and the
/// two details it hides shown as before → after.
struct PrivacyCard<Status: View>: View {
    @Binding var on: Bool
    let tokens: [String]
    @ViewBuilder var status: Status

    private let details = ["Mira", "mira@example.com"]
    private let amber = Color(red: 0.86, green: 0.52, blue: 0.04)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: on ? "eye.slash.fill" : "eye.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(on ? AnyShapeStyle(OBTheme.actionGradient) : AnyShapeStyle(OBTheme.textTertiary.opacity(0.7)),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hide names and emails")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(OBTheme.textPrimary)
                    Text("Hosted models see placeholders. What you paste keeps its original text.")
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .foregroundStyle(OBTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("Hide names and emails from hosted models", isOn: $on)
                    .labelsHidden()
                    .toggleStyle(BigSwitch())
            }
            .padding(16)
            Rectangle().fill(on ? OBTheme.selectionStroke.opacity(0.6) : OBTheme.separator).frame(height: 0.75)
            VStack(spacing: 10) {
                ForEach(0..<2, id: \.self) { i in row(i) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            Rectangle().fill(on ? OBTheme.selectionStroke.opacity(0.6) : OBTheme.separator).frame(height: 0.75)
            status
                .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
        }
        .background(on ? OBTheme.selectionFill : OBTheme.insetFill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(on ? OBTheme.action.opacity(0.55) : OBTheme.separator, lineWidth: on ? 1.5 : 0.75))
        .shadow(color: OBTheme.action.opacity(on ? 0.16 : 0), radius: 16, y: 6)
        .animation(.easeOut(duration: 0.2), value: on)
    }

    private func row(_ i: Int) -> some View {
        HStack(spacing: 10) {
            Text(details[i])
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(OBTheme.highlightText)
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(OBTheme.highlight, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Image(systemName: on ? "arrow.right" : "eye.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(on ? OBTheme.textTertiary : amber)
            if on {
                Text(tokens[i])
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(OBTheme.mark)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(OBTheme.action.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Text("Visible to the model")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(amber)
            }
            Spacer(minLength: 0)
        }
    }
}

/// A large switch: primary blue when on, so the state reads from across the room.
private struct BigSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Capsule()
                .fill(configuration.isOn ? OBTheme.action : OBTheme.inputStroke.opacity(0.6))
                .frame(width: 58, height: 34)
                .overlay {
                    Circle().fill(.white)
                        .frame(width: 28, height: 28)
                        .shadow(color: .black.opacity(0.28), radius: 2, y: 1)
                        .offset(x: configuration.isOn ? 12 : -12)
                }
                .animation(.spring(duration: 0.3, bounce: 0.12), value: configuration.isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(OBPressStyle())
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

// MARK: - Live demo

/// One copied line, on its way to the hosted model. After a rest the name and then the email turn into
/// placeholders. Off means the same line stays as written and the two details are ringed in amber. State
/// driven with no clock: nothing ticks between plays, and the line fades out before each replay.
struct PrivacyDemo: View {
    let masked: Bool
    let tokens: [String]
    let lean: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var risen = false
    @State private var done = [false, false]

    private static let raws = ["Mira", "mira@example.com"]
    private static let rawFont = NSFont.systemFont(ofSize: 24, weight: .medium)
    private static let maskFont = NSFont.monospacedSystemFont(ofSize: 17, weight: .medium)
    private static let amber = Color(red: 0.86, green: 0.52, blue: 0.04)
    private static let navy = Color(red: 0.01, green: 0.05, blue: 0.25)

    private var still: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OB_STILL"] != nil { return true }
        #endif
        return reduceMotion
    }

    var body: some View {
        VStack(spacing: 20) {
            card
            label
        }
        .opacity(still || shown ? 1 : 0)
        .offset(x: lean * 5, y: still || risen ? 0 : 12)
        .rotation3DEffect(.degrees(Double(-lean) * 3), axis: (0, 1, 0), perspective: 0.5)
        .frame(width: 372, height: 504)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(masked
            ? "Demo: a copied line goes to the hosted model with the name and email replaced by placeholders."
            : "Demo: a copied line goes to the hosted model exactly as written.")
        .task(id: masked) { await run() }
    }

    /// Fade out, snap back unseen, land, rest, flip the name, flip the email, hold.
    private func run() async {
        guard !still else { return }
        while !Task.isCancelled {
            withAnimation(OBMotion.exit) { shown = false }
            try? await Task.sleep(for: .seconds(0.4))
            risen = false
            done = [false, false]
            withAnimation(OBMotion.land) { shown = true; risen = true }
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(OBMotion.moderate) { done[0] = true }
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(OBMotion.moderate) { done[1] = true }
            try? await Task.sleep(for: .seconds(4))
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Send the launch brief")
            HStack(spacing: 0) {
                Text("to ")
                chip(0)
            }
            HStack(spacing: 0) {
                Text("at ")
                chip(1)
                Text(".").padding(.leading, -3)
            }
        }
        .font(.system(size: 24))
        .foregroundStyle(OBTheme.textPrimary)
        .padding(28)
        .frame(width: 372, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Self.navy.opacity(0.5), radius: 30, y: 18)
        .shadow(color: Self.navy.opacity(0.3), radius: 3, y: 1)
    }

    private var label: some View {
        HStack(spacing: 7) {
            Image(systemName: masked ? "cloud.fill" : "exclamationmark.triangle.fill")
            Text(masked ? "Sent to hosted model" : "Sent to hosted model as written")
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(masked ? .white.opacity(0.9) : Color(red: 1.0, green: 0.78, blue: 0.32))
    }

    /// One personal detail: the raw word on a highlight that becomes a placeholder chip, or, off, gains an amber ring.
    private func chip(_ i: Int) -> some View {
        let flipped = masked && (still || done[i])
        let ringed = !masked && (still || done[i])
        let raw = Self.raws[i], mask = tokens[i]
        let w = Self.width(flipped ? mask : raw, flipped ? Self.maskFont : Self.rawFont) + 18
        return ZStack {
            Text(raw)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(OBTheme.highlightText)
                .fixedSize()
                .opacity(flipped ? 0 : 1)
            Text(mask)
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .foregroundStyle(OBTheme.mark)
                .fixedSize()
                .opacity(flipped ? 1 : 0)
        }
        .frame(width: w, height: 38)
        .background(flipped ? OBTheme.action.opacity(0.14) : OBTheme.highlight, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Self.amber, lineWidth: 2).opacity(ringed ? 1 : 0))
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private static func width(_ s: String, _ font: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }
}
