import Testing
@testable import Perch

@Test func agentArtIsFixedGrid() {
    // Every pose, every tick: 3 rows × 8 columns, so cards line up and nothing jitters while animating.
    for pose in Pose.allCases {
        for k in 0..<120 {
            let rows = pose.frame(k)
            #expect(rows.count == 3)
            for row in rows { #expect(row.map(\.0).joined().count == 8, "\(pose) k=\(k)") }
        }
    }
}

@Test func needsYouWinsOverStatus() {
    #expect(Pose(.writing, needsYou: true) == .needsYou)
    #expect(Pose(.idle, needsYou: false) == .idle)
}
