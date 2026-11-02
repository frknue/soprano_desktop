import AppKit
import SopranoDesktopCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: SyncCoordinator?
    private var menuBar: MenuBarController?
    private var folioMenuBar: FolioMenuBarController?
    /// macOS's Accessibility prompt is shown at most once per launch.
    private var askedForAccessibility = false

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

        let palette: @MainActor () -> ThemeColors = {
            let id = ThemeCenter.shared.current.id
            return AppTheme.allThemes.first { $0.id == id }?.colors ?? AppTheme.folioPaper.colors
        }
        folioMenuBar = FolioMenuBarController(palette: palette)
        ThemeCenter.shared.addObserver(self) { [weak self] in
            self?.folioMenuBar?.themeDidChange()
        }
        settings.addObserver(self) { [weak self] in self?.updateSurfaces() }
        coordinator.addObserver(self) { [weak self] in self?.updateSurfaces() }
        updateSurfaces()
    }

    /// The Folio menu bar runs while Soprano Desktop is applied and its switch is on. It sits
    /// on the visible menu bar, so it is off while the menu bar hides itself.
    private func updateSurfaces() {
        guard let coordinator else { return }
        let settings = SettingsCenter.shared.settings
        let bar = coordinator.isActive && settings.surfaces.contains(.menuBar) && !settings.desktop.contains(.hideMenuBar)
        if bar { folioMenuBar?.start() } else { folioMenuBar?.stop() }
        if bar, !AccessibilityPermission.isTrusted, !askedForAccessibility {
            askedForAccessibility = true
            AccessibilityPermission.request()
        }
    }
}
