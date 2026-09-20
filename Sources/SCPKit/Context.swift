import AppKit
import ApplicationServices
import Foundation

/// Everything the decision engine knows about "where the user is pasting".
public struct ContextSnapshot: Sendable, Equatable {
    public struct Field: Sendable, Equatable {
        public var role: String = ""
        public var label: String = ""       // AXTitle / AXDescription, whichever exists
        public var placeholder: String = ""
        public var value: String = ""       // current text, truncated to 200 chars
        public var isSecure = false

        /// Text-entry-ish roles. Blacklist, not whitelist: web contenteditable
        /// and friends surface under many roles, so we exclude known
        /// non-textual ones instead of enumerating inputs.
        public var isTextual: Bool {
            !role.isEmpty && !isSecure && !Self.nonTextualRoles.contains(role)
        }

        private static let nonTextualRoles: Set<String> = [
            "AXButton", "AXLink", "AXMenuItem", "AXMenuButton", "AXPopUpButton",
            "AXCheckBox", "AXRadioButton", "AXStaticText", "AXImage", "AXSlider",
            "AXTab", "AXToolbar", "AXMenu", "AXMenuBar",
        ]
    }

    public var appName = ""
    public var bundleID = ""
    public var windowTitle = ""
    public var field = Field()
    /// Screen rect of the focused element (Cocoa coordinates), for HUD positioning.
    public var fieldRect: CGRect? = nil

    public static let empty = ContextSnapshot()
}

/// Reads frontmost app + focused AX element. Requires Accessibility trust.
@MainActor
public enum ContextCaptor {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Ask macOS to prompt the user once, then report current trust state.
    @discardableResult
    public static func requestTrust() -> Bool {
        // kAXTrustedCheckOptionPrompt is a non-Sendable global var; its literal value is used instead.
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary)
    }

    public static func capture() -> ContextSnapshot {
        var ctx = ContextSnapshot()
        let app = NSWorkspace.shared.frontmostApplication
        ctx.appName = app?.localizedName ?? ""
        ctx.bundleID = app?.bundleIdentifier ?? ""
        guard isTrusted else { return ctx }

        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return ctx }
        let el = focusedRef as! AXUIElement

        ctx.field.role = axString(el, kAXRoleAttribute) ?? ""
        ctx.field.isSecure = ctx.field.role == "AXSecureTextField"
        ctx.field.label = axString(el, kAXTitleAttribute)
            ?? axString(el, kAXDescriptionAttribute)
            ?? axString(el, "AXPlaceholderValue")
            ?? ""
        if ctx.field.isSecure {
            ctx.field.value = "" // never read or transmit secure contents
        } else {
            let raw = axString(el, kAXValueAttribute) ?? ""
            ctx.field.value = String(raw.prefix(200))
        }
        ctx.field.placeholder = axString(el, "AXPlaceholderValue") ?? ""
        ctx.fieldRect = axRect(el)
        ctx.windowTitle = windowTitle(of: app) ?? ""
        return ctx
    }

    private static func windowTitle(of app: NSRunningApplication?) -> String? {
        guard let pid = app?.processIdentifier else { return nil }
        let axApp = AXUIElementCreateApplication(pid)
        var winRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &winRef) == .success,
              let winRef, CFGetTypeID(winRef) == AXUIElementGetTypeID() else { return nil }
        return axString(winRef as! AXUIElement, kAXTitleAttribute)
    }

    private static func axString(_ el: AXUIElement, _ attr: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success else { return nil }
        return v as? String
    }

    /// Element frame, converted from AX (top-left origin) to Cocoa (bottom-left origin).
    private static func axRect(_ el: AXUIElement) -> CGRect? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success
        else { return nil }
        var pos = CGPoint.zero
        var size = CGSize.zero
        // Foreign apps can return wrong types — check before casting.
        guard CFGetTypeID(posRef) == AXValueGetTypeID(),
              CFGetTypeID(sizeRef) == AXValueGetTypeID(),
              AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        else { return nil }
        let axRect = CGRect(origin: pos, size: size)
        // Flip Y: AX uses top-left origin of the primary screen.
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: axRect.minX, y: screenH - axRect.maxY, width: axRect.width, height: axRect.height)
    }
}
