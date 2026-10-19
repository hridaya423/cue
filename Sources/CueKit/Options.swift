import Foundation

// MARK: - Paste options

/// One thing that could land in the field: either a whole clip or a detected
/// span (email / phone / URL) inside one. The model only ever ranks options —
/// the pasted text is always one of these exact strings. Model chooses, we
/// execute.
public struct PasteOption: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        /// `code`: a token people lift out of a line — a commit SHA, a request id, a quoted name, an amount.
        case email, phone, url, code, text
    }
    /// "c1"…"cN" in recency order — also the model's criteria key.
    public var id: String
    /// The exact string that would be pasted.
    public var text: String
    public var kind: Kind
    /// The clip this option came from (feedback, "copied from", recency).
    public var clip: Clip
    /// ~40 chars of the clip around the span — lets the model (and the
    /// chooser row) distinguish "priya@acme.com" inside an invoice thread
    /// from the same-looking address inside a newsletter footer.
    /// Whole-clip options carry the clip preview.
    public var snippet: String
}

/// A model-ranked option — `probability` is this option's share, `confidence`
/// is the pick question's reported confidence.
public struct ScoredOption: Sendable {
    public var option: PasteOption
    public var probability: Double
    public var confidence: Double
}

/// What the focused field probably wants, inferred locally from its label /
/// placeholder / nearby text. A hint for ranking and timeout fallback, never
/// a hard filter — a wrong guess would hide the right option.
public enum FieldKind: String, Sendable {
    case email, phone, url, name, generic

    public static func infer(label: String, placeholder: String, nearby: String = "") -> FieldKind {
        // The field's own label and placeholder decide. `nearby` holds the rest of the form or the
        // conversation around a message box, so it only speaks for a field with no label of its own.
        let own = kind(in: "\(label) \(placeholder)")
        return own == .generic && label.isEmpty ? kind(in: nearby) : own
    }

    private static func kind(in text: String) -> FieldKind {
        // Whole words only: "hotel" is not a phone field, "username" is not a name field.
        let s = " " + text.lowercased().split { !$0.isLetter && !$0.isNumber }.joined(separator: " ") + " "
        func has(_ words: [String]) -> Bool { words.contains { s.contains(" \($0) ") } }
        if s == " to " || has(["email", "e mail", "mail address", "cc", "bcc", "recipient", "recipients", "guests", "attendees", "invitees"]) { return .email }
        if has(["phone", "mobile", "tel", "telephone", "cell", "fax", "callback"]) { return .phone }
        if has(["url", "website", "link", "domain", "homepage"]) { return .url }
        if has(["name"]) { return .name }
        return .generic
    }

    /// Would `text`, pasted exactly as copied, already fit this field? The
    /// ⌘V-intercept contract: when it does, a plain paste is the answer and
    /// no model call is made (fast, and never a surprise popup on ⌘V).
    /// Generic fields take anything; typed fields need the whole text to be
    /// one span of that type; name fields need text with no detected span.
    public func acceptsVerbatim(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let spans = SpanExtractor.spansWithContext(in: t).filter { $0.kind != .code }
        let want: PasteOption.Kind
        switch self {
        case .generic: return true
        case .name: return spans.isEmpty
        case .email: want = .email
        case .phone: want = .phone
        case .url: want = .url
        }
        // A list of addresses ("a@x.com, b@y.com") is what a To/Bcc field takes as-is.
        guard !spans.isEmpty, spans.allSatisfy({ $0.kind == want }) else { return false }
        if want != .email { return spans.count == 1 && spans[0].text == t }
        let rest = spans.reduce(t) { $0.replacingOccurrences(of: $1.text, with: "") }
        return rest.allSatisfy { $0 == "," || $0 == ";" || $0.isWhitespace }
    }

    /// Does an option satisfy this field kind?
    public func matches(_ option: PasteOption) -> Bool {
        switch self {
        case .email: option.kind == .email
        case .phone: option.kind == .phone
        case .url: option.kind == .url
        case .name: option.kind == .text
        case .generic: true
        }
    }
}

/// Explicit context evidence: distinctive words from the field's label,
/// window title and nearby text that also appear in an option ("Re: …
/// Priya Shah" ↔ priya.shah@…, "Cc:" ↔ "…, cc legal@…"). Only a match
/// unique to one option counts as a pick — two options sharing the evidence
/// is ambiguity, and the chooser handles it.
public enum ContextSignal {
    static let stop: Set<String> = [
        "the", "and", "for", "from", "with", "your", "you", "our", "new", "message",
        "email", "mail", "address", "phone", "number", "url", "link", "website",
        "com", "org", "net", "www", "http", "https", "example", "subject", "add",
        "contact", "name", "field", "enter", "draft", "reply", "fwd", "re", "to",
    ]

    static func words(_ s: String, min: Int) -> Set<String> {
        Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count >= min && !stop.contains($0) })
    }

    /// Words the option itself carries: an email's local part (the domain is
    /// shared by coworkers, so it isn't evidence), a URL's host and path, a
    /// text clip's words, plus the words just before a span in its clip.
    static func optionWords(_ o: PasteOption) -> Set<String> {
        var own: String
        switch o.kind {
        case .email: own = String(o.text.split(separator: "@").first ?? "")
        case .url, .phone, .code, .text: own = o.text
        }
        if o.kind != .text, let r = o.snippet.range(of: o.text) {
            own += " " + String(o.snippet[..<r.lowerBound].suffix(24))
        }
        return words(own, min: 2)
    }

    /// A whole clip that repeats four or more words of the window title restates the page it would be pasted
    /// into. Spans (an email, a URL) are exempt: "Reply to Priya Shah" naming priya.shah@ is evidence.
    public static func echoes(_ o: PasteOption, window: String) -> Bool {
        o.kind == .text && words(o.text, min: 2).intersection(words(window, min: 2)).count >= 4
    }

    /// The one option with evidence, if exactly one has any.
    public static func uniquePick(_ options: [PasteOption], label: String,
                                  window: String, nearby: String) -> PasteOption? {
        let ctx = words(label, min: 2).union(words("\(window) \(nearby)", min: 3))
        guard !ctx.isEmpty else { return nil }
        let all = options.filter { !optionWords($0).isDisjoint(with: ctx) }
        // A span is more specific than the whole clip it came from.
        let hits = all.filter { h in
            !(h.kind == .text && all.contains { $0.kind != .text && $0.clip.id == h.clip.id })
        }
        return hits.count == 1 ? hits[0] : nil
    }
}

public enum OptionBuilder {
    /// Most clips users juggle live in the last screenful of history. Beyond
    /// that, pins are the user's explicit "this matters" — so the window is
    /// the last 20 clips plus every pin. Options cap at 20: model latency
    /// grows with every option line, and typing in the chooser reaches the rest.
    public static let recentWindow = 20
    public static let maxOptions = 20
    /// The model is offered the clipboard plus what you copied in the last 2 hours (and pins); older is a search.
    /// 15 minutes cost 92% → 87% right and 1% → 4% wrong on CueEval: the right address copied an hour ago
    /// fell out, and the one email left pasted with no model call.
    public static let freshFor: TimeInterval = 2 * 3600

    /// Newest first. Each clip contributes every detected email/phone/URL
    /// span plus the clip itself (skipped when the clip IS one span —
    /// identical options would split the model's probability mass).
    /// Exact-text dedupe keeps the newest occurrence.
    public static func options(from clips: [Clip],
                             recent: Int = recentWindow,
                             maxOptions: Int = maxOptions,
                             freshFor: TimeInterval = freshFor,
                             naming typed: Set<String> = []) -> [PasteOption] {
        let cutoff = Date().addingTimeInterval(-freshFor)
        let scope = clips.prefix(recent).enumerated()
            .filter { $0.offset == 0 || $0.element.pinned || $0.element.copiedAt >= cutoff }.map(\.element)
            + clips.dropFirst(recent).filter(\.pinned)
        var seen = Set<String>()
        func options(of clip: Clip) -> [PasteOption] {
            var own: [PasteOption] = []
            for span in SpanExtractor.spansWithContext(in: clip.text) {
                let trimmed = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard seen.insert(trimmed).inserted else { continue }
                own.append(PasteOption(id: "", text: trimmed, kind: span.kind,
                                       clip: clip, snippet: span.context))
            }
            let whole = clip.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.insert(whole).inserted {
                own.append(PasteOption(id: "", text: clip.text, kind: .text,
                                       clip: clip, snippet: clip.preview))
            }
            return own
        }
        var out = scope.flatMap(options(of:))
        // Over the cap, the oldest unpinned options go; pins always stay.
        while out.count > maxOptions, let i = out.lastIndex(where: { !$0.clip.pinned }) {
            out.remove(at: i)
        }
        // Words typed just before the caret ("Sentry:") name a clip the cap dropped: offer it after the rest.
        if !typed.isEmpty {
            let present = Set(out.map(\.clip.id))
            let named = scope.filter { !present.contains($0.id)
                && !ContextSignal.words($0.text, min: 4).isDisjoint(with: typed) }
            seen = Set(out.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) })
            out += named.prefix(2).flatMap(options(of:))
        }
        for i in out.indices { out[i].id = "c\(i + 1)" }
        return out
    }
}

extension SpanExtractor {
    /// A detected span plus the raw text around it.
    public struct SpanInContext: Sendable, Equatable {
        public var text: String
        public var kind: PasteOption.Kind
        /// ±40 chars of surrounding clip text.
        public var context: String
    }

    /// Every email/phone/URL in `text`, in document order, with context.
    public static func spansWithContext(in text: String) -> [SpanInContext] {
        // A pasted log or dump can be megabytes; the detectors take seconds on that. Spans come from the head.
        let text = text.utf16.count > 20_000 ? String(text.prefix(20_000)) : text
        var tagged: [(Int, SpanInContext)] = []
        func collect(_ values: [(String, NSRange)], _ kind: PasteOption.Kind) {
            for (v, r) in values {
                guard let range = Range(r, in: text) else { continue }
                let lo = text.index(range.lowerBound,
                                    offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
                let hi = text.index(range.upperBound,
                                    offsetBy: 40, limitedBy: text.endIndex) ?? text.endIndex
                tagged.append((r.location, SpanInContext(
                    text: v, kind: kind,
                    context: String(text[lo..<hi]).replacingOccurrences(of: "\n", with: " "))))
            }
        }
        collect(emailRanges(in: text), .email)
        collect(phoneRanges(in: text), .phone)
        collect(urlRanges(in: text), .url)
        let taken = tagged.map { NSRange(location: $0.0, length: ($0.1.text as NSString).length) }
        collect(codeRanges(in: text).filter { r in !taken.contains { NSIntersectionRange($0, r.1).length > 0 } }, .code)
        return tagged.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func emailRanges(in text: String) -> [(String, NSRange)] {
        let range = NSRange(text.startIndex..., in: text)
        return Self.emailPattern.matches(in: text, range: range).map {
            (String(text[Range($0.range, in: text)!]), $0.range)
        }
    }

    /// Quoted or backticked names, hex SHAs, prefixed ids (req_…, txn_…), account/order numbers, and amounts with thousands
    /// separators. Whole-clip copies of these are already options; this only splits them out of a line.
    /// Quotes match as pairs (not the `","` between two strings), and a quoted name followed by `:` is a JSON key, not a value.
    static let codePattern = try! NSRegularExpression(pattern: [
        #""([^"\s:,{}\[\]][^"\n]{2,78}[^"\s:,{}\[\]])"(?!\s*:)"#,
        #"`([^`\n]{4,80})`"#,
        #"(?<![-\w])(?=[0-9a-f]*[0-9])(?=[0-9a-f]*[a-f])[0-9a-f]{7,40}(?![-\w])"#,
        #"\b[a-z]{2,8}_[A-Za-z0-9]{6,}\b"#,
        #"(?<![\w.,-])\d{6,}(?![\w.,-])"#,
        #"(?<![\d,])\d{1,3}(?:,\d{3})+(?:\.\d+)?(?!\d|,\d)"#,
    ].joined(separator: "|"))

    static func codeRanges(in text: String) -> [(String, NSRange)] {
        let range = NSRange(text.startIndex..., in: text)
        return codePattern.matches(in: text, range: range).compactMap { m in
            let r = [1, 2].map(m.range(at:)).first { $0.location != NSNotFound } ?? m.range
            return Range(r, in: text).map { (String(text[$0]), r) }
        }
    }

    // Built once: creating a data detector costs more than running it.
    static let phoneDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
    static let linkDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    static func phoneRanges(in text: String) -> [(String, NSRange)] {
        let range = NSRange(text.startIndex..., in: text)
        return phoneDetector.matches(in: text, range: range).compactMap { m in
            m.phoneNumber.map { ($0, m.range) }
        }
    }

    static func urlRanges(in text: String) -> [(String, NSRange)] {
        let range = NSRange(text.startIndex..., in: text)
        return linkDetector.matches(in: text, range: range).compactMap { m in
            guard let s = m.url?.scheme?.lowercased(), s == "http" || s == "https",
                  let abs = m.url?.absoluteString else { return nil }
            return (abs, m.range)
        }
    }
}

/// The chooser's rows: the model's ranking first, then the rest of history newest-first, so typing a few
/// letters reaches any clip or span the model ranked low or never saw. At most 9 rows (keys 1–9).
public enum ChooserRows {
    public static let visible = 9

    public static func rows(ranked: [ScoredOption], history: [Clip], query: String) -> [ScoredOption] {
        let rest = OptionBuilder.options(from: history, recent: .max, maxOptions: .max, freshFor: .infinity)
            .map { ScoredOption(option: $0, probability: 0, confidence: 0) }
        var seen = Set<String>()
        let all = (ranked + rest).filter { seen.insert($0.option.text).inserted }
        let q = query.trimmingCharacters(in: .whitespaces)
        // Rows whose own text has the query come first; a span found only through its clip's text follows.
        let own = all.filter { $0.option.text.localizedCaseInsensitiveContains(q) }
        let hits = q.isEmpty ? all : own + all.filter {
            !$0.option.text.localizedCaseInsensitiveContains(q) && $0.option.clip.text.localizedCaseInsensitiveContains(q)
        }
        guard q.isEmpty else { return Array(hits.prefix(visible)) }
        let picks = Array(all.prefix(ranked.count))
        // The current clipboard always closes the list, so a plain paste is a visible row, not only Esc.
        guard let latest = history.first, !picks.contains(where: { $0.option.text == latest.text }),
              let row = rest.first(where: { $0.option.text == latest.text }) else { return picks }
        return Array(picks.prefix(visible - 1)) + [row]
    }
}
