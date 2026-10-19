import SwiftUI

extension OnboardingView {
    var practiceControls: some View {
        Group {
            if let practice { PracticeScreen(practice: practice) }
        }
    }

    var practiceStage: some View {
        Group {
            if let practice { PracticeStage(practice: practice) }
        }
    }

    var practicePrimary: OBPrimary {
        guard let p = practice else { return OBPrimary(title: "Continue", enabled: false) }
        switch p.phase {
        case .intro, .armed, .deciding:
            return .none
        case .succeeded:
            return OBPrimary(title: "Start using Cue") {
                model.settings.onboardingDone = true
                closeWindow()
            }
        case .ordinaryPaste, .uncertain, .failed:
            return OBPrimary(title: "Try again") { p.reset(target: nil) }
        case .lostPermission:
            return OBPrimary(title: "Grant access") { step = .accessibility; leavePractice() }
        case .unavailable:
            // No model yet: the way forward is setting one up, not leaving.
            return OBPrimary(title: "Set up a model") {
                forward = false
                step = .models
                stepPrimary = nil
                leavePractice()
            }
        }
    }

    func enterPractice() {
        let p = OnboardingPractice(model: model)
        p.target = .email
        practice = p
        model.practice = p
    }

    func leavePractice() {
        practice?.cancel()
        model.practice = nil
        practice = nil
    }
}

// MARK: - Left column

/// What the stage can't say: the explanation behind a result, and the second-round buttons.
private struct PracticeScreen: View {
    var practice: OnboardingPractice

    private var succeeded: Bool { if case .succeeded = practice.phase { return true }; return false }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusLine
            if succeeded, practice.round == 0 {
                HStack(spacing: 10) {
                    OBBorderedButton(title: practice.target == .website ? "Try Email" : "Try Website") {
                        practice.reset(target: practice.target == .website ? .email : .website)
                    }
                    OBBorderedButton(title: "Try another") { practice.tryAnother() }
                }
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch practice.phase {
        case .intro:
            note("Preparing your sample…")
        case .armed:
            note("The cursor is already in the field. Click it first if it moved.")
        case .deciding:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Deciding…").font(.system(size: 13)).foregroundStyle(OBTheme.textSecondary)
            }
        case .succeeded:
            note(practice.elapsedMilliseconds.map { "Pasted in \($0) ms. Find Cue in your Mac's menu bar." }
                 ?? "Find Cue in your Mac's menu bar.")
        case .ordinaryPaste(let observed):
            VStack(alignment: .leading, spacing: 6) {
                Text("Cue used ordinary paste this time.")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.orange)
                if !observed.isEmpty, observed != practice.expected {
                    note("The field got the whole message, not the \(practice.target.rawValue.lowercased()).")
                }
            }
        case .uncertain:
            note("Cue wasn't sure which detail to paste.")
        case .failed(let msg):
            Text(msg).font(.system(size: 13)).foregroundStyle(.red)
        case .lostPermission:
            Text("Accessibility access is needed to try this.")
                .font(.system(size: 13)).foregroundStyle(.orange)
        case .unavailable:
            note("Smart paste needs a working model — configure one in Settings anytime.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 13)).lineSpacing(2)
            .foregroundStyle(OBTheme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Stage

/// The arena. The copied message and the real field are white cards on the cobalt; the keycaps light up
/// as the user presses the real shortcut; on success the extracted email lifts out of the message and
/// lands in the field. Nothing runs while idle: every animation is a one-shot spring.
private struct PracticeStage: View {
    var practice: OnboardingPractice

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var pressed: Set<String> = []
    @State private var monitor: Any?
    @State private var textFrame = CGRect.zero
    @State private var fieldFrame = CGRect.zero
    @State private var hit = CGRect.zero
    @State private var flight: Flight = .rest

    private enum Flight { case rest, lifted, landed }

    private var phase: OnboardingPractice.Phase { practice.phase }
    private var succeeded: Bool { if case .succeeded = phase { return true }; return false }
    private var keys: [String] { Self.tokens(practice.triggerHint) }
    private var dim: Bool { phase == .unavailable || phase == .lostPermission }
    private var noun: String { practice.target == .website ? "link" : "email" }

    private var caption: String {
        switch phase {
        case .intro: "Preparing your sample…"
        case .armed: "Press \(practice.triggerHint) in the field"
        case .deciding: "Deciding…"
        case .succeeded: "Pasted just the \(noun)"
        case .ordinaryPaste: "Ordinary paste this time"
        case .uncertain: "Cue wasn\u{2019}t sure which to paste"
        case .failed: "Nothing arrived"
        case .lostPermission: "Accessibility access needed"
        case .unavailable: "No model yet"
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                messageCard.modifier(Arrive(on: appeared, from: -16, delay: 0))
                connector.padding(.vertical, 14).modifier(Arrive(on: appeared, from: 0, delay: 0.08))
                fieldCard.modifier(Arrive(on: appeared, from: 16, delay: 0.14))
                keycaps.padding(.top, 44).modifier(Arrive(on: appeared, from: 20, delay: 0.22))
                Text(caption)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.top, 22)
            }
            if flight != .rest, hit != .zero { pill }
        }
        .coordinateSpace(.named("arena"))
        .task {
            practice.copySample()
            await Task.yield()
            practice.focus()
            appeared = true
        }
        .onAppear { monitor = Self.watchKeys { pressed = $0 } }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
        .onChange(of: succeeded) { _, done in land(done) }
        .onChange(of: practice.round) { _, _ in flight = .rest }
    }

    // MARK: Cards

    private var messageCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Copied message").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Label("Copied", systemImage: "checkmark").font(.system(size: 12))
                }
                .foregroundStyle(OBTheme.textTertiary)
                HighlightedParagraph(text: practice.sampleText, highlights: [practice.expected],
                                     fontSize: 15, width: 328, onHighlightRects: { hit = $0.first ?? .zero })
                    .frame(width: 328)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("arena")) } action: { textFrame = $0 }
            }
        }
    }

    private var connector: some View {
        Image(systemName: succeeded ? "checkmark" : "arrow.down")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(succeeded ? Color(red: 0.12, green: 0.62, blue: 0.34) : .white)
            .frame(width: 26, height: 26)
            .background(succeeded ? .white : .white.opacity(0.18), in: Circle())
            .contentTransition(.symbolEffect(.replace))
            .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.3), value: succeeded)
            .accessibilityHidden(true)
    }

    private var fieldCard: some View {
        card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(OBTheme.textTertiary.opacity(0.28)).frame(width: 8, height: 8) }
                }
                Text(practice.fieldLabel)
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(OBTheme.textPrimary)
                PracticeField(label: practice.fieldLabel,
                              placeholder: practice.target == .email ? "name@example.com" : "https://…",
                              practice: practice)
                    .frame(height: 38)
                    .overlay(alignment: .trailing) {
                        if succeeded {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(Color(red: 0.12, green: 0.62, blue: 0.34))
                                .padding(.trailing, 10)
                                .transition(reduceMotion ? .opacity : .scale(scale: 0.5).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(duration: 0.4, bounce: 0.3), value: succeeded)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("arena")) } action: { fieldFrame = $0 }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(red: 0.2, green: 0.8, blue: 0.5), lineWidth: 2)
                .opacity(succeeded ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: succeeded)
        }
    }

    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        let ink = Color(red: 0.01, green: 0.05, blue: 0.3)
        return content()
            .fixedSize(horizontal: false, vertical: true)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                shape.fill(.white)
                    .shadow(color: ink.opacity(0.28), radius: 3, y: 2)
                    .shadow(color: ink.opacity(0.32), radius: 28, y: 16)
            }
            .environment(\.colorScheme, .light)
    }

    // MARK: Flight

    /// The extracted email, lifted off its highlight and carried down into the field.
    private var pill: some View {
        let start = CGPoint(x: textFrame.minX + hit.midX, y: textFrame.minY + hit.midY)
        let end = CGPoint(x: fieldFrame.minX + 12 + hit.width / 2, y: fieldFrame.midY)
        let landed = flight == .landed
        return Text(practice.expected)
            .font(.system(size: 15))
            .foregroundStyle(OBTheme.highlightText)
            .padding(.horizontal, 1.5)
            .frame(width: hit.width, height: hit.height)
            .background(OBTheme.highlight, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .shadow(color: .black.opacity(landed ? 0 : 0.3), radius: 10, y: 6)
            .scaleEffect(landed ? 1 : 1.03)
            .opacity(landed ? 0 : 1)
            .position(landed ? end : start)
            .animation(.spring(duration: 0.55, bounce: 0.12), value: landed)
            .animation(.easeIn(duration: 0.18).delay(0.4), value: landed)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func land(_ done: Bool) {
        guard done, !reduceMotion else { flight = .rest; return }
        flight = .lifted
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            flight = .landed
        }
    }

    // MARK: Keys

    private var keycaps: some View {
        HStack(spacing: 10) {
            ForEach(keys, id: \.self) { k in
                StageKey(glyph: k, lit: pressed.contains(k) || phase == .deciding)
            }
        }
        .opacity(dim ? 0.45 : 1)
        .accessibilityElement()
        .accessibilityLabel("Shortcut \(practice.triggerHint)")
    }

    /// "⌥⌘V" → ["⌥", "⌘", "V"]; a named key ("Space", "F5") stays whole.
    static func tokens(_ hint: String) -> [String] {
        let mods = hint.prefix { StageKey.modifierNames[String($0)] != nil }
        let rest = hint.dropFirst(mods.count)
        return mods.map(String.init) + (rest.isEmpty ? [] : [String(rest)])
    }

    /// Live key state from the window's own events — modifiers by flag, the letter by keyDown/Up.
    private static func watchKeys(_ set: @escaping (Set<String>) -> Void) -> Any? {
        var letter: String?
        return NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown, .keyUp]) { e in
            let flags = e.modifierFlags
            var down = Set<String>()
            for (glyph, flag) in [("⌘", NSEvent.ModifierFlags.command), ("⌥", .option), ("⌃", .control), ("⇧", .shift)]
            where flags.contains(flag) { down.insert(glyph) }
            switch e.type {
            case .keyDown: letter = e.charactersIgnoringModifiers?.uppercased()
            case .keyUp: letter = nil
            default: if down.isEmpty { letter = nil }
            }
            if let letter { down.insert(letter) }
            withAnimation(.easeOut(duration: 0.08)) { set(down) }
            return e
        }
    }
}

/// A thick, dimensional keycap: glass at rest, a lit white face with a glow while its key is down.
private struct StageKey: View {
    static let modifierNames = ["⌘": "command", "⌥": "option", "⌃": "control", "⇧": "shift"]

    let glyph: String
    var lit: Bool

    private var caption: String? { Self.modifierNames[glyph] }
    private var cobalt: Color { Color(red: 0.05, green: 0.22, blue: 0.78) }

    var body: some View {
        let lip: CGFloat = lit ? 2 : 7
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(red: 0.01, green: 0.05, blue: 0.3).opacity(0.5))
                .offset(y: lip)
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(lit ? AnyShapeStyle(.white)
                          : AnyShapeStyle(LinearGradient(colors: [.white.opacity(0.34), .white.opacity(0.16)],
                                                         startPoint: .top, endPoint: .bottom)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(lit ? 0 : 0.4), lineWidth: 1))
                .overlay(alignment: caption == nil ? .center : .topLeading) {
                    Text(glyph)
                        .font(.system(size: caption == nil && glyph.count == 1 ? 34 : 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(lit ? cobalt : .white)
                        .padding(caption == nil ? 0 : 12)
                }
                .overlay(alignment: .bottomLeading) {
                    if let caption {
                        Text(caption).font(.system(size: 12, weight: .medium))
                            .foregroundStyle(lit ? cobalt.opacity(0.7) : .white.opacity(0.7))
                            .padding(12)
                    }
                }
                .shadow(color: .white.opacity(lit ? 0.55 : 0), radius: 20)
                .offset(y: lit ? 5 : 0)
        }
        .frame(width: caption == nil && glyph.count == 1 ? 84 : 104, height: 84)
        .padding(.bottom, 7)
    }
}

/// One-shot entrance: rise into place, staggered. Reduce Motion keeps only the fade.
private struct Arrive: ViewModifier {
    var on: Bool
    var from: CGFloat
    var delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on || reduceMotion ? 0 : from)
            .animation(.timingCurve(0.23, 1, 0.32, 1, duration: reduceMotion ? 0.15 : 0.5).delay(reduceMotion ? 0 : delay), value: on)
    }
}
