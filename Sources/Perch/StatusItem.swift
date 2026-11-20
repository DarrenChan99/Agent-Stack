import AppKit

/// Two-bar menu bar icon: left = 5h, right = weekly, filling from the bottom.
enum StatusIcon {
    static let crimson = NSColor(red: 1, green: 0x6B / 255, blue: 0x80 / 255, alpha: 1)

    /// pct: 0...100 or nil (unknown). Past 80% (or DND) the bar outline is a crimson hairline.
    static func image(fiveHour: Double?, weekly: Double?, pending: Int, dnd: Bool) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            for (i, pct) in [fiveHour, weekly].enumerated() {
                let box = NSRect(x: 2 + CGFloat(i) * 8, y: 2, width: 6, height: 14)
                let outline = NSBezierPath(roundedRect: box.insetBy(dx: 0.25, dy: 0.25), xRadius: 1.5, yRadius: 1.5)
                outline.lineWidth = 0.5
                ((pct ?? 0) >= 80 || dnd ? crimson : NSColor.labelColor.withAlphaComponent(0.6)).setStroke()
                outline.stroke()
                let h = box.height * CGFloat(min(max(pct ?? 0, 0), 100)) / 100
                NSColor.labelColor.setFill()
                NSBezierPath(roundedRect: NSRect(x: box.minX, y: box.minY, width: box.width, height: h), xRadius: 1.5, yRadius: 1.5).fill()
            }
            if pending > 0 && !dnd { // crimson ring dot, top right
                let ring = NSBezierPath(ovalIn: NSRect(x: 11.5, y: 11.5, width: 6, height: 6))
                NSColor.black.withAlphaComponent(0.6).setFill(); ring.fill()
                ring.lineWidth = 1.5; crimson.setStroke(); ring.stroke()
            }
            return true
        }
    }
}

@MainActor
final class StatusItemController: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var pendingCount = 0 { didSet { update() } }
    var dnd = false { didSet { update() } }
    var usage: Usage? { didSet { update() } }

    func update() {
        item.button?.image = StatusIcon.image(fiveHour: usage?.fiveHour?.pct, weekly: usage?.weekly?.pct, pending: pendingCount, dnd: dnd)
    }
}
