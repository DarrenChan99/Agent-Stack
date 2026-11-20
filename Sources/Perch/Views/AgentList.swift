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
        VStack(alignment: .leading, spacing: 8) {
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
                Button { store.prune(); fetcher.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Reload: drop ended agents, refresh usage").foregroundStyle(Theme.textDim)
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

    private var pose: Pose { Pose(session.status, needsYou: queue.has(session: session.id)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                PixelArtView(pixels: { [pose, animal = Animal(sessionId: session.id)] in pose.pixels($0, animal: animal) }, prop: pose.prop)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(session.project).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                        if let icon = appIcon(session.bundleId) { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
                        Spacer(minLength: 4)
                        Button { store.sessions[session.id]?.holdNextStop.toggle() } label: { Image(systemName: "text.bubble") }
                            .help("Hold next Stop to reply")
                            .foregroundStyle(session.holdNextStop ? Theme.crimsonSoft : Theme.textFaint)
                        Button { Jump.to(session) } label: { Image(systemName: "arrow.up.forward.app") }
                            .help("Jump to app").foregroundStyle(Theme.textDim)
                        if let stopItem {
                            Button { queue.dismiss(stopItem) } label: { Image(systemName: "xmark.circle") }
                                .help("Dismiss: let Claude stop normally").foregroundStyle(Theme.textDim)
                        }
                    }.buttonStyle(.plain).font(.system(size: 11))
                    (Text(pose.label).foregroundColor(pose.color) + Text("  ·  \(elapsed)").foregroundColor(Theme.textFaint))
                        .font(.system(size: 11, weight: .medium))
                    if !subs.isEmpty { subagentIcons }
                    ctxLine.font(.system(size: 10, design: .monospaced))
                }
            }
            if stopItem != nil {
                HStack {
                    TextField("Reply…", text: $reply).textFieldStyle(.plain).onSubmit(send)
                    Button(action: send) { Image(systemName: "arrow.up.circle.fill") }.buttonStyle(.plain)
                        .foregroundStyle(Theme.crimsonSoft).disabled(reply.isEmpty)
                }
                .padding(8).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(10)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(pose == .needsYou ? Theme.crimsonBright.opacity(0.8) : .white.opacity(0.06), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(session.project), \(pose.label), context \(Int(session.ctxPct)) percent"
            + (subs.isEmpty ? "" : ", \(subs.count) subagents: " + subs.map(\.label).joined(separator: ", ")))
    }

    /// Running subagents' poses, in a stable order so icons don't shuffle.
    private var subs: [Pose] { session.subagents.sorted { $0.key < $1.key }.map { Pose($0.value, needsYou: false) } }

    /// One tiny icon per running subagent showing what it's doing; "+N" past 4.
    private var subagentIcons: some View {
        HStack(spacing: 5) {
            ForEach(Array(subs.prefix(4).enumerated()), id: \.offset) { _, p in
                Image(systemName: p.symbol).foregroundStyle(p.color == Theme.textFaint ? Theme.textDim : p.color).help(p.label)
            }
            if subs.count > 4 { Text("+\(subs.count - 4)").foregroundStyle(Theme.text) }
        }.font(.system(size: 10, weight: .semibold))
    }

    /// `━━━━━━────────── 42% · 84k`
    private var ctxLine: Text {
        let bar = Meter.bar(cells: 16, pct: session.ctxPct)
        let used = bar.prefix { $0 != "─" }
        let tok = session.tokens >= 1000 ? "\(session.tokens / 1000)k" : "\(session.tokens)"
        return Text(String(used)).foregroundColor(Meter.color(session.ctxPct))
            + Text(String(bar.dropFirst(used.count))).foregroundColor(Theme.textFaint.opacity(0.35))
            + Text(" \(Int(session.ctxPct))% · \(tok)").foregroundColor(Theme.textFaint)
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
}
