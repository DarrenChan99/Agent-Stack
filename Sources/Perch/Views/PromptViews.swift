import AppKit
import Shared
import SwiftUI

/// Shared header: project + app icon, terminal and minimize buttons.
struct PromptHeader: View {
    let session: Session?
    let minimize: () -> Void
    let onTerminal: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            if let icon = appIcon(session?.bundleId) { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
            Text(session?.project ?? "Claude").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            Spacer()
            Button { onTerminal() } label: { Image(systemName: "terminal").hitBox() }.help("Hand back to terminal")
            Button(action: minimize) { Image(systemName: "minus").hitBox() }.help("Minimize")
        }.buttonStyle(.plain).foregroundStyle(Theme.textDim)
    }
}

struct PermissionView: View {
    let item: PromptItem
    let session: Session?
    let queue: PromptQueue
    let minimize: () -> Void
    @State private var shownAt = Date()

    var body: some View {
        guard case .permission(let tool, let input, let suggestions) = item.kind else { return AnyView(EmptyView()) }
        let text = tool == "Bash" ? (input["command"] as? String ?? "")
            : (input["file_path"] as? String ?? Protocol.line(input))
        let destructive = tool == "Bash" && isDestructive(text)
        return AnyView(VStack(alignment: .leading, spacing: 10) {
            PromptHeader(session: session, minimize: minimize, onTerminal: { queue.dismiss(item); if let session { Jump.to(session) } })
            Text(tool).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textDim)
            ScrollView { Text(text).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.text)
                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                .frame(maxHeight: 140).padding(8).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            if let cwd = session?.cwd { Text(cwd).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textFaint).lineLimit(1) }
            if destructive { Label("deletes files", systemImage: "trash").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.crimsonSoft) }
            HStack {
                if suggestions != nil {
                    Button("Always allow \(Self.pattern(suggestions) ?? tool)") { if keyOK { queue.allow(item, always: true) } }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.textDim).lineLimit(1)
                }
                Spacer()
                Button("Deny") { if keyOK { queue.deny(item) } }.buttonStyle(.plain).foregroundStyle(Theme.textDim).keyboardShortcut(.escape, modifiers: [])
                Button("Allow ↵") { if keyOK { queue.allow(item) } }.buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: destructive ? .command : []) // plain ↵ never approves a destructive command
            }
        }.padding(16).frame(width: 340).perchPanel())
    }

    private var keyOK: Bool { PromptQueue.acceptsKey(shownAt: shownAt, now: Date()) }

    /// permission_suggestions: [{type:"addRules", rules:[{toolName, ruleContent}], ...}] → "Bash(npm test)"-style label.
    static func pattern(_ s: [[String: Any]]?) -> String? {
        guard let r = (s?.first?["rules"] as? [[String: Any]])?.first, let t = r["toolName"] as? String else { return nil }
        return (r["ruleContent"] as? String).map { "\(t)(\($0))" } ?? t
    }
}

struct QuestionView: View {
    let item: PromptItem
    let session: Session?
    let queue: PromptQueue
    let minimize: () -> Void
    @State private var page = 0
    @State private var answers: [String: String] = [:]
    @State private var picked: Set<String> = []
    @State private var custom = ""
    @FocusState private var typing: Bool

    var body: some View {
        guard case .question(let qs, _) = item.kind, qs.indices.contains(page) else { return AnyView(EmptyView()) }
        let q = qs[page]
        return AnyView(VStack(alignment: .leading, spacing: 10) {
            HStack {
                PromptHeader(session: session, minimize: minimize, onTerminal: { queue.dismiss(item); if let session { Jump.to(session) } })
                if qs.count > 1 { Text("\(page + 1)/\(qs.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textDim) }
            }
            Text(q.text).font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, label in
                Button { tap(label, q, qs.count) } label: {
                    HStack { Text("\(i + 1)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textDim)
                        Text(label).foregroundStyle(Theme.text); Spacer()
                        if picked.contains(label) { Image(systemName: "checkmark").foregroundStyle(Theme.crimsonSoft) } }
                    .padding(8).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(i < 9 && !typing ? KeyEquivalent(Character("\(i + 1)")) : "\u{0}", modifiers: [])
            }
            if q.multiSelect && !picked.isEmpty {
                Button("Next") { commit(q.options.filter(picked.contains).joined(separator: ", "), q, qs.count) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            HStack {
                TextField("Answer…", text: $custom).textFieldStyle(.plain).focused($typing)
                    .onSubmit { if !custom.isEmpty { commit(custom, q, qs.count) } }
                Button { commit(custom, q, qs.count) } label: { Image(systemName: "arrow.up.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.crimsonSoft).disabled(custom.isEmpty)
            }.padding(8).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        }.padding(16).frame(width: 400).perchPanel())
    }

    private func tap(_ label: String, _ q: Question, _ count: Int) {
        if q.multiSelect { if !picked.insert(label).inserted { picked.remove(label) } } else { commit(label, q, count) }
    }

    /// Record this page's answer; after the last page send everything as one reply.
    private func commit(_ answer: String, _ q: Question, _ count: Int) {
        answers[q.text] = answer
        picked = []; custom = ""
        if page + 1 < count { page += 1 } else { queue.answer(item, answers: answers) }
    }
}
