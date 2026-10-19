import AppKit
import ApplicationServices
import CueKit
import Foundation

// CueDay — replays a persona's day of copies and pastes through the real
// DecisionEngine against surfaces hosted in-process, and compares against a
// computed KLM baseline (the "bar"). Never touches the user's focus, mouse,
// keyboard, or system clipboard.
//
//   swift run -c release CueDay --days Evals/days \
//       --endpoint kev=http://127.0.0.1:8009,kev-latest --tag kev
//       [--mode hotkey] [--record raw.jsonl] [--replay raw.jsonl]
//       [--export-cases cases.jsonl] [--persona nadia]

struct Args {
    var days = "Evals/days"
    var endpoints: [EndpointSpec] = []
    var tag = ""
    var persona: String?
    var mode = "intercept"
    var record: String?
    var replay: String?
    var exportCases: String?
    var results = ""
    var timeout: TimeInterval = 10
    var threshold = 0.7
    var margin = 0.25
    var dumpAX = false
    /// Focus-to-⌘V gap the decision warms in (0 = decide on ⌘V, no precompute).
    var gapMS = 300
    /// "aware": a persona who knows the latest clip isn't what they want presses the smart-paste
    /// hotkey (as the bar's persona opens Spotlight); "cmdv": always ⌘V.
    var intent = "aware"

    var engineMode: DecisionEngine.Mode { mode == "intercept" ? .intercept : .hotkey }

    static func parse() throws -> Args {
        var a = Args()
        var it = Array(CommandLine.arguments.dropFirst()).makeIterator()
        func need(_ name: String) throws -> String {
            guard let v = it.next() else { throw DayError("\(name) needs a value") }
            return v
        }
        while let arg = it.next() {
            switch arg {
            case "--days": a.days = try need(arg)
            case "--endpoint":
                for raw in try need(arg).split(separator: ";") {
                    a.endpoints.append(try EndpointSpec.parse(String(raw)))
                }
            case "--tag": a.tag = try need(arg)
            case "--persona": a.persona = try need(arg)
            case "--mode":
                a.mode = try need(arg)
                guard ["intercept", "hotkey"].contains(a.mode) else {
                    throw DayError("--mode intercept|hotkey")
                }
            case "--record": a.record = try need(arg)
            case "--replay": a.replay = try need(arg)
            case "--export-cases": a.exportCases = try need(arg)
            case "--results": a.results = try need(arg)
            case "--timeout": a.timeout = Double(try need(arg)) ?? 10
            case "--threshold": a.threshold = Double(try need(arg)) ?? 0.7
            case "--margin": a.margin = Double(try need(arg)) ?? 0.25
            case "--dump-ax": a.dumpAX = true
            case "--gap-ms": a.gapMS = Int(try need(arg)) ?? 300
            case "--intent": a.intent = try need(arg)
            default: throw DayError("unknown arg \(arg)")
            }
        }
        if a.replay != nil, a.endpoints.isEmpty {
            a.endpoints = [EndpointSpec(name: "replay",
                endpoint: JevEndpoint.custom(base: "http://127.0.0.1:9", model: "replay")!)]
        }
        guard !a.endpoints.isEmpty else { throw DayError("no --endpoint given") }
        if a.tag.isEmpty { a.tag = a.endpoints[0].name }
        if a.results.isEmpty { a.results = "\(a.days)/results/\(a.tag)" }
        return a
    }
}

func log(_ s: String) {
    FileHandle.standardError.write(Data((s + "\n").utf8))
}

func jsonLine(_ obj: [String: Any]) -> String {
    guard let d = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
          let s = String(data: d, encoding: .utf8) else { return "{}" }
    return s
}

/// Running feedback stats, mirroring FeedbackTracker: contextKey → clipID →
/// net (+kept / −undone). The multiplier formula matches `multipliers(for:)`.
struct DayFeedback {
    var stats: [String: [String: Int]] = [:]

    func multipliers(for ctx: ContextSnapshot) -> [String: Double] {
        let key = FeedbackTracker.contextKey(bundleID: ctx.bundleID, fieldLabel: ctx.field.label)
        return stats[key, default: [:]].mapValues { min(1.5, max(0.1, 1 + 0.25 * Double($0))) }
    }

    mutating func record(clipID: String, ctx: ContextSnapshot, undone: Bool) {
        let key = FeedbackTracker.contextKey(bundleID: ctx.bundleID, fieldLabel: ctx.field.label)
        stats[key, default: [:]][clipID, default: 0] += undone ? -1 : 1
    }
}

struct StepAgg {
    var steps = 0
    var cueCorrect = 0
    var barCorrect = 0
    var wrongPastes = 0
    var misses = 0
    var singleWants = 0
    var chooserOnSingle = 0
    var better = 0
    var tied = 0
    var worse = 0
    var cueS = 0.0
    var barS = 0.0
    var latencies: [Double] = []

    func summary() -> [String: Any] {
        let n = Double(max(1, steps))
        let sorted = latencies.sorted()
        let p = { (q: Double) in sorted.isEmpty ? 0.0 : sorted[min(sorted.count - 1, Int(q * Double(sorted.count)))] }
        return [
            "steps": steps,
            "cue_correct_pct": (Double(cueCorrect) / n * 100).rounded(),
            "bar_correct_pct": (Double(barCorrect) / n * 100).rounded(),
            "wrong_pastes": wrongPastes,
            "wrong_pct": (Double(wrongPastes) / n * 100).rounded(),
            "misses": misses,
            "chooser_rate_single_pct": singleWants == 0 ? 0
                : (Double(chooserOnSingle) / Double(singleWants) * 100).rounded(),
            "p50_decision_ms": p(0.5).rounded(), "p95_decision_ms": p(0.95).rounded(),
            "cue_seconds": (cueS * 100).rounded() / 100, "bar_seconds": (barS * 100).rounded() / 100,
            "cue_better": better, "tied": tied, "cue_worse": worse,
        ]
    }
}

@MainActor
func runDay(_ args: Args) async throws -> Int {
    let daysURL = URL(fileURLWithPath: args.days, isDirectory: true)
    let specs = DayTrace.surfaces(
        try String(contentsOf: daysURL.appendingPathComponent("surfaces.json"), encoding: .utf8))
    guard !specs.isEmpty else { throw DayError("no surfaces in \(args.days)/surfaces.json") }

    // One private pasteboard for every simulated paste — the general
    // pasteboard is never read or written.
    let pb = NSPasteboard(name: NSPasteboard.Name("dev.cueday.\(UUID().uuidString)"))
    var hosts: [String: DaySurfaceHost] = [:]
    for s in specs {
        hosts[s.id] = DaySurfaceHost(spec: s, pagesDir: daysURL.appendingPathComponent("pages"),
                                     pasteboard: pb)
    }
    // Suspension lets the main runloop turn so AppKit registers the
    // ordered-in windows with AX.
    try await Task.sleep(for: .milliseconds(300))
    for h in hosts.values { await h.waitReady() }

    if args.dumpAX {
        for h in hosts.values { await h.dumpAX() }
        return 0
    }

    let specByID = Dictionary(uniqueKeysWithValues: specs.map { ($0.id, $0) })
    let personaFiles = try FileManager.default.contentsOfDirectory(atPath: daysURL.path)
        .filter { $0.hasSuffix(".jsonl") }
        .map { $0 as NSString }
        .map { (path: $0 as String, name: $0.deletingPathExtension) }
        .filter { args.persona == nil || $0.name == args.persona }
        .sorted { $0.name < $1.name }
    guard !personaFiles.isEmpty else { throw DayError("no persona .jsonl in \(args.days)") }

    var recordLines: [String] = []
    var exportLines: [String] = []
    var summaryAll: [String: Any] = [:]

    try FileManager.default.createDirectory(atPath: args.results, withIntermediateDirectories: true)

    for ep in args.endpoints {
        let replay = try args.replay.map { try ReplayProvider(path: $0) }
        let client: any DecisionProvider = replay
            ?? JevClient(endpoint: ep.endpoint, apiKey: ep.key, timeout: args.timeout)
        let recorder = RecordingProvider(client) { caseID, resp in
            let answers = resp.answers.mapValues(ReplayProvider.describe)
            recordLines.append(jsonLine(["case": caseID, "model": resp.model, "answers": answers]))
        }

        var total = StepAgg()
        for file in personaFiles {
            let events = DayTrace.parse(
                try String(contentsOf: daysURL.appendingPathComponent(file.path), encoding: .utf8))
            // Recordings/case exports dropped into the days dir aren't
            // persona traces — zero parseable events means skip it.
            if events.isEmpty {
                log("\(file.name): no trace events — skipped")
                continue
            }
            var history: [(clip: Clip, t: Double)] = []
            var feedback = DayFeedback()
            var agg = StepAgg()
            var lines: [String] = []
            var step = 0

            for ev in events {
                switch ev {
                case .copy(let t, let text, let from):
                    guard let s = specByID[from] else {
                        log("\(file.name): copy from unknown surface \(from) — skipped")
                        continue
                    }
                    let clip = Clip(text: text, kind: Clip.classify(text),
                                    sourceApp: s.app, sourceBundleID: s.bundle)
                    history.removeAll { $0.clip.id == clip.id }
                    history.insert((clip, t), at: 0)

                case .paste(let t, let into, let before, let want, let why):
                    step += 1
                    let line = await pasteStep(
                        args: args, caseID: "day-\(file.name)-\(String(format: "%03d", step))",
                        persona: file.name, step: step, t: t, into: into, before: before,
                        want: want, why: why,
                        history: history, feedback: &feedback, hosts: hosts,
                        specByID: specByID, recorder: recorder, agg: &agg)
                    lines.append(line.line)
                    if let c = line.exportCase { exportLines.append(jsonLine(c)) }

                case .secure(let t, let into):
                    step += 1
                    let line = await secureStep(
                        step: step, t: t, into: into,
                        history: history, hosts: hosts, specByID: specByID, agg: &agg)
                    lines.append(line)
                }
            }

            let out = URL(fileURLWithPath: args.results).appendingPathComponent("\(file.name).jsonl")
            try lines.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
            summaryAll[file.name] = agg.summary()
            total.steps += agg.steps; total.cueCorrect += agg.cueCorrect
            total.barCorrect += agg.barCorrect; total.wrongPastes += agg.wrongPastes; total.misses += agg.misses
            total.singleWants += agg.singleWants; total.chooserOnSingle += agg.chooserOnSingle
            total.better += agg.better; total.tied += agg.tied; total.worse += agg.worse
            total.cueS += agg.cueS; total.barS += agg.barS
            total.latencies += agg.latencies
            log("\(ep.name) \(file.name): \(agg.steps) steps, cue \(agg.cueCorrect) ok, " +
                "\(agg.wrongPastes) wrong, \(agg.misses) missed, cue \(agg.cueS)s vs bar \(agg.barS)s")
        }
        summaryAll["total"] = total.summary()
    }

    let summaryData = try JSONSerialization.data(
        withJSONObject: ["tag": args.tag, "mode": args.mode,
                         "endpoints": args.endpoints.map(\.name), "personas": summaryAll],
        options: [.prettyPrinted, .sortedKeys])
    try summaryData.write(to: URL(fileURLWithPath: args.results).appendingPathComponent("summary.json"))
    log("summary → \(args.results)/summary.json")

    if let path = args.record {
        try recordLines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        log("recorded \(recordLines.count) raw responses → \(path)")
    }
    if let path = args.exportCases {
        try exportLines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
        log("exported \(exportLines.count) cases → \(path)")
    }
    return 0
}

struct StepLine {
    var line: String
    var exportCase: [String: Any]?
}

/// One paste event: focus → capture → decide → execute → persona reacts.
@MainActor
func pasteStep(args: Args, caseID: String, persona: String, step: Int, t: Double, into: String,
               before: String, want: DayWant, why: String,
               history: [(clip: Clip, t: Double)], feedback: inout DayFeedback,
               hosts: [String: DaySurfaceHost], specByID: [String: DaySurface],
               recorder: RecordingProvider, agg: inout StepAgg) async -> StepLine {
    let (sid, fid) = DayEvent.splitInto(into)
    guard let host = hosts[sid], let spec = specByID[sid] else {
        return StepLine(line: jsonLine(["step": step, "t": t, "into": into,
                                        "error": "unknown surface \(sid)"]))
    }
    do { try await host.prepare(field: fid, value: before) }
    catch { log("step \(step): prepare failed: \(error)") }

    var ctx = ContextSnapshot()
    if let el = await host.element(forField: fid) {
        ctx = ContextCaptor.capture(element: el, app: NSRunningApplication.current)
    } else {
        log("step \(step): no AX element for \(into) — captured context is empty")
    }
    // The capture is real; only the impersonated app's identity is stamped on.
    ctx.appName = spec.app
    ctx.bundleID = spec.bundle
    ctx.windowTitle = spec.window
    ctx.webHost = spec.host

    let refNow = Date()
    let candidates = history.map { e -> Clip in
        var c = e.clip
        c.copiedAt = refNow.addingTimeInterval(-max(0, t - e.t))
        return c
    }
    let latestText = candidates.first?.text ?? ""
    let histTexts = candidates.map(\.text)
    let plan = BarModel.plan(wants: want.strings.isEmpty ? [latestText] : want.strings,
                             history: histTexts)

    var kind = "plain"
    var optionsShown: [String] = []
    var landed = ""
    var chooserKeys: [String] = []
    var pickedClipID: String?
    var decisionMS = 0.0
    var trigger = "⌘V"

    if ctx.field.isSecure {
        // Production parity: secure fields never reach the engine.
        let after = (try? await host.insert(fid, latestText)) ?? before
        landed = BarModel.inserted(before: before, after: after)
    } else {
        recorder.currentCaseID = caseID
        (recorder.inner as? ReplayProvider)?.currentCaseID = caseID
        var engine = DecisionEngine(provider: recorder)
        engine.confidenceThreshold = args.threshold
        engine.decisivenessMargin = args.margin
        engine.timeout = args.timeout
        let multipliers = feedback.multipliers(for: ctx)
        let stepMode: DecisionEngine.Mode =
            args.intent == "aware" && !want.satisfiedBy(landed: latestText, latest: latestText) ? .hotkey : args.engineMode
        trigger = stepMode == .hotkey ? "hotkey" : "⌘V"
        let prefetch = DecisionPrefetch()
        if args.gapMS > 0 {
            prefetch.warm(context: ctx, candidates: candidates, engine: engine)
            try? await Task.sleep(for: .milliseconds(args.gapMS))
        }
        let t0 = ContinuousClock.now
        let outcome = await prefetch.outcome(
            context: ctx, candidates: candidates, mode: stepMode,
            feedback: multipliers, engine: engine)
        let decided = ContinuousClock.now
        await prefetch.settle()
        let d = t0.duration(to: decided).components
        decisionMS = Double(d.seconds) * 1000 + Double(d.attoseconds) / 1e15
        if ProcessInfo.processInfo.environment["CUEDAY_DEBUG"] != nil {
            log("  step \(step): label=\(ctx.field.label) ph=\(ctx.field.placeholder) " +
                "nearby=\(ctx.nearby) expects=\(FieldKind.infer(label: ctx.field.label, placeholder: ctx.field.placeholder, nearby: ctx.nearby).rawValue) outcome=\(outcome)")
        }

        switch outcome {
        case .paste(let dec):
            kind = "paste"
            pickedClipID = dec.clip.id
            let after = (try? await host.insert(fid, dec.text)) ?? before
            landed = BarModel.inserted(before: before, after: after)
        case .choose(let opts):
            kind = "choose"
            let accept = want.strings
            // The persona takes a visible row that is (or holds) what they want; failing that they type
            // the same short query the bar types into Spotlight, then take a row.
            func pick(_ rows: [ScoredOption]) -> Int? {
                rows.firstIndex { accept.contains($0.option.text) }
                    ?? rows.firstIndex { r in accept.contains { !$0.isEmpty && r.option.text.contains($0) } }
            }
            var rows = ChooserRows.rows(ranked: opts, history: candidates, query: "")
            var typed: [String] = []
            if pick(rows) == nil, let holder = histTexts.first(where: { h in accept.contains { !$0.isEmpty && h.contains($0) } }) {
                let q = BarModel.query(for: accept.first { holder == $0 } ?? holder, in: histTexts)
                rows = ChooserRows.rows(ranked: opts, history: candidates, query: q)
                typed = ["type:\(q)"]
            }
            optionsShown = rows.map(\.option.text)
            if let k = pick(rows) {
                chooserKeys = typed.isEmpty ? ["\(k + 1)"] : typed + Array(repeating: "↓", count: k) + ["Return"]
                pickedClipID = rows[k].option.clip.id
                let after = (try? await host.insert(fid, rows[k].option.text)) ?? before
                landed = BarModel.inserted(before: before, after: after)
            } else {
                chooserKeys = ["Esc", "⌘V"]
                let after = (try? await host.insert(fid, latestText)) ?? before
                landed = BarModel.inserted(before: before, after: after)
            }
        case .pasteLatest:
            let after = (try? await host.insert(fid, latestText)) ?? before
            landed = BarModel.inserted(before: before, after: after)
        }
    }

    let correct = want.satisfiedBy(landed: landed, latest: latestText)
    // Landed a clip that holds the wanted part: a person trims it, as they would after a plain ⌘V.
    let trimmed = !correct && want.strings.contains { !$0.isEmpty && DayWant.flat(landed).contains(DayWant.flat($0)) }
    var undo = false
    if !correct && !trimmed {
        // Persona ⌘Z — feedback −1, field restored, then the bar's route.
        undo = true
        try? await host.restore(fid, value: before)
    }
    if let cid = pickedClipID {
        feedback.record(clipID: cid, ctx: ctx, undone: undo)
    }

    var cueS = KLM.keystrokeS + decisionMS / 1000.0
    if kind == "choose" {
        let typedChars = chooserKeys.first { $0.hasPrefix("type:") }.map { $0.count - 5 } ?? 0
        cueS += KLM.mentalS + KLM.keystrokeS * Double(chooserKeys.count - (typedChars > 0 ? 1 : 0) + typedChars)
    }
    if undo { cueS += KLM.keystrokeS }
    if trimmed { cueS += BarModel.trimS } else if !correct { cueS += plan.seconds }

    let ctxJSON: [String: Any] = [
        "app": ctx.appName, "bundle": ctx.bundleID, "window": ctx.windowTitle,
        "nearby": ctx.nearby, "webHost": ctx.webHost,
        "field": ["role": ctx.field.role, "label": ctx.field.label,
                  "placeholder": ctx.field.placeholder, "value": ctx.field.value,
                  "secure": ctx.field.isSecure],
    ]
    let rec: [String: Any] = [
        "step": step, "t": t, "into": into, "why": why,
        "want": want.jsonValue.toAny(),
        "latest_text": latestText,
        "history_depth_of_want": plan.depth ?? NSNull(),
        "captured_context": ctxJSON,
        "cue": ["outcome": kind, "options_shown": optionsShown,
                "keys": [trigger] + chooserKeys + (undo ? ["⌘Z"] : []),
                "decision_ms": (decisionMS * 10).rounded() / 10,
                "landed": landed, "correct": correct, "trimmed": trimmed, "undo": undo,
                "est_s": (cueS * 100).rounded() / 100],
        "bar": ["route": plan.route.rawValue, "keys": plan.keys,
                "est_s": (plan.seconds * 100).rounded() / 100,
                "landed": plan.landed, "correct": true],
    ]

    agg.steps += 1
    if correct { agg.cueCorrect += 1 }
    else if kind == "paste" { agg.wrongPastes += 1 }
    else if kind == "plain" && !trimmed { agg.misses += 1 }
    agg.barCorrect += 1
    if want.isSingleString { agg.singleWants += 1; if kind == "choose" { agg.chooserOnSingle += 1 } }
    agg.latencies.append(decisionMS)
    agg.cueS += cueS; agg.barS += plan.seconds
    // Within 10 ms is the same paste to a person.
    let usable = correct || trimmed
    if usable && cueS < plan.seconds - 0.01 { agg.better += 1 }
    else if usable && cueS <= plan.seconds + 0.01 { agg.tied += 1 }
    else { agg.worse += 1 }

    let exportCase: [String: Any]? = args.exportCases != nil ? [
        "id": caseID, "category": "day-\(persona)",
        "mode": args.mode,
        "context": ["app": ctx.appName, "bundle": ctx.bundleID, "window": ctx.windowTitle,
                    "nearby": ctx.nearby, "webHost": ctx.webHost,
                    "field": ["role": ctx.field.role, "label": ctx.field.label,
                              "placeholder": ctx.field.placeholder, "value": ctx.field.value]],
        "clips": history.map { e in
            ["text": e.clip.text, "app": e.clip.sourceApp,
             "age_s": max(0, t - e.t), "pinned": e.clip.pinned] as [String: Any]
        },
        "expect": want.jsonValue.toAny(),
    ] : nil
    return StepLine(line: jsonLine(rec), exportCase: exportCase)
}

/// Secure-field event: plain paste of latest, nothing captured or read.
@MainActor
func secureStep(step: Int, t: Double, into: String,
                history: [(clip: Clip, t: Double)],
                hosts: [String: DaySurfaceHost], specByID: [String: DaySurface],
                agg: inout StepAgg) async -> String {
    let (sid, fid) = DayEvent.splitInto(into)
    let latestText = history.first?.clip.text ?? ""
    var landed = ""
    if let host = hosts[sid] {
        // Insert without reading the field back — secure values stay unread.
        _ = try? await host.insert(fid, latestText)
        landed = latestText
    }
    let plan = BarModel.plan(want: latestText, history: history.map { $0.clip.text })
    agg.steps += 1; agg.cueCorrect += 1; agg.barCorrect += 1
    agg.cueS += KLM.keystrokeS; agg.barS += plan.seconds
    let rec: [String: Any] = [
        "step": step, "t": t, "into": into, "why": "",
        "want": DayWant.plain.jsonValue.toAny(),
        "latest_text": latestText, "history_depth_of_want": plan.depth ?? NSNull(),
        "captured_context": ["secure": true],
        "cue": ["outcome": "plain", "options_shown": [String](), "keys": ["⌘V"],
                "decision_ms": 0, "landed": landed, "correct": true, "undo": false,
                "est_s": KLM.keystrokeS],
        "bar": ["route": plan.route.rawValue, "keys": plan.keys,
                "est_s": plan.seconds, "landed": plan.landed, "correct": true],
    ]
    return jsonLine(rec)
}

@main
enum CueDayMain {
    static func main() async throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        // WebKit only vends the web content AX tree when the app's
        // enhanced-UI flag is on (what AT clients set on the app element).
        let appEl = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterfaceEnabled" as CFString, kCFBooleanTrue)
        let frontBefore = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        do {
            let args = try Args.parse()
            let code = try await runDay(args)
            let frontAfter = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            log("cueday: frontmost before=\(frontBefore) after=\(frontAfter) " +
                "unchanged=\(frontBefore == frontAfter) appActive=\(app.isActive)")
            exit(Int32(code))
        } catch {
            FileHandle.standardError.write(Data("cueday: \(error)\n".utf8))
            exit(2)
        }
    }
}
