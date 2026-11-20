import AppKit
import SwiftUI

@MainActor @Observable
final class PanelModel {
    var dnd = UserDefaults.standard.bool(forKey: "dnd") { didSet { UserDefaults.standard.set(dnd, forKey: "dnd") } }
    var showPrompt = false   // false = agent list
    var pill = false
}

enum Jump {
    private static let openWithCwd: Set<String> = ["com.microsoft.VSCode", "com.google.android.studio"]

    @MainActor static func to(_ s: Session) {
        guard let id = s.bundleId else { return }
        if openWithCwd.contains(id) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-b", id, s.cwd]
            try? p.run()
        } else {
            NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.activate()
        }
    }
}

@MainActor private var iconCache: [String: NSImage] = [:]
@MainActor func appIcon(_ bundleId: String?) -> NSImage? {
    guard let bundleId else { return nil }
    if let i = iconCache[bundleId] { return i }
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return nil }
    let i = NSWorkspace.shared.icon(forFile: url.path)
    iconCache[bundleId] = i
    return i
}

struct AgentList: View {
    let store: SessionStore
    let queue: PromptQueue
    let fetcher: UsageFetcher
    @Bindable var model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(store.sessions.count == 1 ? "1 agent" : "\(store.sessions.count) agents")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                if !queue.prompts.isEmpty {
                    Button("\(queue.prompts.count) needs you") { model.showPrompt = true }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.crimsonSoft)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(Theme.crimsonBright, lineWidth: 1))
                }
                Spacer()
                Button { model.dnd.toggle() } label: { Image(systemName: model.dnd ? "moon.fill" : "moon") }
                    .help("Do not disturb").foregroundStyle(model.dnd ? Theme.crimsonSoft : Theme.textDim)
                Menu { Button("Settings…") { SettingsWindow.show(model: model) }; Button("Quit Perch") { NSApp.terminate(nil) } } label: { Image(systemName: "gearshape") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().foregroundStyle(Theme.textDim)
            }.buttonStyle(.plain)
            if store.sessions.isEmpty {
                QuietView()
            } else {
                ForEach(store.sorted) { s in
                    AgentRow(store: store, queue: queue, session: s)
                }
            }
            MeterView(label: "5H", window: fetcher.displayUsage?.fiveHour)
            MeterView(label: "7D", window: fetcher.displayUsage?.weekly)
            if let email = fetcher.email {
                Text(email).font(.system(size: 10)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
            }
        }
        .padding(16)
        .frame(width: 340)
        .perchPanel()
    }
}

struct AgentRow: View {
    let store: SessionStore
    let queue: PromptQueue
    let session: Session
    @State private var reply = ""

    private var stopItem: PromptItem? {
        queue.items.first { $0.sessionId == session.id && { if case .stop = $0.kind { true } else { false } }($0) }
    }

    private var symbol: (String, Color) {
        if queue.has(session: session.id) { return ("exclamationmark.bubble.fill", Theme.crimsonSoft) }
        switch session.status {
        case .thinking: return ("ellipsis.circle", Theme.textDim)
        case .writing: return ("pencil.circle", Theme.green)
        case .running: return ("terminal", Theme.green)
        case .exploring: return ("magnifyingglass.circle", Theme.amber)
        case .idle: return ("pause.circle", Theme.textFaint)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbol.0).foregroundStyle(symbol.1)
                Text(session.project).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1)
                if let icon = appIcon(session.bundleId) { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
                Spacer(minLength: 4)
                metric("number", session.tokens >= 1000 ? "\(session.tokens / 1000)k" : "\(session.tokens)")
                metric("gauge.medium", "\(Int(session.ctxPct))%")
                metric("clock", elapsed)
                Button { store.sessions[session.id]?.holdNextStop.toggle() } label: { Image(systemName: "text.bubble") }
                    .help("Hold next Stop to reply")
                    .foregroundStyle(session.holdNextStop ? Theme.crimsonSoft : Theme.textFaint)
                Button { Jump.to(session) } label: { Image(systemName: "terminal") }
                    .help("Jump to app").foregroundStyle(Theme.textDim)
                if let stopItem {
                    Button { queue.dismiss(stopItem) } label: { Image(systemName: "xmark.circle") }
                        .help("Dismiss: let Claude stop normally").foregroundStyle(Theme.textDim)
                }
            }.buttonStyle(.plain)
            if stopItem != nil {
                HStack {
                    TextField("Reply…", text: $reply).textFieldStyle(.plain).onSubmit(send)
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill") }.buttonStyle(.plain)
                        .foregroundStyle(Theme.crimsonSoft).disabled(reply.isEmpty)
                }
                .padding(8).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func send() {
        guard let stopItem, !reply.isEmpty else { return }
        queue.stopReply(stopItem, text: reply)
        reply = ""
    }

    private var elapsed: String {
        let m = Int(Date().timeIntervalSince(session.startedAt) / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    private func metric(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 2) { Image(systemName: icon); Text(text) }
            .font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textFaint)
    }
}
