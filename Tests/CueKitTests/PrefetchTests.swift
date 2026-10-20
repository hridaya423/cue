import Foundation
import Testing
@testable import CueKit

/// Call-counting provider box; `delay` keeps a warm in flight long enough to
/// prove `outcome` awaited it rather than deciding again.
final class PrefetchBox: @unchecked Sendable {
    var calls = 0
    var delay: Duration = .zero
}

struct CountingProvider: DecisionProvider {
    var box: PrefetchBox
    var response: JevResponse
    func evaluate(state: JSONValue, questions: [String: Question]) async throws -> JevResponse {
        box.calls += 1
        if box.delay > .zero { try? await Task.sleep(for: box.delay) }
        return response
    }
}

struct FailFirstProvider: DecisionProvider {
    var box: PrefetchBox
    var response: JevResponse
    func evaluate(state: JSONValue, questions: [String: Question]) async throws -> JevResponse {
        box.calls += 1
        if box.calls == 1 { throw JevError.transport("refused") }
        return response
    }
}

@MainActor
struct PrefetchTests {
    private let clips = [
        Clip(text: "latest clip", kind: .text),
        Clip(text: "me@example.com", kind: .text),
        Clip(text: "second@example.com", kind: .text), // two addresses: the model is genuinely asked
    ]

    private func ctx(label: String = "Email", value: String = "") -> ContextSnapshot {
        var c = ContextSnapshot()
        c.appName = "Test"
        c.bundleID = "com.test.app"
        c.field.label = label
        c.field.role = "AXTextField"
        c.field.value = value
        return c
    }

    private func pick(_ key: String, probs: [String: Double]) -> JevResponse {
        JevResponse(model: "stub",
                    answers: ["pick": .choice(key: key, confidence: 0.9, probabilities: probs)])
    }

    /// Decisive older pick → .paste in intercept mode.
    private var decisive: JevResponse {
        pick("c2", probs: ["c1": 0.05, "c2": 0.9, "none": 0.05])
    }
    /// Split mass → .choose on a typed field with no matching options.
    private var split: JevResponse {
        pick("c1", probs: ["c1": 0.45, "c2": 0.45, "none": 0.1])
    }

    private func engine(_ provider: CountingProvider) -> DecisionEngine {
        var e = DecisionEngine(provider: provider)
        e.confidenceThreshold = 0.6
        return e
    }

    @Test func warmThenOutcomeIsOneCall() async {
        let stub = CountingProvider(box: PrefetchBox(), response: decisive)
        let prefetch = DecisionPrefetch()
        prefetch.warm(context: ctx(), candidates: clips, engine: engine(stub))
        let outcome = await prefetch.outcome(context: ctx(), candidates: clips,
                                             mode: .intercept, engine: engine(stub))
        #expect(stub.box.calls == 1)
        guard case .paste(let d) = outcome, d.text == "me@example.com" else {
            Issue.record("expected the warmed paste, got \(outcome)"); return
        }
    }

    @Test func outcomeWithoutWarmDecidesFresh() async {
        let stub = CountingProvider(box: PrefetchBox(), response: decisive)
        let prefetch = DecisionPrefetch()
        let outcome = await prefetch.outcome(context: ctx(), candidates: clips,
                                             mode: .intercept, engine: engine(stub))
        #expect(stub.box.calls == 1)
        guard case .paste = outcome else { Issue.record("expected paste, got \(outcome)"); return }
    }

    @Test func outcomeAwaitsInFlightWarm() async {
        let box = PrefetchBox()
        box.delay = .milliseconds(100)
        let stub = CountingProvider(box: box, response: decisive)
        let prefetch = DecisionPrefetch()
        prefetch.warm(context: ctx(), candidates: clips, engine: engine(stub))
        let outcome = await prefetch.outcome(context: ctx(), candidates: clips,
                                             mode: .intercept, engine: engine(stub))
        // A second decide would have been a second provider call.
        #expect(stub.box.calls == 1)
        guard case .paste = outcome else { Issue.record("expected paste, got \(outcome)"); return }
    }

    @Test func newClipStartsNewDecision() async {
        let stub = CountingProvider(box: PrefetchBox(), response: decisive)
        let prefetch = DecisionPrefetch()
        prefetch.warm(context: ctx(), candidates: clips, engine: engine(stub))
        _ = await prefetch.outcome(context: ctx(), candidates: clips,
                                   mode: .intercept, engine: engine(stub))
        let more = [Clip(text: "newest thing", kind: .text)] + clips
        prefetch.warm(context: ctx(), candidates: more, engine: engine(stub))
        _ = await prefetch.outcome(context: ctx(), candidates: more,
                                   mode: .intercept, engine: engine(stub))
        #expect(stub.box.calls == 2)
    }

    @Test func fieldLabelChangeStartsNewDecision() async {
        let stub = CountingProvider(box: PrefetchBox(), response: decisive)
        let prefetch = DecisionPrefetch()
        prefetch.warm(context: ctx(label: "Email"), candidates: clips, engine: engine(stub))
        _ = await prefetch.outcome(context: ctx(label: "Email"), candidates: clips,
                                   mode: .intercept, engine: engine(stub))
        prefetch.warm(context: ctx(label: "Phone"), candidates: clips, engine: engine(stub))
        _ = await prefetch.outcome(context: ctx(label: "Phone"), candidates: clips,
                                   mode: .intercept, engine: engine(stub))
        #expect(stub.box.calls == 2)
    }

    @Test func fieldValueChangeKeepsKey() async {
        let stub = CountingProvider(box: PrefetchBox(), response: decisive)
        let prefetch = DecisionPrefetch()
        prefetch.warm(context: ctx(value: "a"), candidates: clips, engine: engine(stub))
        _ = await prefetch.outcome(context: ctx(value: "b"), candidates: clips,
                                   mode: .intercept, engine: engine(stub))
        // Typing moved the value; the warm still serves and a same-key rewarm
        // is a no-op — still one provider call total.
        prefetch.warm(context: ctx(value: "c"), candidates: clips, engine: engine(stub))
        let outcome = await prefetch.outcome(context: ctx(value: "c"), candidates: clips,
                                             mode: .intercept, engine: engine(stub))
        #expect(stub.box.calls == 1)
        guard case .paste = outcome else { Issue.record("expected paste, got \(outcome)"); return }
    }

    @Test func oneAnswerServesCmdVAndTheHotkey() async {
        let stub = CountingProvider(box: PrefetchBox(), response: split)
        let prefetch = DecisionPrefetch()
        prefetch.warm(context: ctx(label: "Phone"), candidates: clips, engine: engine(stub))
        for mode in [DecisionEngine.Mode.intercept, .hotkey, .intercept] {
            let outcome = await prefetch.outcome(context: ctx(label: "Phone"), candidates: clips,
                                                 mode: mode, engine: engine(stub))
            guard case .choose = outcome else { Issue.record("\(mode): expected choose, got \(outcome)"); return }
        }
        #expect(stub.box.calls == 1)
    }

    @Test func pasteAndPlainOutcomesAreReused() async {
        let stub = CountingProvider(box: PrefetchBox(), response: decisive)
        let prefetch = DecisionPrefetch()
        prefetch.warm(context: ctx(), candidates: clips, engine: engine(stub))
        for _ in 0..<3 {
            let outcome = await prefetch.outcome(context: ctx(), candidates: clips,
                                                 mode: .intercept, engine: engine(stub))
            guard case .paste = outcome else { Issue.record("expected paste, got \(outcome)"); return }
        }
        #expect(stub.box.calls == 1)

        // Generic field: ⌘V takes the latest clip without using the warmed answer
        // (which the hotkey would use), and repeats stay plain.
        let stub2 = CountingProvider(box: PrefetchBox(), response: split)
        let prefetch2 = DecisionPrefetch()
        prefetch2.warm(context: ctx(label: "Message"), candidates: clips, engine: engine(stub2))
        for _ in 0..<2 {
            let outcome = await prefetch2.outcome(context: ctx(label: "Message"), candidates: clips,
                                                  mode: .intercept, engine: engine(stub2))
            guard case .pasteLatest = outcome else {
                Issue.record("expected pasteLatest, got \(outcome)"); return
            }
        }
        #expect(stub2.box.calls <= 1) // the warm may or may not have reached the provider yet
    }

    @Test func supersededWarmIsDropped() async {
        let box = PrefetchBox()
        box.delay = .milliseconds(150)
        let stub = CountingProvider(box: box, response: decisive)
        let prefetch = DecisionPrefetch()
        prefetch.warm(context: ctx(label: "Email"), candidates: clips, engine: engine(stub))
        // Focus moved before the first warm finished — it is superseded.
        prefetch.warm(context: ctx(label: "Phone"), candidates: clips, engine: engine(stub))
        let outcome = await prefetch.outcome(context: ctx(label: "Phone"), candidates: clips,
                                             mode: .intercept, engine: engine(stub))
        guard case .paste(let d) = outcome, d.text == "me@example.com" else {
            Issue.record("expected the Phone decision, got \(outcome)"); return
        }
        // The cancelled Email warm may have reached the provider before the
        // supersede landed; either way nothing serves its result.
        #expect(stub.box.calls <= 2)
    }

    @Test func clipAgingOutChangesKey() {
        let stale = Clip(text: "me@example.com", kind: .text, copiedAt: Date().addingTimeInterval(-3 * 3600))
        let fresh = Clip(text: "me@example.com", kind: .text)
        let newest = Clip(text: "latest clip", kind: .text)
        #expect(PrefetchKey(context: ctx(), candidates: [newest, fresh])
                != PrefetchKey(context: ctx(), candidates: [newest, stale]))
    }

    @Test func failedWarmIsNotCached() async {
        let box = PrefetchBox()
        let stub = FailFirstProvider(box: box, response: decisive)
        let prefetch = DecisionPrefetch()
        prefetch.warm(context: ctx(), candidates: clips, engine: DecisionEngine(provider: stub))
        await prefetch.settle()
        prefetch.warm(context: ctx(), candidates: clips, engine: DecisionEngine(provider: stub))
        await prefetch.settle()
        #expect(box.calls == 2)
    }
}
