import Foundation
import Shared

// Throwaway: prints every hook event; for blocking events asks you for the reply on stdin.
signal(SIGPIPE, SIG_IGN)
let path = Protocol.socketPath
try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
unlink(path)
let ls = socket(AF_UNIX, SOCK_STREAM, 0)
guard let addr = Protocol.address(path), Protocol.withSockaddr(addr, { bind(ls, $0, $1) }) == 0 else { fatalError("bind failed") }
listen(ls, 16)
print("spike-server listening on \(path)")

let promptLock = NSLock() // one stdin prompt at a time

func ask(_ q: String) -> String { print(q, terminator: " "); fflush(stdout); return readLine() ?? "" }

func reply(to msg: [String: Any]) -> [String: Any]? {
    let tool = msg["tool_name"] as? String
    switch msg["hook_event_name"] as? String ?? "" {
    case "PermissionRequest":
        let input = (msg["tool_input"] as? [String: Any]).map { Protocol.line($0) } ?? ""
        print("  tool=\(tool ?? "?") input=\(input)")
        let sugg = msg["permission_suggestions"] as? [[String: Any]]
        if let sugg { print("  permission_suggestions=\(Protocol.line(["s": sugg]))") }
        switch ask("[a]llow  [d]eny  [A]lways(allow+suggestions)  [m]sg-deny  [enter]=no reply:") {
        case "a": return Protocol.permission(allow: true)
        case "d": return Protocol.permission(allow: false)
        case "A": return Protocol.permission(allow: true, updatedPermissions: sugg)
        case "m": return Protocol.permission(allow: false, message: ask("deny message:"))
        default: return nil
        }
    case "PreToolUse": // AskUserQuestion
        let qs = (msg["tool_input"] as? [String: Any])?["questions"] ?? []
        var answers = [String: String]()
        for q in qs as? [[String: Any]] ?? [] {
            let text = q["question"] as? String ?? ""
            let opts = (q["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
            print("  Q: \(text)  options: \(opts.enumerated().map { "\($0.offset + 1)=\($0.element)" })")
            let a = ask("answer (number or free text, empty=skip all):")
            if a.isEmpty { return nil }
            answers[text] = Int(a).flatMap { opts.indices.contains($0 - 1) ? opts[$0 - 1] : nil } ?? a
        }
        return Protocol.askAnswer(questions: qs, answers: answers)
    case "Stop":
        let r = ask("stop reply (empty=let it stop):")
        return r.isEmpty ? nil : Protocol.stopBlock(reason: r)
    default: return nil
    }
}

func handle(_ c: Int32) {
    var data = [UInt8](), buf = [UInt8](repeating: 0, count: 65536)
    while !data.contains(10) { let n = read(c, &buf, buf.count); if n <= 0 { break }; data += buf[0..<n] }
    defer { close(c) }
    guard let msg = (try? JSONSerialization.jsonObject(with: Data(data))) as? [String: Any] else { return }
    let ev = msg["hook_event_name"] as? String ?? "?"
    let blocking = Protocol.isBlocking(event: ev, tool: msg["tool_name"] as? String)
    print("[\(ev)\(blocking ? " BLOCKING" : "")] tool=\(msg["tool_name"] as? String ?? "-") app=\(msg["__CFBundleIdentifier"] as? String ?? msg["TERM_PROGRAM"] as? String ?? "?") ppid=\(msg["ppid"] ?? "?") tty=\(msg["tty"] ?? "-") cwd=\(msg["cwd"] ?? "-")")
    guard blocking else { return }
    promptLock.lock(); defer { promptLock.unlock() }
    guard let r = reply(to: msg) else { print("  (no reply, closing)"); return }
    let out = Array((Protocol.line(r) + "\n").utf8)
    _ = write(c, out, out.count)
}

while true {
    let c = accept(ls, nil, nil)
    if c >= 0 { Thread.detachNewThread { handle(c) } }
}
