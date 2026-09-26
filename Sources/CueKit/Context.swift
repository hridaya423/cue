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
    /// Short text gathered near the field (label elements, preceding labels,
    /// page title hints). Lets the model tell work vs personal apart.
    public var nearby = ""
    /// Host of the enclosing web area, when the field lives in a browser.
    public var webHost = ""
    /// Screen rect of the focused element (Cocoa coordinates), for HUD positioning.
    public var fieldRect: CGRect? = nil
    /// Caret rect inside the field (Cocoa coordinates), when AX provides one.
    public var caretRect: CGRect? = nil

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
        // A hung target app must not stall a paste — 50 ms per AX call.
        AXUIElementSetMessagingTimeout(system, 0.05)
        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return ctx }
        let el = focusedRef as! AXUIElement

        ctx.field.role = axString(el, kAXRoleAttribute) ?? ""
        ctx.field.isSecure = ctx.field.role == "AXSecureTextField"
        if ctx.field.isSecure {
            // Never read or transmit secure contents — bail immediately.
            ctx.fieldRect = axRect(el)
            ctx.windowTitle = windowTitle(of: app) ?? ""
            return ctx
        }
        ctx.field.label = axString(el, kAXTitleAttribute)
            ?? axString(el, kAXDescriptionAttribute)
            ?? axString(el, "AXPlaceholderValue")
            ?? firstLabelElement(of: el)
            ?? ""
        let raw = axString(el, kAXValueAttribute) ?? ""
        ctx.field.value = String(raw.prefix(200))
        ctx.field.placeholder = axString(el, "AXPlaceholderValue") ?? ""
        ctx.fieldRect = axRect(el)
        ctx.caretRect = caretRect(of: el)
        ctx.nearby = nearbyText(of: el)
        ctx.webHost = webHost(of: el)
        ctx.windowTitle = windowTitle(of: app) ?? ""
        return ctx
    }

    /// AX label element that describes this field (web forms wire these up
    /// via aria-labelledby / <label for>).
    private static func firstLabelElement(of el: AXUIElement) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXTitleUIElement" as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return axString(ref as! AXUIElement, kAXValueAttribute)
            ?? axString(ref as! AXUIElement, kAXTitleAttribute)
    }

    /// Text around the field: the field's help, its parent's title, and
    /// sibling static texts (usually the visible label). ~300 chars max.
    private static func nearbyText(of el: AXUIElement) -> String {
        var parts: [String] = []
        if let help = axString(el, kAXHelpAttribute) { parts.append(help) }
        if let parent = axElement(el, kAXParentAttribute) {
            if let t = axString(parent, kAXTitleAttribute) { parts.append(t) }
            var kids: CFTypeRef?
            if AXUIElementCopyAttributeValue(parent, kAXChildrenAttribute as CFString, &kids) == .success,
               let arr = kids as? [AXUIElement] {
                for k in arr.prefix(20) where axString(k, kAXRoleAttribute) == "AXStaticText" {
                    if let v = axString(k, kAXValueAttribute), !v.isEmpty { parts.append(v) }
                }
            }
            // One level up — section/group headings ("Contact", "Shipping").
            if let gp = axElement(parent, kAXParentAttribute),
               let t = axString(gp, kAXTitleAttribute), !t.isEmpty {
                parts.append(t)
            }
        }
        return String(parts.joined(separator: " · ").prefix(300))
    }

    /// Host of the enclosing AXWebArea — browsers expose the page URL there.
    private static func webHost(of el: AXUIElement) -> String {
        var cur: AXUIElement? = el
        for _ in 0..<6 {
            guard let c = cur else { return "" }
            if axString(c, kAXRoleAttribute) == "AXWebArea",
               let url = axString(c, "AXURL"),
               let host = URLComponents(string: url)?.host { return host }
            cur = axElement(c, kAXParentAttribute)
        }
        return ""
    }

    /// Bounds of the caret (AXSelectedTextRange → AXBoundsForRange), so the
    /// chooser anchors to the insertion point, not the field's edge.
    private static func caretRect(of el: AXUIElement) -> CGRect? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                el, "AXBoundsForRange" as CFString, rangeRef, &boundsRef) == .success,
              let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect) else { return nil }
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: screenH - rect.maxY, width: rect.width, height: rect.height)
    }

    private static func axElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success,
              let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        // CF type verified above — the bridged cast is safe.
        return unsafeDowncast(v, to: AXUIElement.self)
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
