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
    s.apply(["session_id": "b", "hook_event_name": "SessionStart", "cwd": "/y", "ppid": 99])
    #expect(s.sessions["b"] == nil) // a bare SessionStart (idle spare) is not an agent
    s.apply(["session_id": "b", "hook_event_name": "UserPromptSubmit", "cwd": "/y", "ppid": 99])
    #expect(s.sessions["b"]?.status == .thinking)
    s.prune { $0 != 99 }
    #expect(s.sessions["b"] == nil && s.sessions["a"] != nil)
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
