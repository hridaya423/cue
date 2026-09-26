import Foundation

// MARK: - Paste options

/// One thing that could land in the field: either a whole clip or a detected
/// span (email / phone / URL) inside one. The model only ever ranks options —
/// the pasted text is always one of these exact strings. Model chooses, we
/// execute.
public struct PasteOption: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        case email, phone, url, text
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
        let s = "\(label) \(placeholder) \(nearby)".lowercased()
        func has(_ words: [String]) -> Bool { words.contains { s.contains($0) } }
        if has(["email", "e-mail", "mail address"]) { return .email }
        if has(["phone", "mobile", "tel", "fax"]) { return .phone }
        if has(["url", "website", "link", "domain"]) { return .url }
        if has(["first name", "last name", "full name", "name"]) { return .name }
        return .generic
    }

    /// Would `text`, pasted exactly as copied, already fit this field? The
    /// ⌘V-intercept contract: when it does, a plain paste is the answer and
    /// no model call is made (fast, and never a surprise popup on ⌘V).
    /// Generic fields take anything; typed fields need the whole text to be
    /// one span of that type; name fields need text with no detected span.
    public func acceptsVerbatim(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let spans = SpanExtractor.spansWithContext(in: t)
        let want: PasteOption.Kind
        switch self {
        case .generic: return true
        case .name: return spans.isEmpty
        case .email: want = .email
        case .phone: want = .phone
        case .url: want = .url
        }
        return spans.count == 1 && spans[0].kind == want && spans[0].text == t
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

public enum OptionBuilder {
    /// Most clips users juggle live in the last screenful of history. Beyond
    /// that, pins are the user's explicit "this matters" — so the window is
    /// the last 20 clips plus every pin. Options cap at 30: small models
    /// degrade with long criteria lists.
    public static let recentWindow = 20
    public static let maxOptions = 30

    /// Newest first. Each clip contributes every detected email/phone/URL
    /// span plus the clip itself (skipped when the clip IS one span —
    /// identical options would split the model's probability mass).
    /// Exact-text dedupe keeps the newest occurrence.
    public static func options(from clips: [Clip],
                             recent: Int = recentWindow,
                             maxOptions: Int = maxOptions) -> [PasteOption] {
        let scope = clips.prefix(recent) + clips.dropFirst(recent).filter(\.pinned)
        var seen = Set<String>()
        var out: [PasteOption] = []
        for clip in scope {
            for span in SpanExtractor.spansWithContext(in: clip.text) {
                let trimmed = span.text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard seen.insert(trimmed).inserted else { continue }
                out.append(PasteOption(
                    id: "", text: trimmed, kind: span.kind,
                    clip: clip, snippet: span.context))
            }
            let whole = clip.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if seen.insert(whole).inserted {
                out.append(PasteOption(id: "", text: clip.text, kind: .text,
                                       clip: clip, snippet: clip.preview))
            }
        }
        out = Array(out.prefix(maxOptions))
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
        return tagged.sorted { $0.0 < $1.0 }.map(\.1)
    }

    static func emailRanges(in text: String) -> [(String, NSRange)] {
        let range = NSRange(text.startIndex..., in: text)
        return Self.emailPattern.matches(in: text, range: range).map {
            (String(text[Range($0.range, in: text)!]), $0.range)
        }
    }

    static func phoneRanges(in text: String) -> [(String, NSRange)] {
        let range = NSRange(text.startIndex..., in: text)
        let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue)
        return det?.matches(in: text, range: range).compactMap { m in
            m.phoneNumber.map { ($0, m.range) }
        } ?? []
    }

    static func urlRanges(in text: String) -> [(String, NSRange)] {
        let range = NSRange(text.startIndex..., in: text)
        let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        return det?.matches(in: text, range: range).compactMap { m in
            guard let s = m.url?.scheme?.lowercased(), s == "http" || s == "https",
                  let abs = m.url?.absoluteString else { return nil }
            return (abs, m.range)
        } ?? []
    }
}
