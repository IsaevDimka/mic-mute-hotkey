import AppKit

let w = 1080, h = 720
let size = NSSize(width: w, height: h)
let img = NSImage(size: size, flipped: false) { rect in
    let grad = NSGradient(
        starting: NSColor(srgbRed: 0.97, green: 0.98, blue: 1.0, alpha: 1),
        ending: NSColor(srgbRed: 0.87, green: 0.91, blue: 0.98, alpha: 1))!
    grad.draw(in: rect, angle: 90)

    func drawText(_ s: String, center: NSPoint, font: NSFont, color: NSColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let ns = s as NSString
        let sz = ns.size(withAttributes: attrs)
        ns.draw(at: NSPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2), withAttributes: attrs)
    }

    let gray = NSColor(srgbRed: 0.45, green: 0.55, blue: 0.70, alpha: 1)
    gray.setStroke()

    // Стрелка между позициями иконок (центр ~318pt по x -> 636px, y=218pt от низа -> 284px)
    let shaft = NSBezierPath()
    shaft.lineWidth = 14
    shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: 556, y: 284))
    shaft.line(to: NSPoint(x: 700, y: 284))
    shaft.stroke()

    let head = NSBezierPath()
    head.lineWidth = 14
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.move(to: NSPoint(x: 676, y: 318))
    head.line(to: NSPoint(x: 716, y: 284))
    head.line(to: NSPoint(x: 676, y: 250))
    head.stroke()

    drawText("MicMute", center: NSPoint(x: 540, y: 640),
             font: .systemFont(ofSize: 72, weight: .bold),
             color: NSColor(srgbRed: 0.12, green: 0.16, blue: 0.24, alpha: 1))
    drawText("Перетащите приложение в папку «Программы»", center: NSPoint(x: 540, y: 80),
             font: .systemFont(ofSize: 42, weight: .medium),
             color: NSColor(srgbRed: 0.35, green: 0.40, blue: 0.50, alpha: 1))
    return true
}

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let rect = NSRect(x: 0, y: 0, width: w, height: h)
img.draw(in: rect, from: rect, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("background saved")
