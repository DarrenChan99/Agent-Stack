import Testing
@testable import Perch

@Test func spritesAreFixedGridInPalette() {
    // 16×14 pixels, every letter drawable, and exactly two 2×2 eyes for the poses to animate.
    for animal in Animal.allCases {
        #expect(animal.sprite.count == 14, "\(animal)")
        for row in animal.sprite {
            #expect(row.count == 16, "\(animal)")
            for c in row { #expect(c == "." || c == "o" || animal.palette[c] != nil, "\(animal) '\(c)'") }
        }
        #expect(animal.sprite.joined().filter { $0 == "o" }.count == 8, "\(animal)")
    }
}

@Test func agentArtIsFixedGrid() {
    // Every pose, every tick: 16×14 pixels plus a 3×3 prop column, so cards line up and nothing jitters.
    for animal in Animal.allCases {
        for pose in Pose.allCases {
            for k in 0..<120 {
                let px = pose.pixels(k, animal: animal)
                #expect(px.count == 14 && px.allSatisfy { $0.count == 16 }, "\(animal) \(pose) k=\(k)")
            }
        }
    }
    for pose in Pose.allCases {
        for k in 0..<120 {
            let rows = pose.prop(k)
            #expect(rows.count == 3 && rows.allSatisfy { $0.map(\.0).joined().count == 3 }, "\(pose) k=\(k)")
        }
    }
}

@Test func quietOwlIsFixedGrid() {
    // 20×16 sprite in its palette; all five scenes over 60s keep the same pixel grid and a 3×3 side column.
    #expect(QuietView.owl.count == 16)
    for row in QuietView.owl {
        #expect(row.count == 20)
        for c in row { #expect(c == "." || c == "o" || QuietView.palette[c] != nil, "'\(c)'") }
    }
    for k in 0..<300 {
        let px = QuietView.pixels(k)
        #expect(px.count == 16 && px.allSatisfy { $0.count == 20 }, "k=\(k)")
        let side = QuietView.side(k)
        #expect(side.count == 3 && side.allSatisfy { $0.map(\.0).joined().count == 3 }, "k=\(k)")
    }
}

@Test func animalIsStablePerSession() {
    #expect(Animal(sessionId: "abc-123") == Animal(sessionId: "abc-123"))
    #expect(Set((0..<64).map { Animal(sessionId: "s\($0)") }).count > 4) // ids actually spread over the zoo
}

@Test func needsYouWinsOverStatus() {
    #expect(Pose(.writing, needsYou: true) == .needsYou)
    #expect(Pose(.idle, needsYou: false) == .idle)
}
