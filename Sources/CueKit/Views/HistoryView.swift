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
        return (model.settings.hotkey(for: HotkeyManager.Action.smartPaste.rawValue)
            ?? HotkeyManager.Action.smartPaste.default).displayString
    }
}

/// Every clip, in the menu panel's rows and sections, in a window that resizes.
struct HistoryPanel: View {
    let clips: [Clip]
    let queued: Int?
    let smartPasteKeys: String
    let actions: MenuPanelActions

    @State private var filter = ""
    @State private var selection: Clip.ID?
    @State private var keyboardTarget: Clip.ID?
    @Namespace private var highlight
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
    private var selected: Clip.ID? { selection ?? navList.first?.id }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider().opacity(0.5)
            if matches.isEmpty {
                ContentUnavailableView(
                    filter.isEmpty ? "Nothing copied yet" : "No matches",
                    systemImage: "doc.on.clipboard",
                    description: Text(filter.isEmpty
                        ? "Copy some text and it’ll show up here. Then press \(smartPasteKeys) in any text field."
                        : "Try a different search."))
                    .frame(maxHeight: .infinity)
            } else {
                list
            }
        }
        .frame(minWidth: 460, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity, alignment: .top)
        .background(KeyNavHelper(
            onArrow: moveSelection,
            onReturn: { if let c = navList.first(where: { $0.id == selected }) { actions.paste(c) } },
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(sections, id: \.0) { title, rows in
                        if !title.isEmpty {
                            Text(title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .frame(height: 26, alignment: .bottomLeading)
                        }
                        ForEach(rows) { clip in
                            ClipRow(clip: clip, isSelected: selected == clip.id, shortcut: nil, actions: actions)
                                .frame(height: 40)
                                .background {
                                    if selected == clip.id {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(MenuPanel.fill)
                                            .matchedGeometryEffect(id: "highlight", in: highlight)
                                    }
                                }
                                .onHover { if $0 { selection = clip.id } }
                                .contextMenu { menu(clip) }
                                .id(clip.id)
                        }
                    }
                }
                .padding(.horizontal, MenuPanel.edge)
                .padding(.vertical, 6)
                .animation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0), value: selected)
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
        let cur = ids.firstIndex(of: selected ?? "") ?? (delta > 0 ? -1 : ids.count)
        selection = ids[min(ids.count - 1, max(0, cur + delta))]
        keyboardTarget = selection
    }

    /// Writing the pasteboard makes it the newest clip; the monitor records it again.
    private func copyAgain(_ clip: Clip) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clip.text, forType: .string)
    }
}
