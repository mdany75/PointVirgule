import Cocoa

/// Icône de la barre des menus : une touche de clavier avec « , » et « . ».
enum MenuBarIcon {
    static func make() -> NSImage {
        let size = NSSize(width: 21, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let key = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.5, yRadius: 3.5)
            key.lineWidth = 1.25
            key.stroke()

            drawComma(at: NSPoint(x: 7.2, y: 8.2))
            drawPeriod(at: NSPoint(x: 14.2, y: 8.2))
            return true
        }
        image.isTemplate = true
        return image
    }

    private static let dotRadius: CGFloat = 1.9

    private static func drawPeriod(at center: NSPoint) {
        NSBezierPath(ovalIn: NSRect(
            x: center.x - dotRadius, y: center.y - dotRadius,
            width: dotRadius * 2, height: dotRadius * 2
        )).fill()
    }

    private static func drawComma(at center: NSPoint) {
        drawPeriod(at: center)
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: center.x + dotRadius, y: center.y))
        tail.curve(
            to: NSPoint(x: center.x - dotRadius, y: center.y - 4.6),
            controlPoint1: NSPoint(x: center.x + dotRadius, y: center.y - 2.6),
            controlPoint2: NSPoint(x: center.x, y: center.y - 4.2)
        )
        tail.curve(
            to: NSPoint(x: center.x, y: center.y - dotRadius),
            controlPoint1: NSPoint(x: center.x - 0.6, y: center.y - 3.6),
            controlPoint2: NSPoint(x: center.x, y: center.y - 2.8)
        )
        tail.close()
        tail.fill()
    }
}
