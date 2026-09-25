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

    public var engineMode: DecisionEngine.Mode {
        switch mode {
        case "intercept": .intercept
        case "formFill": .formFill
        default: .hotkey
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
    public static func score(_ outcome: EvalNormalizedOutcome,
                             expect: EvalCase.Expectation,
                             latestText: String) -> EvalVerdict {
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
            return .wrong
        }
    }
}
