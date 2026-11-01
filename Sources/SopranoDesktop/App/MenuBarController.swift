import AppKit
import SopranoDesktopCore

/// The status item and its menu, rebuilt each time it opens so every line is current:
/// state, theme, Apply / Restore, the macOS and Apps switches (written to settings.json),
/// the setup lines for apps Soprano Desktop does not configure itself, and problems from the
/// last run.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let settings: SettingsCenter
    private let theme: ThemeCenter
    private let coordinator: SyncCoordinator
    private var statusItem: NSStatusItem?

    init(settings: SettingsCenter = .shared, theme: ThemeCenter = .shared, coordinator: SyncCoordinator) {
        self.settings = settings
        self.theme = theme
        self.coordinator = coordinator
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: "Soprano Desktop")
        image?.isTemplate = true
        item.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for item in makeItems() {
            menu.addItem(item)
        }
    }

    private func makeItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let active = coordinator.isActive
        let pair = theme.pair

        items.append(disabled(coordinator.isRunning ? "Applying…" : (active ? "Applied to macOS and apps" : "Not applied")))
        let themeLine = pair.light == pair.dark
            ? "Theme: \(pair.light.name)"
            : "Theme: \(pair.light.name) · \(pair.dark.name)"
        items.append(disabled(themeLine))
        items.append(.separator())

        items.append(item(active ? "Re-apply" : "Apply Soprano Desktop", action: #selector(apply)))
        let restore = item("Restore macOS", action: #selector(restore))
        restore.isEnabled = active
        items.append(restore)
        items.append(.separator())

        items.append(submenu("macOS", items: SystemSetting.allCases.map { setting in
            let entry = item(setting.displayName, action: #selector(toggleSystem(_:)))
            entry.representedObject = setting.rawValue
            entry.state = settings.settings.system.contains(setting) ? .on : .off
            return entry
        }))

        var appItems: [NSMenuItem] = DesktopTarget.allCases.map { target in
            let installed = coordinator.engine.isInstalled(target)
            let entry = item(installed ? target.displayName : "\(target.displayName) (not installed)", action: #selector(toggleApp(_:)))
            entry.representedObject = target.rawValue
            entry.state = settings.settings.apps.contains(target) ? .on : .off
            return entry
        }
        let setupTargets = DesktopTarget.allCases.filter { !$0.selectsTheme && $0.setupHint != nil }
        appItems.append(.separator())
        for target in setupTargets {
            let title = target == .chrome
                ? "Show Chrome Theme in Finder"
                : "Copy \(target.displayName) Setup Line"
            let entry = item(title, action: #selector(setup(_:)))
            entry.representedObject = target.rawValue
            if let place = target.setupHintPlace {
                entry.toolTip = target == .chrome ? place : "Add to \(place): \(target.setupHint ?? "")"
            }
            appItems.append(entry)
        }
        items.append(submenu("Apps", items: appItems))

        let problems = coordinator.lastReport.compactMap { entry -> String? in
            if case let .failed(message) = entry.status { return "\(entry.name): \(message)" }
            return nil
        }
        if !problems.isEmpty {
            items.append(.separator())
            items.append(submenu("\(problems.count) Problem\(problems.count == 1 ? "" : "s")", items: problems.map(disabled)))
        }

        items.append(.separator())
        items.append(item("Open Settings File", action: #selector(openSettings)))
        let login = item("Launch at Login", action: #selector(toggleLaunchAtLogin))
        login.state = settings.settings.startAtLogin ? .on : .off
        items.append(login)
        items.append(item("About Soprano Desktop", action: #selector(showAbout)))
        items.append(item("Quit Soprano Desktop", action: #selector(quit), key: "q"))
        return items
    }

    private func item(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    @objc private func apply() {
        coordinator.request(.apply)
    }

    @objc private func restore() {
        coordinator.request(.restore)
    }

    @objc private func toggleSystem(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let setting = SystemSetting(rawValue: raw) else { return }
        settings.write(!settings.settings.system.contains(setting), at: ["system", setting.rawValue])
    }

    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let target = DesktopTarget(rawValue: raw) else { return }
        settings.write(!settings.settings.apps.contains(target), at: ["apps", target.rawValue])
    }

    @objc private func setup(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let target = DesktopTarget(rawValue: raw) else { return }
        if target == .chrome {
            let folder = coordinator.engine.paths.themeRoot(for: .chrome).appendingPathComponent("chrome", isDirectory: true)
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            return
        }
        guard let hint = target.setupHint else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hint, forType: .string)
    }

    @objc private func openSettings() {
        settings.openInEditor()
    }

    @objc private func toggleLaunchAtLogin() {
        settings.write(!settings.settings.startAtLogin, at: ["app", "startAtLogin"])
    }

    @objc private func showAbout() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Soprano Desktop",
            .applicationVersion: AppVersion.current,
        ])
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
