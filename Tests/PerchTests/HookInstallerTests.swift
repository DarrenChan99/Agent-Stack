import Foundation
import Testing
@testable import Perch

let settingsFixture = #"""
{
  "model": "opus",
  "permissions": {"allow": ["Bash(ls:*)"], "deny": []},
  "env": {"FOO": "bar"},
  "hooks": {
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "rtk-rewrite", "timeout": 5}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "/usr/local/bin/notify-done"}]}]
  },
  "statusLine": {"type": "command", "command": "echo hi"}
}
"""#

func tempSettings(_ json: String?) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("perch-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("settings.json")
    if let json { try json.write(to: url, atomically: true, encoding: .utf8) }
    return url
}
func load(_ url: URL) throws -> NSDictionary {
    try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! NSDictionary
}
let hook = "/Applications/Perch.app/Contents/MacOS/perch-hook"

@Test func installAddsEntriesAndKeepsForeign() throws {
    let url = try tempSettings(settingsFixture)
    try HookInstaller.install(settings: url, hookPath: hook)
    let hooks = try load(url)["hooks"] as! [String: [[String: Any]]]
    let pre = hooks["PreToolUse"]!
    #expect(pre.count == 2)
    #expect(pre.contains { $0["matcher"] as? String == "Bash" })
    let mine = pre.first { ($0["hooks"] as! [[String: Any]]).contains { ($0["command"] as! String).contains("perch-hook") } }!
    #expect(mine["matcher"] as? String == "AskUserQuestion")
    let h = (mine["hooks"] as! [[String: Any]])[0]
    #expect(h["type"] as? String == "command" && h["command"] as? String == hook && h["timeout"] as? Int == 600)
    #expect(hooks["PermissionRequest"]![0]["matcher"] as? String == "*")
    #expect(hooks["Stop"]!.count == 2)
    let model = try load(url)["model"] as? String
    #expect(model == "opus")
    #expect(FileManager.default.fileExists(atPath: url.path + ".perch-bak"))
}

@Test func backupIsOriginal() throws {
    let url = try tempSettings(settingsFixture)
    try HookInstaller.install(settings: url, hookPath: hook)
    let bak = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: url.path + ".perch-bak"))) as! NSDictionary
    let want = try JSONSerialization.jsonObject(with: Data(settingsFixture.utf8)) as! NSDictionary
    #expect(bak == want)
}

@Test func installTwiceEqualsOnce() throws {
    let a = try tempSettings(settingsFixture), b = try tempSettings(settingsFixture)
    try HookInstaller.install(settings: a, hookPath: hook)
    try HookInstaller.install(settings: b, hookPath: hook)
    try HookInstaller.install(settings: b, hookPath: hook)
    let (la, lb) = (try load(a), try load(b))
    #expect(la == lb)
}

@Test func roundTripRestoresOriginal() throws {
    let url = try tempSettings(settingsFixture)
    try HookInstaller.install(settings: url, hookPath: hook)
    try HookInstaller.uninstall(settings: url)
    let got = try load(url), want = try JSONSerialization.jsonObject(with: Data(settingsFixture.utf8)) as! NSDictionary
    #expect(got == want)
}

@Test func installIntoMissingFileThenUninstall() throws {
    let url = try tempSettings(nil)
    try HookInstaller.install(settings: url, hookPath: hook)
    let n = (try load(url)["hooks"] as! [String: Any]).count
    #expect(n == HookInstaller.events.count)
    try HookInstaller.uninstall(settings: url)
    let got = try load(url)
    #expect(got.count == 0)
}

@Test func destructiveCommands() {
    for c in ["rm -rf build", "sudo rm file", "ls && rm x", "git clean -fd", "git reset --hard HEAD~1",
              "find . -name '*.o' -delete", "truncate -s 0 f", "echo hi > file", "cat a>b", "git rm foo"] {
        #expect(isDestructive(c), "\(c)")
    }
    for c in ["ls", "git status", "echo hi >> log", "ls 2>&1", "make 2>/dev/null", "echo hi > /dev/null", "git reset --soft HEAD~1", "grep farm x"] {
        #expect(!isDestructive(c), "\(c)")
    }
}
