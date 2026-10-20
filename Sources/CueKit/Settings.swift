import Foundation
import Security

/// All user-facing knobs. UserDefaults-backed; secrets live in Keychain.
@MainActor @Observable
public final class AppSettings {
    public static let shared = AppSettings()

    /// Every provider speaks the same System One contract — the difference is
    /// only where the POST goes and which key signs it. `.local` resolves to a
    /// managed model server via `localModelID`/`localVariantID` + ModelCatalog.
    public enum Provider: String, CaseIterable, Codable, Sendable {
        case jevDirect = "jev-direct"
        case jevGateway = "jev-gateway"
        case local        // managed local model server (kev, laya, von, …)
        case custom       // any /v1/systemone endpoint
        case off          // no model — pastes pass through untouched

        public var title: String {
            switch self {
            case .jevDirect: "Jev · TypeSafe"
            case .jevGateway: "Jev · AI Gateway"
            case .local: "Local model"
            case .custom: "Custom endpoint"
            case .off: "Off"
            }
        }

        public var needsAPIKey: Bool { self == .jevDirect || self == .jevGateway }
        /// True when the payload can leave the machine (custom depends on the URL).
        public var mayBeRemote: Bool { self != .local && self != .off }

        /// Decodes current raw values plus both older formats so existing
        /// installs keep their setting. v2's kev/laya cases collapse into
        /// `.local` — the caller recovers which model from `localModelID`.
        init(stored: String) {
            switch stored {
            case "TypeSafe direct", "jev-direct": self = .jevDirect
            case "AI Gateway", "jev-gateway": self = .jevGateway
            case "kev", "laya", "local": self = .local
            case "custom": self = .custom
            case "none", "None (offline)", "off": self = .off
            default: self = .off
            }
        }
    }

    public enum LowConfidenceMode: String, CaseIterable, Codable, Sendable {
        case top3 = "Top-3 toast"
        case picker = "Full picker"
        case pasteBest = "Paste best pick"
        case pasteLatest = "Paste latest"
    }

    /// mode == .intercept means ⌘V itself is smart.
    public enum TriggerMode: String, Codable, Sendable {
        case hotkey
        case intercept
    }

    private let defaults: UserDefaults
    private var revision = 0

    /// Observation doesn't see UserDefaults: `load` reads register `revision`
    /// as a dependency, `store` writes bump it — so views invalidate on change.
    private func load<T>(_ key: String) -> T? {
        _ = revision
        return defaults.object(forKey: key) as? T
    }
    private func store<T>(_ value: T?, forKey key: String) {
        revision += 1
        if let value { defaults.set(value, forKey: key) }
        else { defaults.removeObject(forKey: key) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults === UserDefaults.standard { Self.adoptSettings(from: "com.local.cue", into: defaults) }
        // v2 → v3 migration: "kev"/"laya" providers collapse into .local and
        // recover their identity as catalog model IDs.
        let raw: String = get("provider", "")
        if raw == "kev" || raw == "laya" {
            if localModelID.isEmpty { localModelID = raw }
            provider = .local
        }
    }

    /// Settings saved under the identifier Cue used before it shipped come along once, so a renamed build keeps
    /// the user's model, shortcuts and finished onboarding.
    static func adoptSettings(from oldDomain: String, into defaults: UserDefaults) {
        let marker = "adoptedSettingsFrom"
        guard defaults.object(forKey: marker) == nil, defaults.object(forKey: "provider") == nil,
              let keys = CFPreferencesCopyKeyList(oldDomain as CFString, kCFPreferencesCurrentUser,
                                                  kCFPreferencesAnyHost) as? [String], !keys.isEmpty,
              let values = CFPreferencesCopyMultiple(keys as CFArray, oldDomain as CFString, kCFPreferencesCurrentUser,
                                                     kCFPreferencesAnyHost) as? [String: Any]
        else { return }
        for (key, value) in values where !key.hasPrefix("NS") && !key.hasPrefix("Apple") {
            defaults.set(value, forKey: key)
        }
        defaults.set(oldDomain, forKey: marker)
    }

    private func get<T: Codable>(_ key: String, _ fallback: T) -> T {
        _ = revision
        guard let data = defaults.data(forKey: key),
              let v = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return v
    }
    private func set<T: Codable>(_ key: String, _ value: T) {
        revision += 1
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    public var provider: Provider {
        get { Provider(stored: get("provider", "")) }
        set { set("provider", newValue.rawValue) }
    }

    /// Model strings are per-provider. Cloud defaults: `jev-latest` direct,
    /// `typesafe-ai/jev` on the gateway. Local models get their serve name
    /// from the catalog variant; custom carries its own.
    public var model: String {
        get {
            switch provider {
            case .jevGateway: gatewayModel
            case .local: ModelCatalog.variant(modelID: localModelID, variantID: localVariantID)?.serveModel ?? ""
            case .custom: customModel
            case .off: ""
            case .jevDirect: directModel
            }
        }
        set {
            switch provider {
            case .jevGateway: gatewayModel = newValue
            case .custom: customModel = newValue
            case .jevDirect: directModel = newValue
            case .local, .off: break // catalog-driven, not editable
            }
        }
    }
    public var directModel: String {
        get { load("model.direct") ?? "jev-latest" }
        set { store(newValue, forKey: "model.direct") }
    }
    public var gatewayModel: String {
        get { load("model.gateway") ?? "typesafe-ai/jev" }
        set { store(newValue, forKey: "model.gateway") }
    }
    public var customModel: String {
        get { load("model.custom") ?? "jev-latest" }
        set { store(newValue, forKey: "model.custom") }
    }

    /// Which local model + weight variant is selected. Resolved through
    /// ModelCatalog by providerClient().
    public var localModelID: String {
        get { load("localModel") ?? "" }
        set { store(newValue, forKey: "localModel") }
    }
    public var localVariantID: String {
        get { load("localVariant") ?? "" }
        set { store(newValue, forKey: "localVariant") }
    }

    /// Base URL for the custom endpoint — bare host, host:port, or full
    /// /v1/systemone URL all work (normalized in JevEndpoint.custom).
    public var customURL: String {
        get { load("url.custom") ?? "" }
        set { store(newValue, forKey: "url.custom") }
    }

    /// Tri-state: nil = auto (on for remote providers, off for local),
    /// explicit true/false = user override. Auto is the right default because
    /// redacting traffic that never leaves the device only costs latency.
    public var piiRedaction: Bool? {
        get { load("piiRedaction") }
        set { store(newValue, forKey: "piiRedaction") }
    }

    /// The redaction state that actually applies to the current provider.
    public var effectivePIIRedaction: Bool {
        piiRedaction ?? provider.mayBeRemote
    }

    public var triggerMode: TriggerMode {
        get { get("triggerMode", .hotkey) }
        set { set("triggerMode", newValue) }
    }

    public var showStatusToast: Bool {
        get { load("showStatusToast") ?? true }
        set { store(newValue, forKey: "showStatusToast") }
    }

    public var historyCap: Int {
        get { max(10, load("historyCap") ?? 1000) }
        set { store(newValue, forKey: "historyCap") }
    }

    public var queueMode: Bool {
        get { load("queueMode") ?? false }
        set { store(newValue, forKey: "queueMode") }
    }

    public var launchAtLogin: Bool {
        get { load("launchAtLogin") ?? false }
        set { store(newValue, forKey: "launchAtLogin") }
    }

    public var onboardingDone: Bool {
        get { load("onboardingDone") ?? false }
        set { store(newValue, forKey: "onboardingDone") }
    }

    /// Bundle IDs never captured into history. Structure exists now; default empty.
    public var excludedBundleIDs: [String] {
        get { get("excludedBundleIDs", []) }
        set { set("excludedBundleIDs", newValue) }
    }

    /// Hotkey bindings: keyCode + modifier flags per action name.
    public struct Hotkey: Codable, Sendable, Equatable {
        public var keyCode: UInt32
        public var modifiers: UInt32 // Carbon modifier mask
        public init(keyCode: UInt32, modifiers: UInt32) {
            self.keyCode = keyCode
            self.modifiers = modifiers
        }
    }

    public func hotkey(for action: String) -> Hotkey? {
        get("hotkey.\(action)", Optional<Hotkey>.none)
    }
    public func setHotkey(_ hk: Hotkey?, for action: String) {
        if let hk { set("hotkey.\(action)", hk) }
        else { revision += 1; defaults.removeObject(forKey: "hotkey.\(action)") }
    }

    // MARK: - Keychain

    public var apiKey: String? {
        get { _ = revision; return Keychain.get("apiKey") }
        set { revision += 1; Keychain.set("apiKey", newValue) }
    }

    public var gatewayKey: String? {
        get { _ = revision; return Keychain.get("gatewayKey") }
        set { revision += 1; Keychain.set("gatewayKey", newValue) }
    }

    public var customKey: String? {
        get { _ = revision; return Keychain.get("customKey") }
        set { revision += 1; Keychain.set("customKey", newValue) }
    }

    /// The configured decision provider, or nil when off/unconfigured — in
    /// which case every smart-paste degrades to a silent plain ⌘V.
    /// Every provider is the same client — only (url, model, key) differ.
    public func providerClient(timeout: TimeInterval = 10) -> (any DecisionProvider)? {
        switch provider {
        case .jevDirect:
            guard let key = apiKey, !key.isEmpty else { return nil }
            return JevClient(endpoint: .direct(model: directModel), apiKey: key, timeout: timeout)
        case .jevGateway:
            guard let key = gatewayKey, !key.isEmpty else { return nil }
            return JevClient(endpoint: .gateway(model: gatewayModel), apiKey: key, timeout: timeout)
        case .local:
            guard let v = ModelCatalog.variant(modelID: localModelID, variantID: localVariantID) else {
                return nil
            }
            return JevClient(endpoint: JevEndpoint(url: v.endpointURL, model: v.serveModel), timeout: timeout)
        case .custom:
            guard let ep = JevEndpoint.custom(base: customURL, model: customModel) else { return nil }
            return JevClient(endpoint: ep, apiKey: customKey ?? "", timeout: timeout)
        case .off:
            return nil
        }
    }
}

/// Thin Keychain wrapper — one service, per-item accounts.
enum Keychain {
    private static let service = "com.local.cue"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ account: String, _ value: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let value {
            let attrs = [kSecValueData as String: Data(value.utf8)]
            let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
            if status == errSecItemNotFound {
                var add = query
                add[kSecValueData as String] = Data(value.utf8)
                SecItemAdd(add as CFDictionary, nil)
            }
        } else {
            SecItemDelete(query as CFDictionary)
        }
    }
}
