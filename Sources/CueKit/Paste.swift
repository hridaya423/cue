import Carbon
import Cocoa
import Foundation

/// Writes the pasteboard and posts synthetic key events into the focused app.
/// Requires Accessibility trust for CGEvent posting.
@MainActor
public final class PasteExecutor {
    private let monitor: ClipboardMonitor
    private let hotkeys: HotkeyManager

    /// Optional hook for tests/self-check: observed instead of actually posting keys.
    public var onWouldPost: ((String) -> Void)?

    public init(monitor: ClipboardMonitor, hotkeys: HotkeyManager) {
        self.monitor = monitor
        self.hotkeys = hotkeys
    }

    /// Plain ⌘V — posts the keystroke without touching the pasteboard.
    /// Used for pasteLatest/raw-paste: "latest" means whatever is on the
    /// pasteboard right now, which our monitor may not have seen yet.
    public func pasteCurrent() {
        hotkeys.isSynthesizing = true
        if let onWouldPost {
            onWouldPost(NSPasteboard.general.string(forType: .string) ?? "")
        } else {
            postKey(keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.hotkeys.isSynthesizing = false
        }
    }

    /// Put `text` on the pasteboard and send ⌘V to the focused app.
    public func paste(_ text: String) {
        hotkeys.isSynthesizing = true
        monitor.suppressCapture = true

        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        if let onWouldPost {
            onWouldPost(text)
        } else {
            postKey(keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand)
        }

        // Re-enable capture once the target app has consumed the paste.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.monitor.suppressCapture = false
            self?.hotkeys.isSynthesizing = false
        }
    }

    /// Tab to the next form field (form-fill loop).
    public func tab() {
        postKey(keyCode: UInt16(kVK_Tab), flags: [])
    }

    private func postKey(keyCode: UInt16, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// Walks a form: after each paste, Tab to the next field and ask the engine
/// whether another clip fits — until it says done, the field isn't textual,
/// or we hit the step cap.
@MainActor
public final class FormFiller {
    public static let maxSteps = 20

    private let executor: PasteExecutor
    private let decideNext: (ContextSnapshot) async -> Decision?

    /// `decideNext` is injected so the loop is testable and shares the engine.
    public init(executor: PasteExecutor, decideNext: @escaping (ContextSnapshot) async -> Decision?) {
        self.executor = executor
        self.decideNext = decideNext
    }

    /// Called after the first form field was pasted. Keeps going while the
    /// engine returns a decision. Esc aborts (observed globally — a foreign
    /// app owns the key window while we fill).
    public func run() async {
        var cancelled = false
        let escMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { e in
            if Int(e.keyCode) == kVK_Escape { cancelled = true }
        }
        defer { if let escMonitor { NSEvent.removeMonitor(escMonitor) } }

        var steps = 0
        while steps < Self.maxSteps, !cancelled {
            steps += 1
            executor.tab()
            try? await Task.sleep(for: .milliseconds(250)) // let focus settle

            let ctx = ContextCaptor.capture()
            guard !ctx.field.isSecure, ctx.field.isTextual,
                  let decision = await decideNext(ctx)
            else { break }
            executor.paste(decision.text)
        }
    }
}
