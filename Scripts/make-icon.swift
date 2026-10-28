// Renders AppIcon.icns: white cloud on an orange squircle.
import AppKit

let out = CommandLine.arguments[1]
let iconset = URL(fileURLWithPath: out).deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(
        starting: NSColor(red: 1, green: 0.55, blue: 0.1, alpha: 1),
        ending: NSColor(red: 1, green: 0.25, blue: 0, alpha: 1)
    )!.draw(in: shape, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .bold)
        .applying(.init(paletteColors: [.white]))
    if let cloud = NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let c = cloud.size
        cloud.draw(in: NSRect(x: (s - c.width) / 2, y: (s - c.height) / 2, width: c.width, height: c.height))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out]
try task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
