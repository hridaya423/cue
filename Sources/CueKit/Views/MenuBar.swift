import SwiftUI

/// The menu-bar panel (.window MenuBarExtra): status header, searchable
/// recent clips, mode chips, and a quiet icon footer. Click a clip to
/// paste it into the app you were in.
public struct MenuBarView: View {
    var model: AppModel
    @State private var filter = ""
    /// Hover and arrow keys share one selection — moving the mouse picks
    /// a row, ↑↓ walk from there, Return pastes it.
    @State private var selection: Clip.ID?
    /// Search takes focus on open — the panel is type-to-filter from the
    /// first keystroke, like a launcher.
    @FocusState private var searchFocused: Bool

    private var visibleClips: [Clip] {
        let clips = model.store.clips
        guard !filter.isEmpty else { return clips }
        return clips.filter { $0.preview.localizedCaseInsensitiveContains(filter) }
    }

    /// The rows actually rendered — nav and ⌘N shortcuts operate on this.
    private var navClips: [Clip] { Array(visibleClips.prefix(10)) }

    public var body: some View {
        VStack(spacing: 0) {
            header
            if !model.store.clips.isEmpty {
                searchField
            }
            clipList
            Divider().opacity(0.6)
            controlsRow
            Divider().opacity(0.6)
            footer
        }
        .frame(width: 330)
        .background(KeyNavHelper(
            onArrow: { moveSelection($0) },
            onReturn: { if let c = selectedClip { model.pasteIntoFrontApp(c) } },
            hasSelection: { selectedClip != nil },
            onEscape: {
                if filter.isEmpty { return false }
                filter = ""
                return true
            }))
        .onChange(of: filter) { _, _ in selection = nil }
        .task { searchFocused = true }
    }

    /// The row Return acts on — explicit selection, else the top match.
    private var selectedClip: Clip? {
        selection.flatMap { id in navClips.first { $0.id == id } } ?? navClips.first
    }

    /// Effective row highlight: the explicit selection, or the top row so
    /// Return's target is always visible.
    private var effectiveSelection: Clip.ID? { selection ?? navClips.first?.id }

    private func moveSelection(_ delta: Int) {
        let ids = navClips.map(\.id)
        guard !ids.isEmpty else { return }
        let cur = ids.firstIndex(of: effectiveSelection ?? "") ?? (delta > 0 ? -1 : ids.count)
        selection = ids[min(ids.count - 1, max(0, cur + delta))]
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text("Cue")
                    .font(.system(size: 13, weight: .semibold))
                Text(statusLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
            }
            if let action = model.controller.lastAction {
                Text(action)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.leading, 13)
            }
            if model.settings.triggerMode == .intercept, !model.trusted {
                Label("⌘V interception paused — needs Accessibility",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .padding(.leading, 13)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var statusColor: Color {
        if !model.monitor.running { return .gray }
        if !model.trusted { return .orange }
        switch model.providerStatus.state {
        case .ok: return .green
        case .unreachable: return .red
        case .unknown:
            // No call yet — the managed model's boot state is the signal.
            if case .local = model.settings.provider, let r = model.selectedLocal {
                switch model.models.status(of: r.spec.id) {
                case .running: return .green
                case .failed: return .red
                default: return .orange
                }
            }
            return model.settings.provider == .off ? .gray : .orange
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            TextField("Search clips", text: $filter)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($searchFocused)
            if !filter.isEmpty {
                Button { filter = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(OBTheme.insetFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Clips

    @ViewBuilder
    private var clipList: some View {
        if model.store.clips.isEmpty {
            VStack(spacing: 5) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                Text("Nothing copied yet")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Copy text anywhere — it'll be here, and \(hotkeyHint) smart-pastes it.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else if visibleClips.isEmpty {
            Text("No matches")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        } else {
            // Explicit height: a ScrollView collapses to zero inside the
            // auto-sizing MenuBarExtra window — the content must size itself.
            let rows = min(visibleClips.count, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(navClips.enumerated()), id: \.element.id) { i, clip in
                            clipRow(clip, index: i)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .frame(height: min(CGFloat(rows) * 45 + 8, 320))
                .onChange(of: selection) { _, sel in
                    if let sel { proxy.scrollTo(sel, anchor: .center) }
                }
            }
        }
    }

    private func clipRow(_ clip: Clip, index: Int) -> some View {
        Button {
            model.pasteIntoFrontApp(clip)
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    OBTheme.insetFill
                    SourceAppIcon(clip: clip, size: 16)
                }
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(clip.preview)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(meta(clip))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                if clip.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(OBTheme.foldEdge)
                }
                Text("⌘\(index + 1)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.quaternary)
                    .opacity(index < 9 ? 1 : 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(effectiveSelection == clip.id ? OBTheme.insetFill : .clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { selection = clip.id } }
        .accessibilityLabel("Paste \(clip.preview)")
        .id(clip.id)
        .modifier(RowShortcut(index: index))
    }

    /// ⌘1…⌘9 pastes the nth visible clip while the panel is key.
    private struct RowShortcut: ViewModifier {
        let index: Int
        func body(content: Content) -> some View {
            if index < 9 {
                content.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")),
                                         modifiers: .command)
            } else {
                content
            }
        }
    }

    private func meta(_ clip: Clip) -> String {
        var parts = [clip.copiedAt.relativeAge]
        if !clip.sourceApp.isEmpty { parts.append(clip.sourceApp) }
        if clip.timesPasted > 0 { parts.append("pasted \(clip.timesPasted)×") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Controls

    private var controlsRow: some View {
        HStack(spacing: 6) {
            ModeChip(title: "Intercept ⌘V", isOn: interceptBinding,
                     hint: "Smart-paste runs on every paste")
            ModeChip(title: queueChipTitle, isOn: queueBinding,
                     hint: "FIFO queue: each paste takes the next queued clip")
            ModeChip(title: "Paused", isOn: pausedBinding,
                     hint: "Stop watching the clipboard")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var queueChipTitle: String {
        model.settings.queueMode && !model.store.queue.isEmpty
            ? "Queue \(model.store.queue.count)"
            : "Queue"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 2) {
            footerButton("clock.arrow.circlepath", "History") { model.open(id: "history") }
            footerButton("gearshape", "Settings") { model.open(id: "settings") }
            Spacer()
            footerButton("power", "Quit Cue") { NSApp.terminate(nil) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func footerButton(_ icon: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Status + bindings

    private var hotkeyHint: String {
        model.settings.hotkey(for: HotkeyManager.Action.smartPaste.rawValue)?.displayString ?? "⌃⌥V"
    }

    private var statusLine: String {
        var parts = [model.monitor.running
                     ? (model.trusted ? "ready" : "needs Accessibility")
                     : "paused"]
        switch model.settings.provider {
        case .jevDirect: parts.append("jev direct")
        case .jevGateway: parts.append("jev via gateway")
        case .local:
            if let r = model.selectedLocal {
                var s = "\(r.spec.title.lowercased()) \(r.variant.paramsLabel)"
                switch model.models.status(of: r.spec.id) {
                case .running: s += " · running"
                case .starting: s += " · starting"
                case .installing: s += " · installing"
                case .installed: s += " · stopped"
                case .failed: s += " · failed"
                case .notInstalled: s += " · not installed"
                }
                parts.append(s)
            } else {
                parts.append("local model")
            }
        case .custom: parts.append("custom endpoint")
        case .off: parts.append("off")
        }
        if model.providerStatus.state == .unreachable { parts.append("unreachable") }
        // Mirrors the decision path: scrubbing only happens when the resolved
        // endpoint is actually remote — a loopback custom endpoint is local.
        if model.settings.effectivePIIRedaction,
           model.makeProvider()?.isRemote == true {
            parts.append("pii scrubbed")
        }
        parts.append("\(model.store.clips.count) clips")
        return parts.joined(separator: " · ")
    }

    private var queueBinding: Binding<Bool> {
        Binding(get: { model.settings.queueMode },
                set: { v in
                    model.settings.queueMode = v
                    if !v { model.store.clearQueue() }
                })
    }
    private var interceptBinding: Binding<Bool> {
        Binding(get: { model.settings.triggerMode == .intercept },
                set: { v in
                    model.settings.triggerMode = v ? .intercept : .hotkey
                    model.hotkeys.interceptCmdV = v
                })
    }
    private var pausedBinding: Binding<Bool> {
        Binding(get: { !model.monitor.running },
                set: { paused in paused ? model.monitor.stop() : model.monitor.start() })
    }
}

/// A small pill that fills with the coral accent when on —
/// Control-Center-style toggles for the panel's controls row.
/// (Toggle+buttonStyle leaks the tint into off-state labels on macOS,
/// so this is an explicit Button for a truthful on/off contrast.)
private struct ModeChip: View {
    let title: String
    @Binding var isOn: Bool
    var hint: String = ""

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isOn ? .white : .secondary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .background(Capsule().fill(isOn ? OBTheme.foldEdge
                                                : Color.primary.opacity(0.07)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(isOn ? 0 : 0.12),
                                                lineWidth: 0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(hint)
    }
}
