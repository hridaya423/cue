import Foundation
import Testing
@testable import CueKit

struct SpanExtractorTests {
    @Test func firstSpanOfEachKind() {
        #expect(SpanExtractor.emails(in: "hridya agrawal hridayahoney@gmail.com") == ["hridayahoney@gmail.com"])
        #expect(SpanExtractor.emails(in: "Jane Doe <jane@example.com>") == ["jane@example.com"])
        #expect(SpanExtractor.phones(in: "call Jane +1 (415) 555-0132 tomorrow").first == "+1 (415) 555-0132")
        #expect(SpanExtractor.urls(in: "see https://example.com/a?b=1 for details") == ["https://example.com/a?b=1"])
    }

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
        // A form's other labels sit in `nearby`: the field's own label must win over them.
        #expect(FieldKind.infer(label: "Phone", placeholder: "+1 555 000 0000", nearby: "Work email Phone Website") == .phone)
        #expect(FieldKind.infer(label: "Website", placeholder: "company.com", nearby: "Work email Phone Website") == .url)
        #expect(FieldKind.infer(label: "Hotel", placeholder: "", nearby: "") == .generic)
        #expect(FieldKind.infer(label: "Username", placeholder: "", nearby: "") == .generic)
        #expect(FieldKind.infer(label: "Tell us about yourself", placeholder: "", nearby: "") == .generic)
        #expect(FieldKind.infer(label: "E-mail", placeholder: "", nearby: "") == .email)
        #expect(FieldKind.infer(label: "To:", placeholder: "", nearby: "") == .email)
        #expect(FieldKind.infer(label: "Bcc:", placeholder: "", nearby: "") == .email)
        #expect(FieldKind.infer(label: "Add guests", placeholder: "", nearby: "") == .email)
        #expect(FieldKind.infer(label: "Add to cart", placeholder: "", nearby: "") == .generic)
        #expect(FieldKind.infer(label: "Message body", placeholder: "", nearby: "Mira Chen <mira@acme.example> wrote: what's your email?") == .generic)
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
                          form: Double? = nil) -> JevResponse {
    var answers: [String: Answer] = [
        "pick": .choice(key: pick, confidence: conf, probabilities: probs),
    ]
    if let form { answers["form"] = .noul(probability: form) }
    return JevResponse(model: "jev-latest", answers: answers, inputTokens: 100)
}

struct DecisionEngineTests {
    private func makeContext(label: String = "Email", window: String = "") -> ContextSnapshot {
        var c = ContextSnapshot()
        c.appName = "Safari"
        c.windowTitle = window
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
        let outcome = await engine.decide(context: makeContext(label: "Notes"), candidates: clips, mode: .hotkey)
        guard case .choose(let opts) = outcome else { Issue.record("expected choose, got \(outcome)"); return }
        #expect(opts.count == 2)
        #expect(opts.first?.option.text == "latest clip") // ranked by probability
    }

    @Test func hotkeyWithNothingFittingShowsTheListNotTheLatest() async {
        // The hotkey means "not the latest": an unsure model ranks history; Esc still plain-pastes.
        var engine = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "none", conf: 0.9, probs: ["c1": 0.1, "c2": 0.1, "none": 0.8])))
        engine.confidenceThreshold = 0.6
        let outcome = await engine.decide(context: makeContext(label: "Notes"), candidates: clips, mode: .hotkey)
        guard case .choose(let rows) = outcome, rows.count == 2 else {
            Issue.record("expected the list, got \(outcome)"); return
        }
    }

    @Test func typedFieldOutranksOverAbstainingNone() async {
        // Small models put most mass on `none` even when the Email field has
        // exactly one email option — that option pastes. Several emails →
        // chooser of just the emails.
        let engine = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "none", conf: 0.7, probs: ["c1": 0.1, "c2": 0.1, "none": 0.8])))
        let one = await engine.decide(context: makeContext(label: "Email"), candidates: clips, mode: .hotkey)
        guard case .paste(let d) = one, d.text == "me@example.com" else {
            Issue.record("expected paste of the only email, got \(one)"); return
        }
        let many = [Clip(text: "notes", kind: .text), Clip(text: "a@x.example.com", kind: .text),
                    Clip(text: "b@x.example.com", kind: .text)]
        let e2 = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "none", conf: 0.7, probs: ["c1": 0.1, "c2": 0.05, "c3": 0.05, "none": 0.8])))
        let two = await e2.decide(context: makeContext(label: "Email"), candidates: many, mode: .hotkey)
        guard case .choose(let opts) = two else { Issue.record("expected choose, got \(two)"); return }
        #expect(opts.map(\.option.text).sorted() == ["a@x.example.com", "b@x.example.com"])
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
            pick: "c1", conf: 0.5, probs: ["c1": 0.76, "c2": 0.19, "none": 0.05])))
        engine.confidenceThreshold = 0.6
        // A phone field with no phone among the options: the model's confident leader pastes.
        let outcome = await engine.decide(context: makeContext(label: "Phone"), candidates: clips, mode: .intercept)
        guard case .paste(let d) = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(d.clip.text == "latest clip")
    }

    @Test func interceptUndecidedOffersChooser() async {
        // User answer: popup when the latest doesn't fit — even on ⌘V.
        var engine = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "c1", conf: 0.4, probs: ["c1": 0.45, "c2": 0.45, "none": 0.1])))
        engine.confidenceThreshold = 0.6
        // Phone field: c1 doesn't fit, and no option is a phone.
        let outcome = await engine.decide(context: makeContext(label: "Phone"), candidates: clips, mode: .intercept)
        guard case .choose(let opts) = outcome else { Issue.record("expected choose, got \(outcome)"); return }
        #expect(opts.count == 2)
    }

    @Test func interceptLatestThatFitsSkipsTheModel() async {
        // ⌘V into a typed field whose latest clip fits: plain paste, no provider call — even if the
        // model would have pushed an older option.
        let stub = StubProvider(response: pickResponse(
            pick: "c2", conf: 0.99, probs: ["c1": 0.01, "c2": 0.99]))
        let engine = DecisionEngine(provider: stub)
        let emailFirst = [Clip(text: "dana@acme.example.com", kind: .text),
                          Clip(text: "me@example.com", kind: .text)]
        for (label, cands) in [("Email", emailFirst), ("Search", clips), ("", clips)] {
            let outcome = await engine.decide(context: makeContext(label: label),
                                              candidates: cands, mode: .intercept)
            guard case .pasteLatest(.useLatest) = outcome else {
                Issue.record("\(label): expected plain paste, got \(outcome)"); continue
            }
        }
        #expect(stub.box.calls == 0)
        #expect(FieldKind.email.acceptsVerbatim(" a@b.example.com "))
        #expect(!FieldKind.email.acceptsVerbatim("mail a@b.example.com"))
        #expect(FieldKind.email.acceptsVerbatim("a@b.example.com, c@d.example.org; e@f.example.net"))
        #expect(!FieldKind.name.acceptsVerbatim("a@b.example.com"))
        #expect(FieldKind.url.acceptsVerbatim("https://example.com/x"))
    }

    @Test func providerErrorPastesLatestOrChoosesFallback() async {
        // A dead provider: ⌘V pastes the latest like Cue isn't there; the hotkey, pressed because the
        // latest isn't wanted, offers recent history instead of pasting it anyway.
        let engine = DecisionEngine(provider: StubProvider(
            response: pickResponse(pick: "c1", conf: 1, probs: [:]),
            error: JevError.http(500, "boom")))
        let hotkey = await engine.decide(context: makeContext(label: "Search box"),
                                         candidates: clips, mode: .hotkey)
        guard case .choose(let rows) = hotkey, rows.first?.option.clip.id == clips.first?.id else {
            Issue.record("expected a recent-history chooser, got \(hotkey)"); return
        }
        let email = Clip(text: "a@b.example.com", kind: .text)
        let cmdV = await engine.decide(context: makeContext(label: "Phone"),
                                       candidates: [email] + clips, mode: .intercept)
        guard case .pasteLatest(let r) = cmdV, r == .unreachable else {
            Issue.record("expected pasteLatest(.unreachable), got \(cmdV)"); return
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

    @Test func commandVInEmailFieldTakesTheClipboardsAddress() async {
        let history = [Clip(text: "Reach Sam at sam.okafor@northwind.io or +1 415 555 0142 about the contract.", kind: .text),
                       Clip(text: "weiuhfhuew hridayahoney@gmail.com", kind: .text)]
        let outcome = await DecisionEngine(provider: nil).decide(
            context: makeContext(label: "To"), candidates: history, mode: .intercept)
        guard case .paste(let d) = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        #expect(d.text == "sam.okafor@northwind.io")
    }

    @Test func noProviderPastesLatest() async {
        let engine = DecisionEngine(provider: nil)
        let outcome = await engine.decide(
            context: makeContext(label: "Notes"), candidates: clips, mode: .hotkey)
        guard case .pasteLatest = outcome else { Issue.record("expected pasteLatest, got \(outcome)"); return }
    }

    @Test func formFillModeNeverShowsHUD() async {
        // 3-way split: no option reaches 0.5 → stop the form.
        let three = clips + [Clip(text: "third thing", kind: .text)]
        var engine = DecisionEngine(provider: StubProvider(response: pickResponse(
            pick: "c2", conf: 0.3, probs: ["c1": 0.4, "c2": 0.35, "c3": 0.25])))
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
        _ = await engine.decide(context: makeContext(label: "Notes"), candidates: clips, mode: .hotkey)

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
        let outcome = await engine.decide(context: makeContext(label: "Notes"), candidates: clips, mode: .hotkey)
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
        _ = await engine.decide(context: makeContext(label: "Notes"), candidates: [long, clips[0]], mode: .hotkey)

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
        _ = await engine.decide(context: makeContext(label: "Notes"), candidates: clips, mode: .hotkey)
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
        // Two addresses, so the model is genuinely asked (one would answer itself).
        _ = await engine.decide(context: ctx, candidates: clips + [Clip(text: "second@example.com", kind: .text)],
                                mode: .hotkey)
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
        let outcome = await engine.decide(context: makeContext(label: "Notes"), candidates: clips, mode: .hotkey)
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
        let o = DecisionPolicy.outcome(ranked: ranked, noneProb: 0.02,
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

struct ContextSignalTests {
    func opts(_ texts: [String]) -> [PasteOption] {
        OptionBuilder.options(from: texts.map { Clip(text: $0, kind: .text) })
    }

    @Test func uniqueNameMatchWins() {
        let o = opts(["priya.shah@acme.example.com", "me@gmail.example.com", "noreply@shop.example.io"])
        let p = ContextSignal.uniquePick(o, label: "To:", window: "Re: Q3 roadmap — Priya Shah",
                                         nearby: "From: Priya Shah")
        #expect(p?.text == "priya.shah@acme.example.com")
    }

    @Test func sharedEvidenceIsAmbiguity() {
        let o = opts(["zoe.lin@gmail.example.com", "z.lin@acme.example.com"])
        #expect(ContextSignal.uniquePick(o, label: "To:", window: "Fwd: party pics", nearby: "From: Zoe Lin") == nil)
    }

    @Test func domainIsNotEvidence() {
        // Coworkers share a domain — "Acme" must not single one out.
        let o = opts(["me@gmail.example.com", "alex.rivera@acme.example.com", "dana@acme.example.com"])
        #expect(ContextSignal.uniquePick(o, label: "Work email", window: "Acme Corp", nearby: "") == nil)
    }

    @Test func labelWordsBeforeASpanCount() {
        let o = opts(["Send to finance@acme.example.com, cc legal@acme.example.com today"])
        let p = ContextSignal.uniquePick(o, label: "Cc:", window: "Invoice follow-up", nearby: "")
        #expect(p?.text == "legal@acme.example.com")
    }

    @Test func signalOrdersTheChooserButNeverPastes() {
        let o = opts(["a@x.example.com", "b@x.example.com"])
        let ranked = o.map { ScoredOption(option: $0, probability: 0.4, confidence: 0.2) }
        let out = DecisionPolicy.outcome(ranked: ranked, noneProb: 0.2, isForm: false,
                                         mode: .hotkey, threshold: 0.7, margin: 0.25,
                                         expects: .email, signal: o[1].id)
        guard case .choose(let c) = out else { Issue.record("expected choose, got \(out)"); return }
        #expect(c.first?.option.text == "b@x.example.com")
    }

    @Test func signalAgainstADecisiveLeaderAsks() {
        // ms-07: the model is sure of finance@, the Cc label points at legal@ → chooser, legal first.
        let o = opts(["Send to finance@acme.example.com, cc legal@acme.example.com today"])
        let ranked = [ScoredOption(option: o[0], probability: 0.9, confidence: 0.8),
                      ScoredOption(option: o[1], probability: 0.05, confidence: 0.8)]
        let out = DecisionPolicy.outcome(ranked: ranked, noneProb: 0.05, isForm: false,
                                         mode: .intercept, threshold: 0.7, margin: 0.25,
                                         expects: .email, signal: o[1].id)
        guard case .choose(let c) = out else { Issue.record("expected choose, got \(out)"); return }
        #expect(c.first?.option.text == "legal@acme.example.com")
    }
}

struct UserReportTests {
    @Test func anEmailFieldTakesTheAddressNotTheSentenceAroundIt() {
        let clip = Clip(text: "weiuhfhuew hridayahoney@gmail.com", kind: .text)
        let opts = OptionBuilder.options(from: [clip])
        let whole = opts.first { $0.kind == .text }!, email = opts.first { $0.kind == .email }!
        // The model is sure of the whole clip; the To field still gets the address.
        let ranked = [ScoredOption(option: whole, probability: 0.9, confidence: 0.9),
                      ScoredOption(option: email, probability: 0.08, confidence: 0.9)]
        for mode in [DecisionEngine.Mode.intercept, .hotkey] {
            let out = DecisionPolicy.outcome(ranked: ranked, noneProb: 0.02, isForm: false, mode: mode,
                                             threshold: 0.7, margin: 0.25, expects: .email)
            guard case .paste(let d) = out, d.text == "hridayahoney@gmail.com" else {
                Issue.record("\(mode): expected the address, got \(out)"); return
            }
        }
    }

    @Test func clipsFromDaysAgoAreNotOffered() {
        let old = Clip(text: "SEEDED-CLIP-1421", kind: .text, copiedAt: Date().addingTimeInterval(-18 * 86400))
        let pinnedOld = Clip(text: "my address", kind: .text, copiedAt: Date().addingTimeInterval(-30 * 86400), pinned: true)
        let fresh = Clip(text: "today", kind: .text)
        let texts = OptionBuilder.options(from: [fresh, old, pinnedOld]).map(\.text)
        #expect(texts == ["today", "my address"])
        // The latest clip is always offered, however old; typing in the chooser still finds the rest.
        #expect(OptionBuilder.options(from: [old]).map(\.text) == ["SEEDED-CLIP-1421"])
        #expect(ChooserRows.rows(ranked: [], history: [fresh, old], query: "SEEDED").count == 1)
    }
}

struct TypedFieldWithoutModelTests {
    @Test func oneAddressInAnEmailFieldPastesWithNoModel() async {
        let clip = Clip(text: "weiuhfhuew hridayahoney@gmail.com", kind: .text)
        var ctx = ContextSnapshot(); ctx.appName = "Helium"; ctx.field.role = "AXComboBox"
        ctx.field.label = "To recipients"
        // No provider at all, and a dead one: the address still lands, in both triggers.
        for engine in [DecisionEngine(provider: nil),
                       DecisionEngine(provider: StubProvider(response: pickResponse(pick: "c1", conf: 1, probs: [:]),
                                                             error: JevError.http(500, "down")))] {
            for mode in [DecisionEngine.Mode.intercept, .hotkey] {
                let out = await engine.decide(context: ctx, candidates: [clip], mode: mode)
                guard case .paste(let d) = out, d.text == "hridayahoney@gmail.com" else {
                    Issue.record("\(mode): expected the address, got \(out)"); return
                }
            }
        }
    }
}

struct PageEchoTests {
    @Test func aClipRestatingThePageTitleIsNotAutoPasted() {
        let branch = Clip(text: "kofi/hal-482-duplicate-ledger-entries-on-retry", kind: .text)
        let opts = OptionBuilder.options(from: [branch, Clip(text: "priya.shah@acme.example.com", kind: .text)])
        let title = "HAL-482 Duplicate ledger entries on retry - Halyard - Google Chrome"
        #expect(ContextSignal.echoes(opts[0], window: title))
        // An address naming the person in the title is evidence, not an echo.
        #expect(!ContextSignal.echoes(opts[1], window: "Re: intro - Priya Shah - Gmail"))
        let ranked = [ScoredOption(option: opts[0], probability: 0.9, confidence: 0.9),
                      ScoredOption(option: opts[1], probability: 0.05, confidence: 0.9)]
        let out = DecisionPolicy.outcome(ranked: ranked, noneProb: 0.05, isForm: false, mode: .hotkey,
                                         threshold: 0.7, margin: 0.25, leaderEchoesPage: true)
        guard case .choose = out else { Issue.record("expected the chooser, got \(out)"); return }
    }
}

struct ChooserRowsTests {
    @Test func typingReachesClipsTheModelNeverRanked() {
        let history = (0..<40).map { Clip(text: "note \($0)", kind: .text) }
            + [Clip(text: "PR is up: https://github.com/acme/ledger/pull/1287 please review", kind: .text)]
        let ranked = OptionBuilder.options(from: Array(history.prefix(3)))
            .map { ScoredOption(option: $0, probability: 0.3, confidence: 0.3) }
        #expect(ChooserRows.rows(ranked: ranked, history: history, query: "").count == 3)
        let hits = ChooserRows.rows(ranked: ranked, history: history, query: "pull")
        #expect(hits.first?.option.text == "https://github.com/acme/ledger/pull/1287")
        #expect(hits.count == 2) // the URL span, then the message it came from
        // A span found only through its clip's text ranks after the clip that has the word itself.
        let curl = Clip(text: #"curl -X POST http://localhost:8080/v1/transfers -d '{"from":"acct_1042"}'"#, kind: .text)
        let rows = ChooserRows.rows(ranked: [], history: [curl], query: "curl")
        #expect(rows.first?.option.text == curl.text)
    }

    @Test func currentClipboardClosesTheList() {
        let history = (0..<12).map { Clip(text: "note \($0)", kind: .text) }
        let ranked = OptionBuilder.options(from: Array(history.dropFirst()))
            .map { ScoredOption(option: $0, probability: 0.1, confidence: 0.1) }
        let rows = ChooserRows.rows(ranked: Array(ranked.prefix(3)), history: history, query: "")
        #expect(rows.map(\.option.text) == ["note 1", "note 2", "note 3", "note 0"])
        let full = ChooserRows.rows(ranked: Array(ranked.prefix(9)), history: history, query: "")
        #expect(full.count == ChooserRows.visible)
        #expect(full.last?.option.text == "note 0")
    }
}

struct CodeSpanTests {
    @Test func liftsTokensPeopleCopyOutOfALine() {
        let spans = { (t: String) in SpanExtractor.spansWithContext(in: t).filter { $0.kind == .code }.map(\.text) }
        #expect(spans("e41b7d9 ledger: return original entry on duplicate") == ["e41b7d9"])
        #expect(spans("request failed (req_8f21c0d3a5) after 3 retries") == ["req_8f21c0d3a5"])
        #expect(spans(#"violates unique constraint "ledger_entries_idempotency_key_idx""#) == ["ledger_entries_idempotency_key_idx"])
        #expect(spans("Approved: base $185,000, 0.1% equity") == ["185,000"])
        // Long digit runs become rows (the phone detector may claim a 10-digit one first).
        let wire = SpanExtractor.spansWithContext(in: "Bank: Northgate\nRouting: 121000358\nAccount: 0001234567").map(\.text)
        #expect(wire.contains("121000358") && wire.contains { $0.filter(\.isNumber) == "0001234567" })
        // A JSON blob gives its values, not its keys or the separators between strings.
        #expect(spans(#"{"id":"txn_01JBX4M7Q2N8","status":"completed","amount_cents":12500,"currency":"USD"}"#) == ["txn_01JBX4M7Q2N8", "completed"])
        #expect(spans("key 7f2c9a10-2b1e-4c55-9d0e-a1b2c3d4e5f6 and see https://x.example.com/abc1234def").isEmpty)
    }
}

struct CaretNamingTests {
    @Test func wordsBeforeTheCaretBringBackAClipTheCapDropped() {
        let sentry = Clip(text: "https://halyard.sentry.io/issues/4812207311/", kind: .text)
        let newer = (0..<25).map { Clip(text: "note \($0) about the ledger", kind: .text) }
        let history = newer + [sentry]
        #expect(!OptionBuilder.options(from: history).contains { $0.clip.id == sentry.id })
        let named = OptionBuilder.options(from: history, recent: 30, naming: ["sentry"])
        #expect(named.contains { $0.clip.id == sentry.id })
        #expect(named.prefix(OptionBuilder.maxOptions).allSatisfy { $0.clip.id != sentry.id }) // appended, ids stable
    }
}

struct TimeoutTests {
    @Test func returnsAtTheDeadlineEvenIfWorkIgnoresCancellation() async {
        let slow = Task { try? await Task.sleep(for: .seconds(3)); return 1 }
        let start = ContinuousClock.now
        await #expect(throws: CancellationError.self) {
            try await DecisionEngine.withTimeout(0.2) { await slow.value }
        }
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func returnsTheValueWhenWorkIsFast() async throws {
        #expect(try await DecisionEngine.withTimeout(1) { 7 } == 7)
    }
}
