import Foundation

/// Minimal JSON tree — the wire format for Jev requests and responses.
public enum JSONValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    indirect case object([String: JSONValue])
    indirect case array([JSONValue])

    public func toAny() -> Any {
        switch self {
        case .string(let s): s
        case .number(let n): n
        case .bool(let b): b
        case .null: NSNull()
        case .object(let o): o.mapValues { $0.toAny() }
        case .array(let a): a.map { $0.toAny() }
        }
    }

    public init?(any: Any) {
        switch any {
        case let s as String: self = .string(s)
        case let n as NSNumber:
            // Bool check via CF type — `1.0 as Bool` bridges true and would
            // silently swallow real numbers otherwise.
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else { self = .number(n.doubleValue) }
        case let o as [String: Any]:
            var out: [String: JSONValue] = [:]
            for (k, v) in o {
                guard let j = JSONValue(any: v) else { return nil }
                out[k] = j
            }
            self = .object(out)
        case let a as [Any]:
            var out: [JSONValue] = []
            for v in a {
                guard let j = JSONValue(any: v) else { return nil }
                out.append(j)
            }
            self = .array(out)
        case is NSNull: self = .null
        default: return nil
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { o[key] } else { nil }
    }

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var number: Double? { if case .number(let n) = self { n } else { nil } }
    public var object: [String: JSONValue]? { if case .object(let o) = self { o } else { nil } }
}

// MARK: - Typed contract

/// A typed Jev question. All questions in a request are evaluated in parallel.
public enum Question: Sendable {
    case choice(instructions: String, criteria: [String: String])
    case noul(instructions: String)
    case score(instructions: String, criteria: [String])

    var jsonValue: JSONValue {
        switch self {
        case .choice(let i, let c):
            .object(["type": .string("choice"), "instructions": .string(i),
                     "criteria": .object(c.mapValues { .string($0) })])
        case .noul(let i):
            .object(["type": .string("noul"), "instructions": .string(i)])
        case .score(let i, let c):
            .object(["type": .string("score"), "instructions": .string(i),
                     "criteria": .array(c.map { .string($0) })])
        }
    }
}

/// A typed Jev answer — no free text, ever.
public enum Answer: Sendable, Equatable {
    case choice(key: String, confidence: Double, probabilities: [String: Double])
    case noul(probability: Double)
    case score(score: Double, confidence: Double, probabilities: [String: Double])
}

public struct JevResponse: Sendable, Equatable {
    public var model: String
    public var answers: [String: Answer]
    public var inputTokens: Int
}

public struct JevEndpoint: Sendable {
    public var url: URL
    public var model: String

    /// POST https://api.typesafe.ai/v1/systemone
    public static func direct(model: String) -> JevEndpoint {
        JevEndpoint(url: URL(string: "https://api.typesafe.ai/v1/systemone")!, model: model)
    }

    /// Vercel AI Gateway's TypeSafe-compatible route — same request shape.
    /// POST https://ai-gateway.vercel.sh/typesafe/v1/systemone
    public static func gateway(model: String) -> JevEndpoint {
        JevEndpoint(url: URL(string: "https://ai-gateway.vercel.sh/typesafe/v1/systemone")!, model: model)
    }

    /// Any server speaking the System One contract — kev.serve, the laya shim,
    /// or a self-hosted deployment. Accepts `host:port`, `scheme://host:port`,
    /// or a full `…/v1/systemone` URL; normalizes to the POST URL.
    /// Returns nil for empty/garbage input.
    public static func custom(base: String, model: String) -> JevEndpoint? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard var c = URLComponents(string: s), c.host != nil else { return nil }
        let path = c.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.hasSuffix("v1/systemone") {
            c.path = path.isEmpty ? "/v1/systemone" : "/\(path)/v1/systemone"
        }
        guard let url = c.url else { return nil }
        return JevEndpoint(url: url, model: model)
    }

    /// Loopback endpoints keep payloads on-device — PII redaction is a no-op.
    public var isRemote: Bool {
        guard let h = url.host?.lowercased() else { return true }
        return !(h == "localhost" || h == "::1" || h.hasPrefix("127.") || h.hasSuffix(".local"))
    }
}

public enum JevError: Error, Equatable {
    case http(Int, String)
    case decoding(String)
    case transport(String)
}

/// The seam between the decision engine and whatever answers questions —
/// JevClient in production, a stub in tests.
public protocol DecisionProvider: Sendable {
    /// False when the endpoint is loopback — payloads stay on the device,
    /// so PII redaction is skipped. Defaults true; safe side is remote.
    var isRemote: Bool { get }
    func evaluate(state: JSONValue, questions: [String: Question]) async throws -> JevResponse
}

extension DecisionProvider {
    public var isRemote: Bool { true }
}

/// Observable record of the provider's health for the menu bar / settings UI.
/// `unknown` until the first call completes.
@MainActor @Observable
public final class ProviderStatus {
    public enum State: Sendable, Equatable {
        case unknown, ok, unreachable
    }
    public private(set) var state: State = .unknown
    public init() {}
    nonisolated func record(ok: Bool) {
        Task { @MainActor in self.state = ok ? .ok : .unreachable }
    }
}

/// Wraps a provider and reports each call's success/failure into a
/// ProviderStatus. Transparent to the engine — errors still propagate.
public struct StatusTrackingProvider: DecisionProvider {
    private let inner: any DecisionProvider
    private let status: ProviderStatus
    public var isRemote: Bool { inner.isRemote }

    public init(_ inner: any DecisionProvider, status: ProviderStatus) {
        self.inner = inner
        self.status = status
    }

    public func evaluate(state: JSONValue, questions: [String: Question]) async throws -> JevResponse {
        do {
            let r = try await inner.evaluate(state: state, questions: questions)
            status.record(ok: true)
            return r
        } catch {
            status.record(ok: false)
            throw error
        }
    }
}

public struct JevClient: DecisionProvider {
    public let endpoint: JevEndpoint
    private let apiKey: String
    private let session: URLSession
    private let timeout: TimeInterval

    public var isRemote: Bool { endpoint.isRemote }

    public init(endpoint: JevEndpoint, apiKey: String = "", session: URLSession = .shared,
                timeout: TimeInterval = 10) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
        self.timeout = timeout
    }

    public func evaluate(state: JSONValue, questions: [String: Question]) async throws -> JevResponse {
        var req = URLRequest(url: endpoint.url)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: JSONValue.object([
            "model": .string(endpoint.model),
            "state": state,
            "questions": .object(questions.mapValues(\.jsonValue)),
        ]).toAny())

        let data: Data
        let resp: URLResponse
        do {
            (data, resp) = try await session.data(for: req)
        } catch {
            throw JevError.transport(error.localizedDescription)
        }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(code) else {
            throw JevError.http(code, String(data: data, encoding: .utf8)?.prefix(300).description ?? "")
        }
        guard let root = JSONValue(any: (try? JSONSerialization.jsonObject(with: data)) ?? [:]) else {
            throw JevError.decoding("unparseable body")
        }
        return try Self.parse(root)
    }

    static func parse(_ root: JSONValue) throws -> JevResponse {
        guard let answersObj = root["answers"]?.object else {
            throw JevError.decoding("missing answers")
        }
        var answers: [String: Answer] = [:]
        for (name, v) in answersObj {
            answers[name] = try parseAnswer(v, name: name)
        }
        return JevResponse(
            model: root["model"]?.string ?? "",
            answers: answers,
            inputTokens: Int(root["usage"]?["input_tokens"]?.number ?? 0)
        )
    }

    private static func parseAnswer(_ v: JSONValue, name: String) throws -> Answer {
        func probs() -> [String: Double] {
            (v["probabilities"]?.object ?? [:]).compactMapValues { $0.number }
        }
        switch v["type"]?.string {
        case "choice":
            guard let key = v["choice"]?.string else { throw JevError.decoding("\(name): choice without key") }
            return .choice(key: key, confidence: v["confidence"]?.number ?? 0, probabilities: probs())
        case "noul":
            return .noul(probability: v["noul"]?.number ?? 0)
        case "score":
            return .score(score: v["score"]?.number ?? 0,
                          confidence: v["confidence"]?.number ?? 0,
                          probabilities: probs())
        default:
            throw JevError.decoding("\(name): unknown answer type")
        }
    }
}
