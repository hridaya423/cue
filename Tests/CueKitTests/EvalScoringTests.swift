import Foundation
import Testing
@testable import CueKit

struct EvalScoringTests {
    func out(_ kind: EvalOutcomeKind, _ texts: [String] = []) -> EvalNormalizedOutcome {
        .init(kind: kind, texts: texts)
    }
    let latest = "latest clip text"

    @Test func pasteExpected() {
        #expect(EvalScore.score(out(.paste, ["a@b.com"]), expect: .paste("a@b.com"), latestText: latest) == .exact)
        #expect(EvalScore.score(out(.paste, ["x"]), expect: .paste("a@b.com"), latestText: latest) == .wrong)
        #expect(EvalScore.score(out(.choose, ["a@b.com", "c@d.com"]), expect: .paste("a@b.com"), latestText: latest) == .resolvedByChooser)
        #expect(EvalScore.score(out(.choose, ["nope"]), expect: .paste("a@b.com"), latestText: latest) == .wrong)
        #expect(EvalScore.score(out(.plain), expect: .paste("a@b.com"), latestText: latest) == .miss)
        // Latest clip IS the wanted text → plain paste is correct.
        #expect(EvalScore.score(out(.plain), expect: .paste("latest clip text"), latestText: latest) == .exact)
    }

    @Test func chooseExpected() {
        let set: EvalCase.Expectation = .choose(["a@b.com", "c@d.com"])
        #expect(EvalScore.score(out(.choose, ["c@d.com", "x"]), expect: set, latestText: latest) == .exact)
        #expect(EvalScore.score(out(.paste, ["c@d.com"]), expect: set, latestText: latest) == .luckyGuess)
        #expect(EvalScore.score(out(.paste, ["x"]), expect: set, latestText: latest) == .wrong)
        #expect(EvalScore.score(out(.choose, ["x", "y"]), expect: set, latestText: latest) == .wrong)
        #expect(EvalScore.score(out(.plain), expect: set, latestText: latest) == .miss)
    }

    @Test func plainExpected() {
        #expect(EvalScore.score(out(.plain), expect: .plain, latestText: latest) == .exact)
        #expect(EvalScore.score(out(.paste, ["latest clip text"]), expect: .plain, latestText: latest) == .exact)
        #expect(EvalScore.score(out(.paste, ["other"]), expect: .plain, latestText: latest) == .wrong)
        #expect(EvalScore.score(out(.choose, ["a"]), expect: .plain, latestText: latest) == .wrong)
    }

    @Test func caseDecodes() throws {
        let line = #"{"id":"x","category":"extract","mode":"intercept","context":{"app":"A","field":{"role":"AXTextField","label":"Email","placeholder":"","value":""}},"clips":[{"text":"t","app":"M","age_s":5}],"expect":{"choose":["a","b"]}}"#
        let c = try JSONDecoder().decode(EvalCase.self, from: Data(line.utf8))
        #expect(c.id == "x")
        #expect(c.engineMode == .intercept)
        #expect(c.clipList.count == 1)
        guard case .choose(let set) = c.expect else { Issue.record(); return }
        #expect(set == ["a", "b"])
        #expect(c.contextSnapshot.field.label == "Email")
    }

    @Test func datasetLoadsAndCoversCategories() throws {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Evals/cases.jsonl")
        var seen = Set<String>()
        var count = 0
        for line in try String(contentsOf: path).split(whereSeparator: \.isNewline) {
            let c = try JSONDecoder().decode(EvalCase.self, from: Data(line.utf8))
            seen.insert(c.category)
            count += 1
        }
        #expect(count >= 100)
        #expect(seen == ["extract", "multispan", "amb-signal", "amb-plain", "typed", "noisy", "intercept", "none"])
    }
}
