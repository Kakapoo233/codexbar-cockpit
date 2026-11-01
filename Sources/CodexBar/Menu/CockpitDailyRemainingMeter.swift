import AppKit

/// Continuous remaining-allowance meters. A circle is a bottom-up level, rather than a pie sector.
@MainActor
enum CockpitDailyRemainingMeter {
    enum Shape: CaseIterable {
        case bar
        case circle
    }

    static func image(shape: Shape, percent: Double?, size: NSSize, tint: NSColor) -> NSImage {
        let fraction = percent.flatMap { value in
            value.isFinite && (0...100).contains(value) ? value / 100 : nil
        }
        return NSImage(size: size, flipped: false) { rect in
            let outline = self.path(shape: shape, rect: rect.insetBy(dx: 0.75, dy: 0.75))
            let interiorRect = rect.insetBy(dx: 2, dy: 2)
            if let fraction {
                NSGraphicsContext.saveGraphicsState()
                self.path(shape: shape, rect: interiorRect).addClip()
                tint.setFill()
                let filled = switch shape {
                case .bar:
                    NSRect(
                        x: interiorRect.minX,
                        y: interiorRect.minY,
                        width: interiorRect.width * fraction,
                        height: interiorRect.height)
                case .circle:
                    NSRect(
                        x: interiorRect.minX,
                        y: interiorRect.minY,
                        width: interiorRect.width,
                        height: interiorRect.height * fraction)
                }
                filled.fill()
                NSGraphicsContext.restoreGraphicsState()
            } else {
                // An unavailable observation has its own mark, distinct from a measured empty meter.
                let font = NSFont.systemFont(ofSize: max(5, rect.height * 0.65), weight: .semibold)
                let question = NSAttributedString(string: "?", attributes: [.font: font, .foregroundColor: tint])
                let bounds = question.size()
                question.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
            }
            tint.setStroke()
            outline.lineWidth = 1
            outline.stroke()
            return true
        }
    }

    private static func path(shape: Shape, rect: NSRect) -> NSBezierPath {
        switch shape {
        case .bar: NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        case .circle: NSBezierPath(ovalIn: rect)
        }
    }
}
