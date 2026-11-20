import AppKit
import SwiftUI

@MainActor @Observable
final class PanelModel {
    var dnd = UserDefaults.standard.bool(forKey: "dnd") { didSet { UserDefaults.standard.set(dnd, forKey: "dnd") } }
    var showPrompt = false   // false = agent list
    var pill = false
}

enum Jump {
    private static let openWithCwd: Set<String> = ["com.microsoft.VSCode", "com.google.android.studio"]

    static func canJump(_ s: Session) -> Bool { s.job != nil || s.bundleId != nil }

    /// Job ids go into a shell script, so only accept the short hex/word ids Claude Code uses.
    static func safeJob(_ j: String) -> String? {
        j.range(of: #"^[A-Za-z0-9_-]{1,64}$"#, options: .regularExpression) != nil ? j : nil
    }

    /// ttys that may show this agent: claude's own (foreground run), then any `claude attach <job|session>` client.
    static func ttys(for s: Session, ps: String) -> [String] {
        var out: [String] = []
        let ids = [s.job, s.id].compactMap { $0 }
        for line in ps.split(separator: "\n") {
            let f = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard f.count >= 2, f[1] != "??" else { continue }
            if let p = s.ppid, Int32(f[0]) == p { out.insert(f[1], at: 0); continue }
            if let a = f.firstIndex(of: "attach"), a > 2, f[a - 1].hasSuffix("claude"),
               a + 1 < f.count, f[a + 1].count >= 4, ids.contains(where: { $0.hasPrefix(f[a + 1]) }) {
                out.append(f[1])
            }
        }
        return out.map { "/dev/" + $0 }
    }

    /// Select the Terminal tab on `tty` and raise its window. Only asks Terminal if it's already running.
    @MainActor static func focusTerminal(tty: String) -> Bool {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Terminal").isEmpty,
              tty.range(of: #"^/dev/ttys\d+$"#, options: .regularExpression) != nil else { return false }
        let src = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(tty)" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
        var err: NSDictionary?
        return NSAppleScript(source: src)?.executeAndReturnError(&err).booleanValue ?? false
    }

    /// pids of interactive `claude` runs on a real tty: the agent view where background jobs are watched.
    static func claudeHosts(ps: String) -> [Int32] {
        ps.split(separator: "\n").compactMap { line in
            let f = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard f.count == 3, f[1] != "??", f[2] == "claude" || f[2].hasSuffix("/claude") else { return nil }
            return Int32(f[0])
        }
    }

    /// Folders of open VS Code windows, from its saved window state.
    static func vscodeOpenFolders() -> [String] {
        let f = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Code/User/globalStorage/storage.json")
        guard let d = try? Data(contentsOf: f), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let w = j["windowsState"] as? [String: Any] else { return [] }
        let wins = (w["openedWindows"] as? [[String: Any]] ?? []) + [w["lastActiveWindow"] as? [String: Any] ?? [:]]
        return wins.compactMap { ($0["folder"] as? String).flatMap(URL.init(string:))?.path }
    }

    /// The open window folder that holds `cwd` (deepest wins), else `cwd` itself, so a subfolder session lands in its project window.
    static func vscodeFolder(for cwd: String, openWindows: [String]) -> String {
        openWindows.filter { cwd == $0 || cwd.hasPrefix($0 + "/") }.max(by: { $0.count < $1.count }) ?? cwd
    }

    /// openApplication activates reliably from an accessory app; NSRunningApplication.activate() is often ignored.
    @MainActor private static func activate(_ app: URL, cwd: String? = nil) {
        let cfg = NSWorkspace.OpenConfiguration(); cfg.activates = true
        if let cwd { NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: app, configuration: cfg) }
        else { NSWorkspace.shared.openApplication(at: app, configuration: cfg) }
    }

    @MainActor static func to(_ s: Session) {
        let p = Process(); let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/ps"); p.arguments = ["-ax", "-o", "pid=,tty=,command="]
        p.standardOutput = pipe
        let ps = (try? p.run()) != nil ? String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) : ""
        // Already showing in a Terminal tab (foreground run, or an attached bg job)? Go there.
        if ttys(for: s, ps: ps).contains(where: focusTerminal) { return }
        // Known host app (VS Code, iTerm…): bring it forward.
        if s.bundleId == "com.microsoft.VSCode", let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.microsoft.VSCode"),
           FileManager.default.isExecutableFile(atPath: app.path + "/Contents/Resources/app/bin/code"), !s.cwd.isEmpty {
            // The `code` CLI focuses the window that already has the folder open; a macOS open event just raises the last-used one.
            let c = Process(); c.executableURL = URL(fileURLWithPath: app.path + "/Contents/Resources/app/bin/code")
            c.arguments = [vscodeFolder(for: s.cwd, openWindows: vscodeOpenFolders())]
            if (try? c.run()) != nil { return }
        }
        if let id = s.bundleId, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return activate(app, cwd: openWithCwd.contains(id) ? s.cwd : nil)
        }
        // Background job lives in the daemon with no window: raise the app running the claude agent view.
        if s.job != nil, let app = claudeHosts(ps: ps).lazy.compactMap({ AppIdentity.app(ppid: $0)?.bundleURL }).first {
            return activate(app)
        }
        // Last resort: nowhere to focus, so open a Terminal attached to the job.
        guard let job = s.job.flatMap(safeJob) else { return }
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("perch-attach-\(job).command")
        try? "#!/bin/sh\nexec claude attach \(job)\n".write(to: f, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.path)
        NSWorkspace.shared.open(f)
    }
}

extension View {
    /// Plain-style icon buttons only hit their glyph's pixels; give them a real target.
    func hitBox() -> some View { frame(width: 26, height: 22).contentShape(Rectangle()) }
}

@MainActor private var iconCache: [String: NSImage] = [:]
@MainActor func appIcon(_ bundleId: String?) -> NSImage? {
    guard let bundleId else { return nil }
    if let i = iconCache[bundleId] { return i }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
    let i = NSWorkspace.shared.icon(forFile: url.path)
    iconCache[bundleId] = i
    return i
}

struct AgentList: View {
    let store: SessionStore
    let queue: PromptQueue
    let fetcher: UsageFetcher
    @Bindable var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(store.sessions.count == 1 ? "1 agent" : "\(store.sessions.count) agents")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                if !queue.prompts.isEmpty {
                    Button("\(queue.prompts.count) needs you") { model.showPrompt = true }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.crimsonSoft)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Theme.crimsonBright, lineWidth: 1))
                }
                Spacer()
                Button { store.prune(); fetcher.refresh() } label: { Image(systemName: "arrow.clockwise").hitBox() }
                    .help("Reload: drop ended agents, refresh usage").foregroundStyle(Theme.textDim)
                Button { model.dnd.toggle() } label: { Image(systemName: model.dnd ? "moon.fill" : "moon").hitBox() }
                    .help("Do not disturb").foregroundStyle(model.dnd ? Theme.crimsonSoft : Theme.textDim)
                Menu { Button("Settings…") { SettingsWindow.show(model: model) }; Button("Quit Perch") { NSApp.terminate(nil) } } label: { Image(systemName: "gearshape") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(Theme.textDim)
            }.buttonStyle(.plain)
            if store.sessions.isEmpty {
                QuietView()
            } else {
                ForEach(store.sorted) { s in
                    AgentRow(store: store, queue: queue, session: s)
                }
            }
            MeterView(label: "5H", window: fetcher.displayUsage?.fiveHour)
            MeterView(label: "7D", window: fetcher.displayUsage?.weekly)
            if let email = fetcher.email {
                Text(email).font(.system(size: 10)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(16)
        .frame(width: 340)
        .perchPanel()
    }
}

struct AgentRow: View {
    let store: SessionStore
    let queue: PromptQueue
    let session: Session
    @State private var reply = ""

    private var stopItem: PromptItem? {
        queue.items.first { $0.sessionId == session.id && { if case .stop = $0.kind { true } else { false } }($0) }
    }

    private var pose: Pose { Pose(session.status, needsYou: queue.has(session: session.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                PixelArtView(pixels: { [pose, animal = Animal(sessionId: session.id)] in pose.pixels($0, animal: animal) }, prop: pose.prop)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.project).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        if let icon = appIcon(session.bundleId) { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
                        Spacer(minLength: 4)
                        Button { store.sessions[session.id]?.holdNextStop.toggle() } label: { Image(systemName: "text.bubble").hitBox() }
                            .help("Hold next Stop to reply")
                            .foregroundStyle(session.holdNextStop ? Theme.crimsonSoft : Theme.textFaint)
                        if Jump.canJump(session) {
                            Button { Jump.to(session) } label: {
                                Label("Open", systemImage: "arrow.up.forward.app").font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8).frame(height: 22)
                                    .background(.white.opacity(0.08), in: Capsule()).contentShape(Capsule())
                            }
                            .help(session.job != nil ? "Open this background job in Terminal" : "Jump to its app")
                            .foregroundStyle(Theme.text)
                        }
                        if let stopItem {
                            Button { queue.dismiss(stopItem) } label: { Image(systemName: "xmark.circle").hitBox() }
                                .help("Dismiss: let Claude stop normally").foregroundStyle(Theme.textDim)
                        }
                    }.buttonStyle(.plain).font(.system(size: 11))
                    TimelineView(.periodic(from: .now, by: 30)) { _ in // body alone only re-renders on session changes
                        (Text(pose.label).foregroundColor(pose.color) + Text("  ·  \(elapsed)").foregroundColor(Theme.textFaint))
                    }.font(.system(size: 11, weight: .medium))
                    if !subs.isEmpty { subagentIcons }
                    ctxLine.font(.system(size: 10, design: .monospaced))
                }
            }
            if stopItem != nil {
                HStack {
                    TextField("Reply…", text: $reply).textFieldStyle(.plain).onSubmit(send)
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill") }.buttonStyle(.plain)
                        .foregroundStyle(Theme.crimsonSoft).disabled(reply.isEmpty)
                }
                .padding(8).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(pose == .needsYou ? Theme.crimsonBright.opacity(0.8) : .white.opacity(0.06), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.project), \(pose.label), context \(Int(session.ctxPct)) percent"
            + (subs.isEmpty ? "" : ", \(subs.count) subagents: " + subs.map(\.label).joined(separator: ", ")))
    }

    /// Running subagents' poses, in a stable order so icons don't shuffle.
    private var subs: [Pose] { session.subagents.sorted { $0.key < $1.key }.map { Pose($0.value, needsYou: false) } }

    /// One tiny icon per running subagent showing what it's doing; "+N" past 4.
    private var subagentIcons: some View {
        HStack(spacing: 5) {
            ForEach(Array(subs.prefix(4).enumerated()), id: \.offset) { _, p in
                Image(systemName: p.symbol).foregroundStyle(p.color == Theme.textFaint ? Theme.textDim : p.color).help(p.label)
            }
            if subs.count > 4 { Text("+\(subs.count - 4)").foregroundStyle(Theme.text) }
        }.font(.system(size: 10, weight: .semibold))
    }

    /// `━━━━━━────────── 42% · 84k`
    private var ctxLine: Text {
        let bar = Meter.bar(cells: 16, pct: session.ctxPct)
        let used = bar.prefix { $0 != "─" }
        let tok = session.tokens >= 1000 ? "\(session.tokens / 1000)k" : "\(session.tokens)"
        return Text(String(used)).foregroundColor(Meter.color(session.ctxPct))
            + Text(String(bar.dropFirst(used.count))).foregroundColor(Theme.textFaint.opacity(0.35))
            + Text(" \(Int(session.ctxPct))% · \(tok)").foregroundColor(Theme.textFaint)
    }

    private func send() {
        guard let stopItem, !reply.isEmpty else { return }
        queue.stopReply(stopItem, text: reply)
        reply = ""
    }

    private var elapsed: String {
        let m = Int(Date().timeIntervalSince(session.startedAt) / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }
}
