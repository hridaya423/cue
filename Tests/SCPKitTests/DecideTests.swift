import Foundation
import Testing
@testable import SCPKit

struct TransformsTests {
    @Test func all() {
        #expect(Transform.trim.apply("  hello\n") == "hello")
        #expect(Transform.lowercase.apply("Me@Example.COM") == "me@example.com")
        #expect(Transform.digitsOnly.apply("+1 (415) 555-0132") == "14155550132")
        #expect(Transform.stripURLTracking.apply(
            "https://x.com/p?utm_source=twitter&a=1&fbclid=abc") == "https://x.com/p?a=1")
        #expect(Transform.asIs.apply("  keep  ") == "  keep  ")
    }
}

struct HeuristicRankerTests {
    private func ctx(label: String, placeholder: String = "") -> ContextSnapshot {
        var c = ContextSnapshot()
        c.field.label = label
        c.field.placeholder = placeholder
        c.field.role = "AXTextField"
        return c
    }

    @Test func emailFieldPicksEmail() {
        let clips = [
            Clip(text: "some random sentence", kind: .text),
            Clip(text: "me@example.com", kind: .text),
        ]
        let ranked = HeuristicRanker.rank(context: ctx(label: "Email"), candidates: clips)
        #expect(ranked.first?.clip.text == "me@example.com")
        #expect(ranked.first!.confidence >= 0.7)
    }

    @Test func phoneFieldPicksDigits() {
        let clips = [
            Clip(text: "my notes", kind: .text),
            Clip(text: "+1 (415) 555-0132", kind: .text),
        ]
        let ranked = HeuristicRanker.rank(context: ctx(label: "Phone number"), candidates: clips)
        #expect(ranked.first?.clip.text == "+1 (415) 555-0132")
    }

    @Test func urlFieldPicksURL() {
        let clips = [
            Clip(text: "plain text here", kind: .text),
            Clip(text: "https://github.com/x", kind: .url),
        ]
        let ranked = HeuristicRanker.rank(context: ctx(label: "Website"), candidates: clips)
        #expect(ranked.first?.clip.isURL == true)
    }

    @Test func formDetection() {
        let clips = [Clip(text: "a", kind: .text), Clip(text: "b", kind: .text)]
        #expect(HeuristicRanker.looksFormLike(context: ctx(label: "First name"), candidates: clips))
        #expect(!HeuristicRanker.looksFormLike(context: ctx(label: "Spotlight"), candidates: clips))
        #expect(!HeuristicRanker.looksFormLike(context: ctx(label: "Email"), candidates: [clips[0]]))
    }
}

// MARK: - Engine

/// Stub provider returning canned Jev answers.
struct StubProvider: DecisionProvider {
    var response: JevResponse
    var error: Error?
    func evaluate(state: JSONValue, questions: [String: Question]) async throws -> JevResponse {
        if let error { throw error }
        return response
    }
}

struct DecisionEngineTests {
    private func makeContext(label: String = "Email") -> ContextSnapshot {
        var c = ContextSnapshot()
        c.appName = "Safari"
        c.field.label = label
        c.field.role = "AXTextField"
        return c
    }

    private let clips = [
        Clip(text: "latest clip", kind: .text),
        Clip(text: "me@example.com", kind: .text),
    ]

    private func response(pick: String, conf: Double, form: Double? = nil,
                          useLatest: Double? = nil, transform: String = "as_is",
                          probs: [String: Double]? = nil) -> JevResponse {
        var answers: [String: Answer] = [
            "pick": .choice(key: pick, confidence: conf,
                            probabilities: probs ?? ["c1": pick == "c1" ? 1 : 0, "c2": pick == "c2" ? 1 : 0]),
            "transform": .choice(key: transform, confidence: 1,
                                 probabilities: [transform: 1]),
        ]
        if let form { answers["form"] = .noul(probability: form) }
        if let useLatest { answers["use_latest"] = .noul(probability: useLatest) }
        return JevResponse(model: "jev-latest", answers: answers, inputTokens: 100)
    }

    @Test func confidentPickPastes() async {
        var engine = DecisionEngine(provider: StubProvider(response: response(pick: "c2", conf: 0.95)))
        engine.confidenceThreshold = 0.7
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .paste(let d) = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(d.clip.text == "me@example.com")
        #expect(d.source == .jev)
    }

    @Test func lowConfidenceShowsTop3() async {
        var engine = DecisionEngine(provider: StubProvider(response: response(pick: "c2", conf: 0.5)))
        engine.confidenceThreshold = 0.7
        engine.lowConfidenceMode = .top3
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .top3(let cands) = outcome else { Issue.record("expected top3, got \(outcome)"); return }
        #expect(cands.count == 2)
    }

    @Test func interceptModeRespectsUseLatest() async {
        var engine = DecisionEngine(provider: StubProvider(
            response: response(pick: "c2", conf: 0.99, useLatest: 0.9)))
        engine.confidenceThreshold = 0.7
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .intercept)
        guard case .pasteLatest = outcome else { Issue.record("expected pasteLatest, got \(outcome)"); return }
    }

    @Test func providerErrorFallsBackToHeuristic() async {
        var engine = DecisionEngine(provider: StubProvider(
            response: response(pick: "c1", conf: 1), error: JevError.http(500, "boom")))
        engine.confidenceThreshold = 0.7
        let outcome = await engine.decide(context: makeContext(label: "Email"), candidates: clips, mode: .hotkey)
        // Heuristic should still pick the email clip for an Email field.
        guard case .paste(let d) = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(d.clip.text == "me@example.com")
        #expect(d.source == .heuristic)
    }

    @Test func feedbackDemotesClip() async {
        var engine = DecisionEngine(provider: StubProvider(response: response(
            pick: "c2", conf: 0.95, probs: ["c1": 0.4, "c2": 0.6])))
        engine.confidenceThreshold = 0.7
        // c2 was undone before → multiplier 0.5 → 0.3 < 0.4 → c1 wins.
        let feedback = [clips[1].id: 0.5]
        let outcome = await engine.decide(context: makeContext(), candidates: clips,
                                          mode: .hotkey, feedback: feedback)
        guard case .paste(let d) = outcome else { Issue.record("expected paste"); return }
        #expect(d.clip.text == "latest clip")
    }

    @Test func formFillModeNeverShowsHUD() async {
        var engine = DecisionEngine(provider: StubProvider(response: response(pick: "c2", conf: 0.3)))
        engine.confidenceThreshold = 0.7
        engine.lowConfidenceMode = .top3 // must be ignored in formFill
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .formFill)
        guard case .pasteLatest = outcome else {
            Issue.record("low confidence mid-form should stop, got \(outcome)"); return
        }
    }

    @Test func formFillStopsOnNonFormField() async {
        var engine = DecisionEngine(provider: StubProvider(
            response: response(pick: "c2", conf: 0.99, form: nil).adding(formField: 0.1)))
        engine.confidenceThreshold = 0.7
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .formFill)
        guard case .pasteLatest = outcome else { Issue.record("expected pasteLatest, got \(outcome)"); return }
    }

    @Test func transformAppliesToPick() async {
        var engine = DecisionEngine(provider: StubProvider(
            response: response(pick: "c2", conf: 0.95, transform: "lowercase")))
        engine.confidenceThreshold = 0.7
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .paste(let d) = outcome else { Issue.record("expected paste"); return }
        #expect(d.text == "me@example.com") // already lowercase
    }

    @Test func interceptLowConfidenceIsPlainPaste() async {
        // A hesitant smart-paste on an intercepted ⌘V must degrade to normal
        // paste — popping a HUD on every ⌘V would be unusable.
        var engine = DecisionEngine(provider: StubProvider(response: response(pick: "c2", conf: 0.4)))
        engine.confidenceThreshold = 0.7
        engine.lowConfidenceMode = .top3
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .intercept)
        guard case .pasteLatest = outcome else { Issue.record("expected pasteLatest, got \(outcome)"); return }
    }

    @Test func interceptHeuristicIsPlainPaste() async {
        // Offline + intercept: heuristic confidence is almost always below
        // threshold → plain paste, not a HUD on every ⌘V.
        var engine = DecisionEngine(provider: nil)
        engine.confidenceThreshold = 0.7
        let outcome = await engine.decide(
            context: makeContext(label: "Notes"), candidates: clips, mode: .intercept)
        guard case .pasteLatest = outcome else { Issue.record("expected pasteLatest, got \(outcome)"); return }
    }

    @Test func emptyProbsTrustPickKey() async {
        // Jev answered "c2" but sent no probability map — trust the winner.
        let resp = JevResponse(model: "jev", answers: [
            "pick": .choice(key: "c2", confidence: 0.9, probabilities: [:]),
        ], inputTokens: 0)
        let ranked = DecisionEngine.ranked(from: resp, candidates: clips)
        #expect(ranked.count == 1)
        #expect(ranked.first?.clip.text == "me@example.com")
    }

    @Test func emptyCandidatesPastesLatest() async {
        let engine = DecisionEngine(provider: StubProvider(response: response(pick: "c1", conf: 1)))
        let outcome = await engine.decide(context: makeContext(), candidates: [], mode: .hotkey)
        guard case .pasteLatest = outcome else { Issue.record("expected pasteLatest"); return }
    }
}

private extension JevResponse {
    func adding(formField p: Double) -> JevResponse {
        var r = self
        r.answers["form_field"] = .noul(probability: p)
        return r
    }
}
