import Foundation
import Testing
@testable import Shared

func json(_ d: [String: Any]) -> NSDictionary { d as NSDictionary }
func parse(_ s: String) -> NSDictionary {
    try! JSONSerialization.jsonObject(with: Data(s.utf8)) as! NSDictionary
}

@Test func permissionAllowShape() {
    let out = Protocol.permission(allow: true)
    #expect(json(out) == parse(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#))
}

@Test func permissionDenyWithMessageAndUpdates() {
    let perms: [[String: Any]] = [["type": "addRules", "behavior": "allow"]]
    let out = Protocol.permission(allow: false, message: "no", updatedPermissions: perms)
    #expect(json(out) == parse(#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"no","updatedPermissions":[{"type":"addRules","behavior":"allow"}]}}}"#))
}

@Test func askUserQuestionShape() {
    let qs: [[String: Any]] = [["question": "Pick?", "options": [["label": "A"]]]]
    let out = Protocol.askAnswer(questions: qs, answers: ["Pick?": "A"])
    #expect(json(out) == parse(#"{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":{"questions":[{"question":"Pick?","options":[{"label":"A"}]}],"answers":{"Pick?":"A"}}}}"#))
}

@Test func stopBlockShape() {
    #expect(json(Protocol.stopBlock(reason: "keep going")) == parse(#"{"decision":"block","reason":"keep going"}"#))
}

@Test func blockingEvents() {
    #expect(Protocol.isBlocking(event: "PermissionRequest", tool: "Bash"))
    #expect(Protocol.isBlocking(event: "Stop", tool: nil))
    #expect(Protocol.isBlocking(event: "PreToolUse", tool: "AskUserQuestion"))
    #expect(!Protocol.isBlocking(event: "PreToolUse", tool: "Bash"))
    #expect(!Protocol.isBlocking(event: "PostToolUse", tool: "AskUserQuestion"))
    #expect(!Protocol.isBlocking(event: "SessionStart", tool: nil))
}

@Test func socketPathLocation() {
    #expect(Protocol.socketPath.hasSuffix("/Library/Application Support/Perch/perch.sock"))
}
