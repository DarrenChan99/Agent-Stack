import AppKit
import SwiftUI

enum SettingsLogic {
    static let settingsURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    static func clampTimeout(_ t: Int) -> Int { min(max(t, 11), 3600) }
    /// True when any hook command in the settings file contains perch-hook.
    static func hooksInstalled(settings: URL) -> Bool {
        guard let data = try? Data(contentsOf: settings),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { v in
            (v as? [[String: Any]] ?? []).contains { e in
                (e["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String)?.contains("perch-hook") ?? false }
            }
        }
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    static func show(model: PanelModel) {
        if window == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            w.title = "Perch Settings"; w.styleMask = [.titled, .closable]; w.isReleasedWhenClosed = false
            window = w
        }
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @Bindable var model: PanelModel
    @AppStorage("hookTimeout") private var timeout = 600
    @State private var installed = SettingsLogic.hooksInstalled(settings: SettingsLogic.settingsURL)
    @State private var error: String?
    @State private var login = LaunchAtLogin.isEnabled
    private let bundled = Bundle.main.bundleURL.pathExtension == "app"

    var body: some View {
        Form {
            Section("Claude Code hooks") {
                Text(installed ? "Hooks installed" : "Hooks not installed").foregroundStyle(installed ? .green : .secondary)
                HStack {
                    Button("Install hooks") { run { try HookInstaller.install(settings: SettingsLogic.settingsURL, hookPath: hookPath, timeout: timeout) } }
                        .disabled(!bundled)
                    Button("Uninstall hooks") { run { try HookInstaller.uninstall(settings: SettingsLogic.settingsURL) } }
                }
                if !bundled { Text("Run from Perch.app to install hooks").font(.caption).foregroundStyle(.secondary) }
                TextField("Hook timeout (s)", value: $timeout, format: .number)
                    .onChange(of: timeout) { _, v in if v != SettingsLogic.clampTimeout(v) { timeout = SettingsLogic.clampTimeout(v) } }
                Text("11–3600. Changing it requires re-install.").font(.caption).foregroundStyle(.secondary)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Section {
                Toggle("Do not disturb", isOn: $model.dnd)
                Toggle("Launch at login", isOn: Binding(get: { login }, set: { on in
                    do { try LaunchAtLogin.set(on); error = nil } catch { self.error = error.localizedDescription }
                    login = LaunchAtLogin.isEnabled
                }))
            }
        }
        .formStyle(.grouped).frame(width: 380).fixedSize()
    }

    private var hookPath: String { Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/perch-hook").path }

    private func run(_ op: () throws -> Void) {
        do { try op(); error = nil } catch { self.error = error.localizedDescription }
        installed = SettingsLogic.hooksInstalled(settings: SettingsLogic.settingsURL)
    }
}
