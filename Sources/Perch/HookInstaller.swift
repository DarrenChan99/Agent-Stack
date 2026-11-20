import Foundation

/// Merges/removes perch-hook entries in a Claude Code settings.json. JSONSerialization keeps unknown keys intact.
enum HookInstaller {
    /// One entry per event; PreToolUse uses "*" (not just AskUserQuestion) so tool status works; perch-hook branches on tool_name.
    static let events = ["PermissionRequest", "PreToolUse", "Stop", "SessionStart", "SessionEnd",
                         "PostToolUse", "SubagentStart", "SubagentStop", "Notification", "UserPromptSubmit"]

    static func install(settings: URL, hookPath: String, timeout: Int = 600) throws {
        // Shell-quoted path; the env var lets the hook self-timeout at timeout - 10s.
        let command = "PERCH_HOOK_TIMEOUT=\(timeout) '" + hookPath.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
        let original = try read(settings)
        var root = strip(original)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for event in events {
            let entry: [String: Any] = [
                "matcher": "*",
                "hooks": [["type": "command", "command": command, "timeout": timeout] as [String: Any]],
            ]
            hooks[event] = (hooks[event] as? [Any] ?? []) + [entry]
        }
        root["hooks"] = hooks
        guard (root as NSDictionary) != (original as NSDictionary) else { return } // already installed: don't touch backup
        if FileManager.default.fileExists(atPath: settings.path) {
            let bak = URL(fileURLWithPath: settings.path + ".perch-bak")
            try? FileManager.default.removeItem(at: bak)
            try FileManager.default.copyItem(at: settings, to: bak)
        }
        try write(root, to: settings)
    }

    static func uninstall(settings: URL) throws {
        guard FileManager.default.fileExists(atPath: settings.path) else { return }
        try write(strip(try read(settings)), to: settings)
    }

    /// Removes only hook commands containing "perch-hook"; drops entries/events/`hooks` left empty.
    static func strip(_ root: [String: Any]) -> [String: Any] {
        var root = root
        guard var hooks = root["hooks"] as? [String: Any] else { return root }
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = entries.compactMap { entry in
                guard let inner = entry["hooks"] as? [[String: Any]] else { return entry }
                let rest = inner.filter { !(($0["command"] as? String)?.contains("perch-hook") ?? false) }
                if rest.count == inner.count { return entry }
                if rest.isEmpty { return nil }
                var e = entry; e["hooks"] = rest; return e
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        root["hooks"] = hooks.isEmpty ? nil : hooks
        return root
    }

    private static func read(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
    }

    private static func write(_ root: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}

private let destructivePattern = try! NSRegularExpression(pattern: [
    #"(?:^|[\s;&|('"`/\\])rm(?:\s|$)"#,
    #"\bgit\s+(?:clean\b|reset\s+--hard\b|checkout\s+--|restore\b|branch\s+-D|stash\s+(?:drop|clear)|push\b.*(?:\s-f\b|--force))"#,
    #"\bfind\b.*\s-delete\b"#,
    #"\b(?:truncate|shred|unlink)\b"#,
    #"\bdd\b.*\bof="#,
    #"\bsed\s+(?:-\w*i|--in-place)"#,
    #"--delete\b"#,
    #"(?<![>=-])>(?![>&])(?!\s*/dev/null)"#, // single `>` overwrite (incl. &>, 2>); not >>, 2>&1, ->, or /dev/null
].joined(separator: "|"))

/// True when a shell command probably deletes or overwrites files (drives the "deletes files" tag and ⌘↵ rule).
func isDestructive(_ command: String) -> Bool {
    destructivePattern.firstMatch(in: command, range: NSRange(command.startIndex..., in: command)) != nil
}
