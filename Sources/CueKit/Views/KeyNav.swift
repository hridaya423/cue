import AppKit
import Carbon
import SwiftUI

/// Local key-monitor bridge for list windows: ↑/↓ move a selection,
/// Return activates it, Escape clears search (or passes through to let
/// the panel dismiss). A plain TextField eats arrow keys for caret
/// movement, so list nav has to intercept at the event layer — the same
/// trick the HUD uses for its panels.
struct KeyNavHelper: NSViewRepresentable {
    var onArrow: (Int) -> Void
    /// Called only when `hasSelection()` is true.
    var onReturn: () -> Void
    var hasSelection: () -> Bool
    /// Return true if Escape was handled (consumed); false lets it
    /// propagate (e.g. MenuBarExtra's own dismissal).
    var onEscape: () -> Bool = { false }

    func makeNSView(context: Context) -> KeyNavView {
        let v = KeyNavView()
        update(v)
        return v
    }

    func updateNSView(_ v: KeyNavView, context: Context) { update(v) }

    private func update(_ v: KeyNavView) {
        v.onArrow = onArrow
        v.onReturn = onReturn
        v.hasSelection = hasSelection
        v.onEscape = onEscape
    }

    final class KeyNavView: NSView {
        var onArrow: (Int) -> Void = { _ in }
        var onReturn: () -> Void = {}
        var hasSelection: () -> Bool = { false }
        var onEscape: () -> Bool = { false }
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
                    guard let self, self.handle(e) else { return e }
                    return nil
                }
            } else if window == nil, let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        /// Consume and dispatch navigation keys aimed at our window.
        /// Returns true when the event was handled.
        private func handle(_ e: NSEvent) -> Bool {
            guard e.window == window else { return false }
            switch Int(e.keyCode) {
            case kVK_DownArrow: onArrow(1); return true
            case kVK_UpArrow: onArrow(-1); return true
            case kVK_Return where hasSelection(): onReturn(); return true
            case kVK_Escape: return onEscape()
            default: return false
            }
        }
    }
}
