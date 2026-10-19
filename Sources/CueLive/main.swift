import AppKit
import ApplicationServices
import Carbon
import CueKit
import Foundation

// CueLive — drives a persona day in the real apps, both ways, with real keystrokes.
//
//   CueLive --days Evals/days --persona recruiter --side cue --cue-pid <pid> --out <dir>
//   CueLive --days Evals/days --persona recruiter --side bar --out <dir>
//
// cue: the real Cue app (running, ⌘V intercepted) handles ⌘V and the ⌃⌥V hotkey; its chooser is
// answered by reading its rows through Accessibility. bar: Cue is not running; plain ⌘V, and
// Spotlight's clipboard history (⌘Space, ⌘4, query, Return) when the latest clip isn't wanted.
// Web surfaces load the local pages in the real browser named by the surface; Terminal runs
// `cat > /dev/null`; every other native surface is a TextEdit document. Nothing leaves the Mac.

struct Fail: Error, CustomStringConvertible { var description: String }

func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
func pause(_ ms: Int) { usleep(useconds_t(ms * 1000)) }

// MARK: - Keys

func key(_ code: Int, _ flags: CGEventFlags = []) {
    let src = CGEventSource(stateID: .hidSystemState)
    for down in [true, false] {
        let e = CGEvent(keyboardEventSource: src, virtualKey: CGKeyCode(code), keyDown: down)
        e?.flags = flags
        e?.post(tap: .cghidEventTap)
        pause(12)
    }
}

func typeText(_ s: String) {
    let src = CGEventSource(stateID: .hidSystemState)
    for ch in s {
        if ch == "\n" { key(kVK_Return, .maskShift); continue }
        let u = Array(String(ch).utf16)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)
            e?.flags = [] // a person has let go of the hotkey's ⌃⌥ by now
            e?.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u)
            e?.post(tap: .cghidEventTap)
        }
        pause(6)
    }
}

// MARK: - Accessibility

func ax(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, attr as CFString, &v) == .success ? v : nil
}
func axString(_ el: AXUIElement, _ attr: String) -> String? { ax(el, attr) as? String }
func axKids(_ el: AXUIElement) -> [AXUIElement] { (ax(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func axFind(_ el: AXUIElement, depth: Int = 0, _ hit: (AXUIElement) -> Bool) -> AXUIElement? {
    if hit(el) { return el }
    guard depth < 40 else { return nil }
    for k in axKids(el) { if let f = axFind(k, depth: depth + 1, hit) { return f } }
    return nil
}
func axAll(_ el: AXUIElement, depth: Int = 0, _ hit: (AXUIElement) -> Bool) -> [AXUIElement] {
    var out = hit(el) ? [el] : []
    guard depth < 40 else { return out }
    for k in axKids(el) { out += axAll(k, depth: depth + 1, hit) }
    return out
}

func focusedValue() -> String {
    let sys = AXUIElementCreateSystemWide()
    guard let f = ax(sys, kAXFocusedUIElementAttribute), CFGetTypeID(f) == AXUIElementGetTypeID() else { return "" }
    return axString(f as! AXUIElement, kAXValueAttribute) ?? ""
}

// MARK: - Apps

func activate(_ bundle: String) {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return }
    app.activate()
    for _ in 0..<60 where NSWorkspace.shared.frontmostApplication?.bundleIdentifier != bundle { pause(25) }
}

struct Target {
    var bundle: String
    var browser: String?   // AppleScript app name for web surfaces
}

func target(for s: DaySurface) -> Target {
    if s.kind == "web" {
        return s.app == "Safari" ? Target(bundle: "com.apple.Safari", browser: "Safari")
                                 : Target(bundle: "com.google.Chrome", browser: "Google Chrome")
    }
    return s.app == "Terminal" ? Target(bundle: "com.apple.Terminal") : Target(bundle: "com.apple.TextEdit")
}

/// The web field this step focused (browser pid, DOM id); nil for native surfaces. Chrome rebuilds
/// its AX nodes, so the field is found again on every read rather than cached.
nonisolated(unsafe) var webField: (pid: pid_t, id: String)?

func findWebField(_ f: (pid: pid_t, id: String)) -> AXUIElement? {
    let app = AXUIElementCreateApplication(f.pid)
    guard let w = ax(app, kAXFocusedWindowAttribute) else { return nil }
    return axFind(w as! AXUIElement) { axString($0, "AXDOMIdentifier") == f.id }
}

func prepare(_ s: DaySurface, field fid: String, before: String, pages: URL) throws {
    webField = nil
    let t = target(for: s)
    if let browser = t.browser {
        // A tab of its own per step, opened through Launch Services (no Apple Events permission) and closed with ⌘W after.
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: t.bundle)
        else { throw Fail(description: "\(browser) not installed") }
        NSWorkspace.shared.open([pages.appendingPathComponent(s.page)], withApplicationAt: appURL,
                                configuration: NSWorkspace.OpenConfiguration())
        pause(300)
        activate(t.bundle)
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: t.bundle).first?.processIdentifier
        else { throw Fail(description: "\(browser) not running") }
        let app = AXUIElementCreateApplication(pid)
        // Browsers publish web content to Accessibility only once a client asks for it.
        for attr in ["AXEnhancedUserInterface", "AXManualAccessibility"] {
            AXUIElementSetAttributeValue(app, attr as CFString, kCFBooleanTrue)
        }
        var el: AXUIElement?
        for _ in 0..<200 where el == nil { // up to 10 s: a cold browser launch
            pause(50)
            guard let w = ax(app, kAXFocusedWindowAttribute) else { continue }
            el = axFind(w as! AXUIElement) { axString($0, "AXDOMIdentifier") == fid }
        }
        guard let el else { throw Fail(description: "no #\(fid) in \(s.page)") }
        AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        webField = (pid, fid)
        pause(120)
    } else {
        activate(t.bundle)
        pause(100)
    }
    // Clear, then type what the person had already typed.
    if t.bundle == "com.apple.Terminal" {
        key(kVK_ANSI_U, .maskControl)
    } else {
        key(kVK_ANSI_A, .maskCommand); key(kVK_Delete)
    }
    if !before.isEmpty { typeText(before) }
    pause(80)
}

// MARK: - Cue's chooser

/// The chooser's rows, read from each row button's accessibility label ("Paste <text>, from <app>, <age>").
func chooserRows(cuePID: pid_t) -> [String]? {
    let app = AXUIElementCreateApplication(cuePID)
    for w in (ax(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
        let rows = axAll(w) { axString($0, kAXRoleAttribute) == "AXButton" }.compactMap { b -> String? in
            guard let d = axString(b, kAXDescriptionAttribute), d.hasPrefix("Paste ") else { return nil }
            let body = d.dropFirst("Paste ".count)
            return body.range(of: ", from ", options: .backwards).map { String(body[..<$0.lowerBound]) } ?? String(body)
        }
        if !rows.isEmpty { return rows }
    }
    return nil
}

/// The target app's own focused field — Cue's chooser panel takes key focus while it's up.
func fieldValue(_ bundle: String) -> String {
    if let webField { return findWebField(webField).flatMap { axString($0, kAXValueAttribute) } ?? "" }
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first?.processIdentifier,
          let f = ax(AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute),
          CFGetTypeID(f) == AXUIElementGetTypeID() else { return "" }
    return axString(f as! AXUIElement, kAXValueAttribute) ?? ""
}

// MARK: - Run

struct Args {
    var days = "Evals/days"
    var persona = ""
    var side = "cue"
    var cuePID: pid_t = 0
    var out = "Evals/days/results/live"
    var gapMS = 300
    var only: Int?
    var until: Int?
}

func parseArgs() throws -> Args {
    var a = Args()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let k = it.next() {
        guard let v = it.next() else { throw Fail(description: "\(k) needs a value") }
        switch k {
        case "--days": a.days = v
        case "--persona": a.persona = v
        case "--side": a.side = v
        case "--cue-pid": a.cuePID = pid_t(v) ?? 0
        case "--out": a.out = v
        case "--gap-ms": a.gapMS = Int(v) ?? 300
        case "--only": a.only = Int(v)
        case "--until": a.until = Int(v)
        default: throw Fail(description: "unknown arg \(k)")
        }
    }
    return a
}

@MainActor
func run(_ a: Args) throws {
    let dir = URL(fileURLWithPath: a.days)
    let surfaces = Dictionary(uniqueKeysWithValues: DayTrace.surfaces(
        try String(contentsOf: dir.appendingPathComponent("surfaces.json"), encoding: .utf8)).map { ($0.id, $0) })
    let events = DayTrace.parse(try String(contentsOf: dir.appendingPathComponent("\(a.persona).jsonl"), encoding: .utf8))
    let pages = dir.appendingPathComponent("pages")
    try FileManager.default.createDirectory(atPath: a.out, withIntermediateDirectories: true)
    let outURL = URL(fileURLWithPath: a.out).appendingPathComponent("\(a.persona)-\(a.side).jsonl")
    FileManager.default.createFile(atPath: outURL.path, contents: nil)
    let outFile = try FileHandle(forWritingTo: outURL)

    let pb = NSPasteboard.general
    var history: [String] = []
    var step = 0
    for e in events {
        switch e {
        case .copy(_, let text, _):
            pb.clearContents(); pb.setString(text, forType: .string)
            history.insert(text, at: 0)
            pause(350) // Cue's monitor polls at 4 Hz; Spotlight's history records it too
        case .secure:
            continue
        case .paste(_, let into, let before, let want, let why):
            step += 1
            if let only = a.only, only != step { continue }
            if let until = a.until, step > until { return }
            let (sid, fid) = DayEvent.splitInto(into)
            guard let s = surfaces[sid] else { continue }
            let latest = history.first ?? ""
            // Put the latest clip back: the previous step's bar route may have changed the pasteboard.
            pb.clearContents(); pb.setString(latest, forType: .string)
            do { try prepare(s, field: fid, before: before, pages: pages) }
            catch { log("step \(step): \(error)"); continue }
            let tb = target(for: s).bundle
            let base = fieldValue(tb)
            let wantsLatest = want.satisfiedBy(landed: latest, latest: latest)
            var keys: [String] = []
            var waitMS = 0.0
            let t0 = ContinuousClock.now
            func ms(_ since: ContinuousClock.Instant) -> Double {
                let c = since.duration(to: .now).components
                return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
            }
            func landed() -> String { BarModel.inserted(before: base, after: fieldValue(tb)) }
            func waitForChange(_ ms: Int) -> Bool {
                for _ in 0..<(ms / 20) { if fieldValue(tb) != base { pause(60); return true }; pause(20) }
                return false
            }

            if a.side == "cue" {
                pause(a.gapMS) // the person reaching for the keys: Cue warms its answer here
                if wantsLatest { key(kVK_ANSI_V, .maskCommand); keys = ["⌘V"] }
                else { key(kVK_ANSI_V, [.maskControl, .maskAlternate]); keys = ["hotkey"] }
                let tk = ContinuousClock.now
                var rows: [String]? = nil
                for _ in 0..<150 {
                    if let r = chooserRows(cuePID: a.cuePID) { rows = r; break }
                    if fieldValue(tb) != base { break }
                    pause(20)
                }
                waitMS = ms(tk)
                if let first = rows {
                    pause(250) // reading the list
                    if ProcessInfo.processInfo.environment["LIVE_DEBUG"] != nil {
                        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                        p.arguments = ["-x", "/tmp/live-chooser-\(step).png"]; try? p.run(); p.waitUntilExit()
                    }
                    func pick(_ rows: [String]) -> Int? {
                        rows.firstIndex { r in want.strings.contains { DayWant.flat($0) == DayWant.flat(r) } }
                            ?? rows.firstIndex { r in want.strings.contains { !$0.isEmpty && DayWant.flat(r).contains(DayWant.flat($0)) } }
                    }
                    var i = pick(first)
                    if i == nil, let holder = history.first(where: { h in want.strings.contains { !$0.isEmpty && h.contains($0) } }) {
                        let q = BarModel.query(for: holder, in: history)
                        typeText(q); keys.append("type:\(q)"); pause(250)
                        let after = chooserRows(cuePID: a.cuePID)
                        if ProcessInfo.processInfo.environment["LIVE_DEBUG"] != nil {
                            log("  rows before: \(first.prefix(4).map { $0.prefix(40) })")
                            log("  rows after \(q): \((after ?? []).prefix(4).map { $0.prefix(40) })")
                        }
                        i = after.flatMap(pick)
                    }
                    let digits = Array(1...9)
                    let searched = keys.contains { $0.hasPrefix("type:") }
                    if let i, searched {
                        for _ in 0..<i { key(kVK_DownArrow) }
                        key(kVK_Return); keys += Array(repeating: "↓", count: i) + ["Return"]
                    } else if let i, i < digits.count { typeText("\(i + 1)"); keys.append("\(i + 1)") }
                    else { key(kVK_Escape); keys.append("Esc") }
                }
                _ = waitForChange(2500)
                if ProcessInfo.processInfo.environment["LIVE_DEBUG"] != nil {
                    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    p.arguments = ["-x", "/tmp/live-after-\(step).png"]; try? p.run(); p.waitUntilExit()
                }
            } else {
                let plan = BarModel.plan(wants: want.strings.isEmpty ? [latest] : want.strings, history: history)
                keys = plan.keys
                switch plan.route {
                case .plain, .plainTrim:
                    key(kVK_ANSI_V, .maskCommand)
                    _ = waitForChange(1500)
                case .spotlight, .spotlightTrim:
                    // macOS 27 replaced Spotlight's clipboard history; this route stays the computed KLM time.
                    keys.append("computed")
                case .retype:
                    typeText(want.strings.first ?? "")
                }
            }
            let got = landed()
            if ProcessInfo.processInfo.environment["LIVE_DEBUG"] != nil {
                log("  base=\(base.prefix(60).debugDescription) after=\(fieldValue(tb).prefix(80).debugDescription) web=\(webField != nil)")
                pause(1500)
                log("  +1.5s after=\(fieldValue(tb).prefix(80).debugDescription) url=\(focusedValue().prefix(40).debugDescription)")
            }
            let ok = want.satisfiedBy(landed: got, latest: latest)
            let trimmed = !ok && want.strings.contains { !$0.isEmpty && DayWant.flat(got).contains(DayWant.flat($0)) }
            let rec: [String: Any] = ["step": step, "into": into, "why": why, "side": a.side,
                                      "keys": keys, "wait_ms": (waitMS * 10).rounded() / 10,
                                      "wall_ms": (ms(t0) * 10).rounded() / 10,
                                      "landed": got, "correct": ok, "trimmed": trimmed,
                                      "want": want.strings, "latest": latest]
            outFile.write(try JSONSerialization.data(withJSONObject: rec, options: [.sortedKeys]))
            outFile.write("\n".data(using: .utf8)!)
            log("\(a.side) \(a.persona) \(step): \(ok ? "ok" : trimmed ? "trim" : "X") \(keys.joined(separator: " ")) wait \(Int(waitMS)) ms")
            // Leave the field as the person found it for the other side's pass.
            key(kVK_Escape)
            if webField != nil { key(kVK_ANSI_W, .maskCommand); pause(150) }
        }
    }
}

do {
    let a = try parseArgs()
    guard AXIsProcessTrusted() else { throw Fail(description: "needs Accessibility trust") }
    try MainActor.assumeIsolated { try run(a) }
} catch {
    log("cuelive: \(error)")
    exit(1)
}
