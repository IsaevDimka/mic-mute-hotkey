import AppKit

func makeIcon(_ s: Int) -> NSImage {
    let side = CGFloat(s)
    let size = NSSize(width: side, height: side)
    return NSImage(size: size, flipped: false) { rect in
        let path = NSBezierPath(
            roundedRect: rect.insetBy(dx: side * 0.03, dy: side * 0.03),
            xRadius: side * 0.22, yRadius: side * 0.22)
        let grad = NSGradient(
            starting: NSColor(srgbRed: 0.21, green: 0.56, blue: 0.96, alpha: 1),
            ending: NSColor(srgbRed: 0.09, green: 0.33, blue: 0.74, alpha: 1))!
        grad.draw(in: path, angle: -45)

        let sym = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)!
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.58, weight: .medium)
        let configured = (sym.withSymbolConfiguration(config) ?? sym).copy() as! NSImage
        configured.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: configured.size).fill(using: .sourceAtop)
        configured.unlockFocus()
        let micRect = NSRect(
            x: (side - configured.size.width) / 2,
            y: (side - configured.size.height) / 2 + side * 0.02,
            width: configured.size.width,
            height: configured.size.height)
        configured.draw(in: micRect, from: NSRect(origin: .zero, size: configured.size), operation: .sourceOver, fraction: 1)
        return true
    }
}

func savePNG(_ image: NSImage, _ px: Int, _ path: String) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: px, height: px)
    image.draw(in: rect, from: rect, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: path))
}

let out = CommandLine.arguments[1]
try? FileManager.default.removeItem(atPath: out)
try! FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

for (name, px) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    savePNG(makeIcon(px), px, "\(out)/\(name).png")
    print("saved \(name).png")
}
