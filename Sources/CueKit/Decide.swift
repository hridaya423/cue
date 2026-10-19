import Foundation

// MARK: - Public types

/// Deterministic, local adjustments to a picked clip. Jev chooses; we execute.
public enum Transform: String, Sendable, CaseIterable {
    case asIs = "as_is"
    case trim
    case lowercase
    case digitsOnly = "digits_only"
    case stripURLTracking = "strip_url_tracking"
    /// Span extraction: pull just the email/phone/URL out of a clip that
    /// contains more — the name+email contact-card copy pasting only the
    /// email into a Recipients field is the canonical case.
    case extractEmail = "extract_email"
    case extractPhone = "extract_phone"
    case extractURL = "extract_url"

    public func apply(_ text: String) -> String {
        switch self {
        case .asIs: text
        case .trim: text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .lowercase: text.lowercased()
        case .digitsOnly: String(text.filter(\.isNumber))
        case .stripURLTracking: Self.stripTracking(from: text)
        // No match → the clip unchanged; extraction never fails a paste.
        case .extractEmail: SpanExtractor.emails(in: text).first ?? text
        case .extractPhone: SpanExtractor.phones(in: text).first ?? text
        case .extractURL: SpanExtractor.urls(in: text).first ?? text
        }
    }

    static func stripTracking(from text: String) -> String {
        guard var c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              c.queryItems != nil else { return text }
        let blocked: Set<String> = ["fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "igshid", "ref_src"]
        c.queryItems = c.queryItems?.filter {
            let name = $0.name.lowercased()
            return !name.hasPrefix("utm_") && !blocked.contains(name)
        }
        return c.string ?? text
    }
}

/// Deterministic span detection shared by the extract transforms and the
/// "contains:" hints added to pick criteria. Email needs regex —
/// NSDataDetector only catches mailto:-style links, not bare addresses.
public enum SpanExtractor {
    static let emailPattern = try! NSRegularExpression(
        pattern: #"[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Za-z]{2,}"#, options: .caseInsensitive)

    public static func emails(in text: String) -> [String] {
        let range = NSRange(text.startIndex..., in: text)
        return emailPattern.matches(in: text, range: range)
            .compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    public static func phones(in text: String) -> [String] {
        phoneRanges(in: text).map(\.0)
    }

    /// http(s) links only — skips mailto: and other schemes the detector
    /// lumps into .link.
    public static func urls(in text: String) -> [String] {
        urlRanges(in: text).map(\.0)
    }

    /// Every detected span, deduplicated — feeds the criteria hints.
    public static func spans(in text: String) -> [String] {
        var seen = Set<String>()
        return (emails(in: text) + phones(in: text) + urls(in: text))
            .filter { seen.insert($0).inserted }
    }
}

public struct ScoredCandidate: Sendable {
    public var clip: Clip
    public var probability: Double
    /// The pick question's confidence, broadcast onto each candidate.
    public var confidence: Double
}

public struct Decision: Sendable {
    public var text: String
    public var clip: Clip
    /// Human-readable note for the toast/status line ("email", "picked").
    public var detail: String?
    public var isForm: Bool
    public var confidence: Double
}

/// What the controller should do — UI branches on this and nothing else.
public enum PasteOutcome: Sendable {
    /// Why a smart-paste degraded to a plain ⌘V — shown as the menu bar's
    /// last-action line so a silent fallback is never mysterious.
    public enum PlainReason: Sendable {
        case useLatest      // model judged c1 already right, verbatim
        case nothingFits    // model said none of the options belongs here
        case lowConfidence  // no decisive pick
        case unreachable    // provider call failed
        case noProvider     // off / unconfigured
        case empty          // no candidates to choose among
        case noAnswer       // malformed model response
        case redactionFailed // couldn't scrub PII for a remote model — nothing sent

        public var label: String {
            switch self {
            case .useLatest: "latest was already right"
            case .nothingFits: "nothing here fits this field"
            case .lowConfidence: "not confident"
            case .unreachable: "model unreachable"
            case .noProvider: "no model configured"
            case .empty: "nothing in history"
            case .noAnswer: "model gave no answer"
            case .redactionFailed: "couldn't mask personal details"
            }
        }
    }

    case paste(Decision)
    /// Several options plausibly fit — show the caret-anchored chooser.
    /// Ranked model output; the user (or Esc → plain paste) decides.
    case choose([ScoredOption])
    /// Behave like a plain ⌘V of the most recent clip (also = "stop" in form-fill).
    case pasteLatest(PlainReason)
}

// MARK: - Engine

/// Builds the System One request from a context snapshot and folds the
/// answers into a PasteOutcome. Every failure path — no provider configured,
/// unreachable endpoint, redaction failure, malformed answer — degrades to
/// `.pasteLatest`: a plain ⌘V, silently. Smart paste never blocks a paste.
public struct DecisionEngine: Sendable {
    public enum Mode: Sendable {
        case hotkey
        case intercept   // ⌘V was intercepted; the model runs only when the latest clip doesn't fit
        case formFill    // mid-form Tab walk; low confidence means stop
    }

    public var provider: (any DecisionProvider)?
    /// Top-option probability needed for an automatic paste, and the gap it
    /// must hold over the runner-up. Below it with ≥2 plausible options, the
    /// chooser shows. Tuned by Evals/results — not a guess.
    /// Measured on CueEval and the persona days; not a user setting.
    public var confidenceThreshold = 0.7
    public var decisivenessMargin = 0.25
    /// What undecided cases do — the user's "When unsure" setting.
    public var lowConfidenceMode: AppSettings.LowConfidenceMode = .top3
    /// Model-call ceiling. Intercepted ⌘V caps harder — a slow ⌘V feels
    /// broken, a fast plain paste doesn't.
    public var timeout: TimeInterval = 2.5
    /// When set and the provider is remote, clip/context text is scrubbed of
    /// PII before it goes on the wire. Loopback endpoints skip it entirely.
    public var redactor: (any Redacting)?

    public init(provider: (any DecisionProvider)? = nil, redactor: (any Redacting)? = nil) {
        self.provider = provider
        self.redactor = redactor
    }

    public func decide(
        context: ContextSnapshot,
        candidates: [Clip],
        mode: Mode,
        answer: (@Sendable () async throws -> JevResponse)? = nil
    ) async -> PasteOutcome {
        guard let latest = candidates.first else { return .pasteLatest(.empty) }
        let expects = FieldKind.infer(label: context.field.label,
                                      placeholder: context.field.placeholder,
                                      nearby: context.nearby)
        // ⌘V whose latest clip already fits the field (any clip fits a generic one): no model call,
        // and nothing else is built first — this is most pastes, so it must cost microseconds.
        // A model override in generic fields was measured on the persona days and lost: 1 right, 4 wrong.
        if mode == .intercept, expects.acceptsVerbatim(latest.text) {
            return .pasteLatest(.useLatest)
        }
        let options = OptionBuilder.options(
            from: candidates, naming: ContextSignal.words(String(context.field.value.suffix(40)), min: 4))
        // A typed field (email/phone/URL) with exactly one matching option has one answer: the policy below
        // picks it whatever the model says. So skip the model — instant, and it works with none running.
        // On ⌘V the clipboard wins: one matching part of the latest clip beats older matches (the user just copied it).
        if mode != .formFill, expects != .generic, expects != .name {
            let typed = options.filter { expects.matches($0) }
            let fromLatest = typed.filter { $0.clip.id == latest.id }
            let only = mode == .intercept && fromLatest.count == 1 ? fromLatest : typed
            if only.count == 1 { return .paste(DecisionPolicy.decision(
                ScoredOption(option: only[0], probability: 1, confidence: 1), isForm: false)) }
        }
        guard let provider else { return .pasteLatest(.noProvider) }

        let resp: JevResponse
        var isForm = false
        do {
            // Redaction failure throws → .pasteLatest → nothing leaves the
            // device. Never send raw text after a failed scrub.
            let scrub = provider.isRemote ? redactor : nil
            let limit = mode == .intercept ? min(timeout, 1.2) : timeout
            resp = try await Self.withTimeout(limit) {
                if let answer { return try await answer() }
                let (state, questions): (JSONValue, [String: Question])
                do {
                    state = try await Self.stateJSON(context: context, mode: mode, redactor: scrub)
                    questions = try await Self.questions(options: options, context: context,
                                                         mode: mode, redactor: scrub)
                } catch { throw ScrubFailed() }
                return try await provider.evaluate(state: state, questions: questions)
            }
        } catch is ScrubFailed {
            return .pasteLatest(.redactionFailed)
        } catch {
            // Hotkey: the model is gone but history isn't. The user asked for something other than
            // the latest clip, so offer recent options (typed ones first) instead of pasting it.
            // Intercept stays silent.
            if mode == .hotkey {
                let typed = expects == .generic ? [] : options.filter { expects.matches($0) }
                let recent = (typed.isEmpty ? options : typed)
                    .map { ScoredOption(option: $0, probability: 0, confidence: 0) }
                if typed.count == 1 { return .paste(DecisionPolicy.decision(recent[0], isForm: false)) }
                if !recent.isEmpty { return .choose(Array(recent.prefix(ChooserRows.visible))) }
            }
            return .pasteLatest(.unreachable)
        }

        let ranked = Self.ranked(from: resp, options: options)
        if mode == .formFill, case .noul(let p) = resp.answers["form_field"], p < 0.5 {
            return .pasteLatest(.lowConfidence)
        }
        if case .noul(let p) = resp.answers["form"], p >= 0.5 { isForm = true }

        let noneProb: Double
        if case .choice(_, _, let probs) = resp.answers["pick"] {
            noneProb = probs["none"] ?? 0
        } else { noneProb = 0 }
        return DecisionPolicy.outcome(
            ranked: ranked, noneProb: noneProb, isForm: isForm,
            mode: mode, threshold: confidenceThreshold, margin: decisivenessMargin,
            fallback: lowConfidenceMode, expects: expects,
            // The words just before the caret ("Sentry:", "PR:") are the most specific evidence there is, so
            // they get the first say; a window title like "Issues - Halyard" matches half the history.
            signal: (ContextSignal.uniquePick(options, label: "", window: "",
                                              nearby: String(context.field.value.suffix(40)))
                ?? ContextSignal.uniquePick(options, label: context.field.label,
                                            window: context.windowTitle, nearby: context.nearby))?.id,
            leaderEchoesPage: ranked.first.map { ContextSignal.echoes($0.option, window: context.windowTitle) } ?? false)
    }

    /// The model's answer for this field and history, asked the way the hotkey asks (pick + form).
    /// ⌘V and the hotkey differ only in the policy folded over it, so one warmed answer serves both.
    public func fetch(context: ContextSnapshot, candidates: [Clip]) async throws -> JevResponse {
        guard let provider else { throw ScrubFailed() }
        let scrub = provider.isRemote ? redactor : nil
        let options = OptionBuilder.options(from: candidates)
        let state = try await Self.stateJSON(context: context, mode: .hotkey, redactor: scrub)
        let questions = try await Self.questions(options: options, context: context,
                                                 mode: .hotkey, redactor: scrub)
        return try await provider.evaluate(state: state, questions: questions)
    }

    struct ScrubFailed: Error {}

    /// Wrap a provider call in a hard ceiling — a hanging endpoint must never
    /// stall a paste. Structured-concurrency timeout: the racing task loses.
    static func withTimeout<T: Sendable>(_ seconds: TimeInterval,
                                         _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CancellationError()
            }
            let v = try await group.next()!
            group.cancelAll()
            return v
        }
    }

    // MARK: - Request construction

    static func stateJSON(context: ContextSnapshot, mode: Mode,
                          redactor: (any Redacting)? = nil) async throws -> JSONValue {
        let r = try await scrubbed(
            [context.windowTitle, context.field.label,
             context.field.placeholder, context.field.value, context.nearby],
            redactor: redactor)
        let expects = FieldKind.infer(label: context.field.label,
                                      placeholder: context.field.placeholder,
                                      nearby: context.nearby)
        return .object([
            "task": .string(mode == .formFill ? "form-fill" : "smart-paste"),
            "app": .string(context.appName),
            "window": .string(r[0]),
            "web_host": .string(context.webHost),
            "nearby": .string(r[4]),
            "field": .object([
                "role": .string(context.field.role),
                "label": .string(r[1]),
                "placeholder": .string(r[2]),
                "current_value": .string(r[3]),
                "expects": .string(expects == .generic ? "" : expects.rawValue),
            ]),
        ])
    }

    static func questions(options: [PasteOption], context: ContextSnapshot,
                          mode: Mode, redactor: (any Redacting)? = nil) async throws -> [String: Question] {
        // Each option describes itself: what it is, its exact text, the line
        // of the clip it came from, and where/when it was copied. Whole
        // lines are scrubbed so hinted PII is redacted too.
        let rawLines = options.map { o -> String in
            let app = o.clip.sourceApp.isEmpty ? "unknown app" : o.clip.sourceApp
            let detail = o.kind == .text ? o.snippet : "\(o.text) · in: \"\(o.snippet)\""
            return "\(o.kind.rawValue) · \"\(detail)\" · copied from \(app) · \(o.clip.copiedAt.relativeAge)"
        }
        let lines = try await scrubbed(rawLines, redactor: redactor)
        var criteria: [String: String] = [:]
        for (i, line) in lines.enumerated() { criteria[options[i].id] = line }
        criteria["none"] = "nothing here belongs in this field, such as a verification code or a search box"
        // Prompt C — won the CueEval A/B/C round (Evals/results/summary.md).
        let instructions = """
            The user invoked smart-paste. Choose the option a person would type \
            into the focused field described by `field`. Weigh, in order: the \
            field's purpose (`field.label`, `field.placeholder`, `field.expects`); \
            who or what the surrounding page or conversation is about (`window`, \
            `nearby`, `web_host`); then recency — c1 is newest. Prefer the option \
            matching a person or thing named in `window` or `nearby`.
            """
        var q: [String: Question] = [
            "pick": .choice(instructions: instructions, criteria: criteria),
        ]
        switch mode {
        case .intercept:
            break
        case .formFill:
            q["form_field"] = .noul(
                instructions: "The user is auto-filling consecutive fields of a form. Is the focused field a fillable part of that same form — not a submit button, search box, captcha, or unrelated input?"
            )
        case .hotkey:
            q["form"] = .noul(
                instructions: "Is the focused field part of a multi-field form (signup, checkout, settings) where the user would want the next fields filled too?"
            )
        }
        return q
    }

    /// Redacts every string in parallel (the on-device model is fast but 40
    /// sequential calls would still show up in paste latency).
    private static func scrubbed(_ texts: [String], redactor: (any Redacting)?) async throws -> [String] {
        guard let redactor else { return texts }
        return try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (i, t) in texts.enumerated() {
                group.addTask { (i, try await redactor.redact(t)) }
            }
            var out = [String](repeating: "", count: texts.count)
            for try await (i, s) in group { out[i] = s }
            return out
        }
    }

    static func ranked(from resp: JevResponse, options: [PasteOption]) -> [ScoredOption] {
        guard case .choice(let pick, let confidence, let probs) = resp.answers["pick"] else { return [] }
        var ranked = options.compactMap { o in
            probs[o.id].map { ScoredOption(option: o, probability: $0, confidence: confidence) }
        }
        // If probabilities came back empty, trust the winning key.
        if ranked.isEmpty, let o = options.first(where: { $0.id == pick }) {
            ranked = [ScoredOption(option: o, probability: 1, confidence: confidence)]
        } else {
            // Options the answer didn't score (named by the caret after the warm-up asked) rank last.
            ranked += options.filter { probs[$0.id] == nil }
                .map { ScoredOption(option: $0, probability: 0, confidence: confidence) }
        }
        return ranked.sorted { $0.probability > $1.probability }
    }
}

// MARK: - Policy

/// Pure answer → outcome fold, so the recorded answers can be re-scored
/// offline with different thresholds (CueEval --rescore).
public enum DecisionPolicy {
    /// - `ranked`: model-ranked options, highest probability first.
    /// - `noneProb`: probability on the `none` criterion.
    /// - `isForm`: model flagged a multi-field form (hotkey only).
    public static func outcome(
        ranked: [ScoredOption],
        noneProb: Double,
        isForm: Bool,
        mode: DecisionEngine.Mode,
        threshold: Double,
        margin: Double,
        fallback: AppSettings.LowConfidenceMode = .top3,
        expects: FieldKind = .generic,
        noneThreshold: Double = 0.7,
        signal: String? = nil,
        leaderEchoesPage: Bool = false
    ) -> PasteOutcome {
        let top = ranked.first
        let second = ranked.dropFirst().first
        // Options that clear the noise floor — the chooser never shows junk.
        let plausible = ranked.filter { $0.probability >= 0.1 }
        let noneLeads = top == nil || noneProb >= top!.probability

        // `none` only ends the paste when it's actually dominant — a
        // plurality "none" beside real candidates deserves the chooser
        // (Esc/⌘V inside it still yields a plain paste).
        let noneDominant = noneProb >= noneThreshold && noneProb >= (top?.probability ?? 0)
        // Decisiveness is judged among the real options (their share of the
        // non-`none` mass): "does something fit" and "which one" are separate
        // questions, and small models park mass on `none` even when the
        // choice among options is clear.
        let mass = ranked.reduce(0) { $0 + $1.probability }
        func share(_ s: ScoredOption?) -> Double { mass > 0 ? (s?.probability ?? 0) / mass : 0 }
        // Context evidence pointing at a different option than the model's leader ("cc legal@…" in a
        // Cc field while the model favours finance@) is a disagreement: ask instead of pasting.
        let contested = signal != nil && signal != top?.option.id
        // A clip that restates the page's own title (the branch named after the issue being commented on)
        // is rarely what goes into that page; the model rates the overlap as fit, so ask instead.
        let decisive = top != nil && !noneDominant && !contested && !leaderEchoesPage
            && share(top) >= threshold
            && share(top) - share(second) >= margin
        // Typed field (email/phone/URL): options of that type outrank the
        // model's `none` — small models over-abstain on obvious cases (one
        // email, an Email field). One match pastes; several go to the chooser.
        let typed = expects == .generic || expects == .name
            ? [] : ranked.filter { expects.matches($0.option) }
        // Context evidence unique to one option (ContextSignal) orders the
        // chooser so Return takes it — never an automatic paste: word overlap
        // can't tell "Reply to Priya" from "Nadia's wedding · Your email".
        func choose(_ opts: [ScoredOption]) -> PasteOutcome {
            var o = opts
            if let i = o.firstIndex(where: { $0.option.id == signal }) {
                o.insert(o.remove(at: i), at: 0)
            } else if let named = ranked.first(where: { $0.option.id == signal }) {
                o.insert(named, at: 0)
            }
            return .choose(o)
        }
        // In an email/phone/URL field a confident pick of the clip around an address ("note me@x.com")
        // loses to the address itself: the field takes the span, never the sentence.
        func fitsKind(_ s: ScoredOption) -> Bool { typed.isEmpty || expects.matches(s.option) }
        func typedOutcome(isForm: Bool) -> PasteOutcome? {
            switch typed.count {
            case 0: return nil
            case 1: return .paste(decision(typed[0], isForm: isForm))
            default: return choose(Array(typed.prefix(3)))
            }
        }

        switch mode {
        case .intercept:
            // ⌘V reaches the model only when the latest clip doesn't fit verbatim (decide()).
            if decisive, let top, fitsKind(top) { return .paste(decision(top, isForm: false)) }
            if let t = typedOutcome(isForm: false) { return t }
            if noneDominant { return .pasteLatest(.nothingFits) }
            if plausible.count >= 2 {
                switch fallback {
                case .pasteBest: return .paste(decision(plausible[0], isForm: false))
                case .pasteLatest: return .pasteLatest(.lowConfidence)
                case .picker: return choose(Array(plausible))
                case .top3: return choose(Array(plausible.prefix(3)))
                }
            }
            return .pasteLatest(.lowConfidence)

        case .hotkey:
            if decisive, let top, fitsKind(top) { return .paste(decision(top, isForm: isForm)) }
            if let t = typedOutcome(isForm: isForm) { return t }
            // The hotkey means "not the latest", so an unsure model never answers with the latest: it
            // ranks what history holds (Esc still plain-pastes). On the persona days a weak leader
            // pasted was right 1 time in 5, while the wanted clip sat at rank 2–9 — so up to 9 rows;
            // near-zero junk is dropped unless the model put nearly everything on "none".
            let confident = ranked.filter { $0.probability >= 0.02 }
            let rows = Array((confident.isEmpty ? ranked : confident).prefix(9))
            guard let best = rows.first else { return .pasteLatest(noneLeads ? .nothingFits : .noAnswer) }
            switch fallback {
            case .pasteBest: return .paste(decision(best, isForm: isForm))
            case .pasteLatest: return .pasteLatest(.lowConfidence)
            case .picker, .top3: return choose(rows)
            }

        case .formFill:
            // Mid-form: never pop a chooser — paste confidently or stop.
            guard let top, top.probability >= 0.5 else { return .pasteLatest(.lowConfidence) }
            return .paste(decision(top, isForm: true))
        }
    }

    static func decision(_ s: ScoredOption, isForm: Bool) -> Decision {
        Decision(text: s.option.text, clip: s.option.clip,
                 detail: s.option.kind == .text ? nil : s.option.kind.rawValue,
                 isForm: isForm, confidence: s.confidence)
    }
}

extension Date {
    /// "just now", "3m ago", "2h ago", "4d ago"
    var relativeAge: String {
        let s = -timeIntervalSinceNow
        if s < 60 { return "just now" }
        if s < 3600 { return "\(Int(s / 60))m ago" }
        if s < 86400 { return "\(Int(s / 3600))h ago" }
        return "\(Int(s / 86400))d ago"
    }
}
