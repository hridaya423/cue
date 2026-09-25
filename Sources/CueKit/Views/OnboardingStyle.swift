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

    static let canvasNS        = nsColor(0xFAFAFB, 0x202226)
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

struct FoldOut<Upper: View, Lower: View>: View {
    var showsFold = true
    var verticalPadding: CGFloat = 24
    var lowerTopPadding: CGFloat = 28
    var overlap: CGFloat = 12
    var lowerInset: CGFloat = 16   // lower sheet is narrower by this per side
    var arrowX: CGFloat? = nil
    @ViewBuilder var upper: Upper
    @ViewBuilder var lower: Lower

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: -overlap) {
            upper
                .padding(.horizontal, 24)
                .padding(.vertical, verticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OBTheme.sheet, in: sheetShape)
                .overlay(sheetShape.stroke(sheetEdge, lineWidth: 0.5))
                .shadow(color: .black.opacity(shadowSoft), radius: 2, y: 1)
                .shadow(color: .black.opacity(shadowDeep), radius: 10, y: 6)
                .overlay(alignment: .bottom) {
                    if showsFold && arrowX == nil { foldArrow }
                }
                .overlay(alignment: .bottomLeading) {
                    if showsFold, let arrowX { foldArrow.padding(.leading, max(0, arrowX - 15)) }
                }
                .zIndex(1)
            lower
                .padding(.horizontal, 24)
                .padding(.top, lowerTopPadding + overlap) // content clears the tucked seam
                .padding(.bottom, 20)
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

    private var foldArrow: some View {
        FoldArrowShape()
            .stroke(
                OBTheme.foldEdge,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 34, height: 44)
            .offset(y: 18)
            .shadow(color: OBTheme.foldEdge.opacity(0.25), radius: 3, x: 2, y: 2)
            .accessibilityHidden(true)
    }
}

private struct FoldArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        let tip = CGPoint(x: rect.maxX - 2, y: rect.maxY - 6)
        p.addCurve(to: tip,
                   control1: CGPoint(x: rect.minX, y: rect.maxY * 0.8),
                   control2: CGPoint(x: rect.midX, y: rect.maxY - 4))
        p.move(to: CGPoint(x: tip.x - 8, y: tip.y - 2))
        p.addLine(to: tip)
        p.addLine(to: CGPoint(x: tip.x - 2, y: tip.y - 8))
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
            .font(.system(size: 13))
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
        .frame(width: 20, height: 20)
        .fixedSize()
        .accessibilityHidden(true)
    }
}

struct PermissionSwitchDemo: View {
    var granted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false
    @State private var switched = false
    @State private var pressing = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Capsule()
                .fill(switched || granted ? OBTheme.action : OBTheme.inputStroke)
                .frame(width: 40, height: 24)
                .overlay {
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                        .offset(x: switched || granted ? 8 : -8)
                }
            if !reduceMotion && !granted {
                Image(systemName: "cursorarrow")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(OBTheme.textPrimary)
                    .shadow(color: OBTheme.sheet, radius: 1)
                    .scaleEffect(pressing ? 0.88 : 1, anchor: .topLeading)
                    .offset(x: arrived ? 0 : -40, y: arrived ? 9 : 25)
            }
        }
        .frame(width: 86, height: 54, alignment: .trailing)
        .accessibilityHidden(true)
        .task(id: granted || reduceMotion) {
            guard !granted && !reduceMotion else {
                arrived = false
                pressing = false
                switched = granted
                return
            }
            switched = false
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.62)) { arrived = true }
            try? await Task.sleep(for: .milliseconds(660))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.12)) { pressing = true }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { switched = true; pressing = false }
        }
    }
}

/// What the footer's primary button should be — screens with stateful
/// primaries (models, practice) publish one of these up to the shell.
struct OBPrimary {
    var title: String
    var enabled = true
    var action: () -> Void = {}
}

struct OBPrimaryButton: View {
    var title: String
    var enabled = true
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .frame(minWidth: 140, minHeight: 38)
        }
        .buttonStyle(OBButtonStyle(fill: OBTheme.action))
        .frame(minWidth: 140, maxWidth: 240)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .keyboardShortcut(.defaultAction)
    }
}

private struct OBButtonStyle: ButtonStyle {
    var fill: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(LinearGradient(colors: [fill, fill.opacity(0.92)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct OBBackButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Label("Back", systemImage: "chevron.left")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OBTheme.textSecondary)
                .padding(.horizontal, 14)
                .frame(height: 38)
        }
        .buttonStyle(OBButtonStyle(fill: OBTheme.textTertiary.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(OBTheme.separator, lineWidth: 0.5))
        .frame(minWidth: 64)
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
    var onHighlightRects: ([CGRect]) -> Void = { _ in }

    func makeNSView(context: Context) -> ParagraphNSView {
        let v = ParagraphNSView()
        v.onRects = onHighlightRects
        return v
    }

    func updateNSView(_ v: ParagraphNSView, context: Context) {
        v.onRects = onHighlightRects
        v.update(text: text, highlights: highlights, fontSize: fontSize, width: width)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsview: ParagraphNSView, context: Context) -> CGSize? {
        nsview.update(text: text, highlights: highlights, fontSize: fontSize, width: width)
        return CGSize(width: width, height: nsview.contentHeight)
    }

    final class ParagraphNSView: NSView {
        override var isFlipped: Bool { true }
        var onRects: ([CGRect]) -> Void = { _ in }
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
            para.minimumLineHeight = fontSize * 1.4
            para.maximumLineHeight = fontSize * 1.4
            storage.setAttributedString(NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: fontSize),
                .foregroundColor: OBTheme.textPrimaryNS,
                .paragraphStyle: para,
            ]))
            for span in highlights where !span.isEmpty {
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

        private func highlightRects() -> [CGRect] {
            var rects: [CGRect] = []
            for span in highlights where !span.isEmpty {
                guard let charRange = storage.string.range(of: span)
                        .map({ NSRange($0, in: storage.string) })
                else { continue }
                let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange,
                                                          actualCharacterRange: nil)
                layoutManager.enumerateEnclosingRects(
                    forGlyphRange: glyphRange,
                    withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0),
                    in: container
                ) { r, _ in rects.append(r.insetBy(dx: -3, dy: -2)) }
            }
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
