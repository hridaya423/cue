import Foundation

// MARK: - Public types

/// Deterministic, local adjustments to a picked clip. Jev chooses; we execute.
public enum Transform: String, Sendable, CaseIterable {
    case asIs = "as_is"
    case trim
    case lowercase
    case digitsOnly = "digits_only"
    case stripURLTracking = "strip_url_tracking"

    public func apply(_ text: String) -> String {
        switch self {
        case .asIs: text
        case .trim: text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .lowercase: text.lowercased()
        case .digitsOnly: String(text.filter(\.isNumber))
        case .stripURLTracking: Self.stripTracking(from: text)
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

    /// Labels sent to Jev as choice criteria.
    static var criteriaDescriptions: [String: String] {
        [
            asIs.rawValue: "paste exactly as copied",
            trim.rawValue: "remove leading and trailing whitespace",
            lowercase.rawValue: "lowercase all text (emails, usernames)",
            digitsOnly.rawValue: "keep digits only (phone/number fields)",
            stripURLTracking.rawValue: "strip tracking parameters from a URL (utm_*, fbclid, gclid)",
        ]
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
    public var transform: Transform
    public var isForm: Bool
    public var confidence: Double
}

/// What the controller should do — UI branches on this and nothing else.
public enum PasteOutcome: Sendable {
    case paste(Decision)
    case top3([ScoredCandidate])
    case picker([ScoredCandidate])
    /// Behave like a plain ⌘V of the most recent clip (also = "stop" in form-fill).
    case pasteLatest
}

// MARK: - Engine

/// Builds the System One request from a context snapshot and folds the
/// answers into a PasteOutcome. Every failure path — no provider configured,
/// unreachable endpoint, redaction failure, malformed answer — degrades to
/// `.pasteLatest`: a plain ⌘V, silently. Smart paste never blocks a paste.
public struct DecisionEngine: Sendable {
    public enum Mode: Sendable {
        case hotkey
        case intercept   // ⌘V was intercepted; use_latest gates smartness
        case formFill    // mid-form Tab walk; low confidence means stop
    }

    public var provider: (any DecisionProvider)?
    public var confidenceThreshold = 0.7
    public var lowConfidenceMode: AppSettings.LowConfidenceMode = .top3
    /// When set and the provider is remote, clip/context text is scrubbed of
    /// PII before it goes on the wire. Loopback endpoints skip it entirely.
    public var redactor: (any Redacting)?

    public init(provider: (any DecisionProvider)? = nil, redactor: (any Redacting)? = nil) {
        self.provider = provider
        self.redactor = redactor
    }

    /// `feedback` maps clip.id → probability multiplier from past outcomes.
    public func decide(
        context: ContextSnapshot,
        candidates: [Clip],
        mode: Mode,
        feedback: [String: Double] = [:]
    ) async -> PasteOutcome {
        guard !candidates.isEmpty, let provider else { return .pasteLatest }

        let resp: JevResponse
        var isForm = false
        var transform: Transform = .asIs
        do {
            // Redaction failure throws → .pasteLatest → nothing leaves the
            // device. Never send raw text after a failed scrub.
            let scrub = provider.isRemote ? redactor : nil
            resp = try await provider.evaluate(
                state: try await Self.stateJSON(context: context, mode: mode, redactor: scrub),
                questions: try await Self.questions(candidates: candidates, mode: mode, redactor: scrub)
            )
        } catch {
            return .pasteLatest
        }

        var ranked = Self.ranked(from: resp, candidates: candidates)
        if mode == .intercept, case .noul(let p) = resp.answers["use_latest"], p >= 0.5 {
            return .pasteLatest
        }
        if mode == .formFill, case .noul(let p) = resp.answers["form_field"], p < 0.5 {
            return .pasteLatest
        }
        if case .noul(let p) = resp.answers["form"], p >= 0.5 { isForm = true }
        if case .choice(let key, _, _) = resp.answers["transform"],
           let t = Transform(rawValue: key) { transform = t }

        // Blend local feedback, renormalize.
        if !feedback.isEmpty {
            ranked = ranked.map { sc in
                var s = sc
                s.probability *= feedback[sc.clip.id] ?? 1
                return s
            }
        }
        let total = ranked.reduce(0) { $0 + $1.probability }
        if total > 0 {
            ranked = ranked.map { var s = $0; s.probability /= total; return s }
        }
        ranked.sort { $0.probability > $1.probability }

        guard let top = ranked.first else { return .pasteLatest }

        // Mid-form: never pop a HUD — paste confidently or stop.
        if mode == .formFill {
            return top.confidence >= 0.5 ? makePaste(top, transform: transform, isForm: true) : .pasteLatest
        }

        // Intercepted ⌘V without a confident answer must stay a plain paste —
        // popping a HUD on every paste would be unusable.
        if mode == .intercept, top.confidence < confidenceThreshold {
            return .pasteLatest
        }

        if top.confidence >= confidenceThreshold {
            return makePaste(top, transform: transform, isForm: isForm)
        }
        switch lowConfidenceMode {
        case .top3: return .top3(Array(ranked.prefix(3)))
        case .picker: return .picker(ranked)
        case .pasteBest: return makePaste(top, transform: transform, isForm: isForm)
        case .pasteLatest: return .pasteLatest
        }
    }

    private func makePaste(_ sc: ScoredCandidate, transform: Transform, isForm: Bool) -> PasteOutcome {
        .paste(Decision(
            text: transform.apply(sc.clip.text),
            clip: sc.clip,
            transform: transform,
            isForm: isForm,
            confidence: sc.confidence
        ))
    }

    // MARK: - Request construction

    static func stateJSON(context: ContextSnapshot, mode: Mode,
                          redactor: (any Redacting)? = nil) async throws -> JSONValue {
        let r = try await scrubbed(
            [context.windowTitle, context.field.label,
             context.field.placeholder, context.field.value],
            redactor: redactor)
        return .object([
            "task": .string(mode == .formFill ? "form-fill" : "smart-paste"),
            "app": .string(context.appName),
            "window": .string(r[0]),
            "field": .object([
                "role": .string(context.field.role),
                "label": .string(r[1]),
                "placeholder": .string(r[2]),
                "current_value": .string(r[3]),
            ]),
        ])
    }

    static func questions(candidates: [Clip], mode: Mode,
                          redactor: (any Redacting)? = nil) async throws -> [String: Question] {
        let previews = try await scrubbed(candidates.map(\.preview), redactor: redactor)
        var criteria: [String: String] = [:]
        for (i, clip) in candidates.enumerated() {
            let app = clip.sourceApp.isEmpty ? "unknown app" : clip.sourceApp
            criteria["c\(i + 1)"] = "\(clip.kind.rawValue) · \"\(previews[i])\" · copied from \(app) · \(clip.copiedAt.relativeAge)"
        }
        var q: [String: Question] = [
            "pick": .choice(
                instructions: "The user invoked smart-paste. Which clipboard item best fits the focused field? Use the field's label, placeholder, and current value. c1 is the most recently copied item.",
                criteria: criteria
            ),
            "transform": .choice(
                instructions: "Does the picked item need adjustment to fit this field (e.g. digits-only phone fields, lowercase emails)?",
                criteria: Transform.criteriaDescriptions
            ),
        ]
        switch mode {
        case .intercept:
            q["use_latest"] = .noul(
                instructions: "The user pressed the ordinary paste shortcut. Is the most recently copied item (c1) already the right thing to paste here?"
            )
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

    static func ranked(from resp: JevResponse, candidates: [Clip]) -> [ScoredCandidate] {
        guard case .choice(let pick, let confidence, let probs) = resp.answers["pick"] else { return [] }
        var ranked = candidates.enumerated().compactMap { i, clip in
            probs["c\(i + 1)"].map { ScoredCandidate(clip: clip, probability: $0, confidence: confidence) }
        }
        // If probabilities came back empty, trust the winning key.
        if ranked.isEmpty, pick.hasPrefix("c"), let i = Int(pick.dropFirst()),
           candidates.indices.contains(i - 1) {
            ranked = [ScoredCandidate(clip: candidates[i - 1], probability: 1, confidence: confidence)]
        }
        return ranked
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
