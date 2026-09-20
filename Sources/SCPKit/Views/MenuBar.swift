import SwiftUI

public struct MenuBarView: View {
    var model: AppModel

    public var body: some View {
        Text(statusLine)
            .foregroundStyle(.secondary)
        Divider()

        Toggle("Queue mode", isOn: queueBinding)
        if model.settings.queueMode {
            Text("\(model.store.queue.count) in queue")
                .foregroundStyle(.secondary)
        }
        Toggle("Intercept ⌘V", isOn: interceptBinding)
        Toggle("Pause monitoring", isOn: pausedBinding)
        Divider()

        Button("History…") { model.open(id: "history") }
        Button("Settings…") { model.open(id: "settings") }
        Divider()

        Button("Run self-check") { Task { await model.runSelfCheck() } }
        if let result = model.selfCheckResult {
            Text(result).foregroundStyle(.secondary)
        }
        Divider()

        Button("Quit") { NSApp.terminate(nil) }
    }

    private var statusLine: String {
        var parts = [model.trusted ? "ready" : "needs Accessibility"]
        switch model.settings.provider {
        case .direct: parts.append("jev direct")
        case .gateway: parts.append("jev via gateway")
        case .none: parts.append("heuristic mode")
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
