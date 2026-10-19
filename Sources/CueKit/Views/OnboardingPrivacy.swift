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
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hide names and emails")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OBTheme.textPrimary)
                    Text("Hosted models see placeholders. The detail you paste keeps its original text.")
                        .font(.system(size: 13))
                        .lineSpacing(2)
                        .foregroundStyle(OBTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("Hide names and emails from hosted models", isOn: redactionToggle)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            .padding(16)
            .background(OBTheme.insetFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(OBTheme.separator, lineWidth: 0.75))
            redactorLine
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

    static let privacySample = "Send the launch brief to Mira at mira@example.com."

    /// The live demo: the real redactor's placeholders when it has run, else the labeled static pair.
    var privacyStage: some View {
        PrivacyDemo(masked: settings.effectivePIIRedaction,
                    tokens: Self.orderedPlaceholders(in: redactedSample, count: 2) ?? ["[NAME]", "[EMAIL]"],
                    lean: lean)
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
            HStack(spacing: 8) {
                ProgressView(value: f).frame(width: 120)
                Text("Getting the redaction model… \(Int(f * 100))%")
                    .font(.system(size: 12)).foregroundStyle(OBTheme.textSecondary)
                    .monospacedDigit()
            }
        case .ready:
            Label("Redaction ready", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12)).foregroundStyle(.green)
        case .failed(let msg):
            Label("Download failed — \(msg)", systemImage: "xmark.circle")
                .font(.system(size: 12)).foregroundStyle(.red)
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

// MARK: - Live demo

/// The message leaving the Mac: raw on the left-hand card, then a mask beam sweeps the outgoing copy and
/// each personal detail flips to its placeholder. Off means the beam never runs and the raw text goes out.
/// Every frame is a pure function of one clock `t`; the clock only ticks while a play is running, then
/// the timeline pauses and the settled scene is drawn until the next replay.
struct PrivacyDemo: View {
    let masked: Bool
    let tokens: [String]
    let lean: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var playStart: Date?
    @State private var firstPlay = true

    private static let total = 4.6
    private static let raws = ["Mira", "mira@example.com"]
    private static let ink = Color(red: 0.09, green: 0.10, blue: 0.12)
    private static let coral = Color(red: 0.97, green: 0.75, blue: 0.70)
    private static let amber = Color(red: 1.0, green: 0.78, blue: 0.32)
    private static let navy = Color(red: 0.02, green: 0.08, blue: 0.35)
    private static let rawFont = NSFont.systemFont(ofSize: 17, weight: .medium)
    private static let maskFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: playStart == nil)) { tl in
            scene(frame(at: playStart.map { tl.date.timeIntervalSince($0) }))
        }
        .rotation3DEffect(.degrees(Double(-lean) * 5), axis: (0, 1, 0), perspective: 0.5)
        .frame(width: 372)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(masked
            ? "Demo: the copied message leaves your Mac with the name and email replaced by placeholders."
            : "Demo: the copied message leaves your Mac exactly as written.")
        .task(id: masked) { await run() }
    }

    /// Plays on appearance and whenever the toggle flips, then rests before the next pass.
    private func run() async {
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            playStart = Date()
            try? await Task.sleep(for: .seconds(firstPlay ? Self.total : Self.total - 0.6))
            playStart = nil
            firstPlay = false
            try? await Task.sleep(for: .seconds(5))
        }
    }

    // MARK: Clock

    private struct Frame { var t: Double; var fade: Double }

    /// First pass runs the entrance; replays fade the outgoing copy out, then rejoin just before it arrives.
    private func frame(at elapsed: Double?) -> Frame {
        guard let e = elapsed else { return Frame(t: Self.total, fade: 1) }
        if firstPlay { return Frame(t: min(e, Self.total), fade: 1) }
        if e < 0.3 { return Frame(t: Self.total, fade: 1 - e / 0.3) }
        return Frame(t: min(0.9 + (e - 0.3), Self.total), fade: 1)
    }

    private func ramp(_ t: Double, _ from: Double, _ len: Double) -> Double {
        let x = min(max((t - from) / len, 0), 1)
        return x * x * (3 - 2 * x)
    }

    // MARK: Scene

    private func scene(_ f: Frame) -> some View {
        let t = f.t
        let enter = ramp(t, 0, 0.5)
        let arrive = ramp(t, 1.0, 0.4) * f.fade
        let node = ramp(t, 3.5, 0.4) * f.fade
        return VStack(spacing: 0) {
            sourceCard
                .opacity(enter)
                .offset(x: lean * -5, y: (1 - enter) * 14)
            rail(t: t, start: 0.35, color: Self.coral, height: 52)
            outgoingCard(t: t, arrive: arrive)
                .offset(x: lean * 6)
            rail(t: t, start: 3.0, color: masked ? .white : Self.amber, height: 40)
            modelPill
                .opacity(node)
                .scaleEffect(0.96 + 0.04 * node)
                .offset(y: (1 - node) * 6)
        }
        .background(alignment: .center) {
            Ellipse()
                .fill(RadialGradient(colors: [.white.opacity(0.22), .clear], center: .center, startRadius: 0, endRadius: 240))
                .frame(width: 520, height: 520)
                .allowsHitTesting(false)
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            header("On your Mac", icon: "laptopcomputer", tint: Self.ink.opacity(0.5))
            message(flips: [0, 0], textColor: Self.ink, exposed: false)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.97), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Self.navy.opacity(0.45), radius: 30, y: 18)
        .shadow(color: Self.navy.opacity(0.25), radius: 3, y: 1)
    }

    private func outgoingCard(t: Double, arrive: Double) -> some View {
        let beamStart = 1.55, beamLen = 1.35
        let u = (t - beamStart) / beamLen
        // The beam crosses line one at ~26% of its travel and line two at ~72%; each detail flips as it passes.
        let flips = masked ? [ramp(t, beamStart + beamLen * 0.26, 0.35), ramp(t, beamStart + beamLen * 0.72, 0.35)] : [0, 0]
        let swept = masked && t > beamStart + beamLen * 0.9
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                header("Leaving your Mac", icon: "arrow.up.right", tint: .white.opacity(0.6))
                Spacer()
                statusPill(swept: swept || (masked && t >= Self.total))
            }
            message(flips: flips, textColor: .white.opacity(0.94), exposed: !masked)
                .opacity(arrive)
                .offset(y: (1 - arrive) * 8)
                .overlay(alignment: .top) { if masked { beam(u: u) } }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.05, green: 0.09, blue: 0.26), Color(red: 0.02, green: 0.04, blue: 0.16)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        }
        .shadow(color: Self.navy.opacity(0.55), radius: 34, y: 20)
    }

    private var modelPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "cloud.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            Text("Hosted model").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            Text(masked ? "Names and emails stay here" : "Sees names and emails")
                .font(.system(size: 12)).foregroundStyle(masked ? .white.opacity(0.75) : Self.amber)
        }
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(.white.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.32), lineWidth: 0.75))
    }

    private func header(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(title).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(tint)
    }

    private func statusPill(swept: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: masked ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
            Text(masked ? (swept ? "Masked by Cue" : "Masking…") : "Sent as written")
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(masked ? .white : Self.amber)
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background((masked ? Color.white : Self.amber).opacity(0.14), in: Capsule())
    }

    // MARK: Message

    private func message(flips: [Double], textColor: Color, exposed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text("Send the launch brief to ")
                chip(0, flip: flips[0], exposed: exposed)
            }
            HStack(spacing: 0) {
                Text("at ")
                chip(1, flip: flips[1], exposed: exposed)
                Text(".")
            }
        }
        .font(.system(size: 17))
        .foregroundStyle(textColor)
        .lineLimit(1)
        .fixedSize()
        .frame(width: 336, alignment: .leading)
    }

    /// One personal detail: the raw word on a coral chip that turns about its x-axis into a placeholder chip.
    private func chip(_ i: Int, flip f: Double, exposed: Bool) -> some View {
        let raw = Self.raws[i], mask = tokens[i]
        let rw = Self.width(raw, Self.rawFont), mw = Self.width(mask, Self.maskFont)
        let w = (rw + (mw - rw) * f).rounded() + 14
        return ZStack {
            Text(raw)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Self.ink)
                .fixedSize()
                .frame(width: w, height: 28)
                .background(Self.coral, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: Self.amber.opacity(exposed ? 0.55 : 0), radius: 9)
                .rotation3DEffect(.degrees(f * 180), axis: (1, 0, 0), perspective: 0.6)
                .opacity(f < 0.5 ? 1 : 0)
            Text(mask)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .fixedSize()
                .frame(width: w, height: 28)
                .background(Color(red: 0.14, green: 0.44, blue: 0.98).opacity(0.55), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.45), lineWidth: 0.75))
                .rotation3DEffect(.degrees((f - 1) * 180), axis: (1, 0, 0), perspective: 0.6)
                .opacity(f >= 0.5 ? 1 : 0)
        }
        .frame(width: w, height: 28)
        .shadow(color: .white.opacity(0.9 * sin(.pi * f)), radius: 12)
    }

    private static func width(_ s: String, _ font: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    // MARK: Beam and rails

    /// The mask line sweeping the outgoing copy top to bottom: bright core, wide glow, a Cue shield at its tip.
    private func beam(u: Double) -> some View {
        let travel: CGFloat = 78
        let y = -8 + travel * CGFloat(min(max(u, 0), 1))
        let o = min(1, max(0, u + 0.1) * 6, max(0, 1.1 - u) * 6)
        return ZStack(alignment: .trailing) {
            Rectangle()
                .fill(LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 2)
                .shadow(color: .white, radius: 6)
                .shadow(color: Color(red: 0.3, green: 0.6, blue: 1), radius: 14)
            Image(systemName: "shield.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(red: 0.08, green: 0.38, blue: 0.93))
                .frame(width: 22, height: 22)
                .background(.white, in: Circle())
                .shadow(color: .white.opacity(0.8), radius: 8)
                .padding(.trailing, 14)
        }
        .padding(.horizontal, -18)
        .offset(y: y)
        .opacity(o)
        .allowsHitTesting(false)
    }

    /// A hairline wire with packets of text sliding down it.
    private func rail(t: Double, start: Double, color: Color, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.white.opacity(0.28)).frame(width: 1.5)
            ForEach(0..<3, id: \.self) { k in
                let u = (t - start - Double(k) * 0.14) / 0.6
                let o = min(1, max(0, u) * 5, max(0, 1 - u) * 5)
                Capsule().fill(color)
                    .frame(width: 5, height: 16)
                    .shadow(color: color.opacity(0.9), radius: 6)
                    .offset(y: CGFloat(min(max(u, 0), 1)) * (height - 16))
                    .opacity(u > 0 && u < 1 ? o : 0)
            }
        }
        .frame(width: 8, height: height)
    }
}
