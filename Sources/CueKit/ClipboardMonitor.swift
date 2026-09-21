import AppKit
import Foundation

/// Polls NSPasteboard.changeCount and feeds new text/URL clips into the store.
@MainActor @Observable
public final class ClipboardMonitor {
    public private(set) var running = false

    private var lastChangeCount = 0
    private var timer: Timer?
    private let store: ClipStore
    private let settings: AppSettings

    /// Set while we write the pasteboard ourselves, so our own pastes aren't captured.
    public var suppressCapture = false

    public init(store: ClipStore, settings: AppSettings = .shared) {
        self.store = store
        self.settings = settings
    }

    public func start() {
        guard !running else { return }
        running = true
        lastChangeCount = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        running = false
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard !suppressCapture else { return }
        guard let text = pb.string(forType: .string), !text.isEmpty else { return }

        let source = NSWorkspace.shared.frontmostApplication
        guard !settings.excludedBundleIDs.contains(source?.bundleIdentifier ?? "") else { return }

        store.add(Clip(
            text: text,
            kind: Clip.classify(text),
            sourceApp: source?.localizedName ?? "",
            sourceBundleID: source?.bundleIdentifier,
            queued: settings.queueMode
        ))
    }
}
