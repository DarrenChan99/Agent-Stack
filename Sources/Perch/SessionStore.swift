import AppKit
import Observation

enum AgentStatus: Equatable { case thinking, writing, running, exploring, idle, waiting } // waiting: a permission/question is up

struct Session: Identifiable {
    let id: String
    var cwd: String
    var ppid: Int32?
    var transcriptPath: String?
    var bundleId: String?
    var job: String?           // background job short id (claude attach <job>)
    var status: AgentStatus = .thinking
    var startedAt = Date()
    var lastEvent = Date()
    var tokens = 0
    var ctxPct = 0.0
    var holdNextStop = false
    var subagents: [String: AgentStatus] = [:] // running subagents by agent_id
    var project: String { (cwd as NSString).lastPathComponent }
}

@MainActor @Observable
final class SessionStore {
    var sessions: [String: Session] = [:]
    @ObservationIgnored private var timer: Timer?

    var sorted: [Session] { sessions.values.sorted { $0.startedAt < $1.startedAt } }

    func apply(_ e: [String: Any]) {
        guard let id = e["session_id"] as? String else { return }
        let ev = e["hook_event_name"] as? String ?? ""
        if ev == "SessionEnd" { sessions[id] = nil; return }
        // Pre-warmed background spares fire SessionStart and then sit for hours; only real activity makes an agent.
        if sessions[id] == nil && ["SessionStart", "Stop", "Notification"].contains(ev) { return }
        var s = sessions[id] ?? Session(id: id, cwd: e["cwd"] as? String ?? "")
        if let cwd = e["cwd"] as? String { s.cwd = cwd }
        if let p = e["ppid"] as? Int { s.ppid = Int32(p) }
        if let t = e["transcript_path"] as? String { s.transcriptPath = t }
        if let j = e["job"] as? String { s.job = j }
        if s.bundleId == nil { // env value if the hook had it, else walk the parent chain once (cached)
            s.bundleId = (e["__CFBundleIdentifier"] as? String)
                ?? Self.termProgramBundle[e["TERM_PROGRAM"] as? String ?? ""]
                ?? s.ppid.flatMap { AppIdentity.bundleId(ppid: $0) }
        }
        s.lastEvent = Date()
        let tool = e["tool_name"] as? String
        let agent = e["agent_id"] as? String
        if let agent, ev == "PreToolUse" || ev == "PostToolUse" { // a subagent's tool call: its icon, not the parent's pose
            s.subagents[agent] = ev == "PostToolUse" ? .thinking : Self.status(for: tool)
            sessions[id] = s
            return
        }
        switch ev {
        case "PreToolUse": s.status = Self.status(for: tool)
        case "SubagentStart": s.status = .exploring; if let agent { s.subagents[agent] = .thinking }
        case "SubagentStop": s.status = .thinking; if let agent { s.subagents[agent] = nil }
        case "UserPromptSubmit", "PostToolUse": s.status = .thinking
        case "Stop": s.status = .idle; s.subagents = [:] // safety net for a missed SubagentStop
        case "PermissionRequest": s.status = .waiting
        case "Notification" where e["notification_type"] as? String == "permission_prompt": s.status = .waiting
        // Esc / denied permission ends a turn with no PostToolUse or Stop, leaving the last pose stuck;
        // Claude Code's idle-at-prompt notification (~60s later) is the only signal that it's waiting.
        case "Notification" where e["notification_type"] as? String == "idle_prompt"
            || (e["message"] as? String)?.contains("waiting for your input") == true:
            s.status = .idle; s.subagents = [:]
        default: break
        }
        if ["PostToolUse", "Stop", "UserPromptSubmit"].contains(ev), let path = s.transcriptPath,
           let u = Self.usage(fromTail: Self.tail(path)) { s.tokens = u.tokens; s.ctxPct = u.ctxPct }
        sessions[id] = s
    }

    static func status(for tool: String?) -> AgentStatus {
        switch tool {
        case "Edit", "Write", "NotebookEdit", "MultiEdit": .writing
        case "Bash": .running
        case "AskUserQuestion": .waiting
        case "Task", "Agent", "Grep", "Glob", "WebFetch", "WebSearch": .exploring
        default: .thinking
        }
    }

    static let termProgramBundle = ["Apple_Terminal": "com.apple.Terminal", "iTerm.app": "com.googlecode.iterm2",
                                    "vscode": "com.microsoft.VSCode"]

    /// Silence after which a pose is stale. Background jobs never get idle_prompt, and side queries (away summary)
    /// fire a hook with no Stop after, so without this a finished job reads "Thinking" until its process exits.
    static let staleAfter: TimeInterval = 300

    /// Drop sessions whose claude process is gone (kill(pid,0) fails with ESRCH); idle out stale poses.
    func prune(now: Date = Date(), alive: (Int32) -> Bool = { kill($0, 0) == 0 || errno == EPERM }) {
        for (id, s) in sessions {
            if let p = s.ppid, !alive(p) { sessions[id] = nil; continue }
            // ponytail: Bash exempt so long builds stay Running; an Esc'd Bash still relies on idle_prompt.
            if ![.idle, .running, .waiting].contains(s.status), now.timeIntervalSince(s.lastEvent) > Self.staleAfter {
                sessions[id]?.status = .idle; sessions[id]?.subagents = [:]
            }
        }
    }

    func startPruning() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.prune() }
        }
    }

    // MARK: transcript

    /// Last ~64KB of the file (first line may be cut; the parser skips it).
    static func tail(_ path: String) -> String {
        guard let h = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 65536 ? size - 65536 : 0)
        return String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self)
    }

    /// Last assistant message's usage → tokens and context % (200k, or 1M when the model id has "[1m]").
    nonisolated static func usage(fromTail text: String) -> (tokens: Int, ctxPct: Double)? {
        for line in text.split(separator: "\n").reversed() {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  o["type"] as? String == "assistant", let m = o["message"] as? [String: Any],
                  let u = m["usage"] as? [String: Any] else { continue }
            let n = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens", "output_tokens"]
                .reduce(0) { $0 + (u[$1] as? Int ?? 0) }
            let limit = (m["model"] as? String ?? "").contains("[1m]") ? 1_000_000.0 : 200_000.0
            return (n, Double(n) / limit * 100)
        }
        return nil
    }
}

enum AppIdentity {
    /// Walk up from `pid` until `isApp` says it's a GUI app; nil after `maxDepth` or at the root.
    static func walk(from pid: Int32, parent: (Int32) -> Int32?, isApp: (Int32) -> Bool, maxDepth: Int = 32) -> Int32? {
        var p = pid
        for _ in 0..<maxDepth {
            if isApp(p) { return p }
            guard let next = parent(p), next > 1, next != p else { return nil }
            p = next
        }
        return nil
    }

    static func parentPID(_ pid: Int32) -> Int32? {
        var info = kinfo_proc(), size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    static func app(ppid: Int32) -> NSRunningApplication? {
        walk(from: ppid, parent: parentPID, isApp: { NSRunningApplication(processIdentifier: $0) != nil })
            .flatMap { NSRunningApplication(processIdentifier: $0) }
    }

    static func bundleId(ppid: Int32) -> String? { app(ppid: ppid)?.bundleIdentifier }
}
