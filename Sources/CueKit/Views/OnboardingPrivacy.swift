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

/// A copied note on the left of the glass, the request leaving for the hosted model below it. A mask beam
/// sweeps the request and each personal detail flips to its placeholder. Off means the beam never runs and
/// the raw text goes out. Every frame is a pure function of one clock `t`; the clock only ticks while a play
/// is running, then the timeline pauses and the settled scene is drawn until the next replay.
struct PrivacyDemo: View {
    let masked: Bool
    let tokens: [String]
    let lean: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var playStart: Date?
    @State private var firstPlay = true

    private static let total = 4.6
    private static let beamStart = 1.55
    private static let beamLen = 1.35
    /// `OB_STILL=1` holds the beam mid-sweep: first detail masked, second about to flip.
    private static let stillT = 2.44
    private static let raws = ["Mira", "mira@example.com"]
    private static let ink = Color(red: 0.09, green: 0.10, blue: 0.12)
    private static let coral = Color(red: 0.97, green: 0.75, blue: 0.70)
    private static let amber = Color(red: 1.0, green: 0.78, blue: 0.32)
    private static let navy = Color(red: 0.01, green: 0.05, blue: 0.25)
    private static let rawFont = NSFont.systemFont(ofSize: 16, weight: .medium)
    private static let maskFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)

    private var still: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["OB_STILL"] != nil { return true }
        #endif
        return reduceMotion
    }

    private var holdsMidSweep: Bool {
        #if DEBUG
        return masked && ProcessInfo.processInfo.environment["OB_STILL"] != nil
        #else
        return false
        #endif
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: playStart == nil)) { tl in
            scene(frame(at: playStart.map { tl.date.timeIntervalSince($0) }))
        }
        .rotation3DEffect(.degrees(Double(-lean) * 3), axis: (0, 1, 0), perspective: 0.5)
        .frame(width: 372, height: 504, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(masked
            ? "Demo: a copied note leaves your Mac for the hosted model with the name and email replaced by placeholders."
            : "Demo: a copied note leaves your Mac for the hosted model exactly as written.")
        .task(id: masked) { await run() }
    }

    /// Plays on appearance and whenever the toggle flips, then rests before the next pass.
    private func run() async {
        guard !still else { return }
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
        guard let e = elapsed else { return Frame(t: holdsMidSweep ? Self.stillT : Self.total, fade: 1) }
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
        let arrive = ramp(t, 1.0, 0.45) * f.fade
        let u = (t - Self.beamStart) / Self.beamLen
        // The beam reaches line one at ~30% of its travel and line two at ~76%; each detail flips as it passes.
        let flips = masked
            ? [ramp(t, Self.beamStart + Self.beamLen * 0.3, 0.35), ramp(t, Self.beamStart + Self.beamLen * 0.76, 0.35)]
            : [0, 0]
        let swept = masked && t > Self.beamStart + Self.beamLen * 0.95
        return ZStack(alignment: .topLeading) {
            rail(t: t, start: 0.4, height: 96)
                .offset(x: 92, y: 150)
            note
                .opacity(enter)
                .offset(x: -6 + lean * -4, y: -26 + (1 - enter) * 14)
            maskNode(swept: swept)
                .frame(width: 124)
                .offset(x: 96 - 62, y: 196)
                .opacity(arrive)
            request(t: t, u: u, flips: flips, arrive: arrive)
                .offset(x: 6 + lean * 5, y: 250 + (1 - arrive) * 10)
        }
    }

    // MARK: Source note

    private static let notes = [("Launch brief", "Today"), ("Invoice A-20417", "Tue"), ("Reading list", "Mon"), ("Ideas", "Sep 12")]

    private var note: some View {
        let dark = scheme == .dark
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0.opacity(0.9)).frame(width: 11, height: 11) }
                HStack(spacing: 14) {
                    ForEach(["textformat", "checklist", "tablecells"], id: \.self) { Image(systemName: $0) }
                }
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.leading, 36)
                Spacer()
                Label("Copied", systemImage: "doc.on.doc.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(OBTheme.mark)
                    .padding(.horizontal, 9)
                    .frame(height: 22)
                    .background(OBTheme.action.opacity(0.12), in: Capsule())
                    .padding(.trailing, 22)
            }
            .padding(.leading, 14)
            .frame(height: 38)
            Divider()
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(Self.notes.enumerated()), id: \.offset) { i, n in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(n.0).font(.system(size: 12, weight: .semibold))
                            Text(n.1).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 9)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .background(i == 0 ? Color.yellow.opacity(dark ? 0.28 : 0.4) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
                .padding(7)
                .frame(width: 128)
                .background(.black.opacity(dark ? 0.16 : 0.035))
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    Text("Launch brief").font(.system(size: 20, weight: .bold)).foregroundStyle(.primary)
                        .padding(.bottom, 3)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 0) {
                            Text("Send the launch brief to ")
                            noteMark(Self.raws[0])
                        }
                        HStack(spacing: 0) {
                            Text("at ")
                            noteMark(Self.raws[1])
                            Text(".")
                        }
                    }
                    .font(.system(size: 16))
                    Text("Then book the review for Thursday.").font(.system(size: 16)).foregroundStyle(.tertiary)
                }
                .padding(.leading, 18)
                .padding(.top, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 440, height: 204, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(.white.opacity(dark ? 0.16 : 0.7), lineWidth: 0.75))
        .shadow(color: Self.navy.opacity(0.5), radius: 30, y: 18)
        .shadow(color: Self.navy.opacity(0.3), radius: 3, y: 1)
    }

    private func noteMark(_ s: String) -> some View {
        Text(s)
            .foregroundStyle(OBTheme.highlightText)
            .padding(.horizontal, 5)
            .frame(height: 26)
            .background(OBTheme.highlight, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    // MARK: Request

    private func request(t: Double, u: Double, flips: [Double], arrive: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "cloud.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text("Hosted model").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Spacer(minLength: 8)
                seesPill
            }
            .frame(height: 28)
            Text("POST /v1/systemone")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.top, 8)
            HStack(alignment: .top, spacing: 10) {
                index(1, lit: true)
                message(flips: flips)
            }
            .padding(.top, 14)
            .overlay(alignment: .top) { if masked { beam(u: u) } }
            Rectangle().fill(.white.opacity(0.08)).frame(height: 0.75).padding(.vertical, 14)
            otherRow(2, icon: "note.text", tint: Color(red: 0.98, green: 0.78, blue: 0.2), text: "Order #A-20417 shipped Tue")
            otherRow(3, icon: "message.fill", tint: Color(red: 0.2, green: 0.78, blue: 0.35), text: "northwind.co/launch")
                .padding(.top, 10)
        }
        .padding(.leading, 18)
        .padding(.trailing, 64)
        .padding(.top, 16)
        .frame(width: 444, height: 340, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.06, green: 0.10, blue: 0.29), Color(red: 0.02, green: 0.04, blue: 0.16)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.7), .init(color: .black.opacity(0.08), location: 0.95)],
                             startPoint: .top, endPoint: .bottom))
        .shadow(color: Self.navy.opacity(0.55), radius: 34, y: 20)
        .opacity(arrive)
    }

    private var seesPill: some View {
        HStack(spacing: 5) {
            Image(systemName: masked ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
            Text(masked ? "Sees only placeholders" : "Sees names and emails")
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(masked ? .white : Self.amber)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background((masked ? Color.white : Self.amber).opacity(0.15), in: Capsule())
        .overlay(Capsule().stroke((masked ? Color.white : Self.amber).opacity(0.3), lineWidth: 0.75))
    }

    private func index(_ n: Int, lit: Bool) -> some View {
        Text("\(n)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(lit ? 0.9 : 0.5))
            .frame(width: 22, height: 22)
            .background(.white.opacity(lit ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func otherRow(_ n: Int, icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 10) {
            index(n, lit: false)
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(tint, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text(text).font(.system(size: 14)).foregroundStyle(.white.opacity(0.5))
        }
    }

    /// Cue's shield on the wire: the thing doing the masking.
    private func maskNode(swept: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: masked ? "shield.fill" : "exclamationmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(masked ? OBTheme.action : Color(red: 0.86, green: 0.52, blue: 0.04), in: Circle())
            Text(masked ? (swept ? "Masked by Cue" : "Masking…") : "Not masked")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Self.ink)
        }
        .padding(.leading, 6)
        .padding(.trailing, 12)
        .frame(height: 30)
        .background(.white, in: Capsule())
        .shadow(color: Self.navy.opacity(0.4), radius: 12, y: 5)
    }

    // MARK: Message

    private func message(flips: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text("Send the launch brief to ")
                chip(0, flip: flips[0])
            }
            HStack(spacing: 0) {
                Text("at ")
                chip(1, flip: flips[1])
                Text(".")
            }
        }
        .font(.system(size: 16))
        .foregroundStyle(.white.opacity(0.94))
        .lineLimit(1)
        .fixedSize()
    }

    /// One personal detail: the raw word on a coral chip that turns about its x-axis into a placeholder chip.
    private func chip(_ i: Int, flip f: Double) -> some View {
        let raw = Self.raws[i], mask = tokens[i]
        let rw = Self.width(raw, Self.rawFont), mw = Self.width(mask, Self.maskFont)
        let w = (rw + (mw - rw) * f).rounded() + 14
        return ZStack {
            Text(raw)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Self.ink)
                .fixedSize()
                .frame(width: w, height: 28)
                .background(Self.coral, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: Self.amber.opacity(masked ? 0 : 0.55), radius: 9)
                .rotation3DEffect(.degrees(f * 180), axis: (1, 0, 0), perspective: 0.6)
                .opacity(f < 0.5 ? 1 : 0)
            Text(mask)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
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

    // MARK: Beam and rail

    /// The mask line sweeping the request top to bottom: bright core, wide glow, a Cue shield at its tip.
    private func beam(u: Double) -> some View {
        let travel: CGFloat = 84
        let y = -4 + travel * CGFloat(min(max(u, 0), 1))
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
        }
        .frame(width: 372)
        .padding(.leading, -18)
        .offset(y: y)
        .opacity(o)
        .allowsHitTesting(false)
    }

    /// A hairline wire from the note to the request, with packets of text sliding down it.
    private func rail(t: Double, start: Double, height: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.white.opacity(0.32)).frame(width: 1.5)
            ForEach(0..<3, id: \.self) { k in
                let u = (t - start - Double(k) * 0.14) / 0.7
                let o = min(1, max(0, u) * 5, max(0, 1 - u) * 5)
                Capsule().fill(Self.coral)
                    .frame(width: 5, height: 16)
                    .shadow(color: Self.coral.opacity(0.9), radius: 6)
                    .offset(y: CGFloat(min(max(u, 0), 1)) * (height - 16))
                    .opacity(u > 0 && u < 1 ? o : 0)
            }
        }
        .frame(width: 8, height: height)
    }
}
