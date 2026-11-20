import AppKit
import SwiftUI

enum Meter {
    enum Level { case low, mid, high }

    static func level(_ pct: Double) -> Level { pct < 50 ? .low : pct < 80 ? .mid : .high }

    static func color(_ pct: Double) -> Color {
        switch level(pct) { case .low: Theme.green; case .mid: Theme.amber; case .high: Theme.crimsonSoft }
    }

    /// Bar cells so `fixedChars + cells` monospaced characters fill `width` without overflowing.
    static func cellCount(width: Double, charWidth: Double, fixedChars: Int) -> Int {
        max(0, Int(width / charWidth) - fixedChars)
    }

    /// ━ used, ╸ half cell, ─ remaining. Static: no shimmer, no shaded blocks.
    static func bar(cells: Int, pct: Double) -> String {
        let exact = Double(cells) * min(max(pct, 0), 100) / 100
        let full = Int(exact)
        var s = String(repeating: "━", count: full)
        if full < cells && exact - Double(full) >= 0.5 { s += "╸" }
        return s + String(repeating: "─", count: cells - s.count)
    }

    static func resetText(_ date: Date, now: Date = .now) -> String {
        let m = max(0, Int(date.timeIntervalSince(now) / 60))
        if m >= 24 * 60 { return "\(m / 1440)d \(m % 1440 / 60)h" }
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    static let font: NSFont = NSFont(name: "JetBrainsMono-Regular", size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
    static var charWidth: Double { Double(("━" as NSString).size(withAttributes: [.font: font]).width) }
}

/// `5H ━━━━━━━━╸──── 84%  1h 48m`, sized so the line fills the container exactly.
struct MeterView: View {
    let label: String
    let window: UsageWindow?

    var body: some View {
        GeometryReader { geo in
            Text(line(width: geo.size.width)).font(Font(Meter.font)).lineLimit(1).fixedSize()
        }
        .frame(height: 16)
    }

    private func line(width: Double) -> AttributedString {
        let pctText = window.map { "\(Int($0.pct.rounded()))%" } ?? "—"
        let reset = window?.resetsAt.map { Meter.resetText($0) } ?? ""
        let tail = " \(pctText)" + (reset.isEmpty ? "" : "  \(reset)")
        let fixed = label.count + 1 /* " " */ + tail.count
        let cells = Meter.cellCount(width: width, charWidth: Meter.charWidth, fixedChars: fixed)
        let pct = window?.pct ?? 0
        let bar = Meter.bar(cells: cells, pct: pct)
        let used = bar.prefix { $0 != "─" }
        var s = AttributedString(label + " "); s.foregroundColor = Theme.textDim
        var u = AttributedString(String(used)); u.foregroundColor = Meter.color(pct)
        var r = AttributedString(String(bar.dropFirst(used.count))); r.foregroundColor = Theme.textFaint.opacity(0.35)
        var t = AttributedString(tail); t.foregroundColor = window == nil ? Theme.textFaint : Theme.text
        return s + u + r + t
    }
}
