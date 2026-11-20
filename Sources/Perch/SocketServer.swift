import Foundation
import Shared

/// One accepted hook connection. All callbacks run on the main queue; fds are non-blocking, so main never waits on I/O.
final class Connection {
    private let fd: Int32
    private var source: DispatchSourceRead?
    private var buf = Data()
    private var closed = false
    var onLine: (([String: Any], Connection) -> Void)?
    var onClose: (() -> Void)?

    init(fd: Int32) {
        self.fd = fd
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let s = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        s.setEventHandler { self.readable() } // strong: the source keeps the connection alive until close() cancels it
        source = s
    }
    func start() { source?.resume() }

    private func readable() {
        var chunk = [UInt8](repeating: 0, count: 65536)
        let n = read(fd, &chunk, chunk.count)
        if n == 0 || (n < 0 && errno != EAGAIN && errno != EINTR) { return close() } // EOF/HUP: hook died or timed out
        if n > 0, onLine != nil {
            buf += chunk[0..<n]
            if let nl = buf.firstIndex(of: 10) {
                let obj = try? JSONSerialization.jsonObject(with: buf[buf.startIndex..<nl]) as? [String: Any]
                let cb = onLine; onLine = nil
                guard let obj else { return close() }
                cb?(obj, self)
            } else if buf.count > 4_000_000 { close() }
        }
    }

    /// Write one line in full and close. On a full send buffer, wait up to 2s for the reader to drain.
    /// ponytail: blocks main during that wait; move to a write DispatchSource if replies get big or readers slow.
    func reply(_ line: String?) {
        if let line, !closed {
            let out = Array((line + "\n").utf8)
            var off = 0
            while off < out.count {
                let n = out[off...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
                if n > 0 { off += n; continue }
                if n < 0 && errno == EINTR { continue }
                var p = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                if n < 0 && errno == EAGAIN && poll(&p, 1, 2000) > 0 { continue }
                break
            }
        }
        close()
    }

    func close() {
        guard !closed else { return }
        closed = true
        let cb = onClose; onClose = nil
        source?.cancel(); source = nil
        Darwin.close(fd)
        cb?()
    }
}

@MainActor
final class SocketServer {
    let path: String
    let store: SessionStore
    let queue: PromptQueue
    private var listener: DispatchSourceRead?
    var stopHold: Double = 120
    /// How long a permission/question waits on Perch before Claude gets it back. The card stays red after release
    /// (status .waiting), so the prompt "sits" in Perch while Claude's own terminal prompt takes over.
    var promptHold: Double = 90
    var dnd: () -> Bool = { false }

    init(path: String = Protocol.socketPath, store: SessionStore, queue: PromptQueue) {
        self.path = path; self.store = store; self.queue = queue
    }

    func start() throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        unlink(path)
        let ls = socket(AF_UNIX, SOCK_STREAM, 0)
        guard ls >= 0, let addr = Protocol.address(path), Protocol.withSockaddr(addr, { bind(ls, $0, $1) }) == 0,
              listen(ls, 32) == 0 else { throw POSIXError(.EADDRINUSE) }
        _ = fcntl(ls, F_SETFL, fcntl(ls, F_GETFL) | O_NONBLOCK)
        let s = DispatchSource.makeReadSource(fileDescriptor: ls, queue: .main)
        s.setEventHandler { [weak self] in
            while true {
                let c = accept(ls, nil, nil)
                if c < 0 { break }
                let conn = Connection(fd: c)
                conn.onLine = { e, conn in MainActor.assumeIsolated { self?.route(e, conn) } }
                conn.start()
            }
        }
        s.setCancelHandler { Darwin.close(ls) }
        s.resume()
        listener = s
    }

    func stop() { listener?.cancel(); listener = nil; unlink(path) }

    func route(_ e: [String: Any], _ c: Connection) {
        let ev = e["hook_event_name"] as? String ?? ""
        let tool = e["tool_name"] as? String
        store.apply(e)
        guard let sid = e["session_id"] as? String, Protocol.isBlocking(event: ev, tool: tool) else { return c.close() }
        if ev != "Stop" && dnd() { return c.close() } // DND: never hold Claude for a prompt nobody will see
        let kind: PromptItem.Kind
        switch ev {
        case "PermissionRequest":
            kind = .permission(tool: tool ?? "?", input: e["tool_input"] as? [String: Any] ?? [:],
                               suggestions: e["permission_suggestions"] as? [[String: Any]])
        case "Stop":
            guard store.sessions[sid]?.holdNextStop == true else { return c.close() } // default: don't hold Stop
            store.sessions[sid]?.holdNextStop = false // one use
            kind = .stop
        default: // PreToolUse AskUserQuestion
            let raw = (e["tool_input"] as? [String: Any])?["questions"] ?? []
            let qs = (raw as? [[String: Any]] ?? []).map {
                Question(text: $0["question"] as? String ?? "",
                         options: ($0["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String },
                         multiSelect: $0["multiSelect"] as? Bool ?? false)
            }
            guard !qs.isEmpty else { return c.close() }
            kind = .question(questions: qs, raw: raw)
        }
        let id = queue.enqueue(sessionId: sid, kind: kind, reply: { c.reply($0) })
        c.onClose = { [queue] in MainActor.assumeIsolated { queue.remove(id) } }
        DispatchQueue.main.asyncAfter(deadline: .now() + (ev == "Stop" ? stopHold : promptHold)) { c.reply(nil) }
    }
}
