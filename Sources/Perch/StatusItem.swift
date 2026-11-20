import AppKit

/// Aggregate agent state for the menu-bar ring; most actionable wins.
enum AgentDot: Equatable {
    case none, done, working, needsYou

    static func from(statuses: [AgentStatus], pending: Int) -> AgentDot {
        if pending > 0 || statuses.contains(.waiting) { return .needsYou }
        if statuses.isEmpty { return .none }
        return statuses.contains { $0 != .idle } ? .working : .done
    }

    /// Ring color + alpha at time t: red flashes 1Hz, blue fades over 2s, green is still.
    func look(at t: TimeInterval) -> (NSColor, CGFloat)? {
        switch self {
        case .none: nil
        case .done: (NSColor(red: 0x6E / 255, green: 0xE7 / 255, blue: 0xB0 / 255, alpha: 1), 1)
        case .needsYou: (StatusIcon.crimson, t.truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : 0.15)
        case .working: (NSColor(red: 0x6E / 255, green: 0xA8 / 255, blue: 1, alpha: 1), 0.35 + 0.65 * (0.5 + 0.5 * sin(t * .pi)))
        }
    }
}

/// Two-bar menu bar icon: left = 5h, right = weekly, filling from the bottom.
enum StatusIcon {
    static let crimson = NSColor(red: 1, green: 0x6B / 255, blue: 0x80 / 255, alpha: 1)

    /// pct: 0...100 or nil (unknown). Past 80% (or DND) the bar outline is a crimson hairline.
    static func image(fiveHour: Double?, weekly: Double?, ring: (NSColor, CGFloat)?, dnd: Bool) -> NSImage {
        NSImage(size: NSSize(width: ring == nil ? 18 : 26, height: 18), flipped: false) { _ in
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
            if let (color, alpha) = ring { // hollow ring dot, right of the bars
                let ring = NSBezierPath(ovalIn: NSRect(x: 19, y: 6, width: 6, height: 6))
                NSColor.black.withAlphaComponent(0.6 * alpha).setFill(); ring.fill()
                ring.lineWidth = 1.5; color.withAlphaComponent(alpha).setStroke(); ring.stroke()
            }
            return true
        }
    }
}

@MainActor
final class StatusItemController: NSObject {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var dot = AgentDot.none { didSet { if dot != oldValue { retime() } } }
    var dnd = false { didSet { update() } }
    var usage: Usage? { didSet { update() } }
    private var timer: Timer?

    func update() {
        let ring = dnd && dot == .needsYou ? nil : dot.look(at: Date().timeIntervalSinceReferenceDate)
        item.button?.image = StatusIcon.image(fiveHour: usage?.fiveHour?.pct, weekly: usage?.weekly?.pct, ring: ring, dnd: dnd)
    }

    /// Animate only while red/blue; still states draw once.
    private func retime() {
        timer?.invalidate(); timer = nil
        if dot == .needsYou || dot == .working {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update() }
            }
        }
        update()
    }
}
