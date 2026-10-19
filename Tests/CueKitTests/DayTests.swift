import Foundation
import Testing
@testable import CueKit

struct DayTraceTests {
    @Test func parsesAllEventKinds() {
        let text = """
            {"t":"09:04","copy":{"text":"mira@example.com","from":"mail"}}
            {"t":"09:05","paste":{"into":"web#main","value_before":"Hi ","want":{"paste":"mira@example.com"},"why":"reply"}}
            {"t":"09:06","paste":{"into":"web#cc","value_before":"","want":{"choose":["a@x.com","b@x.com"]},"why":"cc"}}
            {"t":"09:07","secure":{"into":"bank#password"}}
            """
        let ev = DayTrace.parse(text)
        #expect(ev.count == 4)
        guard case .copy(let t, let s, let from) = ev[0] else { Issue.record(); return }
        #expect(t == 9 * 3600 + 4 * 60 && s == "mira@example.com" && from == "mail")
        guard case .paste(_, let into, let before, let want, let why) = ev[1] else { Issue.record(); return }
        #expect(into == "web#main" && before == "Hi " && want == .paste("mira@example.com") && why == "reply")
        guard case .paste(_, _, _, let want2, _) = ev[2] else { Issue.record(); return }
        #expect(want2 == .choose(["a@x.com", "b@x.com"]))
        guard case .secure(_, let sInto) = ev[3] else { Issue.record(); return }
        #expect(sInto == "bank#password")
    }

    @Test func badLinesAreSkipped() {
        let ev = DayTrace.parse("""
            not json
            {"t":"bogus","copy":{"text":"x","from":"a"}}
            {"copy":{"text":"x","from":"a"}}
            {"t":"10:00","copy":{"text":"ok","from":"a"}}
            """)
        #expect(ev.count == 1)
        guard case .copy(let t, let s, _) = ev[0] else { Issue.record(); return }
        #expect(t == 36000 && s == "ok")
    }

    @Test func splitIntoDefaultsToMain() {
        #expect(DayEvent.splitInto("mail#main") == ("mail", "main"))
        #expect(DayEvent.splitInto("mail") == ("mail", "main"))
        #expect(DayEvent.splitInto("web#email") == ("web", "email"))
    }

    @Test func timeParsing() {
        #expect(DayTrace.time("09:04") == 32640)
        #expect(DayTrace.time("09:04:30") == 32670)
        #expect(DayTrace.time("25:00") == nil)
        #expect(DayTrace.time("noon") == nil)
    }

    @Test func surfacesDecode() {
        let json = """
            {"surfaces":[
              {"id":"mail","app":"Mail","bundle":"com.apple.mail","window":"Inbox",
               "kind":"native-text","field":{"role":"AXTextArea","label":"Message"}},
              {"id":"web","app":"Safari","bundle":"com.apple.Safari","window":"Form",
               "kind":"web","page":"form.html","host":"example.com",
               "field":{"role":"AXTextField","label":"Email","placeholder":"you@x.com"}}
            ]}
            """
        let s = DayTrace.surfaces(json)
        #expect(s.count == 2)
        #expect(s[0].kind == "native-text" && s[0].field.label == "Message")
        #expect(s[1].kind == "web" && s[1].host == "example.com")
    }
}

struct BarModelTests {
    let history = ["latest clip", "older clip with elephant", "mid clip"]

    @Test func latestIsPlainPaste() {
        let p = BarModel.plan(want: "latest clip", history: history)
        #expect(p.route == .plain && p.seconds == KLM.keystrokeS && p.depth == 0)
    }

    @Test func wholeClipIsSpotlight() {
        let p = BarModel.plan(want: "mid clip", history: history)
        #expect(p.route == .spotlight && p.depth == 2)
        // ⌘Space, ⌘4, 4-char query, Return, ⌘V
        let q = BarModel.query(for: "mid clip", in: history)
        #expect(q.count == 4)
        #expect(p.seconds == KLM.spotlightOpenS + KLM.mentalS + KLM.keystrokeS * Double(4 + q.count))
    }

    @Test func substringIsSpotlightPlusTrim() {
        let p = BarModel.plan(want: "elephant", history: history)
        #expect(p.route == .spotlightTrim && p.depth == 1)
        let q = BarModel.query(for: "older clip with elephant", in: history)
        #expect(p.seconds == KLM.spotlightOpenS + 2 * KLM.mentalS + KLM.keystrokeS * Double(8 + q.count))
    }

    @Test func unseenStringIsRetyped() {
        let p = BarModel.plan(want: "never copied", history: history)
        #expect(p.route == .retype && p.depth == nil)
        #expect(p.seconds == KLM.mentalS + KLM.keystrokeS * 12)
    }

    @Test func chooseWantPicksCheapest() {
        let p = BarModel.plan(wants: ["elephant", "latest clip"], history: history)
        #expect(p.route == .plain)
    }

    @Test func queryIsRarestWord() {
        // "clip" appears in all three; "elephant" only in one → rarest.
        let q = BarModel.query(for: "a clip about elephant parade", in: history)
        #expect(q == "elep" || q == "para" || q == "abou")
    }

    @Test func insertedDiff() {
        #expect(BarModel.inserted(before: "Hi ", after: "Hi there") == "there")
        #expect(BarModel.inserted(before: "", after: "abc") == "abc")
        #expect(BarModel.inserted(before: "abc", after: "abc") == "")
        #expect(BarModel.inserted(before: "a c", after: "a bc") == "b")
        #expect(BarModel.inserted(before: "x", after: "y") == "y")
        #expect(BarModel.inserted(before: "café ", after: "café ☕️") == "☕️")
    }
}

struct DayWantTests {
    @Test func satisfiedBy() {
        #expect(DayWant.paste("a").satisfiedBy(landed: "a", latest: "x"))
        #expect(!DayWant.paste("a").satisfiedBy(landed: "b", latest: "x"))
        #expect(DayWant.choose(["a", "b"]).satisfiedBy(landed: "b", latest: "x"))
        #expect(DayWant.plain.satisfiedBy(landed: "x", latest: "x"))
        #expect(!DayWant.plain.satisfiedBy(landed: "y", latest: "x"))
    }
}
