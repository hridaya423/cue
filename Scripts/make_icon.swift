// Generates Cue's app icon: a coral squircle (the brand's foldEdge) with
// a subtle vertical gradient and a white clipboard glyph centered.
// Usage: swift Scripts/make_icon.swift <out.iconset dir>
// Then:  iconutil -c icns <out.iconset> -o Resources/AppIcon.icns
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "Cue.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: out)
try! fm.createDirectory(atPath: out, withIntermediateDirectories: true)

// Apple icon canvas: the icon sits at 824/1024 scale inside the canvas
// (the standard "safe area" for Big Sur+ squircle icons).
func draw(_ px: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: px, height: px), flipped: false) { rect in
        let s = px / 1024.0
        let icon = rect.insetBy(dx: 100 * s, dy: 100 * s)

        // Squircle — continuous-corner rounded rect approximates the
        // macOS superellipse closely at icon sizes.
        let path = NSBezierPath(roundedRect: icon,
                                xRadius: icon.width * 0.225,
                                yRadius: icon.height * 0.225)

        // Vertical gradient: lighter coral top -> deeper foldEdge bottom.
        let top = NSColor(calibratedRed: 0.965, green: 0.510, blue: 0.443, alpha: 1)   // #F68271
        let bot = NSColor(calibratedRed: 0.929, green: 0.380, blue: 0.318, alpha: 1)   // #EE6151
        NSGradient(colors: [top, bot])!.draw(in: path, angle: -90)

        // Clip to the squircle for the glyph + sheen.
        NSGraphicsContext.current!.saveGraphicsState()
        path.addClip()

        // Soft top sheen — a highlight band, not a glass gloss.
        let sheen = NSBezierPath(roundedRect: NSRect(x: icon.minX, y: icon.maxY - icon.height * 0.34,
                                                     width: icon.width, height: icon.height * 0.34),
                                 xRadius: icon.width * 0.2, yRadius: icon.height * 0.2)
        NSColor.white.withAlphaComponent(0.10).setFill()
        sheen.fill()
        NSGraphicsContext.current!.restoreGraphicsState()

        // White clipboard glyph, optically centered, ~46% of icon height.
        let glyphH = icon.height * 0.46
        if let sym = NSImage(systemSymbolName: "list.clipboard",
                             accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: glyphH / 1.35, weight: .medium)) {
            let tinted = NSImage(size: sym.size, flipped: false) { r in
                sym.draw(in: r)
                NSColor.white.set()
                r.fill(using: .sourceAtop)
                return true
            }
            let glyphRect = NSRect(
                x: icon.midX - tinted.size.width / 2,
                y: icon.midY - tinted.size.height / 2 - icon.height * 0.02,
                width: tinted.size.width, height: tinted.size.height)
            // Soft drop shadow under the glyph for depth.
            NSGraphicsContext.current!.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = 10 * s
            shadow.shadowOffset = NSSize(width: 0, height: -6 * s)
            shadow.set()
            tinted.draw(in: glyphRect)
            NSGraphicsContext.current!.restoreGraphicsState()
        }
        return true
    }
    return img
}

func write(_ img: NSImage, _ name: String) {
    var r = CGRect(origin: .zero, size: img.size)
    let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil)!
    let rep = NSBitmapImageRep(cgImage: cg)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
}

// iconset naming: base sizes 16,32,128,256,512 at 1x and @2x (covers 1024).
for base in [16, 32, 128, 256, 512] {
    write(draw(CGFloat(base)), "icon_\(base)x\(base).png")
    write(draw(CGFloat(base * 2)), "icon_\(base)x\(base)@2x.png")
}
print("wrote \(out)")
