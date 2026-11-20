import AppKit
import ServiceManagement
import SwiftUI

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let fetcher = UsageFetcher()
    let status = StatusItemController()
    let store = SessionStore()
    let queue = PromptQueue()
    var server: SocketServer!
    var panel: PanelController!
    private var lastCount = 0

    func applicationDidFinishLaunching(_ n: Notification) {
        panel = PanelController(store: store, queue: queue, fetcher: fetcher, anchor: status.item.button)
        server = SocketServer(store: store, queue: queue)
        do { try server.start() } catch { NSLog("Perch: socket server failed: \(error)") } // hooks fail open without it
        status.item.button?.target = self
        status.item.button?.action = #selector(toggle)
        status.update()
        fetcher.start()
        store.startPruning()
        Hotkey.register { [weak self] in self?.panel.toggle(prompt: true) }
        track()
    }

    /// Re-render the icon and react to the queue whenever usage / queue / DND change.
    private func track() {
        withObservationTracking {
            status.usage = fetcher.displayUsage
            status.pendingCount = queue.items.count
            status.dnd = panel.model.dnd
        } onChange: { [weak self] in
            Task { @MainActor in self?.track(); self?.queueChanged() }
        }
    }

    private func queueChanged() {
        let n = queue.items.count
        defer { lastCount = n }
        if n == 0 && lastCount > 0 { panel.queueEmptied() }
        else if n > lastCount && !panel.model.dnd { panel.show(prompt: true, auto: true) }
    }

    @objc func toggle(_ sender: NSStatusBarButton) {
        fetcher.refresh()
        panel.toggle(prompt: false)
    }
}

@main
enum PerchApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
