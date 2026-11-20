import AppKit
import Carbon.HIToolbox
import SwiftUI

final class PerchPanel: NSPanel {
    override var canBecomeKey: Bool { true } // text fields need it; .nonactivatingPanel keeps the app from activating
}

struct PanelRoot: View {
    let store: SessionStore
    let queue: PromptQueue
    let fetcher: UsageFetcher
    @Bindable var model: PanelModel

    var body: some View {
        if let item = queue.head, model.pill {
            Button { model.pill = false; model.showPrompt = true } label: {
                HStack(spacing: 6) {
                    Circle().strokeBorder(Theme.crimsonBright, lineWidth: 2).frame(width: 8, height: 8)
                    Text("\(queue.items.count) needs you · \(store.sessions[item.sessionId]?.project ?? "Claude")")
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text)
                }.padding(.horizontal, 12).padding(.vertical, 6).perchPanel(radius: 16)
            }.buttonStyle(.plain)
        } else if let item = queue.head, model.showPrompt {
            let session = store.sessions[item.sessionId]
            switch item.kind {
            case .permission: PermissionView(item: item, session: session, queue: queue, minimize: { model.pill = true })
            case .question: QuestionView(item: item, session: session, queue: queue, minimize: { model.pill = true }).id(item.id)
            case .stop: AgentList(store: store, queue: queue, fetcher: fetcher, model: model) // reply field lives on the idle row
            }
        } else {
            AgentList(store: store, queue: queue, fetcher: fetcher, model: model)
        }
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let model = PanelModel()
    private let panel = PerchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let queue: PromptQueue
    private weak var anchor: NSStatusBarButton?
    private var transient = false   // opened by click/hotkey: close when focus leaves
    private var shrink: DispatchWorkItem?

    init(store: SessionStore, queue: PromptQueue, fetcher: UsageFetcher, anchor: NSStatusBarButton?) {
        self.queue = queue; self.anchor = anchor
        super.init()
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .popUpMenu; panel.isFloatingPanel = true; panel.delegate = self
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: PanelRoot(store: store, queue: queue, fetcher: fetcher, model: model))
    }

    var isVisible: Bool { panel.isVisible }

    /// Status-item click / hotkey: toggle; opens the queue head if something is waiting (hotkey) or the list (click).
    func toggle(prompt: Bool) {
        if panel.isVisible && transient { return hide() }
        show(prompt: prompt && queue.head != nil, auto: false)
    }

    func show(prompt: Bool, auto: Bool) {
        shrink?.cancel()
        model.showPrompt = prompt; model.pill = false
        transient = !auto
        reposition()
        panel.orderFrontRegardless()
        if !auto { panel.makeKey() }
        if auto { // Notify: shrink to a pill after 20s unless the user is interacting
            let w = DispatchWorkItem { [weak self] in
                guard let self, !panel.isKeyWindow, !queue.items.isEmpty else { return }
                model.pill = true
            }
            shrink = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: w)
        }
    }

    func hide() { shrink?.cancel(); panel.orderOut(nil) }

    func queueEmptied() {
        model.showPrompt = false; model.pill = false
        if !transient { hide() }
    }

    func windowDidResignKey(_ n: Notification) { if transient { hide() } }
    func windowDidResize(_ n: Notification) { reposition() }

    private func reposition() {
        guard let r = anchor?.window?.frame else { return }
        let f = panel.frame
        var x = r.midX - f.width / 2
        if let vis = (anchor?.window?.screen ?? NSScreen.main)?.visibleFrame { x = min(max(x, vis.minX + 8), vis.maxX - f.width - 8) }
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: r.minY - 4))
    }
}

/// Global ⌥⌘Space via Carbon (no accessibility permission needed).
enum Hotkey {
    nonisolated(unsafe) private static var action: (() -> Void)?

    static func register(_ action: @escaping () -> Void) {
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { Hotkey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | optionKey), EventHotKeyID(signature: 0x50524348, id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }
}
