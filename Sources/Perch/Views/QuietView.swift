import SwiftUI

/// Empty state for the agent list (no sessions): a dozing owl, crimson Z's drifting up, a red glint along the perch.
struct QuietView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let k = reduceMotion ? 1 : Int(ctx.date.timeIntervalSinceReferenceDate * 5)
            VStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(Self.frame(k).enumerated()), id: \.offset) { _, line in
                        HStack(spacing: 0) { ForEach(Array(line.enumerated()), id: \.offset) { _, seg in Text(seg.0).foregroundStyle(seg.1) } }
                    }
                }.font(.system(size: 12, weight: .semibold, design: .monospaced))
                Text("All quiet").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .accessibilityElement(children: .ignore).accessibilityLabel("All quiet, no agents running")
        }
    }

    /// One frame of the art at tick `k`, as rows of colored segments.
    static func frame(_ k: Int) -> [[(String, Color)]] {
        let w = Theme.text, r = Theme.crimsonBright
        let eyes = k % 40 < 2 ? "(o,o)" : "(-,-)" // blink awake now and then
        let z = (0..<3).map { row in (k / 3 + row) % 3 == 0 ? ["Z", "z", "."][row] : " " } // rises top-ward
        let branch = Array("─═══\"═\"══════════─")
        let glint = (k / 2) % (branch.count + 6) - 3
        let perch: [(String, Color)] = branch.indices.map { i in
            (String(branch[i]), abs(i - glint) <= 1 ? r : (branch[i] == "\"" ? w : w.opacity(0.55)))
        }
        return [
            [("    ,_,    ", w), ("  " + z[0], r)],
            [("   \(eyes)   ", w), (" " + z[1] + " ", r)],
            [("   /)__)   ", w), (z[2] + "  ", r)],
            perch,
        ]
    }
}
