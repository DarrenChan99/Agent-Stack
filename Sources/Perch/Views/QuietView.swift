import Foundation
import SwiftUI

/// Empty state for the agent list (no sessions): a blue-gray owl on a branch with a firefly for company.
/// Everything, Z's and "hoo" included, is drawn in pixels on one canvas.
struct QuietView: View {
    var body: some View {
        VStack(spacing: 8) {
            PixelArtView(px: 4, pixels: Self.pixels)
            Text("All quiet").font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .accessibilityElement(children: .ignore).accessibilityLabel("All quiet, no agents running")
    }

    /// 20×20 owl. `i` 4×4 irises (pupils drawn per frame at iris origins x 3 and 13, y 6), `y` beak, `k` talons.
    /// Rows 0…10 are the head, which nods and bobs separately from the body.
    static let owl = [
        "..dd............dd..",
        "..dad..........dad..",
        "..daaddddddddddaad..",
        ".daaaaaaaaaaaaaaaad.",
        "daaggggaaaaaaggggaad",
        "daggffggaaaaggffggad",
        "dgfiiiifgaagfiiiifgd",
        "dgfiiiifgaagfiiiifgd",
        "dgfiiiifgyygfiiiifgd",
        "dgfiiiifgyygfiiiifgd",
        "daggffggaayaggffggad",
        ".daaggaaaaaaaaggaad.",
        ".dbaaaccccccccaaabd.",
        "dbbaacvccvvccvcaabbd",
        "dbbacccccccccccbabbd",
        "dbbaccvccvvccvccabbd",
        ".dbbacccccccccccbbd.",
        "..dbbaccvccvccabbd..",
        "...ddbaccccccabdd...",
        "....kk.k....k.kk....",
    ]

    static let palette: [Character: Color] = [
        "d": Color(hex: 0x313C55), "a": Color(hex: 0x7B8CA8), "b": Color(hex: 0x58698A), "g": Color(hex: 0xA2B1C8),
        "f": Color(hex: 0xD9E0E9), "c": Color(hex: 0xE4E9F0), "v": Color(hex: 0x8E9AAE), "i": Color(hex: 0xF5C66B),
        "y": Color(hex: 0xF0A93B), "k": Color(hex: 0xF0A93B), "p": Color(hex: 0x15121A), "w": .white,
        "r": Color(hex: 0x4A4555), "R": Color(hex: 0x635D70), "l": Color(hex: 0x4CC38A), "L": Color(hex: 0x2F9466),
        "z": Color(hex: 0xA9C8FF), "s": .white, "t": Color(hex: 0x8C9BB8),
        "e": Color(hex: 0xE4FF8A), "E": Color(hex: 0xC6F05A).opacity(0.35),
    ]

    static let width = 34, height = 23
    static let ox = 3, oy = 1

    static func pixels(_ k: Int) -> [[Color?]] { frame(k).map { $0.map { palette[$0] } } }

    /// Palette letters at tick `k` (5/s); `.` is clear. A new 10s scene every 50 ticks: doze (Z's float up, head
    /// nods), look around, wing flap, "hoo", stargaze (shooting star). The firefly and the leaves never stop.
    static func frame(_ k: Int) -> [[Character]] {
        var g = Array(repeating: Array(repeating: Character("."), count: width), count: height)
        func put(_ x: Int, _ y: Int, _ c: Character, onlyClear: Bool = false) {
            guard g.indices.contains(y), g[y].indices.contains(x), !onlyClear || g[y][x] == "." else { return }
            g[y][x] = c
        }
        func stamp(_ rows: [String], _ x: Int, _ y: Int, as c: Character? = nil) {
            for (dy, r) in rows.enumerated() { for (dx, ch) in r.enumerated() where ch != "." { put(x + dx, y + dy, c ?? ch) } }
        }
        let scene = k / 50 % 5, t = k % 50

        // Branch with bark knots, a sprig on the right, leaves swaying underneath.
        for x in 0..<width { put(x, 21, x % 7 == 3 ? "R" : "r") }
        let sway = k / 8 % 2
        stamp(["l.", "Ll"], 1 + sway, 22 - 1)
        put(2 + sway, 22, "l")
        stamp([".l", "lL", "L."], 31, 18)
        put(29 - sway, 22, "L")

        // Stars come out for stargazing; a shooting star streaks across the top.
        if scene == 4 {
            for (i, (x, y)) in [(1, 1), (0, 7), (24, 0), (31, 2), (28, 6), (33, 9), (26, 12), (1, 13)].enumerated() {
                put(x, y, (k / 3 + i) % 3 == 0 ? "s" : "t")
            }
            if (8..<24).contains(t) {
                let hx = (t - 8) * 2 + 2, hy = (t - 8) / 4
                put(hx, hy, "s"); put(hx - 1, hy, "t"); put(hx - 2, hy, "t")
            }
        }

        // Wings flap out behind the body.
        if scene == 2 {
            let up = k / 3 % 2 == 0
            let wing = up ? ["...d", "..bd", ".bbd", "bbbd", "bb..", "b..."] : ["....", "...d", "..bd", ".bbd", ".bb.", "..b."]
            stamp(wing, ox - 3, oy + 11)
            stamp(wing.map { String($0.reversed()) }, ox + 19, oy + 11)
        }

        // Body, then the head (nodding while dozing, bobbing on each "hoo").
        let hoot = t % 25
        let headDy = scene == 0 ? (t % 16 >= 12 ? 1 : 0) : scene == 3 && hoot < 8 ? -1 : 0
        stamp(Array(owl[10...]), ox, oy + 10)  // row 10 twice, so a raised head leaves no gap
        stamp(Array(owl[..<11]), ox, oy + headDy)

        // Eyes: closed lids while dozing or blinking, ^^ while hooting, otherwise a pupil that wanders.
        let blink = scene != 0 && k % 30 >= 28
        let gaze: (x: Int, y: Int) = switch scene {
        case 1: [(1, 1), (0, 1), (0, 1), (0, 2), (1, 1), (2, 1), (2, 1), (2, 0)][t / 6 % 8]
        case 4: (min(2, max(0, (t - 8) / 5)), 0)
        default: (1, 1)
        }
        for ix in [3, 13] {
            let ex = ox + ix, ey = oy + headDy + 6
            if scene == 0 || blink { stamp(["ffff", "ffff", "dffd", "fddf"], ex, ey) }
            else if scene == 3 && hoot < 12 { stamp(["ffff", "fddf", "dffd", "ffff"], ex, ey) }
            else { stamp(["wp", "pp"], ex + gaze.x, ey + gaze.y) }
        }

        // Z's drift up and out from the sleeping head, small then big.
        if scene == 0 {
            for j in 0..<2 {
                let p = (t + j * 12) % 24
                guard p < 20 else { continue }
                stamp(p < 8 ? ["zzzz", "..z.", ".z..", "zzzz"] : ["zzzzz", "...z.", "..z..", ".z...", "zzzzz"],
                      ox + 20 + p / 4, oy + 8 - p / 2, as: "z")
            }
        }

        // "hoo" types out letter by letter beside the head, then floats away.
        if scene == 3 && hoot < 20 {
            let y = oy + 4 - max(0, hoot - 10) / 3
            let h = ["z..", "z..", "zzz", "z.z", "z.z"], o = ["...", "...", "zzz", "z.z", "zzz"]
            stamp(h, ox + 20, y)
            if hoot >= 3 { stamp(o, ox + 24, y) }
            if hoot >= 6 { stamp(o, ox + 28, y) }
        }

        // A firefly loops around the right side, pulsing its glow.
        let a = Double(k) * 0.12
        let fx = 28 + Int((4 * sin(a)).rounded()), fy = 14 + Int((3 * sin(a * 1.7 + 1)).rounded())
        put(fx, fy, "e", onlyClear: true)
        if k % 6 < 3 { for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { put(fx + dx, fy + dy, "E", onlyClear: true) } }
        return g
    }
}
