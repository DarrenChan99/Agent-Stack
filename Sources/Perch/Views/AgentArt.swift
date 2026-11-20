import SwiftUI

typealias ArtRow = [(String, Color)]

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

    /// SF Symbol for a subagent doing this.
    var symbol: String {
        switch self {
        case .thinking: "ellipsis"; case .writing: "pencil"; case .running: "scroll"
        case .exploring: "magnifyingglass"; case .idle: "moon.zzz"; case .needsYou: "exclamationmark"
        }
    }

    /// The 3×3 prop column beside the sprite, animating with `k`.
    func prop(_ k: Int) -> [ArtRow] {
        var side = ["   ", "   ", "   "]
        switch self {
        case .thinking: side[0] = [" . ", " .o", " oO"][k / 3 % 3]                  // thought bubble swelling
        case .writing:
            side[1] = "  /"
            side[2] = [" ~ ", " ~~", "~~~"][k / 2 % 3]                              // quill scribbling
        case .running: side[1] = k % 4 < 2 ? " >_" : " > "                          // blinking cursor
        case .exploring: side[0] = k / 4 % 2 == 0 ? " ? " : "  ?"
        case .idle: side = (0..<3).map { r in (k / 3 + r) % 3 == 0 ? [" z ", " z ", " . "][r] : "   " }
        case .needsYou: side[0] = k % 4 < 2 ? " ! " : "   "
        }
        let c = color == Theme.textFaint ? Theme.textDim : color
        return side.map { [($0, c)] }
    }

    /// The animal's 16×14 pixels at tick `k` (nil = clear). Each 2×2 eye is a dark pupil plus one white glint
    /// whose corner shows gaze: up-left normally, up-right thinking, down writing, side to side exploring.
    /// Idle and blinks close the eye (top row takes the colour above it). Needs-you turns the pupil red.
    func pixels(_ k: Int, animal: Animal) -> [[Color?]] {
        let glint: (top: Bool, left: Bool) = switch self {
        case .thinking: (true, false)
        case .writing: (false, true)
        case .exploring: (true, k / 4 % 2 == 0)
        default: (true, true)
        }
        return spritePixels(animal.sprite, animal.palette, closed: self == .idle || k % 30 < 2, glint: glint,
                            pupil: self == .needsYou ? Theme.crimsonBright : nil)
    }
}

/// Paints a sprite: palette letters → colors, `.` → clear, `o` → 2×2 eyes. Open eyes are a dark pupil with one
/// white glint in the `glint` corner; closed eyes keep the bottom row dark and the top row takes the colour above it.
func spritePixels(_ sprite: [String], _ pal: [Character: Color], closed: Bool, glint: (top: Bool, left: Bool),
                  pupil: Color? = nil) -> [[Color?]] {
    let grid = sprite.map(Array.init), dark = pupil ?? Color(hex: 0x15121A)
    return grid.indices.map { y in
        grid[y].indices.map { x in
            let ch = grid[y][x]
            guard ch == "o" else { return pal[ch] }
            let top = y == 0 || grid[y - 1][x] != "o", left = x == 0 || grid[y][x - 1] != "o"
            if closed { return top ? (y > 0 ? pal[grid[y - 1][x]] : nil) : dark }
            return top == glint.top && left == glint.left ? .white : dark
        }
    }
}

/// Pixel sprite (Canvas rects, so no seams between rows) + a monospaced prop column, re-rendered every 0.2s
/// with tick `k` (frozen under Reduce Motion).
struct PixelArtView: View {
    var px: CGFloat = 3
    var textSize: CGFloat = 12
    let pixels: (Int) -> [[Color?]]
    var prop: (Int) -> [ArtRow] = { _ in [] }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
            let k = reduceMotion ? 5 : Int(ctx.date.timeIntervalSinceReferenceDate * 5)
            let grid = pixels(k)
            HStack(spacing: 1) {
                Canvas { g, _ in
                    for (y, row) in grid.enumerated() {
                        for (x, c) in row.enumerated() {
                            if let c { g.fill(Path(CGRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px)), with: .color(c)) }
                        }
                    }
                }
                .frame(width: CGFloat(grid.first?.count ?? 0) * px, height: CGFloat(grid.count) * px)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(prop(k).enumerated()), id: \.offset) { _, row in
                        row.reduce(Text("")) { $0 + Text($1.0).foregroundColor($1.1) }
                    }
                }
                .font(.system(size: textSize, weight: .semibold, design: .monospaced))
                .fixedSize()
            }
        }
        .accessibilityHidden(true)
    }
}

// Block-pixel style and small per-animal gradient palettes borrowed from github.com/kailashsr38/ascii-magic-art (MIT).
/// An agent's card critter. 16×14 pixels, one palette letter each; `.` clear, `o` eyes (two 2×2 blocks, drawn by the pose).
enum Animal: CaseIterable {
    case cat, bunny, bear, pig, mouse, tiger, dragon, wolf, monkey, penguin, duck, octopus

    /// Stable across launches (unlike `hashValue`), so an agent keeps its animal.
    init(sessionId: String) {
        let h = sessionId.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        self = Self.allCases[Int(h % UInt64(Self.allCases.count))]
    }

    var sprite: [String] {
        switch self {
        case .cat: [
                "................",
                ".a............a.",
                ".aa..........aa.",
                ".ana........ana.",
                ".anaaaabbaaaana.",
                ".aaaabaaaabaaaa.",
                "aaaaaaaaaaaaaaaa",
                "aaaooaaaaaaooaaa",
                "aaaooaaaaaaooaaa",
                "gaawwwwnnwwwwaag",
                "awwwwwkwwkwwwwwa",
                "gawwwwwwwwwwwwag",
                "..aawwwwwwwwaa..",
                ".aaaaawwwwaaaaa."]
        case .bunny: [
                "..ab........ba..",
                "..anb......bna..",
                "..anb......bna..",
                "..anb......bna..",
                "..anb......bna..",
                "..aab......baa..",
                ".aaaaaaaaaaaaaa.",
                "aaaaaaaaaaaaaaaa",
                "aaooaaaaaaaaooaa",
                "aaooaaannaaaooaa",
                "naaaaakbbkaaaaan",
                ".aaaaaabbaaaaaa.",
                "..aaaaaaaaaaaa..",
                ".baaaaaaaaaaaab."]
        case .bear: [
                "................",
                ".bb..........bb.",
                "bnnb........bnnb",
                "bnaaaaaaaaaaaanb",
                ".aaaaaaaaaaaaaa.",
                "aaaaaaaaaaaaaaaa",
                "aaooaaaaaaaaooaa",
                "aaooaaaaaaaaooaa",
                "aaaaaccccccaaaaa",
                "aaaaccckkcccaaaa",
                "aaaaccccccccaaaa",
                ".aaaaccccccaaaa.",
                "..aaaaaaaaaaaa..",
                ".baaaaaaaaaaaab."]
        case .pig: [
                "................",
                ".bb..........bb.",
                ".bab........bab.",
                ".baaaaaaaaaaaab.",
                ".aaaaaaaaaaaaaa.",
                "aaaaaaaaaaaaaaaa",
                "aaooaaaaaaaaooaa",
                "aaooaaaaaaaaooaa",
                "aaaaabbbbbbaaaaa",
                "caaaabkbbkbaaaac",
                "aaaaabbbbbbaaaaa",
                ".aaaaaaaaaaaaaa.",
                "..aaaaaaaaaaaa..",
                ".aaaaaaaaaaaaaa."]
        case .mouse: [
                ".bbb........bbb.",
                "bnnnb......bnnnb",
                "bnnnb......bnnnb",
                "bnnnaaaaaaaannnb",
                ".baaaaaaaaaaaab.",
                "..aaaaaaaaaaaa..",
                "..aooaaaaaaooa..",
                "..aooaaaaaaooa..",
                "..aaawwwwwwaaa..",
                "...awwwkkwwwa...",
                "..wawwwwwwwwaw..",
                "...aawwwwwwaa...",
                "...aaaaaaaaaa...",
                "..baaaaaaaaaab.."]
        case .tiger: [
                "................",
                ".kk..........kk.",
                ".kwa.kakkak.awk.",
                ".aaaaakaakaaaaa.",
                "kaaaaaaaaaaaaaak",
                "akaaaaaaaaaaaaka",
                "aaooaaaaaaaaooaa",
                "kaooaaaaaaaaooak",
                "aawwwwwnnwwwwwaa",
                "kawwwwkwwkwwwwak",
                "aawwwwwwwwwwwwaa",
                ".kawwwwwwwwwwak.",
                "..aaaakaakaaaa..",
                ".kaaaaaaaaaaaak."]
        case .dragon: [
                "...h........h...",
                "...hh......hh...",
                "....hb.bb.bh....",
                "...aaabaabaaa...",
                "..aaaaaaaaaaaa..",
                ".baaaaaaaaaaaab.",
                ".aaooaaaaaaooaa.",
                ".aaooaaaaaaooaa.",
                "baaaaaabbaaaaaab",
                "aaaccccaaccccaaa",
                "aacwccccccccwcaa",
                ".accccrrrrcccca.",
                "..baaaaaaaaaab..",
                ".bbaaaaaaaaaabb."]
        case .wolf: [
                ".b............b.",
                ".bb..........bb.",
                ".bdb........bdb.",
                ".bddb......bddb.",
                ".bdbaaaaaaaabdb.",
                ".aaaaaaaaaaaaaa.",
                "aaaaaaaaaaaaaaaa",
                "abooaaaaaaaaooba",
                "aaooaawwwwaaooaa",
                "aaaawwwwwwwwaaaa",
                ".aawwwwwwwwwwaa.",
                "..wwwwwkkwwwww..",
                "..awwwwwwwwwwa..",
                ".aawwwwwwwwwwaa."]
        case .monkey: [
                "................",
                "...aaaaaaaaaa...",
                "..aaaaabbaaaaa..",
                ".aaaaaaaaaaaaaa.",
                ".aaccaccccaccaa.",
                "acnccccccccccnca",
                "acnooccccccoonca",
                "aanooccccccoonaa",
                ".acccccccccccca.",
                "..ccccckkccccc..",
                "..cccccccccccc..",
                "..accckkkkccca..",
                "..aaccccccccaa..",
                ".aaaaaaaaaaaaaa."]
        case .penguin: [
                "................",
                "....aaaaaaaa....",
                "...aaaaaaaaaa...",
                "..aaaaaaaaaaaa..",
                "..aawwwwwwwwaa..",
                ".aawwwwwwwwwwaa.",
                ".aawoowyywoowaa.",
                ".aawooyyyyoowaa.",
                ".aawwwwwwwwwwaa.",
                "bawwwwwwwwwwwwab",
                "baawwwwwwwwwwaab",
                "baawwwwwwwwwwaab",
                ".aaawwwwwwwwaaa.",
                "...yy......yy..."]
        case .duck: [
                "................",
                "....aaaaaaaa....",
                "...aaaaaaaaaa...",
                "..aaaaaaaaaaaa..",
                "..aaaaaaaaaaaa..",
                "..aooaaaaaaooa..",
                "..aooaaaaaaooa..",
                "..aaayyyyyyaaa..",
                "..aayyyyyyyyaa..",
                "...azzzzzzzza...",
                "..baaaaaaaaaab..",
                ".baaaaaaaaaaaab.",
                ".bbaaaaaaaaaabb.",
                "..bbbaaaaaabbb.."]
        case .octopus: [
                "....aaaaaaaa....",
                "...acaaaaaaca...",
                "..accaaaaaacca..",
                "..aaaaaaaaaaaa..",
                ".aaaaaaaaaaaaaa.",
                ".aaooaaaaaaooaa.",
                ".aaooaaaaaaooaa.",
                ".naaaaaaaaaaaan.",
                ".aaaaaaaaaaaaaa.",
                "..aaaaaaaaaaaa..",
                ".aabaabbbbaabaa.",
                ".a.ab.a..a.ba.a.",
                "a..a..a..a..a..a",
                ".a..a..aa..a..a."]
        }
    }

    var palette: [Character: Color] {
        let hex: [Character: UInt32] = switch self {
        case .cat: ["a": 0xF2A04A, "b": 0xC46A24, "w": 0xFCE6C8, "n": 0xF48FB1, "k": 0x5A3418, "g": 0xBDBDBD]
        case .bunny: ["a": 0xECEAF2, "b": 0xB9B4C8, "n": 0xF6A6C1, "k": 0x6B5B7B]
        case .bear: ["a": 0x9A6235, "b": 0x6E4223, "c": 0xD9A877, "k": 0x2B1A0E, "n": 0xC98A5A]
        case .pig: ["a": 0xF7A8BE, "b": 0xE07B9A, "c": 0xFFC9D6, "k": 0x8A3550]
        case .mouse: ["a": 0xA9A9B8, "b": 0x7C7C8E, "n": 0xF4A3B8, "k": 0x2E2E38, "w": 0xD9D9E3]
        case .tiger: ["a": 0xF28C28, "k": 0x2A1A10, "w": 0xFFF4E2, "n": 0xE76F8A]
        case .dragon: ["a": 0x4CC38A, "b": 0x2E8B5E, "c": 0xC9F2A8, "h": 0xF5D27A, "w": 0xFFFFFF, "r": 0xE0354F]
        case .wolf: ["a": 0x8E96A6, "b": 0x5C6372, "w": 0xE6E9EF, "k": 0x22252C, "d": 0xC7CCD6]
        case .monkey: ["a": 0x8B5A33, "b": 0x5E3A1F, "c": 0xF0C9A0, "n": 0xD9A07A, "k": 0x3A2412]
        case .penguin: ["a": 0x2C3140, "b": 0x485066, "w": 0xF4F6FA, "y": 0xF5A623]
        case .duck: ["a": 0xFFD84D, "b": 0xE8B820, "y": 0xFF8C2A, "z": 0xD86A10]
        case .octopus: ["a": 0xB06CF0, "b": 0x7E44C4, "c": 0xD9B2FF, "n": 0xF48FB1]
        }
        return hex.mapValues { Color(hex: $0) }
    }
}
