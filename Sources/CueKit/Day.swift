import Foundation

// MARK: - Day trace model (CueDay persona replay)

/// A hosted replay surface: which app/window it impersonates and what it
/// renders. Loaded from Evals/days/surfaces.json.
public struct DaySurface: Decodable, Sendable {
    public var id: String = ""
    public var app: String = ""
    public var bundle: String = ""
    public var window: String = ""
    /// "web" | "native-text" | "native-field"
    public var kind: String = "native-text"
    /// pages/<page> html file, for web surfaces.
    public var page: String = ""
    /// The host the web surface pretends to serve.
    public var host: String = ""
    public var field: Field = .init()

    public struct Field: Decodable, Sendable {
        public var role: String = ""
        public var label: String = ""
        public var placeholder: String = ""
        public init() {}
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)
            role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
            label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
            placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder) ?? ""
        }
        private enum K: String, CodingKey { case role, label, placeholder }
    }

    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        id = try c.decode(String.self, forKey: .id)
        app = try c.decodeIfPresent(String.self, forKey: .app) ?? ""
        bundle = try c.decodeIfPresent(String.self, forKey: .bundle) ?? ""
        window = try c.decodeIfPresent(String.self, forKey: .window) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "native-text"
        page = try c.decodeIfPresent(String.self, forKey: .page) ?? ""
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        field = try c.decodeIfPresent(Field.self, forKey: .field) ?? .init()
    }
    private enum K: String, CodingKey {
        case id, app, bundle, window, kind, page, host, field
    }
}

/// What the persona wanted to land, decoded from `want`.
public enum DayWant: Sendable, Equatable {
    /// One exact string.
    case paste(String)
    /// Any of these counts.
    case choose([String])
    /// A plain ⌘V of the latest clip was the right answer.
    case plain

    /// The strings that satisfy this want; empty for .plain (satisfied by latest).
    public var strings: [String] {
        switch self {
        case .paste(let s): [s]
        case .choose(let ss): ss
        case .plain: []
        }
    }

    /// Is there exactly one acceptable string? (chooser-rate denominator).
    public var isSingleString: Bool {
        if case .paste = self { return true }
        return false
    }

    /// `landed` satisfies the want; `latest` is the text a plain ⌘V inserts.
    /// Fields reflow whitespace on insert (a single-line input drops newlines) and WebKit's text
    /// insertion applies smart quotes, which a real paste does not — compare text, not typography.
    public func satisfiedBy(landed: String, latest: String) -> Bool {
        let l = Self.flat(landed)
        switch self {
        case .paste(let s): return l == Self.flat(s)
        case .choose(let ss): return ss.contains { Self.flat($0) == l }
        case .plain: return l == Self.flat(latest)
        }
    }

    public static func flat(_ s: String) -> String {
        let plain = s.map { c -> Character in
            switch c {
            case "“", "”": "\""
            case "‘", "’": "'"
            default: c
            }
        }
        return String(plain).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    init?(json: JSONValue) {
        if let p = json["paste"]?.string {
            self = .paste(p)
        } else if case .array(let arr)? = json["choose"] {
            self = .choose(arr.compactMap(\.string))
        } else if case .bool(let b)? = json["plain"], b {
            self = .plain
        } else {
            return nil
        }
    }

    public var jsonValue: JSONValue {
        switch self {
        case .paste(let s): .object(["paste": .string(s)])
        case .choose(let ss): .object(["choose": .array(ss.map { .string($0) })])
        case .plain: .object(["plain": .bool(true)])
        }
    }
}

/// One line of a persona trace.
public enum DayEvent: Sendable {
    case copy(t: Double, text: String, from: String)
    case paste(t: Double, into: String, valueBefore: String, want: DayWant, why: String)
    /// Persona pasted into a secure field: plain paste of latest, no capture.
    case secure(t: Double, into: String)

    public var t: Double {
        switch self {
        case .copy(let t, _, _), .paste(let t, _, _, _, _), .secure(let t, _): t
        }
    }

    /// "surface#field" → (surface, field); a missing field part means "main".
    public static func splitInto(_ into: String) -> (surface: String, field: String) {
        let parts = into.split(separator: "#", maxSplits: 1)
        return (String(parts[0]), parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : "main")
    }
}

public enum DayTrace {
    /// "09:04" or "09:04:30" → seconds into the persona day.
    public static func time(_ s: String) -> Double? {
        let p = s.split(separator: ":").map(String.init)
        guard (2...3).contains(p.count), let h = Double(p[0]), let m = Double(p[1]),
              h < 24, m < 60 else { return nil }
        return h * 3600 + m * 60 + (p.count == 3 ? Double(p[2]) ?? 0 : 0)
    }

    /// One JSON object per line; unparseable lines are skipped.
    public static func parse(_ text: String) -> [DayEvent] {
        text.split(whereSeparator: \.isNewline).compactMap { line -> DayEvent? in
            guard let o = JSONValue(any: (try? JSONSerialization.jsonObject(with: Data(line.utf8))) ?? [:]),
                  let tS = o["t"]?.string, let t = time(tS) else { return nil }
            if let copy = o["copy"]?.object, let text = copy["text"]?.string {
                return .copy(t: t, text: text, from: copy["from"]?.string ?? "")
            }
            if let paste = o["paste"]?.object, let into = paste["into"]?.string,
               let wantJ = paste["want"], let want = DayWant(json: wantJ) {
                return .paste(t: t, into: into,
                              valueBefore: paste["value_before"]?.string ?? "",
                              want: want, why: paste["why"]?.string ?? "")
            }
            if let secure = o["secure"]?.object, let into = secure["into"]?.string {
                return .secure(t: t, into: into)
            }
            return nil
        }
    }

    /// surfaces.json: an array, {"surfaces": […]}, or a dict keyed by id.
    public static func surfaces(_ text: String) -> [DaySurface] {
        guard let root = JSONValue(any: (try? JSONSerialization.jsonObject(with: Data(text.utf8))) ?? [:])
        else { return [] }
        let list: [JSONValue]
        if case .array(let a) = root {
            list = a
        } else if case .array(let a)? = root["surfaces"] {
            list = a
        } else if let obj = root.object {
            list = obj.values.filter { $0["id"] != nil }
        } else {
            list = []
        }
        let dec = JSONDecoder()
        return list.compactMap { v in
            guard let data = try? JSONSerialization.data(withJSONObject: v.toAny()) else { return nil }
            return try? dec.decode(DaySurface.self, from: data)
        }
    }
}

// MARK: - Keystroke-Level Model (Card, Moran & Newell 1980)

public enum KLM {
    public static let keystrokeS = 0.28
    public static let mentalS = 1.35
    /// Spotlight open/search latency — named constant, a later calibration replaces it.
    public static let spotlightOpenS = 0.6
}

public enum BarRoute: String, Sendable {
    /// Wanted string IS the latest clip → ⌘V.
    case plain
    /// Wanted string sits inside the latest clip → ⌘V, then trim by hand.
    case plainTrim = "plain+trim"
    /// Wanted string is a whole clip deeper in history → Spotlight ⌘4 fetch.
    case spotlight
    /// Wanted string is a substring of a clip → Spotlight fetch + manual trim.
    case spotlightTrim = "spotlight+trim"
    /// Nothing in history produces it → type it out.
    case retype
}

public struct BarPlan: Sendable, Equatable {
    public var route: BarRoute
    public var keys: [String]
    public var seconds: Double
    public var landed: String
    /// History position of the clip the route fetches (0 = latest).
    public var depth: Int?

    public init(route: BarRoute, keys: [String], seconds: Double, landed: String, depth: Int?) {
        self.route = route; self.keys = keys; self.seconds = seconds
        self.landed = landed; self.depth = depth
    }
}

/// The "bar" — what a person without Cue does. Computed, never driven.
public enum BarModel {
    public static func plan(want: String, history: [String]) -> BarPlan {
        if history.first == want {
            return BarPlan(route: .plain, keys: ["⌘V"],
                           seconds: KLM.keystrokeS, landed: want, depth: 0)
        }
        if history.first?.contains(want) == true {
            return BarPlan(route: .plainTrim, keys: ["⌘V", "trim×4"],
                           seconds: KLM.keystrokeS + trimS, landed: want, depth: 0)
        }
        if let p = history.firstIndex(of: want) {
            let q = query(for: want, in: history)
            return BarPlan(route: .spotlight,
                           keys: ["⌘Space", "⌘4", "type:\(q)", "Return", "⌘V"],
                           seconds: KLM.spotlightOpenS + KLM.mentalS + KLM.keystrokeS * Double(4 + q.count),
                           landed: want, depth: p)
        }
        if let p = history.firstIndex(where: { $0.contains(want) }) {
            let q = query(for: history[p], in: history)
            // Trim: ~4 select-and-delete keystrokes + an extra mental operator.
            return BarPlan(route: .spotlightTrim,
                           keys: ["⌘Space", "⌘4", "type:\(q)", "Return", "⌘V", "trim×4"],
                           seconds: KLM.spotlightOpenS + KLM.mentalS + KLM.keystrokeS * Double(4 + q.count) + trimS,
                           landed: want, depth: p)
        }
        return BarPlan(route: .retype, keys: ["type"],
                       seconds: KLM.mentalS + KLM.keystrokeS * Double(want.count),
                       landed: want, depth: nil)
    }

    /// Cutting a pasted clip down to the wanted part: decide what to keep, ~4 select-and-delete keystrokes.
    public static let trimS = KLM.mentalS + KLM.keystrokeS * 4

    /// Several acceptable strings → the cheapest route.
    public static func plan(wants: [String], history: [String]) -> BarPlan {
        wants.map { plan(want: $0, history: history) }.min { $0.seconds < $1.seconds }
            ?? BarPlan(route: .retype, keys: ["type"], seconds: KLM.mentalS, landed: "", depth: nil)
    }

    /// Spotlight query: first 4 letters of the clip's rarest word — rare =
    /// appears in the fewest history clips. Ties keep the earliest word.
    public static func query(for clip: String, in history: [String]) -> String {
        let words = clip.lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init).filter { $0.count >= 4 }
        guard var best = words.first else { return String(clip.lowercased().prefix(4)) }
        func rarity(_ w: String) -> Int {
            history.filter { $0.lowercased().contains(w) }.count
        }
        var bestR = rarity(best)
        for w in words.dropFirst() {
            let r = rarity(w)
            if r < bestR { best = w; bestR = r }
        }
        return String(best.prefix(4))
    }

    /// What an insertion actually added: `after` minus the longest common
    /// prefix+suffix it shares with `before`.
    public static func inserted(before: String, after: String) -> String {
        guard before != after else { return "" }
        let b = Array(before), a = Array(after)
        var i = 0
        while i < b.count, i < a.count, b[i] == a[i] { i += 1 }
        var j = 0
        while j < b.count - i, j < a.count - i, b[b.count - 1 - j] == a[a.count - 1 - j] { j += 1 }
        let end = max(i, a.count - j)
        return String(a[i..<end])
    }
}
