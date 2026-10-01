import AppKit
import SwiftUI

public struct HistoryView: View {
    var model: AppModel
    @State private var filter = ""
    @State private var hovered: Clip.ID?

    private var visible: [Clip] {
        guard !filter.isEmpty else { return model.store.clips }
        return model.store.clips.filter { $0.preview.localizedCaseInsensitiveContains(filter) }
    }

    private var pinned: [Clip] { visible.filter(\.pinned) }
    private var recent: [Clip] { visible.filter { !$0.pinned } }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.tertiary)
                TextField("Search clipboard history", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if model.settings.queueMode {
                    Text("\(model.store.queue.count) queued")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(OBTheme.insetFill, in: Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(OBTheme.insetFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider().opacity(0.6)

            if visible.isEmpty {
                ContentUnavailableView(
                    filter.isEmpty ? "Nothing copied yet" : "No matches",
                    systemImage: "doc.on.clipboard",
                    description: Text(filter.isEmpty
                        ? "Copy some text and it'll show up here."
                        : "Try a different search.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 1, pinnedViews: .sectionHeaders) {
                        if !pinned.isEmpty {
                            clipSection("Pinned", pinned)
                        }
                        if !recent.isEmpty {
                            clipSection(pinned.isEmpty ? nil : "Recent", recent)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 360)
    }

    private func clipSection(_ title: String?, _ clips: [Clip]) -> some View {
        Section {
            ForEach(clips) { clip in
                row(clip)
            }
        } header: {
            if let title {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 3)
            }
        }
    }

    private func row(_ clip: Clip) -> some View {
        Button {
            model.pasteIntoFrontApp(clip)
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    OBTheme.insetFill
                    if let icon = SourceAppIcon.image(for: clip.sourceBundleID) {
                        Image(nsImage: icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: clip.isURL ? "link" : "text.alignleft")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.preview)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(meta(clip))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if clip.queued {
                    Image(systemName: "number")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Button { model.store.togglePin(clip) } label: {
                    Image(systemName: clip.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(clip.pinned ? OBTheme.foldEdge
                                                    : Color(nsColor: .quaternaryLabelColor))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(clip.pinned ? "Unpin" : "Pin — pins survive the history cap")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(hovered == clip.id ? OBTheme.insetFill : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in hovered = inside ? clip.id : nil }
        .contextMenu {
            Button("Paste into current app") { model.pasteIntoFrontApp(clip) }
            Button("Copy again") { copyAgain(clip) }
            Button(clip.pinned ? "Unpin" : "Pin") { model.store.togglePin(clip) }
            Divider()
            Button("Delete", role: .destructive) { model.store.remove(clip) }
        }
    }

    private func meta(_ clip: Clip) -> String {
        var parts = [clip.copiedAt.relativeAge]
        if !clip.sourceApp.isEmpty { parts.append(clip.sourceApp) }
        if clip.timesPasted > 0 { parts.append("pasted \(clip.timesPasted)×") }
        return parts.joined(separator: " · ")
    }

    /// Writing the pasteboard makes it the newest clip — the monitor re-captures it.
    private func copyAgain(_ clip: Clip) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(clip.text, forType: .string)
    }
}
