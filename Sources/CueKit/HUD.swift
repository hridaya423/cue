import AppKit
import Carbon
import SwiftUI

/// Borderless, non-activating panels shown next to the focused field.
/// One panel at a time; a local key monitor handles input while shown.
@MainActor
public final class HUDController {
    private var panel: NSPanel?
    fileprivate var keyTap: CFMachPort?
    private var keyTapSource: CFRunLoopSource?
    private var resignObserver: NSObjectProtocol?
    private var outsideClickMonitor: Any?
    private var dismissTask: Task<Void, Never>?
    fileprivate var onKey: ((NSEvent) -> Bool)?

    /// A chooser or picker is waiting for keys. Toasts and the deciding dots don't count:
    /// counting them made a second ⌘V within 1.4 s of a paste skip the decision.
    public var isShowingChoices: Bool { onKey != nil }

    /// Where a panel points: the caret, else the field. A tall editor with no caret
    /// (Notes, Docs, Slack) points at the pointer inside it, not its far edge.
    public static func anchor(caret: CGRect?, field: CGRect?) -> CGRect? {
        if let caret { return caret }
        guard let field, field.height > 80 else { return field }
        let mouse = NSEvent.mouseLocation
        let p = field.contains(mouse) ? mouse : CGPoint(x: field.minX + 12, y: field.maxY - 12)
        return CGRect(x: p.x, y: p.y - 9, width: 2, height: 18)
    }

    public init() {}

    /// Caret-anchored disambiguation: the model's top options, 1/2/3 or
    /// arrows+Return to pick, Esc/⌘V = plain paste. Non-activating.
    /// `fieldLabel` names the destination ("Paste into To:") when known.
    public func showChooser(options: [ScoredOption], history: [Clip] = [], near rect: CGRect?,
                            fieldLabel: String? = nil,
                            onPick: @escaping (ScoredOption?) -> Void) {
        let state = ChooserState(options: options, history: history)
        state.fieldLabel = fieldLabel ?? ""
        state.onPick = { [weak self] i in
            guard let self else { return }
            let row = state.rows[i]
            self.dismiss()
            onPick(row)
        }
        show(view: ChooserView(state: state), near: rect, dismissOnResign: true)
        // The entrance scales out of the edge nearest the caret: flipped
        // panels grow from their bottom edge.
        if let rect, let panel, panel.frame.minY > rect.maxY {
            state.anchor = .bottom
        }
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [.announcement: "Paste options available. Press a number to choose, Escape for a plain paste."])
        onKey = { [weak self] e in
            guard let self else { return true }
            // ⌘V while we're up means "just paste it" — the intercepted key
            // reached us, so decline → plain paste rather than swallow it.
            if e.modifierFlags.contains(.command), Int(e.keyCode) == kVK_ANSI_V {
                self.dismiss(); onPick(nil); return true
            }
            // Any other shortcut belongs to the app: close and let it through.
            if !e.modifierFlags.intersection([.command, .control]).isEmpty { self.dismiss(); return false }
            // A digit held back for the search window: Return confirms it as a pick, Esc drops it,
            // any other key means it began a search ("1291").
            if let d = state.pendingDigit {
                state.pendingDigit = nil
                if Int(e.keyCode) == kVK_Return || Int(e.keyCode) == kVK_ANSI_KeypadEnter {
                    if d <= state.rows.count { state.pick(d - 1) }
                    return true
                }
                if Int(e.keyCode) != kVK_Escape { state.append(String(d)) }
            }
            // A typed digit picks its row — by character, not key code: kVK_ANSI_1…9 aren't
            // contiguous, and on AZERTY the digit keys type "&é\"'" unless Shift is held. It waits
            // 180 ms first: a second key inside that window (people type ~100 ms apart) makes it a search.
            // Once a search has started, digits belong to it ("0143"); Return or the arrows pick.
            if state.filter.isEmpty, let c = e.characters, let d = Int(c), (1...9).contains(d),
               e.modifierFlags.intersection([.command, .control, .option]).isEmpty {
                state.pendingDigit = d
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(180))
                    guard let self, self.onKey != nil, state.pendingDigit == d else { return }
                    state.pendingDigit = nil
                    if d <= state.rows.count { state.pick(d - 1) }
                }
                return true
            }
            switch Int(e.keyCode) {
            case kVK_DownArrow: state.move(1); return true
            case kVK_UpArrow: state.move(-1); return true
            case kVK_Return, kVK_ANSI_KeypadEnter:
                // A resting pointer hovers a row that typing may have filtered away: take the nearest one.
                let rows = state.rows
                let sel = rows.isEmpty ? nil : rows[min(state.selection, rows.count - 1)]
                self.dismiss(); onPick(sel); return true
            case kVK_Escape: self.dismiss(); onPick(nil); return true
            case kVK_Delete: state.backspace(); return true
            default:
                // Letters filter all of history; digits above pick rows.
                if let chars = e.characters, let first = chars.unicodeScalars.first,
                   first.value >= 0x20, !e.modifierFlags.contains(.command) {
                    state.append(chars)
                }
                return true
            }
        }
    }

    public func showPicker(candidates: [ScoredCandidate], near rect: CGRect?,
                           onPick: @escaping (ScoredCandidate?) -> Void) {
        let state = PickerState(candidates: candidates)
        show(view: PickerView(state: state), near: rect, dismissOnResign: true)
        onKey = { [weak self] e in
            guard let self else { return true }
            if e.modifierFlags.contains(.command), Int(e.keyCode) == kVK_ANSI_V {
                self.dismiss(); onPick(nil); return true
            }
            if !e.modifierFlags.intersection([.command, .control]).isEmpty { self.dismiss(); return false }
            switch Int(e.keyCode) {
            case kVK_DownArrow: state.move(1); return true
            case kVK_UpArrow: state.move(-1); return true
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.dismiss(); onPick(state.selected); return true
            case kVK_Escape: self.dismiss(); onPick(nil); return true
            case kVK_Delete: state.backspace(); return true
            default:
                if let chars = e.characters, let first = chars.unicodeScalars.first,
                   first.value >= 0x20, !e.modifierFlags.contains(.command) {
                    state.append(chars)
                }
                return true
            }
        }
    }

    /// Caret-adjacent "thinking" dots while the model is working — much less
    /// intrusive than a top-of-screen toast, and it sits where the result
    /// will appear. Caller dismisses (paste/chooser replaces it).
    public func showDeciding(near rect: CGRect?) {
        show(view: DecidingView(), near: rect, dismissOnResign: false)
    }

    /// Tiny confirmation pill. Auto-dismisses.
    public func showStatus(_ text: String) {
        show(view: StatusToastView(text: text), near: nil, dismissOnResign: false)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            self?.dismiss()
        }
    }

    public func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        if let keyTap { CGEvent.tapEnable(tap: keyTap, enable: false) }
        if let keyTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), keyTapSource, .commonModes) }
        keyTap = nil
        keyTapSource = nil
        onKey = nil
        if let resignObserver { NSWorkspace.shared.notificationCenter.removeObserver(resignObserver) }
        resignObserver = nil
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        panel?.orderOut(nil)
        panel = nil
    }

    private func show(view: some View, near rect: CGRect?, dismissOnResign: Bool) {
        dismiss()
        let hosting = NSHostingView(rootView: view)
        hosting.setFrameSize(hosting.fittingSize)

        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hosting
        panel.setFrameOrigin(Self.position(near: rect, size: hosting.fittingSize))
        panel.orderFront(nil)
        self.panel = panel

        guard dismissOnResign else { return }
        // The chooser never takes key focus: a key panel blurs the field being pasted into (web views
        // don't take it back), so the paste would land nowhere. A session event tap reads the keys
        // instead, consuming the ones the chooser uses while it's up.
        keyTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let hud = Unmanaged<HUDController>.fromOpaque(refcon).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    MainActor.assumeIsolated { if let t = hud.keyTap { CGEvent.tapEnable(tap: t, enable: true) } }
                    return Unmanaged.passUnretained(event)
                }
                guard type == .keyDown, let e = NSEvent(cgEvent: event) else { return Unmanaged.passUnretained(event) }
                let consumed = MainActor.assumeIsolated { hud.onKey?(e) ?? false }
                return consumed ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        if let keyTap, let src = CFMachPortCreateRunLoopSource(nil, keyTap, 0) {
            keyTapSource = src
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        }
        // Switching apps or clicking elsewhere closes it, as resigning key used to.
        resignObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.dismiss() } }
        // A click in another field of the same app left the chooser up, eating every keystroke.
        // Global monitors never see clicks on our own panel, so any click here is outside it.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
    }

    /// Below the field if it fits, otherwise above; clamped to the screen.
    private static func position(near rect: CGRect?, size: CGSize) -> CGPoint {
        let screen = rect.flatMap { screenContaining($0) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        var origin: CGPoint
        if let rect {
            origin = CGPoint(x: rect.minX, y: rect.minY - size.height - 6)
        } else {
            // Status toasts sit near the top of the screen.
            origin = CGPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 80)
        }
        if let rect, origin.y < vf.minY {
            origin.y = rect.maxY + 6 // flip above the field
        }
        origin.x = min(max(origin.x, vf.minX + 8), vf.maxX - size.width - 8)
        origin.y = min(max(origin.y, vf.minY + 8), vf.maxY - size.height - 8)
        return origin
    }


    private static func screenContaining(_ rect: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(rect) }
    }
}

// MARK: - Chooser state

@Observable
final class ChooserState {
    var selection = 0
    /// Edge the entrance scales from — set by the controller once the
    /// panel's anchor point is known.
    var anchor: UnitPoint = .top
    /// Row click handler; dismisses then reports the picked index.
    var onPick: ((Int) -> Void)?
    /// Destination field label for the header ("Paste into To:").
    var fieldLabel = ""
    var filter = ""
    var pendingDigit: Int?
    let options: [ScoredOption]
    let history: [Clip]
    init(options: [ScoredOption], history: [Clip] = []) { self.options = options; self.history = history }
    var rows: [ScoredOption] { ChooserRows.rows(ranked: options, history: history, query: filter) }
    func move(_ delta: Int) {
        selection = min(max(selection + delta, 0), max(rows.count - 1, 0))
    }
    func pick(_ i: Int) {
        guard rows.indices.contains(i) else { return }
        onPick?(i)
    }
    func append(_ s: String) { filter += s; selection = 0 }
    func backspace() { if !filter.isEmpty { filter.removeLast(); selection = 0 } }
}

// MARK: - Picker state

@Observable
final class PickerState {
    var filter = ""
    var selection = 0
    let all: [ScoredCandidate]

    init(candidates: [ScoredCandidate]) { all = candidates }

    var visible: [ScoredCandidate] {
        guard !filter.isEmpty else { return all }
        return all.filter { $0.clip.preview.localizedCaseInsensitiveContains(filter) }
    }

    var selected: ScoredCandidate? {
        guard visible.indices.contains(selection) else { return nil }
        return visible[selection]
    }

    func move(_ delta: Int) {
        selection = min(max(selection + delta, 0), max(visible.count - 1, 0))
    }
    func append(_ s: String) { filter += s; selection = 0 }
    func backspace() { if !filter.isEmpty { filter.removeLast(); selection = 0 } }
}

// MARK: - Views

/// kbd-styled hint key cap — shared by the chooser and picker footers.
private struct KbdCap: View {
    let s: String
    var body: some View {
        Text(s)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(.quaternary.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
    }
}

struct ChooserView: View {
    var state: ChooserState

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if state.filter.isEmpty {
                    Text(state.fieldLabel.isEmpty ? "Which one?" : "Paste into \(state.fieldLabel)")
                } else {
                    Label(state.filter, systemImage: "magnifyingglass")
                }
            }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(state.rows.enumerated()), id: \.offset) { i, so in
                    row(i, so)
                }
            }
            .padding(.horizontal, 6)
            Divider().opacity(0.5).padding(.top, 4)
            HStack(spacing: 4) {
                hintKey("↩")
                Text("paste")
                if state.filter.isEmpty {
                    hintKey("1–\(max(state.rows.count, 1))").padding(.leading, 6)
                    Text("pick")
                    Text("· type to search").foregroundStyle(.tertiary)
                } else {
                    hintKey("↑↓").padding(.leading, 6)
                    Text("move")
                }
                Spacer(minLength: 12)
                hintKey("esc")
                Text("plain paste")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .frame(minWidth: 280, maxWidth: 420)
        .fixedSize(horizontal: true, vertical: true)
        .frame(maxWidth: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: OBTheme.separatorNS).opacity(0.8), lineWidth: 0.5)
        )
        // Fade + a 0.97→1 spring out of the caret-facing edge.
        // Reduce Motion keeps the fade only.
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.97, anchor: state.anchor)
        .task {
            try? await Task.sleep(for: .milliseconds(20)) // let the panel order in
            withAnimation(.spring(duration: 0.2, bounce: 0.12)) { appeared = true }
        }
    }

    private func row(_ i: Int, _ so: ScoredOption) -> some View {
        let selected = i == state.selection
        return Button {
            state.pick(i)
        } label: {
            HStack(alignment: .center, spacing: 9) {
                SourceAppIcon(clip: so.option.clip, size: 18)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(so.option.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? .white : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(contextLine(for: so.option))
                        .font(.system(size: 11))
                        .foregroundStyle(selected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Text("\(i + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? .white : .secondary)
                    .frame(width: 18, height: 18)
                    .background(selected ? Color.white.opacity(0.22) : Color.primary.opacity(0.07),
                                in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                    .opacity(state.filter.isEmpty ? 1 : 0) // while searching, digits type, so no badge
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // The user's own accent colour, like every other selected row on the Mac.
            .background(selected ? Color.accentColor : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { state.selection = i }
        }
        .accessibilityLabel(rowLabel(for: so.option))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func hintKey(_ s: String) -> some View { KbdCap(s: s) }

    /// "Paste {value}, from {app}" — the app name only when we have one.
    private func rowLabel(for o: PasteOption) -> String {
        o.clip.sourceApp.isEmpty
            ? "Paste \(o.text)"
            : "Paste \(o.text), from \(o.clip.sourceApp)"
    }

    /// "Mail · 2m ago · copied from Slack", preferring the app + age; falls
    /// back to the snippet when a span needs its surrounding line.
    private func contextLine(for o: PasteOption) -> String {
        var parts: [String] = []
        if o.clip.id == state.history.first?.id, o.text == o.clip.text { parts.append("Clipboard") }
        if !o.clip.sourceApp.isEmpty { parts.append(o.clip.sourceApp) }
        parts.append(o.clip.copiedAt.relativeAge)
        if o.kind != .text, o.snippet != o.text, !o.snippet.isEmpty {
            parts.append("“\(o.snippet)”")
        }
        return parts.joined(separator: " · ")
    }
}

struct PickerView: View {
    var state: PickerState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text(state.filter.isEmpty ? "Filter clipboard history…" : state.filter)
                    .font(.system(size: 13))
                    .foregroundStyle(state.filter.isEmpty ? .tertiary : .primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)

            Divider().opacity(0.5)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(state.visible.enumerated()), id: \.offset) { i, cand in
                            pickerRow(i, cand)
                        }
                    }
                }
                .frame(maxHeight: 320)
                .onChange(of: state.selection) { _, i in
                    proxy.scrollTo(i, anchor: .center)
                }
            }

            if state.visible.isEmpty {
                Text("No matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }

            HStack(spacing: 4) {
                KbdCap(s: "↩")
                Text("paste")
                KbdCap(s: "↑↓").padding(.leading, 6)
                Text("move")
                Spacer()
                KbdCap(s: "esc")
                Text("plain paste")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
        }
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(nsColor: OBTheme.separatorNS).opacity(0.8), lineWidth: 0.5)
        )
    }

    private func pickerRow(_ i: Int, _ cand: ScoredCandidate) -> some View {
        let sel = i == state.selection
        return HStack(spacing: 10) {
            SourceAppIcon(clip: cand.clip, size: 15)
                .frame(width: 15)
            Text(cand.clip.preview)
                .font(.system(size: 13))
                .foregroundStyle(sel ? .white : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if cand.clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(sel ? .white.opacity(0.8) : .secondary)
            }
            Text(cand.clip.copiedAt.relativeAge)
                .font(.system(size: 11))
                .foregroundStyle(sel ? .white.opacity(0.8) : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(sel ? Color.accentColor : .clear,
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 5)
        .id(i)
    }
}

/// Three pulsing dots in a capsule — sits at the caret while the model works.
struct DecidingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.28, paused: reduceMotion)) { tl in
            let phase = Int(tl.date.timeIntervalSinceReferenceDate / 0.28) % 3
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary.opacity(i == phase ? 0.9 : 0.3))
                        .frame(width: 5, height: 5)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color(nsColor: OBTheme.separatorNS).opacity(0.8), lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Deciding what to paste")
    }
}

struct StatusToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: 420)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color(nsColor: OBTheme.separatorNS).opacity(0.8), lineWidth: 0.5)
            )
    }
}
