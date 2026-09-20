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
    /// Strength of evidence for this specific pick (heuristic), or the
    /// question-level confidence (Jev) broadcast onto each candidate.
    public var confidence: Double
}

public struct Decision: Sendable {
    public var text: String
    public var clip: Clip
    public var transform: Transform
    public var isForm: Bool
    public var confidence: Double
    public var source: Source

    public enum Source: Sendable {
        case jev, heuristic, latest
    }
}

/// What the controller should do — UI branches on this and nothing else.
public enum PasteOutcome: Sendable {
    case paste(Decision)
    case top3([ScoredCandidate])
    case picker([ScoredCandidate])
    /// Behave like a plain ⌘V of the most recent clip (also = "stop" in form-fill).
    case pasteLatest
}

// MARK: - Heuristic fallback

/// Used when no provider is configured or the call fails. Scores clips against
/// the field's label/placeholder with shape rules; never auto-pastes on a pure
/// recency win — low confidence surfaces the picker instead.
public enum HeuristicRanker {
    public static func rank(context: ContextSnapshot, candidates: [Clip]) -> [ScoredCandidate] {
        // Local lets: Regex isn't Sendable, so no statics.
        let emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
        let digitsRe = /\d/
        let probe = [context.field.label, context.field.placeholder, context.windowTitle]
            .joined(separator: " ")
            .lowercased()
        let n = Double(max(candidates.count, 1))

        return candidates.enumerated().map { i, clip in
            var score = 0.0
            var confidence = 0.4
            let text = clip.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let digits = text.filter(\.isNumber).count

            func signal(_ s: Double, _ c: Double) {
                score += s
                confidence = max(confidence, c)
            }

            if probe.contains("email") || probe.contains("e-mail"), text.wholeMatch(of: emailRe) != nil {
                signal(1.0, 0.9)
            }
            if probe.contains("phone") || probe.contains("tel") || probe.contains("mobile"),
               digits >= 7, Double(digits) / Double(max(text.count, 1)) > 0.5 {
                signal(0.9, 0.85)
            }
            if probe.contains("url") || probe.contains("website") || probe.contains("link") || probe.contains("site"),
               clip.isURL {
                signal(0.9, 0.85)
            }
            if probe.contains("zip") || probe.contains("postal"), text.count <= 10 {
                signal(0.6, 0.6)
            }
            if probe.contains("code") || probe.contains("otp") || probe.contains("verification"),
               (4...8).contains(digits), text.count <= 12 {
                signal(0.9, 0.85)
            }
            if probe.contains("name"),
               !text.contains(digitsRe), text.split(separator: " ").count <= 4, text.count <= 40 {
                signal(0.5, 0.6)
            }
            if probe.contains("user") || probe.contains("login"),
               !text.contains(" "), text.count <= 30 {
                signal(0.4, 0.55)
            }
            if probe.contains("search") || probe.contains("query"), text.count <= 60 {
                signal(0.3, 0.5)
            }
            if clip.pinned { score += 0.1 }
            score += 0.15 * (1.0 - Double(i) / n) // recency

            return ScoredCandidate(clip: clip, probability: score, confidence: confidence)
        }
        .sorted { $0.probability > $1.probability }
    }

    /// Does the focused field look like one step of a data-entry form?
    public static func looksFormLike(context: ContextSnapshot, candidates: [Clip]) -> Bool {
        let probe = (context.field.label + " " + context.field.placeholder).lowercased()
        let formWords = ["name", "email", "phone", "address", "street", "city", "zip",
                         "postal", "country", "card", "first", "last", "company"]
        return candidates.count >= 2 && formWords.contains { probe.contains($0) }
    }
}

// MARK: - Engine

/// Builds the Jev request from a context snapshot and folds the answers into
/// a PasteOutcome. Falls back to the heuristic ranker when no provider is
/// configured or the call fails — the outcome contract never changes.
public struct DecisionEngine: Sendable {
    public enum Mode: Sendable {
        case hotkey
        case intercept   // ⌘V was intercepted; use_latest gates smartness
        case formFill    // mid-form Tab walk; low confidence means stop
    }

    public var provider: (any DecisionProvider)?
    public var confidenceThreshold = 0.7
    public var lowConfidenceMode: AppSettings.LowConfidenceMode = .top3

    public init(provider: (any DecisionProvider)? = nil) {
        self.provider = provider
    }

    /// `feedback` maps clip.id → probability multiplier from past outcomes.
    public func decide(
        context: ContextSnapshot,
        candidates: [Clip],
        mode: Mode,
        feedback: [String: Double] = [:]
    ) async -> PasteOutcome {
        guard !candidates.isEmpty else { return .pasteLatest }

        var ranked: [ScoredCandidate]
        var isForm = false
        var transform: Transform = .asIs
        var source: Decision.Source = .jev

        if let provider {
            do {
                let resp = try await provider.evaluate(
                    state: Self.stateJSON(context: context, mode: mode),
                    questions: Self.questions(candidates: candidates, mode: mode)
                )
                ranked = Self.ranked(from: resp, candidates: candidates)

                if mode == .intercept, case .noul(let p) = resp.answers["use_latest"], p >= 0.5 {
                    return .pasteLatest
                }
                if mode == .formFill, case .noul(let p) = resp.answers["form_field"], p < 0.5 {
                    return .pasteLatest
                }
                if case .noul(let p) = resp.answers["form"], p >= 0.5 { isForm = true }
                if case .choice(let key, _, _) = resp.answers["transform"],
                   let t = Transform(rawValue: key) { transform = t }
            } catch {
                ranked = HeuristicRanker.rank(context: context, candidates: candidates)
                source = .heuristic
            }
        } else {
            ranked = HeuristicRanker.rank(context: context, candidates: candidates)
            source = .heuristic
            isForm = HeuristicRanker.looksFormLike(context: context, candidates: candidates)
        }

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
            return top.confidence >= 0.5 ? makePaste(top, transform: transform, isForm: true, source: source) : .pasteLatest
        }

        // Intercepted ⌘V without a confident answer must stay a plain paste —
        // popping a HUD on every paste would be unusable. This applies to the
        // heuristic path (rarely confident) and to a genuinely uncertain Jev.
        if mode == .intercept, top.confidence < confidenceThreshold {
            return .pasteLatest
        }

        if top.confidence >= confidenceThreshold {
            return makePaste(top, transform: transform, isForm: isForm, source: source)
        }
        switch lowConfidenceMode {
        case .top3: return .top3(Array(ranked.prefix(3)))
        case .picker: return .picker(ranked)
        case .pasteBest: return makePaste(top, transform: transform, isForm: isForm, source: source)
        case .pasteLatest: return .pasteLatest
        }
    }

    private func makePaste(_ sc: ScoredCandidate, transform: Transform, isForm: Bool, source: Decision.Source) -> PasteOutcome {
        .paste(Decision(
            text: transform.apply(sc.clip.text),
            clip: sc.clip,
            transform: transform,
            isForm: isForm,
            confidence: sc.confidence,
            source: source
        ))
    }

    // MARK: - Request construction

    static func stateJSON(context: ContextSnapshot, mode: Mode) -> JSONValue {
        .object([
            "task": .string(mode == .formFill ? "form-fill" : "smart-paste"),
            "app": .string(context.appName),
            "window": .string(context.windowTitle),
            "field": .object([
                "role": .string(context.field.role),
                "label": .string(context.field.label),
                "placeholder": .string(context.field.placeholder),
                "current_value": .string(context.field.value),
            ]),
        ])
    }

    static func questions(candidates: [Clip], mode: Mode) -> [String: Question] {
        var criteria: [String: String] = [:]
        for (i, clip) in candidates.enumerated() {
            let app = clip.sourceApp.isEmpty ? "unknown app" : clip.sourceApp
            criteria["c\(i + 1)"] = "\(clip.kind.rawValue) · \"\(clip.preview)\" · copied from \(app) · \(clip.copiedAt.relativeAge)"
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
