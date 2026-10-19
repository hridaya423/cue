import AppKit
import Carbon
import Foundation

/// End-to-end smoke test driven through the REAL path: a live NSTextField
/// labeled "Email", a real context capture, a real decision, a real pasteboard
/// write, and a real paste: on the field editor. Run from the menu bar.
///
/// Invariant checked: the field ends up holding the marker clip the decision
/// must pick — proving capture → decide → paste works.
@MainActor
public enum SelfCheck {
    public static func run(model: AppModel) async -> String {
        guard ContextCaptor.isTrusted else {
            return "FAIL — grant Accessibility first"
        }

        let marker = "scp-\(Int(Date().timeIntervalSince1970))@example.com"
        let probes = [Clip(text: "unrelated decoy", kind: .text, sourceApp: "SelfCheck"),
                      Clip(text: marker, kind: .text, sourceApp: "SelfCheck")]
        probes.forEach(model.store.add)
        defer { probes.forEach(model.store.remove) }

        // A real text field in a real window.
        let field = NSTextField()
        field.setAccessibilityLabel("Email")
        field.setAccessibilityPlaceholderValue("you@example.com")
        field.stringValue = ""
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
                           styleMask: [.titled], backing: .buffered, defer: false)
        win.title = "SelfCheck"
        // Closing a window whose field editor is still first responder
        // over-releases the editor on the next autorelease drain (SIGSEGV).
        // isReleasedWhenClosed must be off — the window outlives its editor.
        win.isReleasedWhenClosed = false
        win.contentView = field
        win.center()
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(field)

        // LSUIElement self-activation is denied without genuine user intent,
        // so the ⌘V leg can't ride the HID event tap (it routes to whatever
        // is system-frontmost — not us). Instead onWouldPost injects a real
        // NSEvent into our own queue: real AppKit dispatch → performKeyEquivalent
        // → paste: → field editor. Everything else (capture → decide →
        // pasteboard write) is the production path.
        model.executor.onWouldPost = { _ in
            guard let ev = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command,
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: win.windowNumber, context: nil,
                characters: "v", charactersIgnoringModifiers: "v",
                isARepeat: false, keyCode: UInt16(kVK_ANSI_V)) else { return }
            // Direct to the field editor — the window can't be key while the
            // app is inactive, and sendEvent drops keyDown on non-key windows.
            // ⌘V is a command, not text: it dispatches via performKeyEquivalent
            // → paste:, not keyDown → insertText.
            let editor = win.firstResponder
            if editor?.performKeyEquivalent(with: ev) != true {
                (editor as? NSTextView)?.paste(nil)
            }
        }
        defer { model.executor.onWouldPost = nil }

        // Wait for the field editor to install — the window never goes key
        // while the app is inactive, but the responder still takes events.
        var tries = 0
        while field.currentEditor() == nil, tries < 20 {
            win.makeFirstResponder(field)
            try? await Task.sleep(for: .milliseconds(100))
            tries += 1
        }
        guard field.currentEditor() != nil else {
            return "FAIL — field never took focus (key=\(win.isKeyWindow))"
        }
        model.controller.smartPaste(intercepted: false)

        // Wait for the decision + synthesized paste to land. The budget
        // exceeds the 10s Jev timeout so a hanging request can't fake a FAIL.
        var waited = 0
        while model.controller.busy, waited < 120 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        try? await Task.sleep(for: .milliseconds(800))
        defer {
            win.makeFirstResponder(nil)
            win.close()
        }

        let pasted = field.stringValue
        guard pasted == marker else {
            let fr = win.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
            return "FAIL — field=\(pasted.prefix(40)) key=\(win.isKeyWindow) fr=\(fr)"
        }
        return "PASS — pasted “\(pasted.prefix(40))”"
    }
}
