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
    let popover = NSPopover()

    func applicationDidFinishLaunching(_ n: Notification) {
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: QuietView(fetcher: fetcher))
        status.item.button?.target = self
        status.item.button?.action = #selector(toggle)
        status.update()
        fetcher.start()
        track()
    }

    /// Re-render the icon whenever usage changes.
    private func track() {
        withObservationTracking { status.usage = fetcher.usage } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
    }

    @objc func toggle(_ sender: NSStatusBarButton) {
        if popover.isShown { popover.performClose(nil); return }
        fetcher.refresh()
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
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
