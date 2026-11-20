import Foundation

/// Wire protocol between perch-hook and the app: newline-delimited JSON over a Unix socket.
public enum Protocol {
    public static var socketPath: String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return home + "/Library/Application Support/Perch/perch.sock"
    }

    /// Blocking: PermissionRequest, Stop, and PreToolUse for AskUserQuestion only.
    /// Everything else (SessionStart/End, other tools, Subagent*, Notification, UserPromptSubmit) is fire-and-forget.
    public static func isBlocking(event: String, tool: String?) -> Bool {
        switch event {
        case "PermissionRequest", "Stop": return true
        case "PreToolUse": return tool == "AskUserQuestion"
        default: return false
        }
    }

    public static func permission(allow: Bool, message: String? = nil,
                                  updatedPermissions: [[String: Any]]? = nil) -> [String: Any] {
        var d: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if let message { d["message"] = message }
        if let updatedPermissions { d["updatedPermissions"] = updatedPermissions }
        return ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": d]]
    }

    public static func askAnswer(questions: Any, answers: [String: String]) -> [String: Any] {
        ["hookSpecificOutput": [
            "hookEventName": "PreToolUse", "permissionDecision": "allow",
            "updatedInput": ["questions": questions, "answers": answers],
        ]]
    }

    public static func stopBlock(reason: String) -> [String: Any] {
        ["decision": "block", "reason": reason]
    }

    /// One JSON object as a single line (no trailing newline).
    public static func line(_ obj: [String: Any]) -> String {
        let d = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: d, as: UTF8.self)
    }
}

public extension Protocol {
    /// sockaddr_un for `path`, nil if it doesn't fit.
    static func address(_ path: String) -> sockaddr_un? {
        var a = sockaddr_un()
        a.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: a.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &a.sun_path) { $0.copyBytes(from: path.utf8) }
        return a
    }

    /// Run a bind/connect-style call against a sockaddr_un.
    static func withSockaddr<T>(_ a: sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        var a = a
        return withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }
}
