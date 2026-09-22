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

    static let canvasNS        = nsColor(0xF7F8FA, 0x202226)
    static let sheetNS         = nsColor(0xFFFFFF, 0x2B2E33)
    static let unfoldedNS      = nsColor(0xFCFCFD, 0x26292E)
    static let textPrimaryNS   = nsColor(0x17191D, 0xF4F5F7)
    static let textSecondaryNS = nsColor(0x626873, 0xB3B8C2)
    static let textTertiaryNS  = nsColor(0x646B76, 0xA1A8B3)
    static let separatorNS     = nsColor(0xDFE2E7, 0x454A53)
    static let inputFillNS     = nsColor(0xFFFFFF, 0x22252A)
    static let inputStrokeNS   = nsColor(0xB9C0CB, 0x747D8B)
    static let actionNS        = nsColor(0x0067E6, 0x0067E6)
    static let selectionFillNS = nsColor(0xEDF4FF, 0x25374F)
    static let selectionStrokeNS = nsColor(0xBED5FA, 0x4E719D)
    static let highlightNS     = nsColor(0xFFD0C8, 0xEBA395)
    static let highlightTextNS = nsColor(0x242124, 0x242124)
    static let foldEdgeNS      = nsColor(0xF28F7E, 0xC77869)

    static var canvas: Color { Color(nsColor: canvasNS) }
    static var sheet: Color { Color(nsColor: sheetNS) }
    static var unfolded: Color { Color(nsColor: unfoldedNS) }
    static var textPrimary: Color { Color(nsColor: textPrimaryNS) }
    static var textSecondary: Color { Color(nsColor: textSecondaryNS) }
    static var textTertiary: Color { Color(nsColor: textTertiaryNS) }
    static var separator: Color { Color(nsColor: separatorNS) }
    static var inputFill: Color { Color(nsColor: inputFillNS) }
    static var inputStroke: Color { Color(nsColor: inputStrokeNS) }
    static var action: Color { Color(nsColor: actionNS) }
    static var selectionFill: Color { Color(nsColor: selectionFillNS) }
    static var selectionStroke: Color { Color(nsColor: selectionStrokeNS) }
    static var highlight: Color { Color(nsColor: highlightNS) }
    static var highlightText: Color { Color(nsColor: highlightTextNS) }
    static var foldEdge: Color { Color(nsColor: foldEdgeNS) }
}

extension NSColor {
    convenience init(obHex: UInt32) {
        self.init(srgbRed: CGFloat((obHex >> 16) & 0xFF) / 255,
                  green: CGFloat((obHex >> 8) & 0xFF) / 255,
                  blue: CGFloat(obHex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: - Fold-out surface

/// The signature surface: an upper sheet whose bottom edge overlaps a
/// lower sheet by 12pt, with a small coral lip at the seam. The upper
/// sheet paints over the seam — zIndex keeps the tuck correct.
struct FoldOut<Upper: View, Lower: View>: View {
    var overlap: CGFloat = 12
    var lowerInset: CGFloat = 16   // lower sheet is narrower by this per side
    @ViewBuilder var upper: Upper
    @ViewBuilder var lower: Lower

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: -overlap) {
            upper
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OBTheme.sheet, in: sheetShape)
                .overlay(sheetShape.stroke(sheetEdge, lineWidth: 0.5))
                .shadow(color: .black.opacity(shadowSoft), radius: 2, y: 1)
                .shadow(color: .black.opacity(shadowDeep), radius: 10, y: 6)
                .overlay(alignment: .bottom) { foldLip }
                .zIndex(1)
            lower
                .padding(.horizontal, 24)
                .padding(.top, 16 + overlap) // content clears the tucked seam
                .padding(.bottom, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OBTheme.unfolded, in: sheetShape)
                .overlay(sheetShape.stroke(sheetEdge, lineWidth: 0.5))
                .shadow(color: .black.opacity(shadowDeep), radius: 8, y: 4)
                .padding(.horizontal, lowerInset)
        }
    }

    private var sheetShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }

    private var sheetEdge: Color {
        scheme == .dark ? .white.opacity(0.08) : OBTheme.separator.opacity(0.7)
    }
    private var shadowSoft: Double { scheme == .dark ? 0 : 0.06 }
    private var shadowDeep: Double { scheme == .dark ? 0.18 : 0.09 }

    /// The coral fold lip: a shallow wedge hanging off the upper sheet's
    /// bottom edge. Decorative only.
    private var foldLip: some View {
        FoldLipShape()
            .fill(
                LinearGradient(colors: [OBTheme.unfolded, OBTheme.foldEdge.opacity(0.55)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay(FoldLipShape().stroke(OBTheme.foldEdge, lineWidth: 1))
            .frame(width: 26, height: 11)
            .offset(y: 5.5)
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

/// Shallow downward curve — the tucked edge of the fold.
private struct FoldLipShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        p.closeSubpath()
        return p
    }
}

// MARK: - Shared shell pieces

/// A panel caption — small secondary label inside sheets.
struct OBCaption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(OBTheme.textTertiary)
    }
}

/// Read-only destination preview — looks like a field, exposed as a preview.
struct OBFieldPreview: View {
    var label: String
    var value: String
    var body: some View {
        HStack(spacing: 8) {
            Text(value.isEmpty ? " " : value)
                .font(.system(size: 15))
                .foregroundStyle(OBTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(OBTheme.inputFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(OBTheme.inputStroke, lineWidth: 0.5))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) preview")
        .accessibilityValue(value.isEmpty ? "empty" : value)
    }
}

/// Radio indicator — the spec's 20pt ring beside full-row hit targets.
struct OBRadio: View {
    var selected: Bool
    var body: some View {
        ZStack {
            Circle()
                .stroke(selected ? OBTheme.action : OBTheme.inputStroke, lineWidth: selected ? 1.5 : 1)
                .frame(width: 20, height: 20)
            if selected {
                Circle().fill(OBTheme.action).frame(width: 10, height: 10)
            }
        }
        .accessibilityHidden(true)
    }
}

/// What the footer's primary button should be — screens with stateful
/// primaries (models, practice) publish one of these up to the shell.
struct OBPrimary {
    var title: String
    var enabled = true
    var action: () -> Void = {}
}

/// Primary action — one filled button per screen, fixed position.
struct OBPrimaryButton: View {
    var title: String
    var enabled = true
    var action: () -> Void
    var body: some View {
        Button(title, action: action)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(OBTheme.action)
            .frame(minWidth: 140, maxWidth: 240)
            .disabled(!enabled)
            .keyboardShortcut(.defaultAction)
    }
}

// MARK: - Highlighted paragraph

/// A paragraph of real text with a coral highlight hugging one substring.
/// TextKit does the layout so the highlight tracks wrapping instead of
/// estimating character positions. Reports highlight rects (view-local,
/// top-left origin) so callers can anchor overlays like the transfer chip.
struct HighlightedParagraph: NSViewRepresentable {
    var text: String
    var highlight: String
    var fontSize: CGFloat = 17
    /// Fixed layout width — panels are fixed-geometry, so measure at the
    /// width the sheet actually gives us.
    var width: CGFloat
    var onHighlightRects: ([CGRect]) -> Void = { _ in }

    func makeNSView(context: Context) -> ParagraphNSView {
        let v = ParagraphNSView()
        v.onRects = onHighlightRects
        return v
    }

    func updateNSView(_ v: ParagraphNSView, context: Context) {
        v.onRects = onHighlightRects
        v.update(text: text, highlight: highlight, fontSize: fontSize, width: width)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsview: ParagraphNSView, context: Context) -> CGSize? {
        nsview.update(text: text, highlight: highlight, fontSize: fontSize, width: width)
        return CGSize(width: width, height: nsview.contentHeight)
    }

    final class ParagraphNSView: NSView {
        override var isFlipped: Bool { true }
        var onRects: ([CGRect]) -> Void = { _ in }
        private(set) var contentHeight: CGFloat = 0

        private let storage = NSTextStorage()
        private let layoutManager = NSLayoutManager()
        private let container = NSTextContainer()
        private var highlight = ""

        override init(frame: NSRect) {
            super.init(frame: frame)
            container.lineFragmentPadding = 0
            layoutManager.addTextContainer(container)
            storage.addLayoutManager(layoutManager)
        }
        required init?(coder: NSCoder) { fatalError() }

        func update(text: String, highlight: String, fontSize: CGFloat, width: CGFloat) {
            let para = NSMutableParagraphStyle()
            para.lineHeightMultiple = 25.0 / 17.0
            storage.setAttributedString(NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: OBTheme.textPrimaryNS,
                .paragraphStyle: para,
            ]))
            self.highlight = highlight
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

        /// Per-line enclosing rects of the highlighted substring. The view
        /// isFlipped, so rects already use top-left origin.
        private func highlightRects() -> [CGRect] {
            guard !highlight.isEmpty,
                  let charRange = storage.string.range(of: highlight)
                        .map({ NSRange($0, in: storage.string) })
            else { return [] }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange,
                                                      actualCharacterRange: nil)
            var rects: [CGRect] = []
            layoutManager.enumerateEnclosingRects(
                forGlyphRange: glyphRange,
                withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                in: container
            ) { r, _ in rects.append(r.insetBy(dx: -3, dy: -2)) }
            return rects
        }

        override func draw(_ dirtyRect: NSRect) {
            OBTheme.highlightNS.setFill()
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
