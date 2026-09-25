import Foundation
import Testing
@testable import CueKit

struct TransformsTests {
    @Test func all() {
        #expect(Transform.trim.apply("  hello\n") == "hello")
        #expect(Transform.lowercase.apply("Me@Example.COM") == "me@example.com")
        #expect(Transform.digitsOnly.apply("+1 (415) 555-0132") == "14155550132")
        #expect(Transform.stripURLTracking.apply(
            "https://x.com/p?utm_source=twitter&a=1&fbclid=abc") == "https://x.com/p?a=1")
        #expect(Transform.asIs.apply("  keep  ") == "  keep  ")
    }

    @Test func extractEmail() {
        // The contact-card case: name + email copied together, only the
        // address belongs in a To: field.
        #expect(Transform.extractEmail.apply("hridya agrawal hridayahoney@gmail.com")
            == "hridayahoney@gmail.com")
        #expect(Transform.extractEmail.apply("Jane Doe <jane@example.com>") == "jane@example.com")
        // No match → unchanged; extraction never produces nothing.
        #expect(Transform.extractEmail.apply("no email here") == "no email here")
    }

    @Test func extractPhoneAndURL() {
        #expect(Transform.extractPhone.apply("call Jane +1 (415) 555-0132 tomorrow")
            == "+1 (415) 555-0132")
        #expect(Transform.extractURL.apply("see https://example.com/a?b=1 for details")
            == "https://example.com/a?b=1")
    }
}

struct SpanExtractorTests {
    @Test func emails() {
        #expect(SpanExtractor.emails(in: "a b x@y.co c") == ["x@y.co"])
        #expect(SpanExtractor.emails(in: "none") == [])
        // Multiple addresses all surface.
        #expect(SpanExtractor.emails(in: "a@b.co then c@d.io").count == 2)
    }

    @Test func urlsSkipMailto() {
        let spans = SpanExtractor.urls(in: "mail me@x.com or visit https://example.com")
        #expect(spans == ["https://example.com"])
    }

    @Test func spansDedup() {
        let spans = SpanExtractor.spans(in: "jane@x.com jane@x.com +1 415 555 0132")
        #expect(spans.filter { $0 == "jane@x.com" }.count == 1)
    }
}

// MARK: - Engine

/// Shared record of what the provider was asked (JSONValue is Equatable).
final class CallBox: @unchecked Sendable {
    var states: [JSONValue] = []
    var questions: [[String: Question]] = []
    var calls = 0
}

/// Stub provider returning canned Jev answers.
struct StubProvider: DecisionProvider {
    var response: JevResponse
    var error: Error?
    var isRemote = true
    var box = CallBox()
    func evaluate(state: JSONValue, questions: [String: Question]) async throws -> JevResponse {
        box.calls += 1
        box.states.append(state)
        box.questions.append(questions)
        if let error { throw error }
        return response
    }
}

/// Replaces every string with a fixed placeholder and records what it saw.
final class StubRedactor: Redacting, @unchecked Sendable {
    private let seenLock = NSLock()
    private var storedSeen: [String] = []
    var seen: [String] {
        seenLock.lock()
        defer { seenLock.unlock() }
        return storedSeen
    }
    var error: Error?
    func redact(_ text: String) async throws -> String {
        if let error { throw error }
        recordSeen(text)
        return "[PII]"
    }

    private func recordSeen(_ text: String) {
        seenLock.lock()
        storedSeen.append(text)
        seenLock.unlock()
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
    }

    @Test func lowConfidenceShowsTop3() async {
        // Neither confidence nor the probability leader is decisive → HUD.
        var engine = DecisionEngine(provider: StubProvider(response: response(
            pick: "c2", conf: 0.5, probs: ["c1": 0.45, "c2": 0.55])))
        engine.confidenceThreshold = 0.7
        engine.lowConfidenceMode = .top3
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .top3(let cands) = outcome else { Issue.record("expected top3, got \(outcome)"); return }
        #expect(cands.count == 2)
    }

    @Test func decisiveLeaderPastesDespiteLowConfidence() async {
        // The Von regression: conf 0.526 < 0.7 but a 76%/24% probability
        // leader is decisive — paste it rather than popping a HUD.
        var engine = DecisionEngine(provider: StubProvider(response: response(
            pick: "c1", conf: 0.526, probs: ["c1": 0.7627, "c2": 0.2372])))
        engine.confidenceThreshold = 0.7
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .paste(let d) = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(d.clip.text == "latest clip")
    }

    @Test func interceptDecisiveLeaderStillPastes() async {
        var engine = DecisionEngine(provider: StubProvider(response: response(
            pick: "c1", conf: 0.526, useLatest: 0.2, probs: ["c1": 0.7627, "c2": 0.2372])))
        engine.confidenceThreshold = 0.7
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .intercept)
        guard case .paste(let d) = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(d.clip.text == "latest clip")
    }

    @Test func interceptModeRespectsUseLatest() async {
        var engine = DecisionEngine(provider: StubProvider(
            response: response(pick: "c2", conf: 0.99, useLatest: 0.9)))
        engine.confidenceThreshold = 0.7
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .intercept)
        guard case .pasteLatest = outcome else { Issue.record("expected pasteLatest, got \(outcome)"); return }
    }

    @Test func providerErrorPastesLatest() async {
        // No heuristics: a dead/unreachable provider degrades to a normal paste.
        let engine = DecisionEngine(provider: StubProvider(
            response: response(pick: "c1", conf: 1), error: JevError.http(500, "boom")))
        let outcome = await engine.decide(context: makeContext(label: "Email"), candidates: clips, mode: .hotkey)
        guard case .pasteLatest = outcome else { Issue.record("expected pasteLatest, got \(outcome)"); return }
    }

    @Test func noProviderPastesLatest() async {
        let engine = DecisionEngine(provider: nil)
        let outcome = await engine.decide(
            context: makeContext(label: "Email"), candidates: clips, mode: .hotkey)
        guard case .pasteLatest = outcome else { Issue.record("expected pasteLatest, got \(outcome)"); return }
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
        // 3-way split: no probability leader can reach 0.5 → stop the form.
        let three = clips + [Clip(text: "third", kind: .text)]
        var engine = DecisionEngine(provider: StubProvider(response: response(
            pick: "c2", conf: 0.3, probs: ["c1": 0.4, "c2": 0.35, "c3": 0.25])))
        engine.confidenceThreshold = 0.7
        engine.lowConfidenceMode = .top3 // must be ignored in formFill
        let outcome = await engine.decide(context: makeContext(), candidates: three, mode: .formFill)
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
        // paste — popping a HUD on every ⌘V would be unusable. Neither the
        // confidence nor the probability split is decisive here.
        var engine = DecisionEngine(provider: StubProvider(response: response(
            pick: "c2", conf: 0.4, probs: ["c1": 0.4, "c2": 0.6])))
        engine.confidenceThreshold = 0.7
        engine.lowConfidenceMode = .top3
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .intercept)
        guard case .pasteLatest = outcome else { Issue.record("expected pasteLatest, got \(outcome)"); return }
    }

    @Test func interceptNoProviderIsPlainPaste() async {
        // Offline + intercept: nothing to decide → plain paste on every ⌘V.
        let engine = DecisionEngine(provider: nil)
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

    @Test func remoteProviderGetsRedactedText() async {
        let redactor = StubRedactor()
        let provider = StubProvider(response: response(pick: "c2", conf: 0.95))
        var engine = DecisionEngine(provider: provider, redactor: redactor)
        engine.confidenceThreshold = 0.7
        _ = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)

        // The pick criteria must carry placeholders, never the raw clip text.
        guard let pick = provider.box.questions.first?["pick"]?.jsonValue["criteria"],
              case .object(let criteria) = pick else {
            Issue.record("no pick criteria captured"); return
        }
        #expect(criteria["c2"]?.string?.contains("[PII]") == true)
        #expect(criteria["c2"]?.string?.contains("me@example.com") == false)
        // The raw text stayed on-device — only the local redactor saw it
        // (whole criteria lines are scrubbed, so it arrives as a substring).
        #expect(redactor.seen.contains { $0.contains("me@example.com") })
    }

    @Test func loopbackProviderSkipsRedaction() async {
        // kev/laya run on-device — scrubbing adds latency for zero privacy gain.
        let redactor = StubRedactor()
        var endpoint = StubProvider(response: response(pick: "c2", conf: 0.95))
        endpoint.isRemote = false
        var engine = DecisionEngine(provider: endpoint, redactor: redactor)
        engine.confidenceThreshold = 0.7
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .paste = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(redactor.seen.isEmpty)
    }

    @Test func redactionFailureNeverLeaksToProvider() async {
        struct Fail: Error {}
        let redactor = StubRedactor()
        redactor.error = Fail()
        let provider = StubProvider(response: response(pick: "c2", conf: 0.95))
        var engine = DecisionEngine(provider: provider, redactor: redactor)
        engine.confidenceThreshold = 0.7
        let outcome = await engine.decide(context: makeContext(label: "Email"), candidates: clips, mode: .hotkey)
        #expect(provider.box.calls == 0) // nothing was sent
        guard case .pasteLatest = outcome else {
            Issue.record("expected pasteLatest, got \(outcome)"); return
        }
    }

    @Test func rawClipPastesAfterRedaction() async {
        // Redaction scrubs what the model sees; the paste still executes on
        // the raw clip — placeholders like [EMAIL_1] must never reach the field.
        let redactor = StubRedactor()
        let provider = StubProvider(response: response(pick: "c2", conf: 0.95))
        var engine = DecisionEngine(provider: provider, redactor: redactor)
        engine.confidenceThreshold = 0.7
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .paste(let d) = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(d.text == "me@example.com")
        #expect(!d.text.contains("[PII]"))
    }

    @Test func emptyCandidatesPastesLatest() async {
        let engine = DecisionEngine(provider: StubProvider(response: response(pick: "c1", conf: 1)))
        let outcome = await engine.decide(context: makeContext(), candidates: [], mode: .hotkey)
        guard case .pasteLatest = outcome else { Issue.record("expected pasteLatest"); return }
    }

    @Test func extractTransformPastesOnlyTheSpan() async {
        // Contact-card clip picked for a To: field + extract_email → the
        // field gets just the address, not "name address".
        let card = [Clip(text: "hridya agrawal hridayahoney@gmail.com", kind: .text),
                    Clip(text: "unrelated", kind: .text)]
        var engine = DecisionEngine(provider: StubProvider(response: response(
            pick: "c1", conf: 0.95, transform: "extract_email")))
        engine.confidenceThreshold = 0.7
        let outcome = await engine.decide(context: makeContext(label: "To:"), candidates: card, mode: .hotkey)
        guard case .paste(let d) = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(d.text == "hridayahoney@gmail.com")
    }

    @Test func transformQuestionIncludesCopiedText() async {
        let provider = StubProvider(response: response(pick: "c1", conf: 0.95,
                                                       transform: "extract_url"))
        var engine = DecisionEngine(provider: provider)
        engine.confidenceThreshold = 0.7
        _ = await engine.decide(context: makeContext(label: "Website"),
                                candidates: [Clip(text: "Invoice portal https://example.com/pay", kind: .text)],
                                mode: .hotkey)

        let instructions = provider.box.questions.first?[
            "transform"]?.jsonValue["instructions"]?.string
        #expect(instructions?.contains("Invoice portal https://example.com/pay") == true)
        #expect(instructions?.contains("extract_url") == true)
    }

    @Test func spanHintsReachTheModelPastPreviewTruncation() async {
        // Preview truncates at 80 chars — an email at char 100 must still be
        // advertised to the model via the "contains:" criteria hint.
        let long = Clip(text: String(repeating: "lorem ipsum dolor sit amet ", count: 4)
                        + "buried@example.com", kind: .text)
        let provider = StubProvider(response: response(pick: "c1", conf: 0.9))
        var engine = DecisionEngine(provider: provider)
        engine.confidenceThreshold = 0.7
        _ = await engine.decide(context: makeContext(), candidates: [long, clips[0]], mode: .hotkey)

        guard let pick = provider.box.questions.first?["pick"]?.jsonValue["criteria"],
              case .object(let criteria) = pick,
              case .string(let c1) = criteria["c1"] else {
            Issue.record("no pick criteria captured"); return
        }
        #expect(!long.preview.contains("buried@example.com")) // premise: it IS truncated
        #expect(c1.contains("buried@example.com"))
        #expect(c1.contains("contains:"))
    }

    @Test func pasteLatestCarriesReason() async {
        // Menu bar breadcrumb: every plain-paste outcome says why.
        let engine = DecisionEngine(provider: nil)
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .pasteLatest(let reason) = outcome, reason == .noProvider else {
            Issue.record("expected pasteLatest(.noProvider), got \(outcome)"); return
        }
        #expect(!reason.label.isEmpty)
    }
}

private extension JevResponse {
    func adding(formField p: Double) -> JevResponse {
        var r = self
        r.answers["form_field"] = .noul(probability: p)
        return r
    }
}
