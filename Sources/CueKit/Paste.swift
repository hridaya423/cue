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

    /// The user's own clipboard, held while a smart paste borrows the pasteboard.
    private var borrowed: (original: [NSPasteboardItem], changeCount: Int)?

    public init(monitor: ClipboardMonitor, hotkeys: HotkeyManager) {
        self.monitor = monitor
        self.hotkeys = hotkeys
    }

    /// Plain ⌘V — posts the keystroke without touching the pasteboard.
    /// Used for pasteLatest/raw-paste: "latest" means whatever is on the
    /// pasteboard right now, which our monitor may not have seen yet.
    public func pasteCurrent() {
        hotkeys.isSynthesizing = true
        hotkeys.suspendIntercept()
        if let onWouldPost {
            onWouldPost(NSPasteboard.general.string(forType: .string) ?? "")
        } else {
            postKey(keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            self?.hotkeys.isSynthesizing = false
            self?.hotkeys.resumeIntercept()
        }
    }

    /// Put `text` on the pasteboard, send ⌘V to the focused app, then give the user's clipboard back.
    /// Leaving the pick there made the next plain ⌘V paste it while the engine had judged the latest copy.
    public func paste(_ text: String) {
        hotkeys.isSynthesizing = true
        hotkeys.suspendIntercept()
        monitor.suppressCapture = true

        let pb = NSPasteboard.general
        let original = borrowed?.original ?? Self.copyItems(of: pb)
        pb.clearContents()
        pb.setString(text, forType: .string)
        let written = pb.changeCount
        borrowed = (original, written)

        if let onWouldPost {
            onWouldPost(text)
        } else {
            postKey(keyCode: UInt16(kVK_ANSI_V), flags: .maskCommand)
        }

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.borrowed?.changeCount == written else { return }
            self.borrowed = nil
            if pb.changeCount == written, !original.isEmpty {
                pb.clearContents()
                pb.writeObjects(original)
            }
            try? await Task.sleep(for: .milliseconds(300))
            self.monitor.suppressCapture = false
            self.hotkeys.isSynthesizing = false
            self.hotkeys.resumeIntercept()
        }
    }

    private static func copyItems(of pb: NSPasteboard) -> [NSPasteboardItem] {
        (pb.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
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
