import AppKit
import SopranoDesktopCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: SyncCoordinator?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = SettingsCenter.shared
        settings.start()
        ThemeCenter.shared.start()
        LoginItem.sync(enabled: settings.settings.startAtLogin)
        settings.addObserver(self) {
            LoginItem.sync(enabled: SettingsCenter.shared.settings.startAtLogin)
        }

        let coordinator = SyncCoordinator(engine: DesktopEngine(dependencies: .live()))
        let menuBar = MenuBarController(coordinator: coordinator)
        menuBar.install()
        coordinator.start()
        self.coordinator = coordinator
        self.menuBar = menuBar
    }
}
