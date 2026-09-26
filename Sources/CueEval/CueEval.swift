import CueKit
import Foundation

// CueEval — measures the real DecisionEngine against a labeled dataset.
//
//   swift run -c release CueEval --cases Evals/cases.jsonl \
//       --endpoint von=http://127.0.0.1:8766,von-1.0 \
//       --endpoint jev=https://api.typesafe.ai,jev-latest,env:TYPESAFE_API_KEY \
//       --repeats 3 --record Evals/results/raw.jsonl --json Evals/results/summary.json
//
// Scores the exact strings that would land in the field. `--record` writes
// the raw request+response per run so policies can be re-derived offline.

struct EndpointSpec {
    var name: String
    var endpoint: JevEndpoint
    var key: String
}

struct Args {
    var cases = "Evals/cases.jsonl"
    var endpoints: [EndpointSpec] = []
    var repeats = 3
    var timeout: TimeInterval = 30
    var record: String?
    var json: String?
    var onlyCategory: String?
    var onlyCase: String?
    /// Replays recorded answers (a --record file) instead of calling the
    /// endpoint: instant policy/threshold sweeps through the real engine.
    var replay: String?
    var threshold = 0.7
    var margin = 0.25

    static func parse() throws -> Args {
        var a = Args()
        var it = Array(CommandLine.arguments.dropFirst()).makeIterator()
        while let arg = it.next() {
            switch arg {
            case "--cases": a.cases = try need(&it, "--cases")
            case "--endpoint":
                for raw in try need(&it, "--endpoint").split(separator: ";") {
                    a.endpoints.append(try parseEndpoint(String(raw)))
                }
            case "--repeats": a.repeats = Int(try need(&it, "--repeats")) ?? 3
            case "--timeout": a.timeout = Double(try need(&it, "--timeout")) ?? 30
            case "--record": a.record = try need(&it, "--record")
            case "--json": a.json = try need(&it, "--json")
            case "--category": a.onlyCategory = try need(&it, "--category")
            case "--only": a.onlyCase = try need(&it, "--only")
            case "--replay": a.replay = try need(&it, "--replay")
            case "--threshold": a.threshold = Double(try need(&it, "--threshold")) ?? 0.7
            case "--margin": a.margin = Double(try need(&it, "--margin")) ?? 0.25
            default: throw Err("unknown arg \(arg)")
            }
        }
        if let r = a.replay, a.endpoints.isEmpty {
            a.endpoints = [EndpointSpec(name: "replay",
                                        endpoint: JevEndpoint.custom(base: "http://127.0.0.1:9", model: "replay")!,
                                        key: "")]
            _ = r
        }
        guard !a.endpoints.isEmpty else { throw Err("no --endpoint given") }
        return a
    }

    private static func need(_ it: inout IndexingIterator<[String]>,
                             _ name: String) throws -> String {
        guard let v = it.next() else { throw Err("\(name) needs a value") }
        return v
    }

    /// "name=base,model" or "name=base,model,env:VAR"
    private static func parseEndpoint(_ s: String) throws -> EndpointSpec {
        guard let eq = s.firstIndex(of: "=") else { throw Err("endpoint needs name=base,model") }
        let name = String(s[s.startIndex..<eq])
        let parts = s[s.index(after: eq)...].split(separator: ",").map(String.init)
        guard parts.count >= 2 else { throw Err("endpoint needs base,model") }
        guard let ep = JevEndpoint.custom(base: parts[0], model: parts[1]) else {
            throw Err("bad base URL \(parts[0])")
        }
        var key = ""
        if parts.count >= 3, parts[2].hasPrefix("env:") {
            key = ProcessInfo.processInfo.environment[String(parts[2].dropFirst(4))] ?? ""
        }
        return EndpointSpec(name: name, endpoint: ep, key: key)
    }
}

struct Err: Error, CustomStringConvertible { var description: String; init(_ s: String) { description = s } }

/// Provider wrapper that records each raw request/response for offline rescoring.
final class RecordingProvider: DecisionProvider, @unchecked Sendable {
    let inner: any DecisionProvider
    let sink: (String, JevResponse) -> Void
    var isRemote: Bool { inner.isRemote }
    var currentCaseID = ""

    init(_ inner: any DecisionProvider, sink: @escaping (String, JevResponse) -> Void) {
        self.inner = inner; self.sink = sink
    }
    func evaluate(state: JSONValue, questions: [String: Question]) async throws -> JevResponse {
        let r = try await inner.evaluate(state: state, questions: questions)
        sink(currentCaseID, r)
        return r
    }
}

/// Serves the first recorded response per case id (the --record format).
final class ReplayProvider: DecisionProvider, @unchecked Sendable {
    var isRemote: Bool { false }
    var currentCaseID = ""
    private var byCase: [String: JevResponse] = [:]

    init(path: String) throws {
        for line in try String(contentsOfFile: path, encoding: .utf8).split(whereSeparator: \.isNewline) {
            guard let o = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = o["case"] as? String, byCase[id] == nil,
                  let raw = o["answers"] as? [String: String] else { continue }
            byCase[id] = JevResponse(model: o["model"] as? String ?? "replay",
                                     answers: raw.compactMapValues(Self.parse))
        }
    }

    /// "choice:c2 conf=0.4 c1=0.1,c2=0.9" | "noul:0.3" | "score:3 conf=0.5"
    static func parse(_ s: String) -> Answer? {
        let parts = s.split(separator: " ", maxSplits: 2).map(String.init)
        guard let head = parts.first, let colon = head.firstIndex(of: ":") else { return nil }
        let kind = head[..<colon], val = String(head[head.index(after: colon)...])
        let conf = parts.count > 1 ? Double(parts[1].replacingOccurrences(of: "conf=", with: "")) ?? 0 : 0
        switch kind {
        case "noul": return Double(val).map { .noul(probability: $0) }
        case "choice":
            var probs: [String: Double] = [:]
            if parts.count > 2 {
                for kv in parts[2].split(separator: ",") {
                    let p = kv.split(separator: "=")
                    if p.count == 2, let v = Double(p[1]) { probs[String(p[0])] = v }
                }
            }
            return .choice(key: val, confidence: conf, probabilities: probs)
        case "score": return Double(val).map { .score(score: $0, confidence: conf, probabilities: [:]) }
        default: return nil
        }
    }

    func evaluate(state: JSONValue, questions: [String: Question]) async throws -> JevResponse {
        guard let r = byCase[currentCaseID] else { throw Err("no recording for \(currentCaseID)") }
        return r
    }
}

struct CaseResult: Sendable {
    var caseID: String
    var verdict: EvalVerdict
    var latencies: [Double]
    var outcomeKind: String
    var pasted: String
    /// Expected a single paste — a chooser here is friction, not safety.
    var unambiguous: Bool
}

func normalize(_ outcome: PasteOutcome) -> EvalNormalizedOutcome {
    switch outcome {
    case .paste(let d): return .init(kind: .paste, texts: [d.text])
    case .choose(let opts): return .init(kind: .choose, texts: opts.map { $0.option.text })
    case .pasteLatest: return .init(kind: .plain, texts: [])
    }
}

func loadCases(_ path: String) throws -> [EvalCase] {
    let data = try String(contentsOfFile: path, encoding: .utf8)
    let dec = JSONDecoder()
    return data.split(whereSeparator: \.isNewline).compactMap { line in
        line.isEmpty ? nil : try? dec.decode(EvalCase.self, from: Data(line.utf8))
    }
}

func run() async throws -> Int {
    let args = try Args.parse()
    var cases = try loadCases(args.cases)
    if let c = args.onlyCategory { cases = cases.filter { $0.category == c } }
    if let c = args.onlyCase { cases = cases.filter { $0.id == c } }
    guard !cases.isEmpty else { throw Err("no cases decoded from \(args.cases)") }

    var recordLines: [String] = []
    var summary: [String: [String: Any]] = [:]

    func pad(_ s: String, _ w: Int) -> String {
        s.count >= w ? String(s.prefix(w)) : s + String(repeating: " ", count: w - s.count)
    }
    print("\(pad("endpoint", 16)) \(pad("case", 34)) \(pad("verdict", 18)) \(pad("kind", 7)) \(pad("pasted", 32)) ms")
    print(String(repeating: "-", count: 118))

    for ep in args.endpoints {
        var results: [CaseResult] = []
        let replay = try args.replay.map { try ReplayProvider(path: $0) }
        let client: any DecisionProvider = replay
            ?? JevClient(endpoint: ep.endpoint, apiKey: ep.key, timeout: args.timeout)
        let recorder = RecordingProvider(client) { caseID, resp in
            let answers = resp.answers.mapValues { a -> String in
                switch a {
                case .choice(let k, let c, let p):
                    return "choice:\(k) conf=\(c) \(p.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ","))"
                case .noul(let p): return "noul:\(p)"
                case .score(let s, let c, _): return "score:\(s) conf=\(c)"
                }
            }
            if let d = try? JSONSerialization.data(withJSONObject: [
                "case": caseID, "model": resp.model, "answers": answers]),
               let line = String(data: d, encoding: .utf8) {
                recordLines.append(line)
            }
        }
        for c in cases {
            recorder.currentCaseID = c.id
            replay?.currentCaseID = c.id
            var latencies: [Double] = []
            var lastOutcome: EvalNormalizedOutcome?
            for rep in 0..<args.repeats {
                var engine = DecisionEngine(provider: recorder)
                engine.confidenceThreshold = args.threshold
                engine.decisivenessMargin = args.margin
                let t0 = ContinuousClock.now
                let outcome = await engine.decide(
                    context: c.contextSnapshot, candidates: c.clipList, mode: c.engineMode)
                let d = t0.duration(to: .now).components
                let ms = Double(d.seconds) * 1000 + Double(d.attoseconds) / 1e15
                if rep == 0 { lastOutcome = normalize(outcome) }
                latencies.append(ms)
            }
            let o = lastOutcome ?? .init(kind: .plain, texts: [])
            let latest = c.clipList.first?.text ?? ""
            let verdict = EvalScore.score(o, expect: c.expect, latestText: latest)
            results.append(CaseResult(caseID: c.id, verdict: verdict, latencies: latencies,
                                      outcomeKind: o.kind.rawValue,
                                      pasted: o.texts.first.map { String($0.prefix(30)) } ?? "",
                                      unambiguous: { if case .paste = c.expect { return true }; return false }()))
            let msAvg = latencies.reduce(0, +) / Double(latencies.count)
            print("\(pad(ep.name, 16)) \(pad(c.id, 34)) \(pad(verdict.rawValue, 18)) \(pad(o.kind.rawValue, 7)) \(pad(String((o.texts.first ?? "-").prefix(32)), 32)) \(Int(msAvg.rounded()))")
        }
        // Aggregate
        let n = Double(results.count)
        let byVerdict = Dictionary(grouping: results, by: \.verdict)
        let all = results.flatMap(\.latencies).sorted()
        let p = { (q: Double) in all.isEmpty ? 0 : all[min(all.count - 1, Int(q * Double(all.count)))] }
        let wrongs = byVerdict[.wrong]?.count ?? 0
        let exacts = byVerdict[.exact]?.count ?? 0
        let chooser = byVerdict[.resolvedByChooser]?.count ?? 0
        let lucky = byVerdict[.luckyGuess]?.count ?? 0
        let misses = byVerdict[.miss]?.count ?? 0
        let unamb = results.filter(\.unambiguous)
        let chooserUnamb = unamb.isEmpty ? 0
            : Double(unamb.filter { $0.outcomeKind == "choose" }.count) / Double(unamb.count) * 100
        summary[ep.name] = [
            "exact": exacts, "resolved_chooser": chooser, "lucky_guess": lucky,
            "miss": misses, "wrong": wrongs, "cases": results.count,
            "resolved_pct": (Double(exacts + chooser) / n * 100).rounded(),
            "wrong_pct": (Double(wrongs) / n * 100).rounded(),
            "p50_ms": p(0.5).rounded(), "p95_ms": p(0.95).rounded(),
            "chooser_on_unambiguous_pct": chooserUnamb.rounded(),
        ]
        print("\(pad(ep.name, 16)) \(pad("TOTAL", 34)) \(exacts)+\(chooser) ok, \(lucky) lucky, \(misses) miss, \(wrongs) wrong")
        print(String(repeating: "-", count: 118))
    }

    print("\n=== SUMMARY ===")
    for ep in args.endpoints {
        if let s = summary[ep.name] {
            print("\(ep.name): resolved \(s["resolved_pct"]!)%  wrong \(s["wrong_pct"]!)%  p50 \(s["p50_ms"]!)ms  p95 \(s["p95_ms"]!)ms  chooser-on-unambiguous \(s["chooser_on_unambiguous_pct"]!)%")
        }
    }

    if let path = args.record {
        try recordLines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        print("recorded \(recordLines.count) raw responses → \(path)")
    }
    if let path = args.json {
        let d = try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
        try d.write(to: URL(fileURLWithPath: path))
        print("summary → \(path)")
    }
    return 0
}

func log(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

@main
struct CueEvalMain {
    static func main() async throws {
        print("cueeval: starting"); fflush(stdout)
        exit(Int32(try await run()))
    }
}
