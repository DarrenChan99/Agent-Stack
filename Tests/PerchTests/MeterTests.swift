import Testing
@testable import Perch

@Test func meterFillsWidth() {
    // 400pt / 7.2pt = 55 chars; 18 fixed chars -> 37 bar cells; line is exactly 55 chars, never wider than the box.
    let cells = Meter.cellCount(width: 400, charWidth: 7.2, fixedChars: 18)
    #expect(cells == 37)
    #expect(Double(cells + 18) * 7.2 <= 400)
    #expect(Double(cells + 19) * 7.2 > 400)
    #expect(Meter.cellCount(width: 50, charWidth: 7.2, fixedChars: 18) == 0)
}

@Test func meterBarCells() {
    #expect(Meter.bar(cells: 10, pct: 0) == "──────────")
    #expect(Meter.bar(cells: 10, pct: 100) == "━━━━━━━━━━")
    #expect(Meter.bar(cells: 10, pct: 84) == "━━━━━━━━──") // 8.4 cells: 0.4 rounds down
    #expect(Meter.bar(cells: 10, pct: 86) == "━━━━━━━━╸─") // 8.6 cells: half cell
    #expect(Meter.bar(cells: 10, pct: 86).count == 10)
}

@Test func meterColorLevels() {
    #expect(Meter.level(49.9) == .low && Meter.level(50) == .mid && Meter.level(79.9) == .mid && Meter.level(80) == .high)
}
