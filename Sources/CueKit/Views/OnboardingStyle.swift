import AppKit
import SwiftUI

// MARK: - Tokens (DESIGN.md)

/// Light/dark token pairs from DESIGN.md. NSColor-backed so both SwiftUI
/// views and the AppKit paragraph renderer share one source of truth.
/// The window follows the system theme — no forced color scheme.
enum OBTheme {
    static func nsColor(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil, dynamicProvider: { appearance in
            let darkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(obHex: darkMode ? dark : light)
        })
    }

    static let canvasNS        = nsColor(0xFDFDFB, 0x202226)
    static let sheetNS         = nsColor(0xFBFAF8, 0x2B2E33)
    static let insetFillNS     = nsColor(0xF3F2F0, 0x2A2C31)
    static let textPrimaryNS   = nsColor(0x17191D, 0xF4F5F7)
    static let textSecondaryNS = nsColor(0x626873, 0xB3B8C2)
    static let textTertiaryNS  = nsColor(0x646B76, 0xA1A8B3)
    static let separatorNS     = nsColor(0xE7E5E2, 0x454A53)
    static let inputFillNS     = nsColor(0xFFFFFF, 0x22252A)
    static let inputStrokeNS   = nsColor(0xC9C6C1, 0x747D8B)
    static let actionNS        = nsColor(0x1463EC, 0x1463EC)
    static let markNS          = nsColor(0x1463EC, 0x5C97FF)
    static let actionTopNS     = nsColor(0x2A7FF6, 0x2A7FF6)
    static let actionBottomNS  = nsColor(0x0F5FEA, 0x0F5FEA)
    static let selectionFillNS = nsColor(0xEDF4FF, 0x25374F)
    static let selectionStrokeNS = nsColor(0xBED5FA, 0x4E719D)
    static let highlightNS     = nsColor(0xF8C0B6, 0xEBA395)
    static let highlightTextNS = nsColor(0x242124, 0x242124)

    static var canvas: Color { Color(nsColor: canvasNS) }
    static var sheet: Color { Color(nsColor: sheetNS) }
    static var insetFill: Color { Color(nsColor: insetFillNS) }
    static var textPrimary: Color { Color(nsColor: textPrimaryNS) }
    static var textSecondary: Color { Color(nsColor: textSecondaryNS) }
    static var textTertiary: Color { Color(nsColor: textTertiaryNS) }
    static var separator: Color { Color(nsColor: separatorNS) }
    static var inputFill: Color { Color(nsColor: inputFillNS) }
    static var inputStroke: Color { Color(nsColor: inputStrokeNS) }
    static var action: Color { Color(nsColor: actionNS) }
    static var mark: Color { Color(nsColor: markNS) }
    static var actionGradient: LinearGradient {
        LinearGradient(colors: [Color(nsColor: actionTopNS), Color(nsColor: actionBottomNS)],
                       startPoint: .top, endPoint: .bottom)
    }
    static var selectionFill: Color { Color(nsColor: selectionFillNS) }
    static var selectionStroke: Color { Color(nsColor: selectionStrokeNS) }
    static var highlight: Color { Color(nsColor: highlightNS) }
    static var highlightText: Color { Color(nsColor: highlightTextNS) }
}

extension NSColor {
    convenience init(obHex: UInt32) {
        self.init(srgbRed: CGFloat((obHex >> 16) & 0xFF) / 255,
                  green: CGFloat((obHex >> 8) & 0xFF) / 255,
                  blue: CGFloat(obHex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Fold-out surface

// MARK: - Shared shell pieces

/// Radio indicator — a filled blue disc with a white dot beside
/// full-row hit targets; a plain ring when unselected.
struct OBRadio: View {
    var selected: Bool
    var body: some View {
        ZStack {
            Circle()
                .fill(selected ? OBTheme.action : .clear)
                .overlay(Circle().stroke(OBTheme.inputStroke,
                                         lineWidth: selected ? 0 : 1))
                .frame(width: 20, height: 20)
            if selected {
                Circle().fill(.white).frame(width: 8, height: 8)
            }
        }
        .frame(width: 20, height: 20)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

/// What the footer's primary button should be — screens with stateful
/// primaries (models, practice) publish one of these up to the shell.
struct OBPrimary {
    var title: String
    var enabled = true
    var action: () -> Void = {}
    /// A step waiting on the user's own keystroke shows no button: a greyed one reads as broken.
    static var none: OBPrimary { OBPrimary(title: "", enabled: false) }
}

/// Any secondary action drawn as a bordered rounded rect ("Try Website",
/// "Try another" beside the practice field).
struct OBBorderedButton: View {
    var title: String
    var action: () -> Void
    var body: some View {
        Button(title, action: action).modifier(OBBorderedLabel())
    }
}

private struct OBBorderedLabel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OBTheme.textSecondary)
            .padding(.horizontal, 14)
            .frame(minWidth: 64, minHeight: 36)
            .buttonStyle(.plain)
            .background(OBTheme.inputFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(OBTheme.inputStroke, lineWidth: 0.75))
    }
}

// MARK: - Highlighted paragraph

/// A paragraph of real text with a coral highlight hugging one substring.
/// TextKit does the layout so the highlight tracks wrapping instead of
/// estimating character positions. Reports highlight rects (view-local,
/// top-left origin) so callers can anchor overlays like the transfer chip.
struct HighlightedParagraph: NSViewRepresentable {
    var text: String
    var highlights: [String]
    var fontSize: CGFloat = 17
    /// Fixed layout width — panels are fixed-geometry, so measure at the
    /// width the sheet actually gives us.
    var width: CGFloat
    /// Redaction placeholders: a neutral chip, so coral keeps one meaning — the detail Cue found.
    var masked = false
    var onHighlightRects: ([CGRect]) -> Void = { _ in }

    func makeNSView(context: Context) -> ParagraphNSView {
        let v = ParagraphNSView()
        v.onRects = onHighlightRects
        return v
    }

    func updateNSView(_ v: ParagraphNSView, context: Context) {
        v.onRects = onHighlightRects
        v.masked = masked
        v.update(text: text, highlights: highlights, fontSize: fontSize, width: width)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsview: ParagraphNSView, context: Context) -> CGSize? {
        nsview.masked = masked
        nsview.update(text: text, highlights: highlights, fontSize: fontSize, width: width)
        return CGSize(width: width, height: nsview.contentHeight)
    }

    final class ParagraphNSView: NSView {
        override var isFlipped: Bool { true }
        var onRects: ([CGRect]) -> Void = { _ in }
        var masked = false
        private(set) var contentHeight: CGFloat = 0

        private let storage = NSTextStorage()
        private let layoutManager = NSLayoutManager()
        private let container = NSTextContainer()
        private var highlights: [String] = []

        override init(frame: NSRect) {
            super.init(frame: frame)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            storage.addLayoutManager(layoutManager)
        }
        required init?(coder: NSCoder) { fatalError() }

        func update(text: String, highlights: [String], fontSize: CGFloat, width: CGFloat) {
            let para = NSMutableParagraphStyle()
            para.minimumLineHeight = fontSize * 1.3
            para.maximumLineHeight = fontSize * 1.3
            storage.setAttributedString(NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: OBTheme.textPrimaryNS,
                .paragraphStyle: para,
            ]))
            for span in highlights where !span.isEmpty && !masked {
                if let range = text.range(of: span) {
                    storage.addAttribute(.foregroundColor, value: OBTheme.highlightTextNS,
                                         range: NSRange(range, in: text))
                }
            }
            self.highlights = highlights
            container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: container)
            let h = ceil(layoutManager.usedRect(for: container).height)
            if h != contentHeight { contentHeight = h; invalidateIntrinsicContentSize() }
            needsDisplay = true
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: contentHeight)
        }

        override func layout() {
            super.layout()
            if bounds.width > 0, container.containerSize.width != bounds.width {
                container.containerSize = NSSize(width: bounds.width,
                                               height: .greatestFiniteMagnitude)
                needsDisplay = true
            }
        }

        // One rect per line of each span: baseline − ascent … baseline −
        // descent so the coral hugs the glyphs, padded 3×2.
        private func highlightRects() -> [CGRect] {
            var rects: [CGRect] = []
            let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                ?? .systemFont(ofSize: 17)
            for span in highlights where !span.isEmpty {
                guard let charRange = storage.string.range(of: span)
                        .map({ NSRange($0, in: storage.string) })
                else { continue }
                let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange,
                                                          actualCharacterRange: nil)
                layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
                    lineRect, _, textContainer, fragGlyphRange, _ in
                    // fragGlyphRange is the fragment's whole range — clip it
                    // to the span's glyphs or the coral paints the full line.
                    let spanInLine = NSIntersectionRange(glyphRange, fragGlyphRange)
                    let g = self.layoutManager.boundingRect(forGlyphRange: spanInLine,
                                                            in: textContainer)
                    let baseline = lineRect.minY
                        + self.layoutManager.location(forGlyphAt: fragGlyphRange.location).y
                    rects.append(
                        CGRect(x: g.minX,
                               y: baseline - font.ascender,
                               width: g.width,
                               height: font.ascender - font.descender)
                        .insetBy(dx: -1.5, dy: -2)) // narrower than a space, so words stay apart
                }
            }
            return rects
        }

        override func draw(_ dirtyRect: NSRect) {
            (masked ? NSColor.secondaryLabelColor.withAlphaComponent(0.16) : OBTheme.highlightNS).setFill()
            let rects = highlightRects()
            for r in rects {
                NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
            }
            let used = layoutManager.glyphRange(for: container)
            layoutManager.drawGlyphs(forGlyphRange: used, at: .zero)
            // Report after draw — deferred so SwiftUI state isn't mutated
            // mid-render.
            DispatchQueue.main.async { [onRects] in onRects(rects) }
        }
    }
}
