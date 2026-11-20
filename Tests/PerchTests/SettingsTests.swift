import Foundation
import Testing
@testable import Perch

@Test func timeoutClamps() {
    #expect(SettingsLogic.clampTimeout(0) == 11)
    #expect(SettingsLogic.clampTimeout(11) == 11)
    #expect(SettingsLogic.clampTimeout(600) == 600)
    #expect(SettingsLogic.clampTimeout(99999) == 3600)
}

@Test func hooksInstalledDetection() throws {
    let url = try tempSettings(settingsFixture)
    #expect(!SettingsLogic.hooksInstalled(settings: url))
    try HookInstaller.install(settings: url, hookPath: hook)
    #expect(SettingsLogic.hooksInstalled(settings: url))
    try HookInstaller.uninstall(settings: url)
    #expect(!SettingsLogic.hooksInstalled(settings: url))
    #expect(!SettingsLogic.hooksInstalled(settings: try tempSettings(nil)))
}
