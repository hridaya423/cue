import Foundation
import Security

/// All user-facing knobs. UserDefaults-backed; secrets live in Keychain.
@MainActor @Observable
public final class AppSettings {
    public static let shared = AppSettings()

    public enum Provider: String, CaseIterable, Codable, Sendable {
        case direct = "TypeSafe direct"
        case gateway = "AI Gateway"
        case none = "None (offline)"
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
        get { get("provider", .none) }
        set { set("provider", newValue) }
    }

    /// Model strings are per-provider: the direct API uses `jev-latest`,
    /// AI Gateway uses `typesafe-ai/jev`. Both user-editable.
    public var model: String {
        get { provider == .gateway ? gatewayModel : directModel }
        set { if provider == .gateway { gatewayModel = newValue } else { directModel = newValue } }
    }
    public var directModel: String {
        get { load("model.direct") ?? "jev-latest" }
        set { store(newValue, forKey: "model.direct") }
    }
    public var gatewayModel: String {
        get { load("model.gateway") ?? "typesafe-ai/jev" }
        set { store(newValue, forKey: "model.gateway") }
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

    /// The configured Jev client, or nil when offline/none-selected.
    /// Direct and AI Gateway are the same client with different (url, model, key).
    public func jevProvider() -> (any DecisionProvider)? {
        switch provider {
        case .direct:
            guard let key = apiKey, !key.isEmpty else { return nil }
            return JevClient(endpoint: .direct(model: directModel), apiKey: key)
        case .gateway:
            guard let key = gatewayKey, !key.isEmpty else { return nil }
            return JevClient(endpoint: .gateway(model: gatewayModel), apiKey: key)
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
