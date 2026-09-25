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
        let opts = OptionBuilder.options(from: [
            Clip(text: "jane@x.com jane@x.com +1 415 555 0132", kind: .text)])
        #expect(opts.filter { $0.text == "jane@x.com" }.count == 1)
    }

    @Test func spansWithContextCarrySurroundings() {
        let spans = SpanExtractor.spansWithContext(
            in: "For onboarding ping mira@acme.example.com, for invoices billing@acme.example.com")
        #expect(spans.count == 2)
        #expect(spans[0].kind == .email)
        #expect(spans[0].context.contains("onboarding ping"))
        #expect(spans[1].context.contains("for invoices"))
    }
}

struct OptionBuilderTests {
    func clip(_ t: String, pinned: Bool = false) -> Clip {
        Clip(text: t, kind: Clip.classify(t), pinned: pinned)
    }

    @Test func spanAndWholeClipBothBecomeOptions() {
        let opts = OptionBuilder.options(from: [
            clip("reach me at sarah.lee@example.com or 415-555-0168"),
            clip("call dentist tuesday"),
        ])
        let texts = opts.map(\.text)
        #expect(texts.contains("sarah.lee@example.com"))
        #expect(texts.contains("call dentist tuesday"))
        #expect(opts.first(where: { $0.text == "sarah.lee@example.com" })?.kind == .email)
        // Option keys are c1..cN in order.
        #expect(opts.map(\.id) == (1...opts.count).map { "c\($0)" })
    }

    @Test func clipThatIsASpanStaysOneOption() {
        let opts = OptionBuilder.options(from: [clip("me@example.com")])
        #expect(opts.count == 1)
        #expect(opts[0].kind == .email)
    }

    @Test func dedupeKeepsNewest() {
        let opts = OptionBuilder.options(from: [
            clip("same@example.com"),          // newest
            clip("note with same@example.com"), // older, span dedupes
        ])
        #expect(opts.filter { $0.text == "same@example.com" }.count == 1)
        #expect(opts.first?.text == "same@example.com")
    }

    @Test func last20PlusPins() {
        var clips = (1...25).map { clip("clip number \($0)") }
        clips.append(clip("a pinned email pin@example.com", pinned: true))
        let opts = OptionBuilder.options(from: clips)
        // The 25th unpinned clip is out of scope; the pin (position 26) is in.
        #expect(opts.contains { $0.text == "clip number 6" })       // within 20
        #expect(!opts.contains { $0.text == "clip number 21" })     // beyond window
        #expect(opts.contains { $0.text == "pin@example.com" })     // pinned
    }

    @Test func fieldKindInference() {
        #expect(FieldKind.infer(label: "Email", placeholder: "", nearby: "") == .email)
        #expect(FieldKind.infer(label: "", placeholder: "(___) ___-____", nearby: "phone") == .phone)
        #expect(FieldKind.infer(label: "Website", placeholder: "", nearby: "") == .url)
        #expect(FieldKind.infer(label: "Search", placeholder: "Search…", nearby: "") == .generic)
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

/// A canned pick response. Option keys are c1/c2/… in option order
/// (spans first, then the whole clip, per clip) plus "none".
private func pickResponse(pick: String, conf: Double,
                          probs: [String: Double],
                          form: Double? = nil, useLatest: Double? = nil) -> JevResponse {
    var answers: [String: Answer] = [
        "pick": .choice(key: pick, confidence: conf, probabilities: probs),
    ]
    if let form { answers["form"] = .noul(probability: form) }
    if let useLatest { answers["use_latest"] = .noul(probability: useLatest) }
    return JevResponse(model: "jev-latest", answers: answers, inputTokens: 100)
}

struct DecisionEngineTests {
    private func makeContext(label: String = "Email") -> ContextSnapshot {
        var c = ContextSnapshot()
        c.appName = "Safari"
        c.field.label = label
        c.field.role = "AXTextField"
        return c
    }

    // Two plain-text clips → options: c1 = "latest clip" (text),
    // c2 = "me@example.com" (email span; the clip IS the span).
    private let clips = [
        Clip(text: "latest clip", kind: .text),
        Clip(text: "me@example.com", kind: .text),
    ]

    @Test func decisivePickPastesTheSpan() async {
        var engine = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "c2", conf: 0.95, probs: ["c1": 0.05, "c2": 0.9, "none": 0.05])))
        engine.confidenceThreshold = 0.6
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .paste(let d) = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(d.text == "me@example.com")
        #expect(d.detail == "email")
    }

    @Test func ambiguousPickShowsChooser() async {
        // Two options split probability → caret-anchored chooser.
        var engine = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "c1", conf: 0.5, probs: ["c1": 0.45, "c2": 0.45, "none": 0.1])))
        engine.confidenceThreshold = 0.6
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .choose(let opts) = outcome else { Issue.record("expected choose, got \(outcome)"); return }
        #expect(opts.count == 2)
        #expect(opts.first?.option.text == "latest clip") // ranked by probability
    }

    @Test func noneLeadingIsPlainPaste() async {
        var engine = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "none", conf: 0.9, probs: ["c1": 0.1, "c2": 0.1, "none": 0.8])))
        engine.confidenceThreshold = 0.6
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .pasteLatest(let r) = outcome, r == .nothingFits else {
            Issue.record("expected pasteLatest(.nothingFits), got \(outcome)"); return
        }
    }

    @Test func weakSingleLeaderStillPastes() async {
        // One option, weak but unopposed → take it rather than bare ⌘V.
        var engine = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "c2", conf: 0.5, probs: ["c1": 0.05, "c2": 0.55, "none": 0.4])))
        engine.confidenceThreshold = 0.6
        engine.decisivenessMargin = 0.6 // gap .5 < margin → weak, but unopposed
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .paste(let d) = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(d.text == "me@example.com")
    }

    @Test func interceptDecisiveLeaderStillPastes() async {
        var engine = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "c1", conf: 0.5, probs: ["c1": 0.76, "c2": 0.19, "none": 0.05], useLatest: 0.2)))
        engine.confidenceThreshold = 0.6
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .intercept)
        guard case .paste(let d) = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(d.clip.text == "latest clip")
    }

    @Test func interceptModeRespectsUseLatest() async {
        var engine = DecisionEngine(provider: StubProvider(
            response: pickResponse(pick: "c2", conf: 0.99,
                                   probs: ["c1": 0.1, "c2": 0.9], useLatest: 0.9)))
        engine.confidenceThreshold = 0.6
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .intercept)
        guard case .pasteLatest(let r) = outcome, r == .useLatest else {
            Issue.record("expected pasteLatest(.useLatest), got \(outcome)"); return
        }
    }

    @Test func interceptUndecidedOffersChooser() async {
        // User answer: popup when the latest doesn't fit — even on ⌘V.
        var engine = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "c1", conf: 0.4, probs: ["c1": 0.45, "c2": 0.45, "none": 0.1], useLatest: 0.1)))
        engine.confidenceThreshold = 0.6
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .intercept)
        guard case .choose(let opts) = outcome else { Issue.record("expected choose, got \(outcome)"); return }
        #expect(opts.count == 2)
    }

    @Test func providerErrorPastesLatestOrChoosesFallback() async {
        // No heuristics: a dead/unreachable provider degrades to a normal
        // paste — or, on the hotkey with ≥2 kind-matching options, a chooser
        // (history still helps when the model doesn't answer).
        let engine = DecisionEngine(provider: StubProvider(
            response: pickResponse(pick: "c1", conf: 1, probs: [:]),
            error: JevError.http(500, "boom")))
        let outcome = await engine.decide(context: makeContext(label: "Search box"),
                                          candidates: clips, mode: .hotkey)
        guard case .pasteLatest(let r) = outcome, r == .unreachable else {
            Issue.record("expected pasteLatest(.unreachable), got \(outcome)"); return
        }
    }

    @Test func providerErrorOnEmailFieldOffersMatchingOptions() async {
        let engine = DecisionEngine(provider: StubProvider(
            response: pickResponse(pick: "c1", conf: 1, probs: [:]),
            error: JevError.http(500, "boom")))
        let more = [Clip(text: "a@b.co", kind: .text), Clip(text: "c@d.io", kind: .text)]
        let outcome = await engine.decide(context: makeContext(label: "Email"),
                                          candidates: more + clips, mode: .hotkey)
        guard case .choose(let opts) = outcome else {
            Issue.record("expected chooser fallback, got \(outcome)"); return
        }
        #expect(opts.allSatisfy { $0.option.kind == .email })
    }

    @Test func noProviderPastesLatest() async {
        let engine = DecisionEngine(provider: nil)
        let outcome = await engine.decide(
            context: makeContext(label: "Email"), candidates: clips, mode: .hotkey)
        guard case .pasteLatest = outcome else { Issue.record("expected pasteLatest, got \(outcome)"); return }
    }

    @Test func feedbackDemotesClip() async {
        var engine = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "c2", conf: 0.95, probs: ["c1": 0.4, "c2": 0.6])))
        engine.confidenceThreshold = 0.5
        engine.decisivenessMargin = 0.1
        // c2 was undone before → multiplier 0.5 → .429 vs .571 → c1 wins.
        let feedback = [clips[1].id: 0.5]
        let outcome = await engine.decide(context: makeContext(), candidates: clips,
                                          mode: .hotkey, feedback: feedback)
        guard case .paste(let d) = outcome else { Issue.record("expected paste"); return }
        #expect(d.clip.text == "latest clip")
    }

    @Test func formFillModeNeverShowsHUD() async {
        // 3-way split: no option reaches 0.5 → stop the form.
        let three = clips + [Clip(text: "third thing", kind: .text)]
        var engine = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "c2", conf: 0.3, probs: ["c1": 0.4, "c2": 0.35, "c3": 0.25])))
        engine.lowConfidenceMode = .top3 // must be ignored in formFill
        let outcome = await engine.decide(context: makeContext(), candidates: three, mode: .formFill)
        guard case .pasteLatest = outcome else {
            Issue.record("low confidence mid-form should stop, got \(outcome)"); return
        }
    }

    @Test func formFillStopsOnNonFormField() async {
        var engine = DecisionEngine(provider: StubProvider(
            response: pickResponse(pick: "c2", conf: 0.99,
                                   probs: ["c1": 0.1, "c2": 0.9]).adding(formField: 0.1)))
        engine.confidenceThreshold = 0.6
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .formFill)
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
        let opts = OptionBuilder.options(from: clips)
        let ranked = DecisionEngine.ranked(from: resp, options: opts)
        #expect(ranked.count == 1)
        #expect(ranked.first?.option.text == "me@example.com")
    }

    @Test func remoteProviderGetsRedactedText() async {
        let redactor = StubRedactor()
        let provider = StubProvider(response: pickResponse(
            pick: "c2", conf: 0.95, probs: ["c2": 0.95]))
        var engine = DecisionEngine(provider: provider, redactor: redactor)
        engine.confidenceThreshold = 0.6
        _ = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)

        // The pick criteria must carry placeholders, never the raw clip text.
        guard let pick = provider.box.questions.first?["pick"]?.jsonValue["criteria"],
              case .object(let criteria) = pick else {
            Issue.record("no pick criteria captured"); return
        }
        #expect(criteria["c2"]?.string?.contains("[PII]") == true)
        #expect(criteria["c2"]?.string?.contains("me@example.com") == false)
        // The raw text stayed on-device — only the local redactor saw it.
        #expect(redactor.seen.contains { $0.contains("me@example.com") })
    }

    @Test func loopbackProviderSkipsRedaction() async {
        // Local models run on-device — scrubbing adds latency for zero gain.
        let redactor = StubRedactor()
        var endpoint = StubProvider(response: pickResponse(
            pick: "c2", conf: 0.95, probs: ["c2": 0.95, "none": 0.05]))
        endpoint.isRemote = false
        var engine = DecisionEngine(provider: endpoint, redactor: redactor)
        engine.confidenceThreshold = 0.6
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .paste = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(redactor.seen.isEmpty)
    }

    @Test func redactionFailureNeverLeaksToProvider() async {
        struct Fail: Error {}
        let redactor = StubRedactor()
        redactor.error = Fail()
        let provider = StubProvider(response: pickResponse(
            pick: "c2", conf: 0.95, probs: ["c2": 0.95]))
        var engine = DecisionEngine(provider: provider, redactor: redactor)
        engine.confidenceThreshold = 0.6
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
        let provider = StubProvider(response: pickResponse(
            pick: "c2", conf: 0.95, probs: ["c2": 0.95, "none": 0.05]))
        var engine = DecisionEngine(provider: provider, redactor: redactor)
        engine.confidenceThreshold = 0.6
        let outcome = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .paste(let d) = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(d.text == "me@example.com")
        #expect(!d.text.contains("[PII]"))
    }

    @Test func emptyCandidatesPastesLatest() async {
        let engine = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "c1", conf: 1, probs: [:])))
        let outcome = await engine.decide(context: makeContext(), candidates: [], mode: .hotkey)
        guard case .pasteLatest = outcome else { Issue.record("expected pasteLatest"); return }
    }

    @Test func spanOptionPastesOnlyTheSpan() async {
        // Contact-card clip: name + email copied together — the email option
        // pastes just the address, no transform question needed.
        let card = [Clip(text: "hridya agrawal hridayahoney@gmail.com", kind: .text),
                    Clip(text: "unrelated", kind: .text)]
        let provider = StubProvider(response: pickResponse(
            pick: "c1", conf: 0.95, probs: ["c1": 0.9, "c2": 0.05, "c3": 0.02, "none": 0.03]))
        var engine = DecisionEngine(provider: provider)
        engine.confidenceThreshold = 0.6
        let outcome = await engine.decide(context: makeContext(label: "To:"), candidates: card, mode: .hotkey)
        guard case .paste(let d) = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(d.text == "hridayahoney@gmail.com")
    }

    @Test func spanOptionsReachTheModelPastPreviewTruncation() async {
        // Preview truncates at 80 chars — a buried email still becomes its
        // own option via span extraction, criteria carries it verbatim.
        let long = Clip(text: String(repeating: "lorem ipsum dolor sit amet ", count: 4)
                        + "buried@example.com", kind: .text)
        let provider = StubProvider(response: pickResponse(
            pick: "c1", conf: 0.9, probs: ["c1": 0.9, "none": 0.1]))
        var engine = DecisionEngine(provider: provider)
        engine.confidenceThreshold = 0.6
        _ = await engine.decide(context: makeContext(), candidates: [long, clips[0]], mode: .hotkey)

        guard let pick = provider.box.questions.first?["pick"]?.jsonValue["criteria"],
              case .object(let criteria) = pick else {
            Issue.record("no pick criteria captured"); return
        }
        #expect(!long.preview.contains("buried@example.com")) // premise: it IS truncated
        #expect(criteria.values.contains { $0.string?.contains("buried@example.com") == true })
    }

    @Test func noneIsACriterion() async {
        let provider = StubProvider(response: pickResponse(
            pick: "c1", conf: 0.9, probs: ["c1": 0.9]))
        var engine = DecisionEngine(provider: provider)
        engine.confidenceThreshold = 0.6
        _ = await engine.decide(context: makeContext(), candidates: clips, mode: .hotkey)
        guard case .object(let criteria) = provider.box.questions
                .first?["pick"]?.jsonValue["criteria"] else {
            Issue.record(); return
        }
        #expect(criteria["none"] != nil)
    }

    @Test func stateCarriesNearbyAndExpects() async {
        var ctx = makeContext(label: "Email")
        ctx.nearby = "From: Priya Shah"
        ctx.webHost = "mail.example.com"
        let provider = StubProvider(response: pickResponse(
            pick: "c1", conf: 0.9, probs: ["c1": 0.9]))
        var engine = DecisionEngine(provider: provider)
        engine.confidenceThreshold = 0.6
        _ = await engine.decide(context: ctx, candidates: clips, mode: .hotkey)
        guard case .object(let state) = provider.box.states.first else {
            Issue.record("no state captured"); return
        }
        #expect(state["nearby"]?.string?.contains("Priya") == true)
        #expect(state["web_host"]?.string == "mail.example.com")
        guard case .object(let field) = state["field"] else { Issue.record(); return }
        #expect(field["expects"]?.string == "email")
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

struct DecisionPolicyTests {
    private func opt(_ t: String, _ p: Double) -> ScoredOption {
        ScoredOption(option: .init(id: "c", text: t, kind: .text,
                                   clip: Clip(text: t, kind: .text), snippet: t),
                     probability: p, confidence: p)
    }

    @Test func threeNearEqualEmailsChoose() {
        let ranked = [opt("a@x.com", 0.34), opt("b@x.com", 0.33), opt("c@x.com", 0.31)]
        let o = DecisionPolicy.outcome(ranked: ranked, noneProb: 0.02, useLatest: nil,
                                       isForm: false, mode: .hotkey, threshold: 0.6, margin: 0.25)
        guard case .choose(let opts) = outcome(o), opts.count == 3 else {
            Issue.record("expected choose(3), got \(o)"); return
        }
    }
    private func outcome(_ o: PasteOutcome) -> PasteOutcome { o }

    @Test func hotkeyTimeoutStyleFallbackUsesFieldKind() async {
        // Provider throws, field says "Phone" → the chooser shows phones only.
        let provider = StubProvider(response: pickResponse(
            pick: "c1", conf: 1, probs: [:]), error: JevError.http(500, "x"))
        let engine = DecisionEngine(provider: provider)
        var ctx = ContextSnapshot()
        ctx.field.label = "Phone"; ctx.field.role = "AXTextField"
        let clips = [Clip(text: "+1 415 555 0177", kind: .text),
                     Clip(text: "415-555-0101", kind: .text),
                     Clip(text: "me@example.com", kind: .text)]
        let outcome = await engine.decide(context: ctx, candidates: clips, mode: .hotkey)
        guard case .choose(let opts) = outcome else {
            Issue.record("expected chooser, got \(outcome)"); return
        }
        #expect(opts.count == 2)
        #expect(opts.allSatisfy { $0.option.kind == .phone })
    }
}

private extension JevResponse {
    func adding(formField p: Double) -> JevResponse {
        var r = self
        r.answers["form_field"] = .noul(probability: p)
        return r
    }
}
