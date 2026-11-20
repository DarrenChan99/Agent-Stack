import Foundation
import Testing
@testable import Perch

@MainActor @Test func statusTransitionsAndPrune() {
    let s = SessionStore()
    func ev(_ e: String, _ tool: String? = nil) -> [String: Any] {
        var d: [String: Any] = ["session_id": "a", "hook_event_name": e, "cwd": "/x/proj", "__CFBundleIdentifier": "com.test"]
        d["tool_name"] = tool
        return d
    }
    let cases: [(String, String?, AgentStatus)] = [
        ("PreToolUse", "Edit", .writing), ("PreToolUse", "Write", .writing), ("PreToolUse", "NotebookEdit", .writing),
        ("PreToolUse", "Bash", .running), ("PreToolUse", "Task", .exploring), ("PreToolUse", "Read", .thinking),
        ("SubagentStart", nil, .exploring), ("UserPromptSubmit", nil, .thinking), ("PostToolUse", "Bash", .thinking),
        ("Stop", nil, .idle),
    ]
    for (e, t, want) in cases {
        s.apply(ev(e, t))
        #expect(s.sessions["a"]?.status == want, "\(e) \(t ?? "")")
    }
    #expect(s.sessions["a"]?.project == "proj" && s.sessions["a"]?.bundleId == "com.test")
    // interrupted Bash: no PostToolUse/Stop, only the idle notification
    s.apply(ev("PreToolUse", "Bash"))
    var n = ev("Notification"); n["notification_type"] = "permission_prompt"
    s.apply(n)
    #expect(s.sessions["a"]?.status == .waiting) // terminal is showing a permission dialog
    n["notification_type"] = "idle_prompt"
    s.apply(n)
    #expect(s.sessions["a"]?.status == .idle)
    s.apply(["session_id": "b", "hook_event_name": "SessionStart", "cwd": "/y", "ppid": 99])
    #expect(s.sessions["b"] == nil) // a bare SessionStart (idle spare) is not an agent
    s.apply(["session_id": "b", "hook_event_name": "UserPromptSubmit", "cwd": "/y", "ppid": 99])
    #expect(s.sessions["b"]?.status == .thinking)
    s.prune { $0 != 99 }
    #expect(s.sessions["b"] == nil && s.sessions["a"] != nil)
    // A turn-ending event that never comes (background job's away-summary, no idle_prompt) mustn't pin a pose forever.
    s.apply(ev("UserPromptSubmit"))
    s.prune(now: Date().addingTimeInterval(60)) { _ in true }
    #expect(s.sessions["a"]?.status == .thinking)
    s.prune(now: Date().addingTimeInterval(SessionStore.staleAfter + 1)) { _ in true }
    #expect(s.sessions["a"]?.status == .idle)
    s.apply(ev("PreToolUse", "Bash"))
    s.prune(now: Date().addingTimeInterval(SessionStore.staleAfter + 1)) { _ in true }
    #expect(s.sessions["a"]?.status == .running) // long builds/tests stay Running
    s.apply(ev("SessionEnd"))
    #expect(s.sessions.isEmpty)
}

@Test func transcriptUsage() {
    let tail = """
    {"type":"assistant","message":{"model":"claude-opus-4[1m]","usage":{"input_tokens":1,"cache_read_input_tokens":2,"cache_creation_input_tokens":3,"output_tokens":4}}}
    {"type":"user","message":{"content":"hi"}}
    {"type":"assistant","message":{"model":"claude-sonnet-5","usage":{"input_tokens":10000,"cache_read_input_tokens":80000,"cache_creation_input_tokens":5000,"output_tokens":5000}}}
    {"type":"user","message":{}}
    {"cut off partial line
    """
    let u = SessionStore.usage(fromTail: tail)!
    #expect(u.tokens == 100_000 && u.ctxPct == 50)
    let big = SessionStore.usage(fromTail: tail.split(separator: "\n").first!.description)!
    #expect(big.tokens == 10 && big.ctxPct == 10.0 / 1_000_000 * 100)
    #expect(SessionStore.usage(fromTail: "garbage\n{}") == nil)
}

@Test func parentChainWalk() {
    let parents: [Int32: Int32] = [100: 50, 50: 20, 20: 1]
    #expect(AppIdentity.walk(from: 100, parent: { parents[$0] }, isApp: { $0 == 20 }) == 20)
    #expect(AppIdentity.walk(from: 100, parent: { parents[$0] }, isApp: { _ in false }) == nil)
    #expect(AppIdentity.walk(from: 5, parent: { _ in 5 }, isApp: { _ in false }) == nil) // loop guard
    _ = AppIdentity.app(ppid: getpid()) // real sysctl walk terminates (xctest may or may not sit under an app)
}

@MainActor @Test func subagentsTrackedSeparately() {
    let s = SessionStore()
    func ev(_ e: String, _ tool: String? = nil, agent: String? = nil) {
        var d: [String: Any] = ["session_id": "a", "hook_event_name": e, "cwd": "/x", "__CFBundleIdentifier": "c"]
        d["tool_name"] = tool; d["agent_id"] = agent
        s.apply(d)
    }
    ev("UserPromptSubmit")
    ev("SubagentStart", agent: "x"); ev("SubagentStart", agent: "y")
    ev("PreToolUse", "Edit", agent: "x"); ev("PreToolUse", "Grep", agent: "y")
    #expect(s.sessions["a"]?.subagents == ["x": .writing, "y": .exploring])
    #expect(s.sessions["a"]?.status == .exploring) // parent is waiting on its subagents, not writing
    ev("PostToolUse", "Edit", agent: "x")
    #expect(s.sessions["a"]?.subagents["x"] == .thinking)
    ev("SubagentStop", agent: "x")
    #expect(s.sessions["a"]?.subagents == ["y": .exploring])
    ev("Stop")
    #expect(s.sessions["a"]?.subagents.isEmpty == true)
}

@Test func menuBarDotShowsMostActionable() {
    #expect(AgentDot.from(statuses: [], pending: 0) == .none)
    #expect(AgentDot.from(statuses: [.idle, .idle], pending: 0) == .done)
    #expect(AgentDot.from(statuses: [.idle, .running], pending: 0) == .working)
    #expect(AgentDot.from(statuses: [.idle, .running], pending: 1) == .needsYou)
}

/// A released prompt (DND or hold timeout) must keep the card red and never stale out, and bg jobs must be jumpable.
@MainActor @Test func waitingSurvivesReleaseAndBgJobsJump() {
    let s = SessionStore()
    s.apply(["session_id": "j", "hook_event_name": "PreToolUse", "tool_name": "Bash", "cwd": "/p", "job": "c918b816"])
    #expect(s.sessions["j"]?.job == "c918b816")
    s.apply(["session_id": "j", "hook_event_name": "PermissionRequest", "tool_name": "Bash"])
    #expect(s.sessions["j"]?.status == .waiting)
    s.prune(now: Date().addingTimeInterval(3600)) { _ in true }
    #expect(s.sessions["j"]?.status == .waiting) // a prompt may sit for hours
    #expect(Pose(.waiting, needsYou: false) == .needsYou)
    #expect(AgentDot.from(statuses: [.running, .waiting], pending: 0) == .needsYou)
    s.apply(["session_id": "j", "hook_event_name": "PostToolUse", "tool_name": "Bash"])
    #expect(s.sessions["j"]?.status == .thinking)
    s.apply(["session_id": "j", "hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion"])
    #expect(s.sessions["j"]?.status == .waiting)
    #expect(Jump.safeJob("c918b816") == "c918b816" && Jump.safeJob("x; rm -rf ~") == nil)
}

@Test @MainActor func jumpFindsTerminalTTYs() {
    let ps = """
      100 ttys003 claude
      200 ??      claude --bg-pty-host x
      300 ttys009 /Users/me/.local/bin/claude attach c918b816
      301 ttys010 claude attach ffff0000
      302 ttys011 vim attach c918b816
    """
    var fg = Session(id: "sess-a", cwd: "/x"); fg.ppid = 100
    #expect(Jump.ttys(for: fg, ps: ps) == ["/dev/ttys003"])
    var bg = Session(id: "c918b816-7b43", cwd: "/x"); bg.ppid = 200; bg.job = "c918b816"
    #expect(Jump.ttys(for: bg, ps: ps) == ["/dev/ttys009"])
    #expect(Jump.claudeHosts(ps: ps) == [100])
}

@Test func jumpPicksVSCodeWindowFolder() {
    let wins = ["/Users/d/Agent-Stack", "/Users/d/Task-Stack", "/Users/d/Agent-Stack/web"]
    #expect(Jump.vscodeFolder(for: "/Users/d/Task-Stack", openWindows: wins) == "/Users/d/Task-Stack")
    #expect(Jump.vscodeFolder(for: "/Users/d/Agent-Stack/Sources", openWindows: wins) == "/Users/d/Agent-Stack")
    #expect(Jump.vscodeFolder(for: "/Users/d/Agent-Stack/web/src", openWindows: wins) == "/Users/d/Agent-Stack/web")
    #expect(Jump.vscodeFolder(for: "/Users/d/Agent-StackX", openWindows: wins) == "/Users/d/Agent-StackX")
}
