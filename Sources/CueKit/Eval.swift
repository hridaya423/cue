import Foundation

// MARK: - Eval cases

/// One benchmark case: a context snapshot, a clipboard history, and the
/// outcome a good decision engine produces. Lives in CueKit so the eval
/// executable and tests share the decoding, and so `EvalScore` can be pinned
/// by unit tests without any model server.
public struct EvalCase: Decodable, Sendable {
    public var id: String
    public var category: String = ""
    /// "hotkey" | "intercept" | "formFill" — anything else → hotkey.
    public var mode: String = "hotkey"
    public var context: Ctx
    public var clips: [Clip_]
    public var expect: Expectation

    public struct Ctx: Decodable, Sendable {
        public var app: String = ""
        public var bundle: String = ""
        public var window: String = ""
        public var nearby: String = ""   // v3 only; baseline ignores
        public var webHost: String = ""  // v3 only
        public var field: Field_

        public struct Field_: Decodable, Sendable {
            public var role: String = "AXTextField"
            public var label: String = ""
            public var placeholder: String = ""
            public var value: String = ""

            private enum K: String, CodingKey { case role, label, placeholder, value }
            public init() { role = "AXTextField"; label = ""; placeholder = ""; value = "" }
            public init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: K.self)
                role = try c.decodeIfPresent(String.self, forKey: .role) ?? "AXTextField"
                label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
                placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder) ?? ""
                value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
            }
        }

        private enum K: String, CodingKey { case app, bundle, window, nearby, webHost, field }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            app = try c.decodeIfPresent(String.self, forKey: .app) ?? ""
            bundle = try c.decodeIfPresent(String.self, forKey: .bundle) ?? ""
            window = try c.decodeIfPresent(String.self, forKey: .window) ?? ""
            nearby = try c.decodeIfPresent(String.self, forKey: .nearby) ?? ""
            webHost = try c.decodeIfPresent(String.self, forKey: .webHost) ?? ""
            field = try c.decodeIfPresent(Field_.self, forKey: .field) ?? .init()
        }
    }

    public struct Clip_: Decodable, Sendable {
        public var text: String
        public var app: String = ""
        public var age_s: Double = 60
        public var pinned: Bool = false

        private enum K: String, CodingKey { case text, app, age_s, pinned }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            text = try c.decode(String.self, forKey: .text)
            app = try c.decodeIfPresent(String.self, forKey: .app) ?? ""
            age_s = try c.decodeIfPresent(Double.self, forKey: .age_s) ?? 60
            pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        }
    }

    /// What a good engine does with this case.
    public enum Expectation: Sendable {
        /// The exact pasted string the user wants.
        case paste(String)
        /// Genuine ambiguity: showing the chooser with any of these is correct.
        /// Pasting one of them outright is a "lucky guess", anything else wrong.
        case choose([String])
        /// Right answer is a plain ⌘V of whatever is on the pasteboard.
        case plain
    }

    /// How a person would trigger this paste (the persona days' rule): ⌘V when what they want is the
    /// latest clip or a plain paste, the smart-paste hotkey only when they want something older.
    public var engineMode: DecisionEngine.Mode {
        switch mode {
        case "intercept": return .intercept
        case "formFill": return .formFill
        default:
            switch expect {
            case .plain: return .intercept
            case .paste(let want) where want == clips.first?.text: return .intercept
            default: return .hotkey
            }
        }
    }

    public var contextSnapshot: ContextSnapshot {
        var c = ContextSnapshot()
        c.appName = context.app
        c.bundleID = context.bundle
        c.windowTitle = context.window
        c.field.role = context.field.role
        c.field.label = context.field.label
        c.field.placeholder = context.field.placeholder
        c.field.value = context.field.value
        c.nearby = context.nearby
        c.webHost = context.webHost
        return c
    }

    public var clipList: [Clip] {
        clips.map {
            Clip(text: $0.text, kind: Clip.classify($0.text), sourceApp: $0.app,
                 copiedAt: Date().addingTimeInterval(-$0.age_s), pinned: $0.pinned)
        }
    }

    /// Decodes `expect` from either {"paste": "…"}, {"choose": ["…"]} or
    /// {"plain": true}.
    private enum CodingKeys: String, CodingKey {
        case id, category, mode, context, clips, expect
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        mode = try c.decodeIfPresent(String.self, forKey: .mode) ?? "hotkey"
        context = try c.decode(Ctx.self, forKey: .context)
        clips = try c.decode([Clip_].self, forKey: .clips)
        let e = try c.decode(Exp_.self, forKey: .expect)
        if let p = e.paste { expect = .paste(p) }
        else if let ch = e.choose { expect = .choose(ch) }
        else { expect = .plain }
    }
    private struct Exp_: Decodable {
        var paste: String?
        var choose: [String]?
        var plain: Bool?
    }
}

// MARK: - Scoring

/// Normalized decision result so the scorer doesn't care whether the engine
/// returned options or clips: `kind` is what happened, `texts` are the exact
/// strings that would land in the field, in rank order.
public enum EvalOutcomeKind: String, Sendable {
    case paste, choose, plain
}

public struct EvalNormalizedOutcome: Sendable {
    public var kind: EvalOutcomeKind
    public var texts: [String]
    public init(kind: EvalOutcomeKind, texts: [String]) {
        self.kind = kind; self.texts = texts
    }
}

/// The verdict ordering is meaningful: a confident wrong paste is worse than
/// a miss; a miss is worse than a resolved-by-chooser.
public enum EvalVerdict: String, Sendable, Comparable {
    case exact, resolvedByChooser = "resolved_chooser", luckyGuess = "lucky_guess", miss, wrong
    public static func < (a: EvalVerdict, b: EvalVerdict) -> Bool {
        rank(a) < rank(b)
    }
    private static func rank(_ v: EvalVerdict) -> Int {
        switch v { case .exact: 0; case .resolvedByChooser: 1
                   case .luckyGuess: 2; case .miss: 3; case .wrong: 4 }
    }
}

public enum EvalScore {
    /// `latestText` is what a plain ⌘V would have inserted (c1's text).
    /// `hotkey`: the user pressed smart paste to get something other than the latest clip, so when
    /// nothing fits, the list (Esc = plain paste) is a correct answer there; on ⌘V it is noise.
    public static func score(_ outcome: EvalNormalizedOutcome,
                             expect: EvalCase.Expectation,
                             latestText: String, hotkey: Bool = false) -> EvalVerdict {
        switch (expect, outcome.kind) {
        case (.paste(let want), .paste):
            return outcome.texts.first == want ? .exact : .wrong
        case (.paste(let want), .choose):
            return outcome.texts.contains(want) ? .resolvedByChooser : .wrong
        case (.paste(let want), .plain):
            // Plain paste inserts the latest clip verbatim — only "exact"
            // when that WAS the wanted string.
            return latestText == want ? .exact : .miss

        case (.choose(let set), .choose):
            return outcome.texts.contains { set.contains($0) } ? .exact : .wrong
        case (.choose(let set), .paste):
            return outcome.texts.first.map { set.contains($0) } == true
                ? .luckyGuess : .wrong
        case (.choose, .plain):
            return .miss

        case (.plain, .plain):
            return .exact
        case (.plain, .paste):
            // Pasting the latest verbatim is a plain paste in effect.
            return outcome.texts.first == latestText ? .exact : .wrong
        case (.plain, .choose):
            return hotkey ? .resolvedByChooser : .wrong
        }
    }
}

// MARK: - Record / replay providers

/// Provider wrapper that records each raw response under `currentCaseID`,
/// via the sink — one `{"case","model","answers"}` line per call.
public final class RecordingProvider: DecisionProvider, @unchecked Sendable {
    public let inner: any DecisionProvider
    public let sink: (String, JevResponse) -> Void
    public var isRemote: Bool { inner.isRemote }
    public var currentCaseID = ""

    public init(_ inner: any DecisionProvider, sink: @escaping (String, JevResponse) -> Void) {
        self.inner = inner; self.sink = sink
    }

    public func evaluate(state: JSONValue, questions: [String: Question]) async throws -> JevResponse {
        let r = try await inner.evaluate(state: state, questions: questions)
        sink(currentCaseID, r)
        return r
    }
}

/// Serves the first recorded response per case id (the --record format).
public final class ReplayProvider: DecisionProvider, @unchecked Sendable {
    public var isRemote: Bool { false }
    public var currentCaseID = ""
    private var byCase: [String: JevResponse] = [:]

    public init(path: String) throws {
        for line in try String(contentsOfFile: path, encoding: .utf8).split(whereSeparator: \.isNewline) {
            guard let o = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = o["case"] as? String, byCase[id] == nil,
                  let raw = o["answers"] as? [String: String] else { continue }
            byCase[id] = JevResponse(model: o["model"] as? String ?? "replay",
                                     answers: raw.compactMapValues(Self.parse))
        }
    }

    /// "choice:c2 conf=0.4 c1=0.1,c2=0.9" | "noul:0.3" | "score:3 conf=0.5"
    public static func parse(_ s: String) -> Answer? {
        let parts = s.split(separator: " ", maxSplits: 2).map(String.init)
        guard let head = parts.first, let colon = head.firstIndex(of: ":") else { return nil }
        let kind = head[..<colon], val = String(head[head.index(after: colon)...])
        let conf = parts.count > 1 ? Double(parts[1].replacingOccurrences(of: "conf=", with: "")) ?? 0 : 0
        switch kind {
        case "noul": return Double(val).map { .noul(probability: $0) }
        case "choice":
            var probs: [String: Double] = [:]
            if parts.count > 2 {
                for kv in parts[2].split(separator: ",") {
                    let p = kv.split(separator: "=")
                    if p.count == 2, let v = Double(p[1]) { probs[String(p[0])] = v }
                }
            }
            return .choice(key: val, confidence: conf, probabilities: probs)
        case "score": return Double(val).map { .score(score: $0, confidence: conf, probabilities: [:]) }
        default: return nil
        }
    }

    /// The --record wire form of an answer — `parse` is its inverse.
    public static func describe(_ a: Answer) -> String {
        switch a {
        case .choice(let k, let c, let p):
            return "choice:\(k) conf=\(c) \(p.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ","))"
        case .noul(let p): return "noul:\(p)"
        case .score(let s, let c, _): return "score:\(s) conf=\(c)"
        }
    }

    public func evaluate(state: JSONValue, questions: [String: Question]) async throws -> JevResponse {
        guard let r = byCase[currentCaseID] else {
            throw JevError.decoding("no recording for \(currentCaseID)")
        }
        return r
    }
}
