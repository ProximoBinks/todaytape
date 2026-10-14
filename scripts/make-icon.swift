// Draws the Todaytape app icon (a dark tape with three calendar blocks and the
// red now line) at every size macOS needs, then iconutil packs Todaytape.icns.
// Usage: swift scripts/make-icon.swift <output-dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build", isDirectory: true)
let iconset = out.appendingPathComponent("Todaytape.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        // Design space is 1024 with y down; AppKit is y up.
        NSRect(x: x * s, y: (1024 - y - h) * s, width: w * s, height: h * s)
    }
    // Background squircle (macOS icon grid: 824pt body inset 100).
    let body = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: color(0xF6F2EA), ending: color(0xE4DCCD))!.draw(in: body, angle: -90)
    color(0x000000).withAlphaComponent(0.08).setStroke()
    body.lineWidth = 2 * s
    body.stroke()
    // The tape.
    let shellRect = r(390, 170, 300, 684)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 34 * s
    shadow.shadowOffset = NSSize(width: 0, height: -14 * s)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color(0x16161A).setFill()
    NSBezierPath(roundedRect: shellRect, xRadius: 92 * s, yRadius: 92 * s).fill()
    NSGraphicsContext.restoreGraphicsState()
    // Calendar blocks.
    for (y, h, hex) in [(230.0, 170.0, 0x6FA8DC), (430.0, 120.0, 0x65B8A6), (580.0, 214.0, 0xDEB568)] as [(CGFloat, CGFloat, UInt32)] {
        color(hex).setFill()
        NSBezierPath(roundedRect: r(440, y, 200, h), xRadius: 44 * s, yRadius: 44 * s).fill()
    }
    // The now line and its head.
    color(0xFF3B30).setFill()
    NSBezierPath(rect: r(250, 476, 390, 28)).fill()
    NSBezierPath(ovalIn: r(196, 430, 120, 120)).fill()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try draw(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try draw(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("Todaytape.icns").path]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else { fatalError("iconutil failed") }
try draw(1024).write(to: out.appendingPathComponent("Todaytape-1024.png"))
try? FileManager.default.removeItem(at: iconset)
print("Wrote \(out.appendingPathComponent("Todaytape.icns").path)")
