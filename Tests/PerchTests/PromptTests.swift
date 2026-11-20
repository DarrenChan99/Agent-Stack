import Foundation
import Testing
import Shared
@testable import Perch

@MainActor private func obj(_ s: String?) -> [String: Any]? {
    s.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
}

@MainActor @Test func queueFifoCloseAndReplies() {
    let q = PromptQueue()
    var sent: [String?] = []
    let perm = PromptItem.Kind.permission(tool: "Bash", input: [:], suggestions: [["type": "addRules"]])
    let id1 = q.enqueue(sessionId: "a", kind: perm) { sent.append($0) }
    q.enqueue(sessionId: "b", kind: .stop) { sent.append($0) }
    #expect(q.head?.id == id1 && q.items.count == 2)
    q.remove(id1) // connection closed
    #expect(q.head?.sessionId == "b" && sent.isEmpty)

    q.enqueue(sessionId: "c", kind: perm) { sent.append($0) }
    q.allow(q.items[1], always: true)
    var d = (obj(sent[0])?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
    #expect(d?["behavior"] as? String == "allow" && (d?["updatedPermissions"] as? [Any])?.count == 1)
    q.enqueue(sessionId: "c", kind: perm) { sent.append($0) }
    q.deny(q.items[1])
    d = (obj(sent[1])?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
    #expect(d?["behavior"] as? String == "deny" && d?["updatedPermissions"] == nil)

    q.enqueue(sessionId: "d", kind: .question(questions: [], raw: [["question": "Q1"], ["question": "Q2"]])) { sent.append($0) }
    q.answer(q.items[1], answers: ["Q1": "yes", "Q2": "typed"])
    let upd = ((obj(sent[2])?["hookSpecificOutput"] as? [String: Any])?["updatedInput"]) as? [String: Any]
    #expect(upd?["answers"] as? [String: String] == ["Q1": "yes", "Q2": "typed"] && (upd?["questions"] as? [Any])?.count == 2)

    q.stopReply(q.head!, text: "keep going")
    #expect(obj(sent[3])?["decision"] as? String == "block" && obj(sent[3])?["reason"] as? String == "keep going")
    #expect(q.items.isEmpty)
}

/// Blocking POSIX client off the main actor: send one line, return the first reply line (nil on EOF).
private func client(_ path: String, _ line: String, readFirst: Bool = true) async -> String? {
    await withCheckedContinuation { k in
        DispatchQueue.global().async {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            defer { close(fd) }
            guard let a = Protocol.address(path), Protocol.withSockaddr(a, { connect(fd, $0, $1) }) == 0 else { return k.resume(returning: nil) }
            let m = Array((line + "\n").utf8); _ = write(fd, m, m.count)
            var buf = [UInt8](repeating: 0, count: 4096)
            let n = read(fd, &buf, buf.count)
            k.resume(returning: n > 0 ? String(decoding: buf[0..<n], as: UTF8.self).trimmingCharacters(in: .newlines) : nil)
        }
    }
}

@MainActor @Test func socketRoundTrip() async throws {
    let path = "/tmp/perch-test-\(getpid()).sock"
    let store = SessionStore(), q = PromptQueue()
    let server = SocketServer(path: path, store: store, queue: q)
    try server.start()
    defer { server.stop() }

    let ev = #"{"session_id":"s1","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"/p"}"#
    async let reply = client(path, ev)
    while q.items.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(store.sessions["s1"] != nil)
    q.allow(q.head!)
    #expect(await reply == Protocol.line(Protocol.permission(allow: true)))

    // Stop without holdNextStop: immediate EOF, nothing queued.
    let stop = #"{"session_id":"s1","hook_event_name":"Stop"}"#
    #expect(await client(path, stop) == nil && q.items.isEmpty)

    // Armed: held, reply goes out as stopBlock, and it disarms.
    store.sessions["s1"]?.holdNextStop = true
    async let held = client(path, stop)
    while q.items.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(store.sessions["s1"]?.holdNextStop == false)
    q.stopReply(q.head!, text: "more")
    #expect(await held == Protocol.line(Protocol.stopBlock(reason: "more")))

    // Hook goes away while queued: item is removed.
    await withCheckedContinuation { (k: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().async {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            let a = Protocol.address(path)!
            _ = Protocol.withSockaddr(a) { connect(fd, $0, $1) }
            let m = Array((ev + "\n").utf8); _ = write(fd, m, m.count)
            usleep(200_000); close(fd); k.resume()
        }
    }
    for _ in 0..<100 where !q.items.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
    #expect(q.items.isEmpty)
}

@MainActor @Test func alwaysAllowSendsOnlyFirstSuggestion() {
    let q = PromptQueue()
    var sent: [String?] = []
    let s: [[String: Any]] = [["type": "addRules", "n": 1], ["type": "setMode", "n": 2]]
    q.enqueue(sessionId: "a", kind: .permission(tool: "Bash", input: [:], suggestions: s)) { sent.append($0) }
    q.allow(q.head!, always: true)
    let d = (obj(sent[0])?["hookSpecificOutput"] as? [String: Any])?["decision"] as? [String: Any]
    #expect((d?["updatedPermissions"] as? [Any])?.count == 1)
}

@MainActor @Test func promptHeadSkipsHeldStop() {
    let q = PromptQueue()
    q.enqueue(sessionId: "a", kind: .stop) { _ in }
    #expect(q.promptHead == nil)
    let id = q.enqueue(sessionId: "b", kind: .permission(tool: "Bash", input: [:], suggestions: nil)) { _ in }
    #expect(q.promptHead?.id == id && q.head?.sessionId == "a")
}

@MainActor @Test func dismissClosesWithEmptyReplyAndRemoves() {
    let q = PromptQueue()
    var sent: [String?] = []
    q.enqueue(sessionId: "a", kind: .permission(tool: "Bash", input: [:], suggestions: nil)) { sent.append($0) }
    q.dismiss(q.head!)
    #expect(sent.count == 1 && sent[0] == nil && q.items.isEmpty)
}

@Test func keysIgnoredRightAfterPromptAppears() {
    let t = Date()
    #expect(!PromptQueue.acceptsKey(shownAt: t, now: t.addingTimeInterval(0.1)))
    #expect(PromptQueue.acceptsKey(shownAt: t, now: t.addingTimeInterval(0.5)))
}

@MainActor @Test func largeReplyIsWrittenInFull() async {
    var fds: [Int32] = [0, 0]
    #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
    let conn = Connection(fd: fds[0]), rfd = fds[1]
    conn.start()
    let payload = String(repeating: "x", count: 100_000)
    let got: Int = await withCheckedContinuation { k in
        DispatchQueue.global().async {
            usleep(200_000) // slow reader: sender hits EAGAIN first
            var total = 0, buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = read(rfd, &buf, buf.count)
                if n <= 0 { break }
                total += n
            }
            close(rfd)
            k.resume(returning: total)
        }
        DispatchQueue.main.async { conn.reply(payload) }
    }
    #expect(got == payload.utf8.count + 1)
}
