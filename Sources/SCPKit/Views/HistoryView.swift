import AppKit
import SwiftUI

public struct HistoryView: View {
    var model: AppModel
    @State private var filter = ""

    private var visible: [Clip] {
        guard !filter.isEmpty else { return model.store.clips }
        return model.store.clips.filter { $0.preview.localizedCaseInsensitiveContains(filter) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $filter)
                    .textFieldStyle(.plain)
                if model.settings.queueMode {
                    Text("\(model.store.queue.count) queued")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)

            Divider()

            if visible.isEmpty {
                ContentUnavailableView(
                    filter.isEmpty ? "Nothing copied yet" : "No matches",
                    systemImage: "doc.on.clipboard",
                    description: Text(filter.isEmpty
                        ? "Copy some text and it'll show up here."
                        : "Try a different search.")
                )
            } else {
                List(visible) { clip in
                    HStack(spacing: 10) {
                        Image(systemName: clip.isURL ? "link" : "text.alignleft")
                            .foregroundStyle(.secondary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clip.preview)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(meta(clip))
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if clip.queued {
                            Image(systemName: "number")
                                .foregroundStyle(.secondary)
                        }
                        Button { model.store.togglePin(clip) } label: {
                            Image(systemName: clip.pinned ? "pin.fill" : "pin")
                                .foregroundStyle(clip.pinned ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(clip.pinned ? "Unpin" : "Pin")
                    }
                    .contextMenu {
                        Button("Copy again") { copyAgain(clip) }
                        Button(clip.pinned ? "Unpin" : "Pin") { model.store.togglePin(clip) }
                        Divider()
                        Button("Delete", role: .destructive) { model.store.remove(clip) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 460, minHeight: 360)
    }

    private func meta(_ clip: Clip) -> String {
        var parts = [clip.copiedAt.relativeAge]
        if !clip.sourceApp.isEmpty { parts.append("from \(clip.sourceApp)") }
        if clip.timesPasted > 0 { parts.append("pasted \(clip.timesPasted)×") }
        return parts.joined(separator: " · ")
    }

    /// Writing the pasteboard makes it the newest clip — the monitor re-captures it.
    private func copyAgain(_ clip: Clip) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clip.text, forType: .string)
    }
}
