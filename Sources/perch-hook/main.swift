import Foundation
import Shared

// Fail open: any problem -> exit 0 with no stdout, so Claude Code falls back to its normal prompt.
signal(SIGPIPE, SIG_IGN)

var input = (try? JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile())) as? [String: Any] ?? [:]
let env = ProcessInfo.processInfo.environment
input["ppid"] = Int(getppid())
input["__CFBundleIdentifier"] = env["__CFBundleIdentifier"]
input["TERM_PROGRAM"] = env["TERM_PROGRAM"]
for fd: Int32 in [0, 1, 2] { if let t = ttyname(fd) { input["tty"] = String(cString: t); break } }

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0, let addr = Protocol.address(Protocol.socketPath) else { exit(0) }
let ok = Protocol.withSockaddr(addr) { connect(fd, $0, $1) }
guard ok == 0 else { exit(0) }

let msg = Array((Protocol.line(input) + "\n").utf8)
guard write(fd, msg, msg.count) == msg.count else { exit(0) }
let event = input["hook_event_name"] as? String ?? ""
guard Protocol.isBlocking(event: event, tool: input["tool_name"] as? String) else { exit(0) }

// Wait for one reply line; self-timeout = hook timeout - 10s.
let timeout = max(1, (Double(env["PERCH_HOOK_TIMEOUT"] ?? "") ?? 600) - 10)
let deadline = Date().addingTimeInterval(timeout)
var reply = [UInt8]()
var buf = [UInt8](repeating: 0, count: 4096)
while !reply.contains(10) {
    let left = Int32(deadline.timeIntervalSinceNow * 1000)
    var p = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
    guard left > 0, poll(&p, 1, left) > 0 else { exit(0) }
    let n = read(fd, &buf, buf.count)
    guard n > 0 else { exit(0) } // EOF: server closed or died
    reply += buf[0..<n]
}
FileHandle.standardOutput.write(Data(reply[0...reply.firstIndex(of: 10)!]))
exit(0)
