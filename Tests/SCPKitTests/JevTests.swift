import Foundation
import Testing
@testable import SCPKit

struct JevTests {
    @Test func parsesDocFixture() throws {
        // Shape taken from docs.typesafe.ai response example.
        let json = """
        {
          "model": "jev-1.13.0",
          "answers": {
            "topic":    { "type": "choice", "choice": "billing", "confidence": 1.0,
                          "probabilities": { "billing": 1.0, "bug": 0.0, "account": 0.0 } },
            "severity": { "type": "score", "score": 3.0, "confidence": 1.0,
                          "probabilities": { "0": 0.0, "3": 1.0 } },
            "escalate": { "type": "noul", "noul": 0.8 }
          },
          "usage": { "input_tokens": 434, "output_tokens": 75 }
        }
        """
        let root = JSONValue(any: try JSONSerialization.jsonObject(with: Data(json.utf8)))!
        let resp = try JevClient.parse(root)

        #expect(resp.model == "jev-1.13.0")
        #expect(resp.inputTokens == 434)

        guard case .choice(let key, let conf, let probs) = resp.answers["topic"] else {
            Issue.record("topic not a choice")
            return
        }
        #expect(key == "billing")
        #expect(conf == 1.0)
        #expect(probs["billing"] == 1.0)

        guard case .score(let s, _, _) = resp.answers["severity"] else {
            Issue.record("severity not a score")
            return
        }
        #expect(s == 3.0)

        guard case .noul(let p) = resp.answers["escalate"] else {
            Issue.record("escalate not a noul")
            return
        }
        #expect(p == 0.8)
    }

    @Test func questionEncoding() {
        let q = Question.choice(instructions: "pick one",
                                criteria: ["a": "first", "b": "second"]).jsonValue
        #expect(q["type"]?.string == "choice")
        #expect(q["instructions"]?.string == "pick one")
        #expect(q["criteria"]?["a"]?.string == "first")

        let n = Question.noul(instructions: "yes or no").jsonValue
        #expect(n["type"]?.string == "noul")
        #expect(n["criteria"] == nil)

        let s = Question.score(instructions: "rate", criteria: ["low", "high"]).jsonValue
        #expect(s["type"]?.string == "score")
    }

    @Test func endpoints() {
        #expect(JevEndpoint.direct(model: "jev-latest").url.absoluteString
            == "https://api.typesafe.ai/v1/systemone")
        #expect(JevEndpoint.gateway(model: "typesafe-ai/jev").url.absoluteString
            == "https://ai-gateway.vercel.sh/typesafe/v1/systemone")
    }

    @Test func malformedAnswerThrows() throws {
        let root = JSONValue(any: ["answers": ["x": ["type": "mystery"]]])!
        #expect(throws: JevError.self) { try JevClient.parse(root) }
    }

    @Test func httpErrorPropagates() async {
        let client = JevClient(
            endpoint: JevEndpoint(url: URL(string: "https://example.invalid/x")!, model: "jev-latest"),
            apiKey: "k",
            session: .shared
        )
        await #expect(throws: JevError.self) {
            try await client.evaluate(state: .string("s"), questions: [:])
        }
    }
}
