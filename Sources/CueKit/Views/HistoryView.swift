import AppKit
import SwiftUI

/// The History window. Maps the app's state onto `HistoryPanel`, which only draws plain values.
public struct HistoryView: View {
    var model: AppModel

    public var body: some View {
        HistoryPanel(
            clips: model.store.clips,
            queued: model.settings.queueMode ? model.store.queue.count : nil,
            smartPasteKeys: smartPasteKeys,
            actions: MenuPanelActions(
                paste: { model.pasteIntoFrontApp($0) },
                togglePin: { model.store.togglePin($0) },
                remove: { model.store.remove($0) },
                openHistory: {},
                openSettings: { model.open(id: "settings") }))
    }

    private var smartPasteKeys: String {
        if model.settings.triggerMode == .intercept { return "⌘V" }
        return model.settings.hotkey(for: .smartPaste).displayString
    }
}

/// Every clip: the list on the left, the selected clip in full on the right. Clicking selects; Return or Paste
/// pastes into the app you were in.
struct HistoryPanel: View {
    let clips: [Clip]
    let queued: Int?
    let smartPasteKeys: String
    let actions: MenuPanelActions

    @State private var filter = ""
    @State private var selection: Clip.ID?
    @State private var keyboardTarget: Clip.ID?
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var matches: [Clip] {
        guard !filter.isEmpty else { return clips }
        return clips.filter {
            $0.text.localizedCaseInsensitiveContains(filter) || $0.sourceApp.localizedCaseInsensitiveContains(filter)
        }
    }
    private var sections: [(title: String, rows: [Clip])] {
        filter.isEmpty ? MenuPanel.sections(matches) : [("", matches)]
    }
    private var navList: [Clip] { sections.flatMap(\.rows) }
    private var selected: Clip? { navList.first { $0.id == selection } ?? navList.first }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                searchField
                if matches.isEmpty {
                    ContentUnavailableView(
                        filter.isEmpty ? "Nothing copied yet" : "No matches",
                        systemImage: filter.isEmpty ? "doc.on.clipboard" : "magnifyingglass",
                        description: Text(filter.isEmpty
                            ? "Copy some text and it shows up here. Then press \(smartPasteKeys) in any text field."
                            : "Try a different search."))
                        .frame(maxHeight: .infinity)
                } else {
                    list
                }
            }
            .frame(width: 300)
            Divider()
            Group {
                if let selected {
                    ClipDetail(clip: selected, actions: actions, copyAgain: copyAgain).id(selected.id)
                } else {
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity, alignment: .top)
        .background(KeyNavHelper(
            onArrow: moveSelection,
            onReturn: { if let selected { actions.paste(selected) } },
            hasSelection: { selected != nil },
            onEscape: {
                guard !filter.isEmpty else { return false }
                filter = ""
                return true
            }))
        .onChange(of: filter) { _, _ in selection = nil }
        .task { searchFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Search history", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            if let queued {
                Text("\(queued) queued")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(MenuPanel.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(12)
    }

    private var list: some View {
        let picking = MenuPanelActions(paste: { selection = $0.id }, togglePin: actions.togglePin,
                                       remove: actions.remove, openHistory: {}, openSettings: {})
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.0) { title, rows in
                        if !title.isEmpty {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .frame(height: 26, alignment: .bottomLeading)
                        }
                        ForEach(rows) { clip in
                            ClipRow(clip: clip, isSelected: selected?.id == clip.id, shortcut: nil, actions: picking)
                                .frame(height: 42)
                                .background(selected?.id == clip.id ? Color.accentColor.opacity(0.16) : .clear,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .contextMenu { menu(clip) }
                                .id(clip.id)
                        }
                    }
                }
                .padding(.horizontal, MenuPanel.edge)
                .padding(.bottom, 10)
            }
            .onChange(of: keyboardTarget) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    @ViewBuilder private func menu(_ clip: Clip) -> some View {
        Button("Paste into Current App") { actions.paste(clip) }
        Button("Copy Again") { copyAgain(clip) }
        Button(clip.pinned ? "Unpin" : "Pin") { actions.togglePin(clip) }
        Divider()
        Button("Delete", role: .destructive) { actions.remove(clip) }
    }

    private func moveSelection(_ delta: Int) {
        let ids = navList.map(\.id)
        guard !ids.isEmpty else { return }
        let cur = ids.firstIndex(of: selected?.id ?? "") ?? (delta > 0 ? -1 : ids.count)
        selection = ids[min(ids.count - 1, max(0, cur + delta))]
        keyboardTarget = selection
    }

    /// Writing the pasteboard makes it the newest clip; the monitor records it again.
    private func copyAgain(_ clip: Clip) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clip.text, forType: .string)
    }
}

/// One clip in full: what it is, all of it, where it came from, and what you can do with it.
struct ClipDetail: View {
    let clip: Clip
    let actions: MenuPanelActions
    let copyAgain: (Clip) -> Void
    @State private var revealed = false

    var body: some View {
        let look = ClipLook.of(clip)
        let short = clip.text.count <= 60 && !clip.text.contains("\n")
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                LookTile(look: look, text: clip.text)
                Text(look.label).font(.system(size: 13, weight: .semibold))
                Spacer()
                if clip.pinned {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 52)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if look == .color, let color = Color(hex: clip.text) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(color).frame(height: 96)
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    }
                    Text(look == .secret && !revealed ? ClipLook.masked(clip.text) : clip.text)
                        .font(short ? .system(size: 20, weight: .medium, design: look.isMono ? .monospaced : .default)
                              : look.isMono ? .system(size: 13, design: .monospaced) : .system(size: 14))
                        .lineSpacing(look.isMono ? 3 : 4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if look == .secret {
                        Button(revealed ? "Hide" : "Show") { revealed.toggle() }
                            .controlSize(.small)
                    }
                }
                .padding(20)
            }
            .frame(maxHeight: .infinity)
            Divider()
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                GridRow {
                    label("Source")
                    HStack(spacing: 6) {
                        if clip.sourceBundleID != nil { SourceAppIcon(clip: clip, size: 14) }
                        Text(clip.sourceApp.isEmpty ? "Unknown" : clip.sourceApp)
                    }
                }
                GridRow { label("Copied"); Text(clip.copiedAt.formatted(date: .abbreviated, time: .shortened)) }
                GridRow { label("Size"); Text(size(look)) }
                GridRow {
                    label("Pasted")
                    Text(clip.timesPasted == 0 ? "Not yet" : clip.timesPasted == 1 ? "Once" : "\(clip.timesPasted) times")
                }
            }
            .font(.system(size: 12))
            .monospacedDigit()
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            Divider()
            HStack(spacing: 8) {
                Button("Paste") { actions.paste(clip) }
                    .buttonStyle(.borderedProminent)
                    .help("Paste into the app you were using (Return)")
                Button("Copy") { copyAgain(clip) }
                Spacer()
                Button { actions.togglePin(clip) } label: {
                    Image(systemName: clip.pinned ? "pin.slash" : "pin")
                }
                .help(clip.pinned ? "Unpin" : "Pin")
                .accessibilityLabel(clip.pinned ? "Unpin" : "Pin")
                Button(role: .destructive) { actions.remove(clip) } label: { Image(systemName: "trash") }
                    .help("Delete")
                    .accessibilityLabel("Delete")
            }
            .controlSize(.regular)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    private func size(_ look: ClipLook) -> String {
        let lines = clip.text.split(separator: "\n", omittingEmptySubsequences: false).count
        let words = clip.text.split(whereSeparator: { $0.isWhitespace }).count
        var parts = ["\(clip.text.count) characters"]
        if lines > 1 { parts.append("\(lines) lines") } else if words > 1 { parts.append("\(words) words") }
        return parts.joined(separator: " · ")
    }
}
