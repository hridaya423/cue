import ApplicationServices

public func ax(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}

public func axString(_ el: AXUIElement, _ attr: String) -> String? { ax(el, attr) as? String }

public func axElement(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
    guard let v = ax(el, attr), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(v, to: AXUIElement.self)
}

public func axChildren(_ el: AXUIElement) -> [AXUIElement] { (ax(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }

public func axFind(_ el: AXUIElement, depth: Int = 0, where hit: (AXUIElement) -> Bool) -> AXUIElement? {
    if hit(el) { return el }
    guard depth < 40 else { return nil }
    for k in axChildren(el) { if let f = axFind(k, depth: depth + 1, where: hit) { return f } }
    return nil
}

public func axAll(_ el: AXUIElement, depth: Int = 0, where hit: (AXUIElement) -> Bool) -> [AXUIElement] {
    var out = hit(el) ? [el] : []
    guard depth < 40 else { return out }
    for k in axChildren(el) { out += axAll(k, depth: depth + 1, where: hit) }
    return out
}
