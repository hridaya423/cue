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

    public func showTop3(candidates: [ScoredCandidate], near rect: CGRect?,
                         onPick: @escaping (ScoredCandidate?) -> Void) {
        show(view: Top3View(candidates: candidates), near: rect, dismissOnResign: true)
        onKey = { [weak self] e in
            guard let self else { return true }
            // ⌘V while we're up means "just paste it" — the intercepted key
            // reached us, so decline → plain paste rather than swallow it.
            if e.modifierFlags.contains(.command), Int(e.keyCode) == kVK_ANSI_V {
                self.dismiss(); onPick(nil); return true
            }
            switch Int(e.keyCode) {
            case kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3:
                let i = Int(e.keyCode) - kVK_ANSI_1
                if i < candidates.count { self.dismiss(); onPick(candidates[i]) }
                return true
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

private extension Clip {
    var kindIcon: String { isURL ? "link" : "text.alignleft" }
}

struct Top3View: View {
    let candidates: [ScoredCandidate]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Not sure — pick one")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            ForEach(Array(candidates.prefix(3).enumerated()), id: \.offset) { i, cand in
                HStack(spacing: 10) {
                    Text("\(i + 1)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .frame(width: 18, height: 18)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                    Image(systemName: cand.clip.kindIcon)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(cand.clip.preview)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text("\(Int(cand.probability * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            Text("esc for plain paste")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .frame(width: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
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
                            HStack(spacing: 10) {
                                Image(systemName: cand.clip.kindIcon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(i == state.selection ? Color.accentColor : .secondary)
                                    .frame(width: 14)
                                Text(cand.clip.preview)
                                    .font(.system(size: 13))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 8)
                                Text(cand.clip.copiedAt.relativeAge)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(i == state.selection ? Color.accentColor.opacity(0.12) : .clear)
                            .id(i)
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

            Text("↑↓ choose · ⏎ paste · esc plain paste")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(width: 420)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
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
    }
}
