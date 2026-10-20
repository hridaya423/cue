// Usage: swift Scripts/make_icon.swift <out.iconset dir>
// Then:  iconutil -c icns <out.iconset> -o Resources/AppIcon.icns
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "Cue.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: out)
try! fm.createDirectory(atPath: out, withIntermediateDirectories: true)

let runs: [(Int, CGFloat, CGFloat)] = [
    (0, 0.0857, 0.2597), (0, 0.3481, 0.4431), (0, 0.5529, 0.6479), (0, 0.7470, 0.9197),
    (1, 0.0375, 0.3066), (1, 0.3481, 0.4431), (1, 0.5529, 0.6479), (1, 0.7028, 0.9639),
    (2, 0.0147, 0.1191), (2, 0.2222, 0.3280), (2, 0.3481, 0.4431), (2, 0.5529, 0.6479),
    (2, 0.6801, 0.7791), (2, 0.8902, 0.9853), (3, 0.0027, 0.1004), (3, 0.3481, 0.4431),
    (3, 0.5529, 0.6479), (3, 0.6680, 0.7644), (3, 0.9023, 0.9960),
    (4, 0.0000, 0.0964), (4, 0.3481, 0.4431), (4, 0.5529, 0.6479), (4, 0.6653, 1.0000),
    (5, 0.0027, 0.1004), (5, 0.2383, 0.3079), (5, 0.3481, 0.4431), (5, 0.5515, 0.6479),
    (5, 0.6680, 0.7644),
    (6, 0.0147, 0.1191), (6, 0.2236, 0.3280), (6, 0.3494, 0.4525), (6, 0.5382, 0.6479),
    (6, 0.6801, 0.7791), (6, 0.8929, 0.9920),
    (7, 0.0375, 0.3066), (7, 0.3614, 0.5582), (7, 0.5596, 0.6479), (7, 0.7015, 0.9719),
    (8, 0.0830, 0.2610), (8, 0.3909, 0.5288), (8, 0.5609, 0.6479), (8, 0.7470, 0.9264),
]

func draw(_ px: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: px, height: px), flipped: true) { rect in
        let s = px / 1024.0
        let icon = rect.insetBy(dx: 100 * s, dy: 100 * s)
        let squircle = NSBezierPath(roundedRect: icon, xRadius: icon.width * 0.225, yRadius: icon.height * 0.225)
        NSColor(srgbRed: 0.114, green: 0.251, blue: 0.941, alpha: 1).setFill()
        squircle.fill()

        let w = icon.width * 0.74, h = w / 2.8295
        let origin = CGPoint(x: icon.midX - w / 2, y: icon.midY - h / 2)
        let pitch = h / 9, bar = pitch * 0.62
        NSColor(srgbRed: 0.965, green: 0.969, blue: 0.984, alpha: 1).setFill()
        for (row, from, to) in runs {
            let r = NSRect(x: origin.x + from * w, y: origin.y + CGFloat(row) * pitch + (pitch - bar) / 2,
                           width: (to - from) * w, height: bar)
            NSBezierPath(roundedRect: r, xRadius: bar / 2, yRadius: bar / 2).fill()
        }
        return true
    }
}

func write(_ img: NSImage, _ name: String) {
    var r = CGRect(origin: .zero, size: img.size)
    let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil)!
    let rep = NSBitmapImageRep(cgImage: cg)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: out).appendingPathComponent(name))
}

for base in [16, 32, 128, 256, 512] {
    write(draw(CGFloat(base)), "icon_\(base)x\(base).png")
    write(draw(CGFloat(base * 2)), "icon_\(base)x\(base)@2x.png")
}
print("wrote \(out)")
