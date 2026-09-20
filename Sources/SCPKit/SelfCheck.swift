import AppKit
import Foundation

/// End-to-end smoke test driven through the REAL path: a live NSTextField
/// labeled "Email", a real context capture, a real decision, a real pasteboard
/// write, and a real synthesized ⌘V. Run from the menu bar (Debug → self-check).
///
/// Invariant checked: the field ends up holding exactly what the pasteboard
/// holds after the decision — proving capture → decide → paste works. With the
/// heuristic provider, the seeded email clip must also be the actual pick.
@MainActor
public enum SelfCheck {
    public static func run(model: AppModel) async -> String {
        guard ContextCaptor.isTrusted else {
            return "FAIL — grant Accessibility first"
        }

        let marker = "scp-\(Int(Date().timeIntervalSince1970))@example.com"
        model.store.add(Clip(text: "unrelated decoy", kind: .text, sourceApp: "SelfCheck"))
        model.store.add(Clip(text: marker, kind: .text, sourceApp: "SelfCheck"))

        // A real text field in a real window — CGEvent delivery included.
        let field = NSTextField()
        field.setAccessibilityLabel("Email")
        field.setAccessibilityPlaceholderValue("you@example.com")
        field.stringValue = ""
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
                           styleMask: [.titled], backing: .buffered, defer: false)
        win.title = "SelfCheck"
        win.contentView = field
        win.center()
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(field)

        try? await Task.sleep(for: .milliseconds(600)) // let focus settle
        model.controller.smartPaste()

        // Wait for the decision + synthesized paste to land. The budget
        // exceeds the 10s Jev timeout so a hanging request can't fake a FAIL.
        var waited = 0
        while model.controller.busy, waited < 120 {
            try? await Task.sleep(for: .milliseconds(100))
            waited += 1
        }
        try? await Task.sleep(for: .milliseconds(800))
        defer { win.close() }

        let pasted = NSPasteboard.general.string(forType: .string) ?? ""
        guard field.stringValue == pasted, !pasted.isEmpty else {
            return "FAIL — field=\(field.stringValue.prefix(40)) pasteboard=\(pasted.prefix(40))"
        }
        if model.settings.provider == .none, field.stringValue != marker {
            return "FAIL — heuristic picked '\(pasted.prefix(40))' for an Email field, expected the seeded email"
        }
        return "PASS — pasted “\(pasted.prefix(40))”"
    }
}
