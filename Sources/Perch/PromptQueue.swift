import Foundation
import Observation
import Shared

struct Question {
    var text: String
    var options: [String]
    var multiSelect: Bool
}

struct PromptItem: Identifiable {
    enum Kind {
        case permission(tool: String, input: [String: Any], suggestions: [[String: Any]]?)
        case question(questions: [Question], raw: Any)
        case stop
    }
    let id = UUID()
    let sessionId: String
    let kind: Kind
    /// Writes one line to the hook's connection and closes it; nil just closes (hook falls back to the normal prompt).
    let reply: (String?) -> Void
}

@MainActor @Observable
final class PromptQueue {
    private(set) var items: [PromptItem] = []   // FIFO
    var head: PromptItem? { items.first }
    /// Permission/question prompts only; a held Stop just drives its session row's reply field.
    var prompts: [PromptItem] { items.filter { if case .stop = $0.kind { false } else { true } } }
    var promptHead: PromptItem? { prompts.first }
    /// Ignore Allow/Deny keys right after a prompt appears so a repeated Return can't approve an unseen one.
    nonisolated static func acceptsKey(shownAt: Date, now: Date) -> Bool { now.timeIntervalSince(shownAt) >= 0.4 }
    func has(session: String) -> Bool { items.contains { $0.sessionId == session } }

    @discardableResult
    func enqueue(sessionId: String, kind: PromptItem.Kind, reply: @escaping (String?) -> Void) -> UUID {
        let item = PromptItem(sessionId: sessionId, kind: kind, reply: reply)
        items.append(item)
        return item.id
    }

    /// Connection closed / timed out: drop silently (no reply to write).
    func remove(_ id: UUID) { items.removeAll { $0.id == id } }

    private func finish(_ item: PromptItem, _ obj: [String: Any]?) {
        remove(item.id)
        item.reply(obj.map(Protocol.line))
    }

    func allow(_ item: PromptItem, always: Bool = false) {
        var suggestions: [[String: Any]]?
        if always, case .permission(_, _, let s) = item.kind { suggestions = s?.first.map { [$0] } } // label names rules[0] only
        finish(item, Protocol.permission(allow: true, updatedPermissions: suggestions))
    }
    func deny(_ item: PromptItem, message: String? = nil) { finish(item, Protocol.permission(allow: false, message: message)) }
    func answer(_ item: PromptItem, answers: [String: String]) {
        guard case .question(_, let raw) = item.kind else { return }
        finish(item, Protocol.askAnswer(questions: raw, answers: answers))
    }
    func stopReply(_ item: PromptItem, text: String) { finish(item, Protocol.stopBlock(reason: text)) }
    /// Let Claude Code show its own prompt / stop normally.
    func dismiss(_ item: PromptItem) { finish(item, nil) }
}
