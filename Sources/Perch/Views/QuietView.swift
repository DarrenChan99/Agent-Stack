import SwiftUI

/// Empty state for the agent list (no sessions): a dozing owl, crimson Z's drifting up, a red glint along the perch.
struct QuietView: View {
    var body: some View {
        VStack(spacing: 8) {
            PixelArtView(px: 4, pixels: Self.pixels, prop: Self.side)
            Text("All quiet").font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .accessibilityElement(children: .ignore).accessibilityLabel("All quiet, no agents running")
    }

    /// 20×16 owl on a branch. `o` eyes, `i` iris, `W` outstretched wings, `s`/`S` twinkling stars, `r` branch.
    static let owl = [
        "s.................S.",
        "....S..........s....",
        "...b............b...",
        "...bb..........bb...",
        "...baaaaaaaaaaaab...",
        "..aaffffaaaaffffaa..",
        "..afiiiifaafiiiifa..",
        "..afiooifaafiooifa..",
        "..afiooifyyfiooifa..",
        "..aafiifayyafiifaa..",
        "..abccccccccccccba..",
        ".WabcbcccbbcccbcbaW.",
        "WWabccccccccccccbaWW",
        ".W.bcbccbccbccbcb.W.",
        "rrrrrrrrrrrrrrrrrrrr",
        "..l..r........r..l..",
    ]

    static let palette: [Character: Color] = [
        "a": 0x8A6A4E, "b": 0x5E4632, "c": 0xE3CFAF, "f": 0xF2E6D2, "i": 0xF5C66B, "y": 0xF5A623,
        "r": 0x6B4A2F, "l": 0x4CC38A, "W": 0x8A6A4E, "s": 0xFF6B80, "S": 0xFF6B80,
    ].mapValues { Color(hex: $0) }

    /// Owl pixels at tick `k`. A new scene every 10s (50 ticks): doze, head swivel (eyes roll around),
    /// wing stretch, "hoo", stargazing (stars twinkle). A crimson glint runs along the branch throughout.
    static func pixels(_ k: Int) -> [[Color?]] {
        var pal = palette
        let scene = k / 50 % 5, out = scene == 2 && k / 6 % 2 == 0
        let closed = scene == 0 ? k % 40 >= 2 : out
        let glint: (top: Bool, left: Bool) = switch scene {
        case 1: [(true, true), (true, false), (false, false), (false, true)][k / 6 % 4]
        case 4: (true, false)
        default: (true, true)
        }
        if closed { pal["i"] = pal["f"] }
        if !out { pal["W"] = nil }
        if scene == 4 {
            pal[k / 3 % 2 == 0 ? "S" : "s"] = Theme.crimsonBright.opacity(0.35)
        } else { pal["s"] = nil; pal["S"] = nil }
        var grid = spritePixels(owl, pal, closed: closed, glint: glint)
        let g = (k / 2) % 26 - 3
        for y in grid.indices { for x in grid[y].indices where Array(owl[y])[x] == "r" && abs(x - g) <= 1 { grid[y][x] = Theme.crimsonBright } }
        return grid
    }

    /// Crimson side column: Z's drifting up while dozing, "hoo" in the hoo scene.
    static func side(_ k: Int) -> [ArtRow] {
        var rows = ["   ", "   ", "   "]
        switch k / 50 % 5 {
        case 0:
            let z = (0..<3).map { row in (k / 3 + row) % 3 == 0 ? ["Z", "z", "."][row] : " " }
            rows = ["  " + z[0], " " + z[1] + " ", z[2] + "  "]
        case 3: rows[1] = k % 10 < 6 ? "hoo" : "   "
        default: break
        }
        return rows.map { [($0, Theme.crimsonBright)] }
    }
}
