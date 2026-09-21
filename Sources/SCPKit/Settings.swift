import Foundation
import Security

/// All user-facing knobs. UserDefaults-backed; secrets live in Keychain.
@MainActor @Observable
public final class AppSettings {
    public static let shared = AppSettings()

    /// Every provider speaks the same System One contract — the difference is
    /// only where the POST goes and which key signs it.
    public enum Provider: String, CaseIterable, Codable, Sendable {
        case jevDirect = "jev-direct"
        case jevGateway = "jev-gateway"
        case kev          // local kev.serve instance
        case laya         // local laya shim (Scripts/laya_server.py)
        case custom       // any /v1/systemone endpoint
        case none

        public var title: String {
            switch self {
            case .jevDirect: "Jev · TypeSafe"
            case .jevGateway: "Jev · AI Gateway"
            case .kev: "Kev · local"
            case .laya: "Laya · local"
            case .custom: "Custom endpoint"
            case .none: "None · offline"
            }
        }

        public var blurb: String {
            switch self {
            case .jevDirect: "TypeSafe's hosted model. Best quality, ~100ms, needs an API key."
            case .jevGateway: "Jev through Vercel's AI Gateway — same model, your own gateway account."
            case .kev: "jaredpalmer/kev — open Jev-like weights on your Mac via kev.serve. Data never leaves the device."
            case .laya: "convaiinnovations/laya — open-weight System 1 model via a local shim. Data never leaves the device."
            case .custom: "Any server that answers POST {base}/v1/systemone with the System One contract."
            case .none: "No model calls. Local heuristics pick clips; the app still works end-to-end."
            }
        }

        public var needsAPIKey: Bool { self == .jevDirect || self == .jevGateway }
        /// Endpoint-based providers get URL + model fields.
        public var isEndpointBased: Bool {
            self == .kev || self == .laya || self == .custom
        }
        /// True when the payload can leave the machine (custom depends on the URL).
        public var mayBeRemote: Bool { isEndpointBased ? self == .custom : needsAPIKey }

        /// Decodes both current raw values and the original display-string
        /// values so existing installs keep their setting.
        init(stored: String) {
            switch stored {
            case "TypeSafe direct": self = .jevDirect
            case "AI Gateway": self = .jevGateway
            case "None (offline)": self = .none
            default: self = Provider(rawValue: stored) ?? .none
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
        defaults.set(value, forKey: key)
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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
    /// `typesafe-ai/jev` on the gateway. Endpoint providers carry their own.
    public var model: String {
        get {
            switch provider {
            case .jevGateway: gatewayModel
            case .kev: kevModel
            case .laya: layaModel
            case .custom: customModel
            default: directModel
            }
        }
        set {
            switch provider {
            case .jevGateway: gatewayModel = newValue
            case .kev: kevModel = newValue
            case .laya: layaModel = newValue
            case .custom: customModel = newValue
            default: directModel = newValue
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
    public var kevModel: String {
        get { load("model.kev") ?? "kev-latest" }
        set { store(newValue, forKey: "model.kev") }
    }
    public var layaModel: String {
        get { load("model.laya") ?? "laya" }
        set { store(newValue, forKey: "model.laya") }
    }
    public var customModel: String {
        get { load("model.custom") ?? "jev-latest" }
        set { store(newValue, forKey: "model.custom") }
    }

    /// Base URLs for endpoint providers — bare host, host:port, or full
    /// /v1/systemone URL all work (normalized in JevEndpoint.custom).
    public var kevURL: String {
        get { load("url.kev") ?? "http://127.0.0.1:8009" }
        set { store(newValue, forKey: "url.kev") }
    }
    public var layaURL: String {
        get { load("url.laya") ?? "http://127.0.0.1:8765" }
        set { store(newValue, forKey: "url.laya") }
    }
    public var customURL: String {
        get { load("url.custom") ?? "" }
        set { store(newValue, forKey: "url.custom") }
    }

    /// Redact PII from clips/context before they reach a remote provider.
    /// Loopback endpoints skip redaction — the data never leaves the device.
    public var piiRedaction: Bool {
        get { load("piiRedaction") ?? true }
        set { store(newValue, forKey: "piiRedaction") }
    }

    public var triggerMode: TriggerMode {
        get { get("triggerMode", .hotkey) }
        set { set("triggerMode", newValue) }
    }

    public var confidenceThreshold: Double {
        get { load("confidenceThreshold") ?? 0.7 }
        set { store(newValue, forKey: "confidenceThreshold") }
    }

    public var lowConfidenceMode: LowConfidenceMode {
        get { get("lowConfidenceMode", .top3) }
        set { set("lowConfidenceMode", newValue) }
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

    /// The configured decision provider, or nil when offline/none-selected.
    /// Every provider is the same client — only (url, model, key) differ.
    public func providerClient() -> (any DecisionProvider)? {
        switch provider {
        case .jevDirect:
            guard let key = apiKey, !key.isEmpty else { return nil }
            return JevClient(endpoint: .direct(model: directModel), apiKey: key)
        case .jevGateway:
            guard let key = gatewayKey, !key.isEmpty else { return nil }
            return JevClient(endpoint: .gateway(model: gatewayModel), apiKey: key)
        case .kev:
            return JevEndpoint.custom(base: kevURL, model: kevModel).map { JevClient(endpoint: $0) }
        case .laya:
            return JevEndpoint.custom(base: layaURL, model: layaModel).map { JevClient(endpoint: $0) }
        case .custom:
            guard let ep = JevEndpoint.custom(base: customURL, model: customModel) else { return nil }
            return JevClient(endpoint: ep, apiKey: customKey ?? "")
        case .none:
            return nil
        }
    }
}

/// Thin Keychain wrapper — one service, per-item accounts.
enum Keychain {
    private static let service = "com.local.smartcopypaste"

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
