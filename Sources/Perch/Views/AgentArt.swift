import SwiftUI

typealias ArtRow = [(String, Color)]

/// Monospaced colored ASCII art, re-rendered every 0.2s with a tick `k` (frozen at 1 under Reduce Motion).
struct ArtView: View {
    var size: CGFloat = 12
    let frame: (Int) -> [ArtRow]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let k = reduceMotion ? 1 : Int(ctx.date.timeIntervalSinceReferenceDate * 5)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(frame(k).enumerated()), id: \.offset) { _, row in
                    row.reduce(Text("")) { $0 + Text($1.0).foregroundColor($1.1) }
                }
            }
            .font(.system(size: size, weight: .semibold, design: .monospaced))
            .fixedSize()
        }
        .accessibilityHidden(true)
    }
}

/// What an agent's owl is doing. `needsYou` wins over the hook status.
enum Pose: CaseIterable {
    case thinking, writing, running, exploring, idle, needsYou

    init(_ s: AgentStatus, needsYou: Bool) {
        if needsYou { self = .needsYou; return }
        switch s {
        case .thinking: self = .thinking
        case .writing: self = .writing
        case .running: self = .running
        case .exploring: self = .exploring
        case .idle: self = .idle
        }
    }

    var label: String {
        switch self {
        case .thinking: "Thinking"; case .writing: "Writing"; case .running: "Running"
        case .exploring: "Exploring"; case .idle: "Idle"; case .needsYou: "Needs you"
        }
    }

    var color: Color {
        switch self {
        case .thinking: Theme.textDim; case .writing, .running: Theme.green; case .exploring: Theme.amber
        case .idle: Theme.textFaint; case .needsYou: Theme.crimsonSoft
        }
    }

    /// 3 rows × 8 columns: a 5-wide owl plus a 3-wide prop column that animates with `k`.
    func frame(_ k: Int) -> [ArtRow] {
        let body = self == .idle ? Theme.textDim : Theme.text
        let blink = k % 30 < 2
        let eyes: String
        var side = ["   ", "   ", "   "]
        switch self {
        case .thinking:
            eyes = blink ? "(-,-)" : "(o,o)"
            side[0] = [" . ", " .o", " oO"][k / 3 % 3]                  // thought bubble swelling
        case .writing:
            eyes = "(.,.)"                                              // eyes down on the page
            side[1] = "  /"
            side[2] = [" ~ ", " ~~", "~~~"][k / 2 % 3]                  // quill scribbling
        case .running:
            eyes = "(O,O)"
            side[1] = k % 4 < 2 ? " >_" : " > "                         // blinking cursor
        case .exploring:
            eyes = k / 4 % 2 == 0 ? "(<,<)" : "(>,>)"                   // looking around
            side[0] = k / 4 % 2 == 0 ? " ? " : "  ?"
        case .idle:
            eyes = "(-,-)"
            side = (0..<3).map { r in (k / 3 + r) % 3 == 0 ? [" z ", " z ", " . "][r] : "   " }
        case .needsYou:
            eyes = "(O,O)"
            side[0] = k % 4 < 2 ? " ! " : "   "
        }
        let prop = self.color == Theme.textFaint ? Theme.textDim : self.color
        return [
            [(" ,_, ", body), (side[0], prop)],
            [(eyes, body), (side[1], prop)],
            [("/)__)", body), (side[2], prop)],
        ]
    }
}
