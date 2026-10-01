// Génère AppIcon.iconset (à convertir avec iconutil) : swift make_icon.swift <dossier.iconset>
import Cocoa

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

/// Dessine l'icône dans un repère de 1024 × 1024.
func drawIcon() {
    // Fond : carré arrondi aux proportions des icônes macOS.
    let background = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 186, yRadius: 186)
    NSGradient(starting: color(0x5B7CFA), ending: color(0x2A3DB8))!.draw(in: background, angle: -90)

    // Touche de clavier.
    let keyRect = NSRect(x: 232, y: 250, width: 560, height: 540)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.shadowBlurRadius = 36
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color(0xD5DAEA).setFill()
    NSBezierPath(roundedRect: keyRect, xRadius: 96, yRadius: 96).fill()
    NSGraphicsContext.restoreGraphicsState()

    let top = NSBezierPath(roundedRect: keyRect.insetBy(dx: 26, dy: 26).offsetBy(dx: 0, dy: 14), xRadius: 76, yRadius: 76)
    NSGradient(starting: .white, ending: color(0xEEF1F9))!.draw(in: top, angle: -90)

    // Virgule et point.
    let ink = color(0x1F2B6C)
    ink.setFill()
    let radius: CGFloat = 52
    let baseline: CGFloat = 452
    let commaCenter = NSPoint(x: 400, y: baseline)
    let periodCenter = NSPoint(x: 624, y: baseline)
    for center in [commaCenter, periodCenter] {
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
    }
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: commaCenter.x + radius, y: commaCenter.y))
    tail.curve(
        to: NSPoint(x: commaCenter.x - radius, y: commaCenter.y - 116),
        controlPoint1: NSPoint(x: commaCenter.x + radius, y: commaCenter.y - 66),
        controlPoint2: NSPoint(x: commaCenter.x, y: commaCenter.y - 106)
    )
    tail.curve(
        to: NSPoint(x: commaCenter.x, y: commaCenter.y - radius),
        controlPoint1: NSPoint(x: commaCenter.x - 16, y: commaCenter.y - 92),
        controlPoint2: NSPoint(x: commaCenter.x, y: commaCenter.y - 76)
    )
    tail.close()
    tail.fill()

    // Flèches d'inversion.
    let accent = color(0x4A67EE)
    accent.setStroke()
    accent.setFill()
    func arrow(from start: NSPoint, to end: NSPoint) {
        let direction: CGFloat = end.x > start.x ? 1 : -1
        let line = NSBezierPath()
        line.lineWidth = 30
        line.lineCapStyle = .round
        line.move(to: start)
        line.line(to: NSPoint(x: end.x - direction * 34, y: end.y))
        line.stroke()
        let head = NSBezierPath()
        head.move(to: NSPoint(x: end.x + direction * 14, y: end.y))
        head.line(to: NSPoint(x: end.x - direction * 50, y: end.y + 48))
        head.line(to: NSPoint(x: end.x - direction * 50, y: end.y - 48))
        head.close()
        head.fill()
    }
    arrow(from: NSPoint(x: 380, y: 684), to: NSPoint(x: 644, y: 684))
    arrow(from: NSPoint(x: 644, y: 598), to: NSPoint(x: 380, y: 598))
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = NSAffineTransform()
    transform.scale(by: CGFloat(pixels) / 1024)
    transform.concat()
    drawIcon()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage : make_icon <dossier.iconset>\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(pixels: points).write(to: output.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(pixels: points * 2).write(to: output.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
