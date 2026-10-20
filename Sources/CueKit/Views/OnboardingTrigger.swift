import SwiftUI

extension OnboardingView {
    var triggerControls: some View {
        let shortcut = settings.hotkey(for: HotkeyManager.Action.smartPaste.rawValue)
            ?? HotkeyManager.Action.smartPaste.default
        return VStack(alignment: .leading, spacing: 12) {
            TriggerCard(
                title: "Use \u{2318}V",
                detail: "Cue pastes what fits the field. Your shortcut still opens the choices.",
                keys: ["\u{2318}", "V"],
                selected: settings.triggerMode == .intercept
            ) {
                NSApp.keyWindow?.makeFirstResponder(nil)
                setTrigger(.intercept)
            }
            TriggerCard(
                title: "Only my shortcut",
                detail: "\u{2318}V stays ordinary. Cue steps in when you ask.",
                keys: TriggerKeys.split(shortcut.displayString),
                selected: settings.triggerMode == .hotkey,
                recorder: shortcut,
                onRecord: recordSmartPaste
            ) {
                setTrigger(.hotkey)
            }
            if let recorderConflict {
                Text(recorderConflict)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
    }

    var triggerStage: some View {
        let keys = settings.triggerMode == .intercept
            ? ["\u{2318}", "V"]
            : TriggerKeys.split((settings.hotkey(for: HotkeyManager.Action.smartPaste.rawValue)
                ?? HotkeyManager.Action.smartPaste.default).displayString)
        return TriggerStage(keys: keys)
    }

    func setTrigger(_ mode: AppSettings.TriggerMode) {
        settings.triggerMode = mode
        model.hotkeys.interceptCmdV = mode == .intercept
    }

    /// Reject bindings that collide with another Cue action — the recorder
    /// keeps its prior value when we refuse to persist.
    func recordSmartPaste(_ hk: AppSettings.Hotkey) {
        for action in HotkeyManager.Action.allCases where action != .smartPaste {
            let other = settings.hotkey(for: action.rawValue) ?? action.default
            if other.keyCode == hk.keyCode && other.modifiers == hk.modifiers {
                recorderConflict = "That shortcut is already used for “\(action.title)”."
                return
            }
        }
        recorderConflict = nil
        settings.setHotkey(hk, for: HotkeyManager.Action.smartPaste.rawValue)
        model.hotkeys.reregister()
    }

}

enum TriggerKeys {
    /// "⌃⌥V" → ["⌃", "⌥", "V"]; a named key ("Space") stays whole.
    static func split(_ display: String) -> [String] {
        let mods = display.prefix { "⌃⌥⇧⌘".contains($0) }
        let key = display.dropFirst(mods.count)
        return mods.map(String.init) + (key.isEmpty ? [] : [String(key)])
    }
}

// MARK: - Keycap

/// A key as it looks on the keyboard: a face on a lip that the face sinks into when pressed.
struct TriggerKey: View {
    let label: String
    var size: CGFloat = 40
    var pressed = false
    /// On the cobalt stage the key is always a white one, in both appearances.
    var onStage = false

    private var depth: CGFloat { max(3, size * 0.08) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.24, style: .continuous) }

    var body: some View {
        ZStack(alignment: .top) {
            shape.fill(lip)
                .offset(y: depth)
                .shadow(color: .black.opacity(onStage ? 0.28 : 0.16), radius: size * 0.12, y: depth + size * 0.06)
            Text(label)
                .font(.system(size: label.count > 1 ? size * 0.34 : size * 0.46, weight: .semibold, design: .rounded))
                .foregroundStyle(glyph)
                .padding(.horizontal, label.count > 1 ? size * 0.3 : 0)
                .frame(minWidth: size, minHeight: size)
                .background(LinearGradient(colors: [faceTop, faceBottom], startPoint: .top, endPoint: .bottom), in: shape)
                .overlay(shape.strokeBorder(edge, lineWidth: 0.75))
                .offset(y: pressed ? depth * 0.85 : 0)
        }
        .padding(.bottom, depth)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private var faceTop: Color { onStage ? .white : Color(nsColor: OBTheme.nsColor(0xFFFFFF, 0x4C5059)) }
    private var faceBottom: Color { onStage ? Color(red: 0.92, green: 0.95, blue: 1) : Color(nsColor: OBTheme.nsColor(0xF3F2F0, 0x3F434B)) }
    private var lip: Color { onStage ? Color(red: 0.69, green: 0.78, blue: 0.97) : Color(nsColor: OBTheme.nsColor(0xD3D0CB, 0x17191C)) }
    private var edge: Color { onStage ? .white : Color(nsColor: OBTheme.nsColor(0xBDB9B3, 0x686E7A)) }
    private var glyph: Color { onStage ? OBTheme.action : OBTheme.textPrimary }
}

// MARK: - Choice card

/// One way to trigger Cue as a large selectable card: the keys you would press, then what it means.
/// The recorder, when given, sits over the keys and only records; the card paints the keys and the armed state.
struct TriggerCard: View {
    let title: String
    let detail: String
    let keys: [String]
    let selected: Bool
    var recorder: AppSettings.Hotkey?
    var onRecord: (AppSettings.Hotkey) -> Void = { _ in }
    let onSelect: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    @State private var armed = false
    @State private var pressed = false

    private let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
    private static let keySize: CGFloat = 44
    private static let keyRowHeight: CGFloat = 48

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        Color.clear.frame(width: 1, height: Self.keyRowHeight)
                        Spacer()
                        OBRadio(selected: selected)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(OBTheme.textPrimary)
                        Text(detail).font(.system(size: 13))
                            .foregroundStyle(OBTheme.textSecondary)
                            .lineSpacing(1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
                .background(selected ? OBTheme.selectionFill : OBTheme.insetFill, in: shape)
                .overlay(shape.strokeBorder(selected ? OBTheme.action : OBTheme.separator, lineWidth: selected ? 2 : 1))
                .shadow(color: OBTheme.action.opacity(selected ? 0.2 : 0), radius: 14, y: 6)
                .contentShape(shape)
            }
            .buttonStyle(TriggerCardStyle())
            .accessibilityAddTraits(selected ? .isSelected : [])

            keyRow
                .padding(.leading, 18)
                .padding(.top, 18)
                .allowsHitTesting(recorder != nil)
        }
        .offset(y: hovered && !selected && !reduceMotion ? -1 : 0)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovered = h } }
        .animation(.easeOut(duration: 0.2), value: selected)
        .onChange(of: selected) { _, now in
            guard now, !reduceMotion else { return }
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.08)) { pressed = true }
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(OBMotion.moderate) { pressed = false }
            }
        }
    }

    @ViewBuilder private var keyRow: some View {
        if let recorder {
            ZStack(alignment: .leading) {
                if armed {
                    Text("Press your shortcut\u{2026}")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(OBTheme.action)
                        .padding(.horizontal, 14)
                        .frame(height: Self.keyRowHeight)
                        .background(OBTheme.action.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(OBTheme.action, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
                } else {
                    HStack(spacing: 14) {
                        keycaps
                        Text("Click to change")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(OBTheme.textTertiary)
                    }
                }
                HotkeyRecorder(value: recorder, onChange: onRecord, chromeless: true) { on in
                    armed = on
                    if on { onSelect() }
                }
                .frame(width: 168, height: Self.keyRowHeight)
                .accessibilityLabel("Shortcut")
            }
        } else {
            keycaps
        }
    }

    private var keycaps: some View {
        HStack(spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                TriggerKey(label: key, size: Self.keySize, pressed: pressed)
            }
        }
    }
}

private struct TriggerCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Stage

/// The chosen trigger doing its job: the keys land and just the email arrives in the field.
/// Event-driven: it sleeps between steps, so nothing runs while it waits. Reduce Motion shows the arrived state.
struct TriggerStage: View {
    let keys: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var modsDown = false
    @State private var keyDown = false
    @State private var arrived = false
    @State private var chip = false

    private let email = OnboardingSample.Target.email.expected

    var body: some View {
        VStack(spacing: 22) {
            OBStageCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Copied message")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OBTheme.textTertiary)
                    HighlightedParagraph(
                        text: "Reach Mira at mira@example.com or +44 7700 900123.",
                        highlights: [email],
                        fontSize: 15, width: 336)
                }
            }
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(Array(keys.enumerated()), id: \.offset) { i, key in
                        TriggerKey(label: key, size: 72, pressed: i == keys.count - 1 ? keyDown : modsDown, onStage: true)
                    }
                }
                Text("Press \(keys.joined()) in the Email field")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .contentTransition(.opacity)
            }
            OBStageCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(OBTheme.textTertiary)
                    ZStack(alignment: .leading) {
                        Capsule().fill(OBTheme.action).frame(width: 1.5, height: 18)
                            .opacity(arrived ? 0 : 1)
                        if arrived {
                            Text(email)
                                .font(.system(size: 15))
                                .foregroundStyle(OBTheme.highlightText)
                                .padding(.horizontal, 2)
                                .background(OBTheme.highlight.opacity(chip ? 1 : 0), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .transition(.opacity.combined(with: .offset(y: -10)).combined(with: .scale(scale: 0.96, anchor: .leading)))
                        }
                    }
                    .frame(height: 22, alignment: .leading)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(OBTheme.action, lineWidth: 2))
        }
        .accessibilityElement(children: .combine)
        .task(id: keys) { await play() }
    }

    @MainActor private func play() async {
        modsDown = false; keyDown = false; arrived = false; chip = false
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.15)) { arrived = true }
            return
        }
        while await wait(900) {
            withAnimation(.easeOut(duration: 0.07)) { modsDown = true }
            guard await wait(70) else { return }
            withAnimation(.easeOut(duration: 0.07)) { keyDown = true }
            guard await wait(150) else { return }
            withAnimation(OBMotion.fast) { modsDown = false; keyDown = false }
            withAnimation(OBMotion.land) { arrived = true; chip = true }
            guard await wait(700) else { return }
            withAnimation(.easeOut(duration: 0.9)) { chip = false }
            guard await wait(2600) else { return }
            withAnimation(.easeIn(duration: 0.25)) { arrived = false }
        }
    }

    private func wait(_ ms: Int) async -> Bool {
        (try? await Task.sleep(for: .milliseconds(ms))) != nil
    }
}
