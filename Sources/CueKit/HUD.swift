import AppKit
import Carbon
import SwiftUI

/// Borderless, non-activating panels shown next to the focused field.
/// One panel at a time; a local key monitor handles input while shown.
@MainActor
public final class HUDController {
    private var panel: NSPanel?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var dismissTask: Task<Void, Never>?
    private var onKey: ((NSEvent) -> Bool)?

    public var isShowing: Bool { panel != nil }

    public init() {}

    /// Caret-anchored disambiguation: the model's top options, 1/2/3 or
    /// arrows+Return to pick, Esc/⌘V = plain paste. Non-activating.
    /// `fieldLabel` names the destination ("Paste into To:") when known.
    public func showChooser(options: [ScoredOption], near rect: CGRect?,
                            fieldLabel: String? = nil,
                            onPick: @escaping (ScoredOption?) -> Void) {
        let state = ChooserState(options: options)
        state.fieldLabel = fieldLabel ?? ""
        state.onPick = { [weak self] i in
            guard let self else { return }
            self.dismiss()
            onPick(state.options[i])
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
            switch Int(e.keyCode) {
            case kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                 kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9:
                let i = Int(e.keyCode) - kVK_ANSI_1
                if i < state.options.count { state.pick(i) }
                return true
            case kVK_DownArrow: state.move(1); return true
            case kVK_UpArrow: state.move(-1); return true
            case kVK_Return, kVK_ANSI_KeypadEnter:
                let sel = state.options.indices.contains(state.selection) ? state.options[state.selection] : nil
                self.dismiss(); onPick(sel); return true
            case kVK_Escape: self.dismiss(); onPick(nil); return true
            default: return true // swallow everything else
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
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        onKey = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
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
        panel.makeKey()
        self.panel = panel

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, let onKey = self.onKey else { return e }
            return onKey(e) ? nil : e
        }
        if dismissOnResign {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
            ) { [weak self] _ in Task { @MainActor in self?.dismiss() } }
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
    let options: [ScoredOption]
    init(options: [ScoredOption]) { self.options = options }
    func move(_ delta: Int) {
        selection = min(max(selection + delta, 0), max(options.count - 1, 0))
    }
    func pick(_ i: Int) {
        guard options.indices.contains(i) else { return }
        onPick?(i)
    }
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
            Text(state.fieldLabel.isEmpty ? "Which one?" : "Paste into \(state.fieldLabel)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(state.options.enumerated()), id: \.offset) { i, so in
                    row(i, so)
                }
            }
            .padding(.horizontal, 6)
            Divider().opacity(0.5).padding(.top, 4)
            HStack(spacing: 4) {
                hintKey("1–\(state.options.count)")
                Text("choose")
                Spacer()
                hintKey("esc")
                Text("plain paste")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
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
                SourceAppIcon(clip: so.option.clip, size: 16)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 1) {
                    Text(so.option.text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(selected ? OBTheme.highlightText : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(contextLine(for: so.option))
                        .font(.system(size: 10))
                        .foregroundStyle(selected
                            ? OBTheme.highlightText.opacity(0.65)
                            : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Text("\(i + 1)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(selected ? OBTheme.highlightText.opacity(0.7) : .secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        selected ? Color.white.opacity(0.45) : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .strokeBorder(.black.opacity(selected ? 0.12 : 0.18), lineWidth: 0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(selected ? OBTheme.highlight : .clear,
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
                KbdCap(s: "↑↓")
                Text("choose")
                KbdCap(s: "⏎")
                Text("paste")
                Spacer()
                KbdCap(s: "esc")
                Text("plain paste")
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
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
                .foregroundStyle(sel ? OBTheme.highlightText : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if cand.clip.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(sel ? OBTheme.highlightText.opacity(0.7) : OBTheme.foldEdge)
            }
            Text(cand.clip.copiedAt.relativeAge)
                .font(.system(size: 11))
                .foregroundStyle(sel ? OBTheme.highlightText.opacity(0.7)
                                     : Color(nsColor: .tertiaryLabelColor))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(sel ? OBTheme.highlight : .clear)
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
