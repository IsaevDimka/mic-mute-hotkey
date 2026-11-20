import AppKit

// Marketing screenshot: desktop + menu bar with the MicMute icon and menu open.

let w = 1440, h = 900
let size = NSSize(width: w, height: h)

func drawSymbol(_ name: String, in rect: NSRect, color: NSColor, pointSize: CGFloat) {
    let sym = NSImage(systemSymbolName: name, accessibilityDescription: nil)!
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
    let configured = (sym.withSymbolConfiguration(config) ?? sym).copy() as! NSImage
    configured.lockFocus()
    color.setFill()
    NSRect(origin: .zero, size: configured.size).fill(using: .sourceAtop)
    configured.unlockFocus()
    configured.draw(in: rect, from: NSRect(origin: .zero, size: configured.size), operation: .sourceOver, fraction: 1)
}

func drawText(_ s: String, _ frame: NSRect, size: CGFloat, weight: NSFont.Weight, color: NSColor, align: NSTextAlignment = .left) {
    let para = NSMutableParagraphStyle()
    para.alignment = align
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
        .paragraphStyle: para,
    ]
    (s as NSString).draw(in: frame, withAttributes: attrs)
}

let img = NSImage(size: size, flipped: false) { rect in
    // Wallpaper
    let grad = NSGradient(
        starting: NSColor(srgbRed: 0.55, green: 0.68, blue: 0.85, alpha: 1),
        ending: NSColor(srgbRed: 0.85, green: 0.78, blue: 0.72, alpha: 1))!
    grad.draw(in: rect, angle: 65)

    // Menu bar (y from top: 0..34)
    let barHeight: CGFloat = 34
    NSColor(white: 0.96, alpha: 0.92).setFill()
    NSRect(x: 0, y: CGFloat(h) - barHeight, width: CGFloat(w), height: barHeight).fill()
    NSColor(white: 0, alpha: 0.12).setFill()
    NSRect(x: 0, y: CGFloat(h) - barHeight, width: CGFloat(w), height: 1).fill()

    let barY = CGFloat(h) - barHeight
    drawText("MicMute", NSRect(x: 18, y: barY + 8, width: 200, height: 20), size: 14, weight: .bold, color: .black)
    drawText("File    Edit    View    Window    Help", NSRect(x: 100, y: barY + 9, width: 400, height: 18), size: 13, weight: .regular, color: .black)

    // Right side: time + Control Center + mic icon (muted, red)
    drawText("Fri 20 Nov  22:41", NSRect(x: CGFloat(w) - 320, y: barY + 9, width: 150, height: 18), size: 13, weight: .regular, color: .black, align: .right)
    let ccRect = NSRect(x: CGFloat(w) - 158, y: barY + 6, width: 24, height: 22)
    NSColor(white: 0, alpha: 0.08).setFill()
    NSBezierPath(roundedRect: ccRect, xRadius: 6, yRadius: 6).fill()
    drawSymbol("switch.2", in: NSRect(x: ccRect.minX + 4, y: ccRect.minY + 3, width: 16, height: 16), color: .black, pointSize: 12)
    drawSymbol("mic.slash.fill", in: NSRect(x: CGFloat(w) - 126, y: barY + 8, width: 18, height: 18), color: .systemRed, pointSize: 14)

    // Open menu under the mic icon
    let menuW: CGFloat = 280, menuX = CGFloat(w) - 126 - menuW + 30
    let rows: [(String, Bool, Bool)] = [
        ("Microphone: off", false, false),
        ("Toggle (⌥M)", true, false),
        ("—", false, false),
        ("⌨️ ⌥M — active (Carbon)", false, false),
        ("Change Hotkey…  (⌥M)", true, false),
        ("Launch at login", true, false),
        ("—", false, false),
        ("About MicMute", true, false),
        ("GitHub Repository", true, false),
        ("—", false, false),
        ("MicMute v1.1.1, build 3", false, false),
        ("Quit MicMute", true, false),
    ]
    let rowH: CGFloat = 26, menuH = CGFloat(rows.count) * rowH + 16
    let menuY = barY - 8 - menuH

    let shadow = NSShadow()
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -6)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    let menuRect = NSRect(x: menuX, y: menuY, width: menuW, height: menuH)
    NSBezierPath(roundedRect: menuRect, xRadius: 10, yRadius: 10).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    var y = menuRect.maxY - 8 - rowH
    for (title, enabled, _) in rows {
        if title == "—" {
            NSColor(white: 0, alpha: 0.1).setFill()
            NSRect(x: menuRect.minX + 12, y: y + rowH / 2, width: menuW - 24, height: 1).fill()
        } else {
            let color = enabled ? NSColor.black : NSColor(white: 0, alpha: 0.45)
            drawText(title, NSRect(x: menuRect.minX + 16, y: y + 5, width: menuW - 32, height: rowH - 8),
                     size: 13, weight: .regular, color: color)
            if title.hasPrefix("Launch") {
                drawText("✓", NSRect(x: menuRect.maxX - 30, y: y + 5, width: 18, height: rowH - 8),
                         size: 13, weight: .regular, color: .black, align: .right)
            }
        }
        y -= rowH
    }
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
    .write(to: URL(fileURLWithPath: "docs/menu.png"))
print("docs/menu.png saved")
