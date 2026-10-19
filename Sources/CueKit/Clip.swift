import CryptoKit
import Foundation

public struct Clip: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case text
        case url
    }

    public let id: String
    public var text: String
    public var kind: Kind
    public var sourceApp: String
    public var sourceBundleID: String?
    public var copiedAt: Date
    public var pinned: Bool
    public var timesPasted: Int
    public var queued: Bool

    public init(
        text: String,
        kind: Kind,
        sourceApp: String = "",
        sourceBundleID: String? = nil,
        copiedAt: Date = Date(),
        pinned: Bool = false,
        timesPasted: Int = 0,
        queued: Bool = false
    ) {
        self.id = Self.hash(text)
        self.text = text
        self.kind = kind
        self.sourceApp = sourceApp
        self.sourceBundleID = sourceBundleID
        self.copiedAt = copiedAt
        self.pinned = pinned
        self.timesPasted = timesPasted
        self.queued = queued
    }

    static func hash(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8))
            .prefix(8)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Whitespace-collapsed first line, for labels and Jev criteria.
    public var preview: String {
        let squashed = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return squashed.count > 80 ? String(squashed.prefix(80)) + "…" : squashed
    }

    public var isURL: Bool {
        kind == .url
    }

    public static func classify(_ text: String) -> Kind {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: t), let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()), url.host != nil
        else { return .text }
        return .url
    }
}
