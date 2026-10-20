import Carbon
import Cocoa
import Foundation

/// Named global hotkeys via Carbon RegisterEventHotKey — consumed, so ⌘V
/// interception actually swallows the event before the target app sees it.
@MainActor
public final class HotkeyManager {
    public enum Action: String, CaseIterable, Sendable {
        case smartPaste
        case picker
        case queueToggle
        case settings
        case rawPaste

        public var title: String {
            switch self {
            case .smartPaste: "Show choices"
            case .picker: "Search history"
            case .queueToggle: "Turn queue on or off"
            case .settings: "Open Settings"
            case .rawPaste: "Plain paste"
            }
        }

        /// Defaults chosen to avoid common app bindings; all rebindable.
        public var `default`: AppSettings.Hotkey {
            switch self {
            case .smartPaste: .init(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey))
            case .picker: .init(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(controlKey | optionKey))
            case .queueToggle: .init(keyCode: UInt32(kVK_ANSI_Q), modifiers: UInt32(controlKey | optionKey))
            case .settings: .init(keyCode: UInt32(kVK_ANSI_Comma), modifiers: UInt32(controlKey | optionKey))
            case .rawPaste: .init(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey | shiftKey))
            }
        }
    }

    /// When true, ⌘V itself is registered as a hotkey → smart paste.
    /// Only actually registered while Accessibility-trusted: an intercepted
    /// ⌘V we can't repost (CGEvent needs trust) would be eaten — the worst
    /// possible outcome for a paste. Untrusted → the real keystroke reaches
    /// the app normally.
    public var interceptCmdV = false {
        didSet { reregister(); syncTrustWatch() }
    }

    /// Set around synthesized ⌘V so we never retrigger ourselves.
    public var isSynthesizing = false

    private var handlers: [Action: () -> Void] = [:]
    /// The intercepted ⌘V — a plain-paste-or-better, distinct from the explicit smart-paste hotkey.
    private var interceptHandler: (() -> Void)?
    private var bodies: [UInt32: () -> Void] = [:]
    private var hotkeyRefs: [EventHotKeyRef?] = []
    private var nextID: UInt32 = 1
    /// The live ⌘V intercept registration, tracked separately so a synthetic
    /// paste can lift it — RegisterEventHotKey consumes ⌘V wholesale, which
    /// would otherwise eat our own repost before the target app sees it.
    private var interceptRef: EventHotKeyRef?
    private var interceptRegistered: Bool { interceptRef != nil }
    private var interceptSuspended = false
    private var trustTimer: Timer?
    private let settings: AppSettings

    public init(settings: AppSettings = .shared) {
        self.settings = settings
        installHandler()
    }

    public func onIntercept(_ handler: @escaping () -> Void) { interceptHandler = handler }

    public func on(_ action: Action, handler: @escaping () -> Void) {
        handlers[action] = handler
    }

    /// (Re)register all bindings from settings + intercept mode.
    public func reregister() {
        for ref in hotkeyRefs { if let ref { UnregisterEventHotKey(ref) } }
        hotkeyRefs.removeAll()
        interceptRef = nil // the loop above already unregistered it
        bodies.removeAll()
        nextID = 1
        for action in Action.allCases {
            let hk = settings.hotkey(for: action)
            register(hk) { [weak self] in self?.fire(action) }
        }
        registerIntercept()
    }

    private func registerIntercept() {
        guard interceptCmdV, ContextCaptor.isTrusted, !interceptSuspended, interceptRef == nil else { return }
        interceptRef = register(.init(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey))) { [weak self] in
            self?.fireIntercept()
        }
    }

    /// Temporarily lift the ⌘V intercept registration so a synthesized paste
    /// reaches the focused app. Without this the hotkey machinery consumes the
    /// synthetic event itself — isSynthesizing only stops our handler, the
    /// keystroke is already gone. resumeIntercept() restores it.
    public func suspendIntercept() {
        interceptSuspended = true
        guard let ref = interceptRef else { return }
        UnregisterEventHotKey(ref)
        interceptRef = nil
    }

    public func resumeIntercept() {
        interceptSuspended = false
        registerIntercept()
    }

    /// Trust can flip after grant or revoke; poll while interception is
    /// wanted so the ⌘V hotkey appears/disappears without an app restart.
    private func syncTrustWatch() {
        if interceptCmdV, trustTimer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.syncInterceptRegistration() }
            }
            RunLoop.main.add(t, forMode: .common)
            trustTimer = t
        } else if !interceptCmdV {
            trustTimer?.invalidate()
            trustTimer = nil
        }
    }

    private func syncInterceptRegistration() {
        let should = interceptCmdV && ContextCaptor.isTrusted && !interceptSuspended
        if should != interceptRegistered { reregister() }
    }

    private func fire(_ action: Action) {
        guard !isSynthesizing else { return }
        handlers[action]?()
    }

    private func fireIntercept() {
        guard !isSynthesizing else { return }
        interceptHandler?()
    }

    @discardableResult
    private func register(_ hk: AppSettings.Hotkey, body: @escaping () -> Void) -> EventHotKeyRef? {
        let id = EventHotKeyID(signature: OSType(0x53435048), id: nextID) // 'SCPH'
        var ref: EventHotKeyRef?
        let err = RegisterEventHotKey(hk.keyCode, hk.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        guard err == noErr else { return nil }
        bodies[nextID] = body
        hotkeyRefs.append(ref)
        nextID += 1
        return ref
    }

    private func handle(id: UInt32) {
        bodies[id]?()
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard err == noErr else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { manager.handle(id: id.id) }
            return noErr
        }, 1, &spec, selfPtr, nil)
    }
}

/// Formats a hotkey for display in settings, e.g. "⌃⌥V".
public extension AppSettings.Hotkey {
    var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        s += Self.keyNames[Int(keyCode)] ?? "?"
        return s
    }

    /// NSEvent modifiers → Carbon modifier mask.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option) { m |= UInt32(optionKey) }
        if flags.contains(.shift) { m |= UInt32(shiftKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
        kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
        kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
        kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
        kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_ANSI_Comma: ",", kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/",
        kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4",
        kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8",
        kVK_ANSI_9: "9", kVK_ANSI_0: "0",
    ]
}
