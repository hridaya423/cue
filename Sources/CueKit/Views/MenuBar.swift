import SwiftUI

/// The menu-bar panel (.window MenuBarExtra). Maps the app's state onto `MenuPanel`, which only draws plain values,
/// so the panel renders off-screen without the live app (hotkeys, clipboard monitor, model server).
public struct MenuBarView: View {
    var model: AppModel

    public var body: some View {
        MenuPanel(
            status: status,
            detail: model.controller.lastAction,
            clips: model.store.clips,
            mode: Binding(get: { mode }, set: setMode),
            paused: Binding(get: { !model.monitor.running },
                            set: { $0 ? model.monitor.stop() : model.monitor.start() }),
            actions: MenuPanelActions(
                paste: { model.pasteIntoFrontApp($0) },
                togglePin: { model.store.togglePin($0) },
                remove: { model.store.remove($0) },
                openHistory: { model.open(id: "history") },
                openSettings: { model.open(id: "settings") }))
    }

    private var mode: PasteMode {
        if model.settings.queueMode { return .queue }
        return model.settings.triggerMode == .intercept ? .smart : .plain
    }

    private func setMode(_ mode: PasteMode) {
        let intercept = mode != .plain
        model.settings.triggerMode = intercept ? .intercept : .hotkey
        model.hotkeys.interceptCmdV = intercept
        model.settings.queueMode = mode == .queue
        if mode != .queue { model.store.clearQueue() }
    }

    private var status: PanelStatus {
        if !model.monitor.running { return .init(.paused, "Paused") }
        if !model.trusted { return .init(.warning, "Needs Accessibility") }
        if model.providerStatus.state == .unreachable { return .init(.error, "Model not responding") }
        switch model.settings.provider {
        case .off: return .init(.ready, "Ready", note: "smart picks off")
        case .jevDirect, .jevGateway, .custom: return .init(.ready, "Ready", note: "hosted model")
        case .local:
            guard let r = model.selectedLocal else { return .init(.warning, "No model chosen") }
            let name = "\(r.spec.title) on this Mac"
            switch model.models.status(of: r.spec.id) {
            case .running: return .init(.ready, "Ready", note: name)
            case .starting: return .init(.warning, "Model starting", note: name)
            case .installing: return .init(.warning, "Installing model", note: name)
            case .failed: return .init(.error, "Model failed to start", note: name)
            case .installed: return .init(.warning, "Model not running", note: name)
            case .notInstalled: return .init(.warning, "Model not installed", note: name)
            }
        }
    }
}

public enum PasteMode: String, CaseIterable, Sendable {
    case smart, queue, plain

    var title: String {
        switch self {
        case .smart: "Smart"
        case .queue: "Queue"
        case .plain: "Plain"
        }
    }
}

public struct PanelStatus: Equatable, Sendable {
    public enum Tone: Sendable { case ready, warning, error, paused }
    public var tone: Tone
    public var title: String
    public var note: String?

    public init(_ tone: Tone, _ title: String, note: String? = nil) {
        self.tone = tone
        self.title = title
        self.note = note
    }

    var color: Color {
        switch tone {
        case .ready: .green
        case .warning: .orange
        case .error: .red
        case .paused: .gray
        }
    }
}

public struct MenuPanelActions {
    public var paste: (Clip) -> Void
    public var togglePin: (Clip) -> Void
    public var remove: (Clip) -> Void
    public var openHistory: () -> Void
    public var openSettings: () -> Void
}

struct MenuPanel: View {
    let status: PanelStatus
    let detail: String?
    let clips: [Clip]
    @Binding var mode: PasteMode
    @Binding var paused: Bool
    let actions: MenuPanelActions

    @State private var filter = ""
    /// Hover and arrow keys share one selection; Return pastes it.
    @State private var selection: Clip.ID?
    /// Set only by arrow keys: hovering selects a row too, and scrolling on hover made the list jump under the pointer.
    @State private var keyboardTarget: Clip.ID?
    @Namespace private var highlight
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let recentWindow: TimeInterval = OptionBuilder.freshFor
    /// Content starts 24 pt from the panel edge; cards, fields and row highlights sit 12 pt in.
    static let edge: CGFloat = 12
    static let fill = Color.primary.opacity(0.07)
    private static let rowHeight: CGFloat = 40
    private static let maxListHeight: CGFloat = 340

    private var matches: [Clip] {
        guard !filter.isEmpty else { return clips }
        return clips.filter {
            $0.text.localizedCaseInsensitiveContains(filter) || $0.sourceApp.localizedCaseInsensitiveContains(filter)
        }
    }

    /// What arrows, Return and ⌘1–⌘9 walk: the clipboard card first, then the rows, in screen order.
    private var navClips: [Clip] { Array(matches.prefix(30)) }
    private var clipboard: Clip? { filter.isEmpty ? clips.first : nil }
    private var listed: [Clip] { clipboard == nil ? navClips : Array(navClips.dropFirst()) }
    private var sections: [(title: String, rows: [Clip])] {
        filter.isEmpty ? Self.sections(listed) : [("", listed)]
    }

    /// Pinned first, then by age: the last 2 hours (what smart paste draws from), the rest of today, older.
    static func sections(_ clips: [Clip]) -> [(title: String, rows: [Clip])] {
        let unpinned = clips.filter { !$0.pinned }
        let age = { (c: Clip) in -c.copiedAt.timeIntervalSinceNow }
        let today = Calendar.current.startOfDay(for: Date())
        return [("Pinned", clips.filter(\.pinned)),
                ("Recent", unpinned.filter { age($0) < recentWindow }),
                ("Today", unpinned.filter { age($0) >= recentWindow && $0.copiedAt >= today }),
                ("Older", unpinned.filter { age($0) >= recentWindow && $0.copiedAt < today })]
            .filter { !$0.rows.isEmpty }
    }
    private var selected: Clip.ID? { selection ?? navClips.first?.id }

    var body: some View {
        VStack(spacing: 0) {
            if !clips.isEmpty { searchField }
            if let clipboard { clipboardCard(clipboard) }
            list
            Divider().opacity(0.5)
            modeRow
            footer
        }
        .frame(width: 340)
        .background(KeyNavHelper(
            onArrow: moveSelection,
            onReturn: { if let c = navClips.first(where: { $0.id == selected }) { actions.paste(c) } },
            hasSelection: { selected != nil },
            onEscape: {
                guard !filter.isEmpty else { return false }
                filter = ""
                return true
            }))
        .onChange(of: filter) { _, _ in selection = nil }
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: clips.map(\.id))
        .task { searchFocused = true }
    }

    private func moveSelection(_ delta: Int) {
        let ids = navClips.map(\.id)
        guard !ids.isEmpty else { return }
        let cur = ids.firstIndex(of: selected ?? "") ?? (delta > 0 ? -1 : ids.count)
        selection = ids[min(ids.count - 1, max(0, cur + delta))]
        keyboardTarget = selection
    }

    private func shortcutIndex(_ clip: Clip) -> Int? {
        navClips.firstIndex(of: clip).flatMap { $0 < 9 ? $0 : nil }
    }

    // MARK: Header

    /// Status the user rarely acts on lives in the footer; the details sit in its tooltip.
    private var statusLabel: some View {
        HStack(spacing: 6) {
            Circle().fill(status.color).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(status.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(.leading, 12)
        .contentShape(Rectangle())
        .help([status.note, detail.map { "Last paste: \($0)" }].compactMap { $0 }.joined(separator: "\n"))
        .accessibilityElement(children: .combine)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Search history", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            if !filter.isEmpty {
                Button { filter = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Self.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, Self.edge)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: Clipboard

    private func clipboardCard(_ clip: Clip) -> some View {
        let isSelected = selected == clip.id
        return Button { actions.paste(clip) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Clipboard")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    ReturnHint(visible: isSelected)
                }
                ClipLook.of(clip).title(clip.text, weight: .medium)
                    .lineLimit(2)
                    .truncationMode(ClipLook.of(clip).truncation)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    SourceAppIcon(clip: clip, size: 12)
                    Text(ClipLook.meta(clip)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Self.fill,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .onHover { if $0 { selection = clip.id } }
        .modifier(RowShortcut(index: 0))
        .accessibilityLabel("Paste your clipboard, \(clip.preview)")
        .padding(.horizontal, Self.edge)
        .padding(.bottom, 6)
    }

    // MARK: History

    @ViewBuilder
    private var list: some View {
        if clips.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 24)).foregroundStyle(.secondary)
                Text("Nothing copied yet").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Text("Copy text in any app and it shows up here.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
        } else if navClips.isEmpty {
            Text("No clips match “\(filter)”")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else if !listed.isEmpty {
            let sections = sections
            let contentHeight = CGFloat(listed.count) * Self.rowHeight
                + CGFloat(sections.filter { !$0.0.isEmpty }.count) * 22 + 6
            let overflows = contentHeight > Self.maxListHeight
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sections, id: \.0) { title, rows in
                            if !title.isEmpty {
                                Text(title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 12)
                                    .frame(height: 22, alignment: .bottomLeading)
                            }
                            ForEach(rows) { clip in
                                ClipRow(clip: clip, isSelected: selected == clip.id,
                                        shortcut: shortcutIndex(clip), actions: actions)
                                    .frame(height: Self.rowHeight)
                                    .background {
                                        // One highlight that glides between rows instead of blinking row to row.
                                        if selected == clip.id {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(Self.fill)
                                                .matchedGeometryEffect(id: "highlight", in: highlight)
                                        }
                                    }
                                    .onHover { if $0 { selection = clip.id } }
                                    .id(clip.id)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .padding(.horizontal, Self.edge)
                    .padding(.bottom, overflows ? 14 : 6)
                    .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0), value: selected)
                }
                .frame(height: min(contentHeight, Self.maxListHeight))
                .mask(ScrollFade(active: overflows, height: min(contentHeight, Self.maxListHeight)))
                .onChange(of: keyboardTarget) { _, target in
                    if let target { proxy.scrollTo(target) }
                }
            }
        }
    }

    // MARK: Controls

    private var modeRow: some View {
        HStack(spacing: 10) {
            Text("⌘V pastes").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Picker("⌘V pastes", selection: $mode) {
                ForEach(PasteMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .help(modeHelp)
        }
        .padding(.leading, 24)
        .padding(.trailing, Self.edge)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var modeHelp: String {
        switch mode {
        case .smart: "⌘V pastes your clipboard, adapted to the field. Choices appear only when unsure."
        case .queue: "Each ⌘V pastes the next clip, oldest first."
        case .plain: "⌘V is untouched. The choices shortcut still works."
        }
    }

    private var footer: some View {
        HStack(spacing: 2) {
            statusLabel
            Spacer()
            FooterButton(title: "History", icon: "clock.arrow.circlepath", action: actions.openHistory)
            FooterButton(title: "Settings", icon: "gearshape", action: actions.openSettings)
            Menu {
                Button(paused ? "Resume Copying" : "Pause Copying") { paused.toggle() }
                Divider()
                Button("Quit Cue") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .medium))
                    .frame(width: 26, height: 24)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(.secondary)
            .accessibilityLabel("More")
        }
        .padding(.leading, Self.edge)
        .padding(.trailing, Self.edge)
        .padding(.top, 4)
        .padding(.bottom, 9)
    }
}

/// How a clip shows itself: link, mono and plain styling, and truncation that keeps the part people recognize.
enum ClipLook {
    case link, email, number, code, multiline, text

    static func of(_ option: PasteOption) -> ClipLook {
        switch option.kind {
        case .url: .link
        case .email: .email
        case .phone: .number
        case .code: .code
        case .text: of(option.clip)
        }
    }

    static func of(_ clip: Clip) -> ClipLook {
        let t = clip.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if clip.isURL { return .link }
        if !t.contains(where: \.isWhitespace), t.contains("@"), t.contains(".") { return .email }
        if t.count >= 4, t.allSatisfy({ $0.isNumber || " +-().,".contains($0) }) { return .number }
        if t.count >= 6, !t.contains(where: \.isWhitespace), t.contains(where: \.isNumber), t.contains(where: \.isLetter) {
            return .code
        }
        if t.contains("\n") { return .multiline }
        return .text
    }

    /// Links keep their host and their last path part; prose keeps its opening words.
    var truncation: Text.TruncationMode { self == .link ? .middle : .tail }

    /// Links read as host + path with the scheme dropped; numbers and codes are monospaced so digits line up.
    /// `muted` colors a link's path; a row drawn on the accent passes white.
    func title(_ text: String, weight: Font.Weight = .regular, muted: Color = .secondary) -> Text {
        let preview = Clip.preview(of: text)
        switch self {
        case .link:
            guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let host = url.host() else { return Text(preview).font(.system(size: 13, weight: weight)) }
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            let rest = url.path() + (url.query().map { "?\($0)" } ?? "")
            return Text(bare).font(.system(size: 13, weight: weight == .regular ? .medium : .semibold))
                + Text(rest == "/" ? "" : rest).font(.system(size: 13, weight: weight)).foregroundColor(muted)
        case .number, .code:
            return Text(preview).font(.system(size: 13, weight: weight, design: .monospaced))
        default:
            return Text(preview).font(.system(size: 13, weight: weight))
        }
    }

    static func meta(_ clip: Clip) -> String {
        [age(clip.copiedAt), clip.sourceApp].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// "18d ago" says less than "1 Oct" past a week.
    static func age(_ date: Date) -> String {
        -date.timeIntervalSinceNow < 7 * 86400 ? date.relativeAge : date.formatted(.dateTime.day().month(.abbreviated))
    }
}

struct ClipRow: View {
    let clip: Clip
    let isSelected: Bool
    let shortcut: Int?
    let actions: MenuPanelActions
    @State private var hovered = false

    var body: some View {
        let look = ClipLook.of(clip)
        Button { actions.paste(clip) } label: {
            HStack(spacing: 10) {
                SourceAppIcon(clip: clip, size: 18)
                VStack(alignment: .leading, spacing: 1) {
                    look.title(clip.text)
                        .lineLimit(1)
                        .truncationMode(look.truncation)
                    Text(ClipLook.meta(clip))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if hovered {
                    RowAction(icon: clip.pinned ? "pin.slash" : "pin", label: clip.pinned ? "Unpin" : "Pin") {
                        actions.togglePin(clip)
                    }
                    RowAction(icon: "trash", label: "Delete") { actions.remove(clip) }
                } else if clip.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
                if isSelected, !hovered { ReturnHint(visible: true) }
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { inside in withAnimation(.easeOut(duration: 0.12)) { hovered = inside } }
        .modifier(RowShortcut(index: shortcut))
        .accessibilityLabel("Paste \(clip.preview), \(ClipLook.meta(clip))")
    }
}

private struct RowAction: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .help(label)
        .accessibilityLabel(label)
        .transition(.opacity)
    }
}

/// Return pastes the highlighted clip; the hint sits only on that one.
private struct ReturnHint: View {
    let visible: Bool

    var body: some View {
        Text("↩")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.tertiary)
            .opacity(visible ? 1 : 0)
            .accessibilityHidden(true)
    }
}

private struct FooterButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(hovered ? .primary : .secondary)
                .frame(width: 28, height: 24)
                .background(hovered ? Color.primary.opacity(0.07) : .clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .onHover { hovered = $0 }
        .help(title)
        .accessibilityLabel(title)
    }
}

/// Press feedback: a slight scale while held.
private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A list that scrolls fades out at its bottom edge, so a cut row reads as "more below".
private struct ScrollFade: View {
    let active: Bool
    let height: CGFloat

    var body: some View {
        LinearGradient(stops: [.init(color: active ? .clear : .black, location: 0),
                               .init(color: .black, location: active ? 8 / max(height, 18) : 0),
                               .init(color: .black, location: active ? 1 - 18 / max(height, 18) : 1),
                               .init(color: active ? .clear : .black, location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// ⌘1–⌘9 pastes the matching clip while the panel is key.
private struct RowShortcut: ViewModifier {
    let index: Int?

    func body(content: Content) -> some View {
        if let index, index < 9 {
            content.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        } else {
            content
        }
    }
}
