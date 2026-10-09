// Draws the app icon: a small traffic light on a graphite tile, green lit.
// Usage: swift scripts/icon.swift <out.icns>   (needs sips and iconutil, both ship with macOS)
import AppKit

func render(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let k = CGFloat(size) / 1024

    // Tile on Apple's macOS icon grid: 824pt square with a 100pt margin.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k),
                            xRadius: 185 * k, yRadius: 185 * k)
    NSGraphicsContext.saveGraphicsState()
    let drop = NSShadow()
    drop.shadowColor = NSColor.black.withAlphaComponent(0.35)
    drop.shadowBlurRadius = 20 * k
    drop.shadowOffset = NSSize(width: 0, height: -8 * k)
    drop.set()
    NSColor(white: 0.16, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(white: 0.30, alpha: 1), ending: NSColor(white: 0.11, alpha: 1))!.draw(in: tile, angle: -90)

    // Housing.
    let housing = NSBezierPath(roundedRect: NSRect(x: 352 * k, y: 172 * k, width: 320 * k, height: 680 * k),
                               xRadius: 160 * k, yRadius: 160 * k)
    NSColor(white: 0.06, alpha: 1).setFill()
    housing.fill()
    NSColor(white: 1, alpha: 0.08).setStroke()
    housing.lineWidth = 6 * k
    housing.stroke()

    // Lights, top to bottom: red and yellow off, green on with a glow.
    let lights: [(NSColor, Bool, CGFloat)] = [
        (NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1), false, 640),
        (NSColor(srgbRed: 1.00, green: 0.80, blue: 0.00, alpha: 1), false, 432),
        (NSColor(srgbRed: 0.20, green: 0.84, blue: 0.29, alpha: 1), true, 224),
    ]
    for (c, on, y) in lights {
        let r = NSRect(x: 422 * k, y: y * k, width: 180 * k, height: 180 * k)
        NSGraphicsContext.saveGraphicsState()
        if on {
            let glow = NSShadow()
            glow.shadowColor = c.withAlphaComponent(0.9)
            glow.shadowBlurRadius = 70 * k
            glow.set()
        }
        (on ? c : c.blended(withFraction: 0.78, of: NSColor(white: 0.05, alpha: 1))!).setFill()
        NSBezierPath(ovalIn: r).fill()
        NSGraphicsContext.restoreGraphicsState()
        // Soft highlight on the upper part of each lens.
        let hl = NSBezierPath(ovalIn: r.insetBy(dx: 30 * k, dy: 30 * k).offsetBy(dx: 0, dy: 28 * k))
        NSGradient(starting: NSColor(white: 1, alpha: on ? 0.45 : 0.10), ending: NSColor(white: 1, alpha: 0))!
            .draw(in: hl, angle: -90)
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.last { $0.hasSuffix(".icns") } ?? "AppIcon.icns"
let set = NSTemporaryDirectory() + "AppIcon-\(getpid()).iconset"
try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
    try! render(s).write(to: URL(fileURLWithPath: "\(set)/icon_\(s)x\(s).png"))
    try! render(s * 2).write(to: URL(fileURLWithPath: "\(set)/icon_\(s)x\(s)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set, "-o", out]
try! p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(atPath: set)
print("wrote \(out)")
