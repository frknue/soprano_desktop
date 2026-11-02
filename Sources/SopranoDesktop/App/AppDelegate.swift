import AppKit
import SopranoDesktopCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: SyncCoordinator?
    private var menuBar: MenuBarController?
    private var focusBorder: FocusBorderController?
    private var folioMenuBar: FolioMenuBarController?

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
        focusBorder = FocusBorderController(palette: palette)
        folioMenuBar = FolioMenuBarController(palette: palette)
        ThemeCenter.shared.addObserver(self) { [weak self] in
            self?.focusBorder?.themeDidChange()
            self?.folioMenuBar?.themeDidChange()
        }
        settings.addObserver(self) { [weak self] in self?.updateSurfaces() }
        coordinator.addObserver(self) { [weak self] in self?.updateSurfaces() }
        updateSurfaces()
    }

    /// The surfaces run while Soprano Desktop is applied and their switch is on. The Folio
    /// menu bar sits on the visible menu bar, so it is off while the menu bar hides itself.
    private func updateSurfaces() {
        guard let coordinator else { return }
        let settings = SettingsCenter.shared.settings
        let active = coordinator.isActive
        let border = active && settings.surfaces.contains(.focusBorder)
        let bar = active && settings.surfaces.contains(.menuBar) && !settings.desktop.contains(.hideMenuBar)
        if border { focusBorder?.start() } else { focusBorder?.stop() }
        if bar { folioMenuBar?.start() } else { folioMenuBar?.stop() }
    }
}
