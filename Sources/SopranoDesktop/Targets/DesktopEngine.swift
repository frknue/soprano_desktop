import CryptoKit
import Foundation
import OSLog
import SopranoDesktopCore

private let engineLog = Logger(subsystem: "com.soprano.desktop", category: "engine")

/// Applies the theme to macOS and the apps, keeps it current, and restores the user's own
/// values (`docs/ARCHITECTURE.md`, "Sync").
///
/// `sync` is the only path that changes anything. While `state.active`, every enabled
/// setting gets its theme value (its original is recorded first, once) and every enabled
/// installed app gets fresh theme files. A setting that is no longer wanted — Restore,
/// or its switch turned off — gets its original back and leaves `originals`.
@MainActor
final class DesktopEngine {
    struct Dependencies {
        var paths: TargetPaths
        var preferences: PreferencesStore
        var desktop: DesktopPictures
        var runner: ProcessRunning
        var apps: AppLocating
        var iconAppearance: IconAppearanceStore
        var folderIcons: FolderIconStore
        /// The packaged `Soprano.saver`; nil when running unpackaged.
        var screenSaver: URL?

        static func live() -> Dependencies {
            Dependencies(
                paths: TargetPaths(),
                preferences: LivePreferences(),
                desktop: LiveDesktopPictures(),
                runner: LiveProcessRunner(),
                apps: LiveAppLocator(),
                iconAppearance: LiveIconAppearance(),
                folderIcons: LiveFolderIcons(),
                screenSaver: Bundle.main.url(forResource: "Soprano", withExtension: "saver")
            )
        }
    }

    enum Status: Equatable {
        /// Changed now.
        case applied
        /// Already on the theme.
        case unchanged
        /// Put back to the user's value.
        case restored
        /// Not installed, or switched off.
        case skipped(String)
        /// Files are current; the user adds one line once (`DesktopTarget.setupHint`).
        case needsSetup(String)
        case failed(String)
    }

    struct ReportItem: Equatable {
        var name: String
        var status: Status
    }

    enum Operation {
        case sync
        case apply
        case restore
    }

    static let vscodeBundleID = "com.microsoft.VSCode"
    static let cursorBundleID = "com.todesktop.230313mzl4w4u92"
    static let ghosttyBundleID = "com.mitchellh.ghostty"
    static let chromeBundleIDs = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary"]
    /// `--theme-light` / `--theme-dark` arrived in bat 0.25.
    static let minimumBatVersion = (0, 25)

    let dependencies: Dependencies
    /// The last state read from state.json (an empty state when it does not exist).
    private(set) var state = DesktopState()
    /// Why state.json could not be read; while set, nothing is changed (fail closed: an
    /// unreadable file may hold the user's originals).
    private(set) var stateError: String?
    private let lock: StateLock
    /// Whether `~/Library/Sounds/Soprano.aiff` holds the current sound (set each run).
    private var alertSoundReady = false

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        self.lock = StateLock(url: dependencies.paths.stateLockFile)
        reloadState()
    }

    var paths: TargetPaths { dependencies.paths }

    /// Re-reads state.json (another process — the CLI or the app — may have changed it).
    func reloadState() {
        let url = paths.stateFile
        guard let data = try? Data(contentsOf: url) else {
            state = DesktopState()
            stateError = FileManager.default.fileExists(atPath: url.path) ? "\(paths.display(url)) could not be read" : nil
            return
        }
        do {
            state = try DesktopState.decode(data)
            stateError = nil
        } catch {
            engineLog.error("state.json could not be read: \(error.localizedDescription, privacy: .public)")
            state = DesktopState()
            stateError = "\(paths.display(url)) is not valid (\(error.localizedDescription)); fix or remove it"
        }
    }

    func apply(settings: DesktopSettings, pair: ThemePair, appearance: Appearance) async -> [ReportItem] {
        await run(.apply, settings: settings, pair: pair, appearance: appearance, waitForLock: true) ?? []
    }

    func restore(settings: DesktopSettings, pair: ThemePair, appearance: Appearance) async -> [ReportItem] {
        await run(.restore, settings: settings, pair: pair, appearance: appearance, waitForLock: true) ?? []
    }

    func sync(settings: DesktopSettings, pair: ThemePair, appearance: Appearance) async -> [ReportItem] {
        await run(.sync, settings: settings, pair: pair, appearance: appearance, waitForLock: true) ?? []
    }

    /// Runs one operation under the state lock, on state freshly read under it. nil when
    /// `waitForLock` is false and another process holds the lock.
    func run(
        _ operation: Operation,
        settings: DesktopSettings,
        pair: ThemePair,
        appearance: Appearance,
        waitForLock: Bool
    ) async -> [ReportItem]? {
        guard lock.lock(wait: waitForLock) else {
            if waitForLock {
                return [ReportItem(name: "state.lock", status: .failed("\(paths.display(paths.stateLockFile)) could not be locked"))]
            }
            return nil
        }
        defer { lock.unlock() }
        reloadState()
        if let stateError {
            return [ReportItem(name: "state.json", status: .failed(stateError))]
        }
        switch operation {
        case .sync: break
        case .apply, .restore:
            state.active = operation == .apply
            if let error = saveState() {
                return [ReportItem(name: "state.json", status: .failed(error))]
            }
        }

        var report: [ReportItem] = []
        // Theme files first, so an app is only switched to themes that exist; an app whose
        // themes could not be written or installed is not switched (or is switched back).
        var failed: Set<DesktopTarget> = []
        if state.active {
            for target in DesktopTarget.allCases {
                let status = await writeTheme(for: target, enabled: settings.apps.contains(target), pair: pair)
                if case .failed = status { failed.insert(target) }
                report.append(ReportItem(name: target.displayName, status: status))
            }
        }
        alertSoundReady = state.active && settings.system.contains(.alertSound) && prepareAlertSound()
        let palette = pair.palette(for: appearance)
        for (setting, desired) in registry(settings: settings, palette: palette, failed: failed) {
            report.append(ReportItem(name: setting.label, status: reconcile(setting, desired: desired)))
        }
        if let error = saveState() {
            report.append(ReportItem(name: "state.json", status: .failed(error)))
        }
        return report
    }

    /// Whether `target` is installed on this Mac.
    func isInstalled(_ target: DesktopTarget) -> Bool {
        let apps = dependencies.apps
        let fileManager = FileManager.default
        switch target {
        case .ghostty:
            return apps.application(bundleIdentifier: Self.ghosttyBundleID) != nil
        case .vscode:
            return editorCLI(for: .vscode) != nil
        case .cursor:
            return editorCLI(for: .cursor) != nil
        case .bat:
            return apps.executable(named: "bat") != nil
        case .fzf:
            return apps.executable(named: "fzf") != nil
        case .neovim:
            return apps.executable(named: "nvim") != nil
                || fileManager.fileExists(atPath: paths.neovimConfigDirectory.path)
        case .chrome:
            return Self.chromeBundleIDs.contains { apps.application(bundleIdentifier: $0) != nil }
        }
    }

    // MARK: Settings

    /// Every setting Soprano Desktop may change, with its theme value while it is wanted
    /// (active, switched on, app installed) and nil otherwise.
    private func registry(settings: DesktopSettings, palette: Palette, failed: Set<DesktopTarget>) -> [(ManagedSetting, JSONValue?)] {
        let active = state.active
        var entries: [(ManagedSetting, JSONValue?)] = []
        let preferences = dependencies.preferences

        func wants(_ system: SystemSetting) -> Bool { active && settings.system.contains(system) }
        func wants(_ behavior: DesktopBehavior) -> Bool { active && settings.desktop.contains(behavior) }
        func wants(_ target: DesktopTarget) -> Bool {
            active && settings.apps.contains(target) && isInstalled(target) && !failed.contains(target)
        }

        entries.append((
            DefaultsSetting(id: "system.accentColor", label: SystemSetting.accentColor.displayName,
                            key: "AppleAccentColor", notifications: PreferenceNotification.colorChange, preferences: preferences),
            wants(.accentColor) ? .number(Double(SystemAccent.nearest(to: palette.accent).rawValue)) : nil
        ))
        entries.append((
            DefaultsSetting(id: "system.highlightColor", label: SystemSetting.highlightColor.displayName,
                            key: "AppleHighlightColor", notifications: PreferenceNotification.colorChange, preferences: preferences),
            wants(.highlightColor) ? .string(SystemHighlight.value(for: SystemHighlight.color(for: palette))) : nil
        ))
        // One entry per screen on its current Space. Recorded originals of Spaces not
        // visible now are not in the registry, so they stay recorded until their Space is.
        for screen in dependencies.desktop.screens() {
            guard let setting = WallpaperSetting(screen: screen, desktop: dependencies.desktop) else { continue }
            entries.append((setting, wants(.wallpaper) ? wallpaperValue(for: palette, screen: screen) : nil))
        }
        entries.append((IconAppearanceSetting(store: dependencies.iconAppearance), iconAppearanceValue(
            folderColor: wants(.folderColor), tintedIcons: wants(.tintedIcons), palette: palette
        )))
        for folder in FolioFolder.allCases {
            let url = folder.url(home: paths.home)
            let setting = FolderIconSetting(
                folder: folder, url: url, store: dependencies.folderIcons,
                lastWritten: state.written[FolderIconSetting.idPrefix + url.path]
            )
            // A folder with an icon of its own is never touched.
            if state.originals[setting.id] == nil, dependencies.folderIcons.hasCustomIcon(url) { continue }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            entries.append((setting, wants(.folderIcons) ? .string(FolderIconRenderer.version) : nil))
        }
        entries.append((
            DefaultsSetting(id: "system.alertSound", label: SystemSetting.alertSound.displayName,
                            key: "com.apple.sound.beep.sound",
                            notifications: [.distributed("com.apple.sound.settingsChangedNotification")],
                            preferences: preferences),
            wants(.alertSound) && alertSoundReady ? .string(paths.alertSoundFile.path) : nil
        ))
        if let saver = dependencies.screenSaver, let hash = ScreenSaverSetting.executableHash(of: saver) {
            entries.append((
                ScreenSaverSetting(source: saver, destination: paths.screenSaverBundle),
                wants(.screenSaver) ? .string(hash) : nil
            ))
        } else if state.originals["system.screenSaver"] != nil {
            // Unpackaged run: still able to remove what a packaged run installed.
            entries.append((ScreenSaverSetting(source: paths.screenSaverBundle, destination: paths.screenSaverBundle), nil))
        }

        let dockChanged: [PreferenceNotification] = [.darwin("com.apple.dock.prefchanged")]
        let menuBarChanged: [PreferenceNotification] = [
            .distributed("AppleInterfaceMenuBarHidingChangedNotification"),
            .distributed("AppleInterfaceFullScreenMenuBarVisibilityChangedNotification"),
        ]
        let behaviours: [(DesktopBehavior, String, String, String, JSONValue, [PreferenceNotification])] = [
            (.hideDesktopIcons, "desktop.hideDesktopIcons", "com.apple.WindowManager", "StandardHideDesktopIcons", .bool(true), []),
            (.hideDockRecents, "desktop.hideDockRecents", "com.apple.dock", "show-recents", .bool(false), dockChanged),
            (.hideMenuBar, "desktop.hideMenuBar.option", "com.apple.controlcenter", "AutoHideMenuBarOption", .number(0), menuBarChanged),
            (.hideMenuBar, "desktop.hideMenuBar", PreferencesDomain.global, "_HIHideMenuBar", .bool(true), menuBarChanged),
            (.hideMenuBar, "desktop.hideMenuBar.fullScreen", PreferencesDomain.global, "AppleMenuBarVisibleInFullscreen", .bool(false), menuBarChanged),
        ]
        for (behaviour, id, domain, key, value, notifications) in behaviours {
            entries.append((
                DefaultsSetting(id: id, label: behaviour.displayName, key: key, domain: domain,
                                notifications: notifications, preferences: preferences),
                wants(behaviour) ? value : nil
            ))
        }

        entries.append((
            ConfigFileSetting(owner: DesktopTarget.ghostty.rawValue, label: "Ghostty config",
                              file: paths.ghosttyConfigFile, format: .ghostty),
            wants(.ghostty) ? .object(["theme": .string(GhosttyTheme.themeSetting)]) : nil
        ))
        for (target, file) in [(DesktopTarget.vscode, paths.vscodeSettingsFile), (.cursor, paths.cursorSettingsFile)] {
            entries.append((
                ConfigFileSetting(owner: target.rawValue, label: "\(target.displayName) settings", file: file, format: .jsonc),
                wants(target) ? .object([
                    "window.autoDetectColorScheme": .bool(true),
                    "workbench.preferredLightColorTheme": .string(ThemeNames.light),
                    "workbench.preferredDarkColorTheme": .string(ThemeNames.dark),
                ]) : nil
            ))
        }
        // `auto:system` picks --theme-light / --theme-dark from macOS's appearance, also when
        // bat's output is not a terminal (plain `auto` then falls back to bat's default).
        entries.append((
            ConfigFileSetting(owner: DesktopTarget.bat.rawValue, label: "bat config", file: paths.batConfigFile, format: .argument),
            wants(.bat) ? .object([
                "theme": .string("auto:system"),
                "theme-light": .string("\"\(ThemeNames.light)\""),
                "theme-dark": .string("\"\(ThemeNames.dark)\""),
            ]) : nil
        ))

        // Config files recorded earlier that are no longer the target (another environment's
        // path, a newly created Ghostty file): restored from their self-describing record.
        let listed = Set(entries.map { $0.0.id })
        for (id, record) in state.originals.sorted(by: { $0.key < $1.key }) where !listed.contains(id) {
            if let setting = ConfigFileSetting(id: id, record: record) {
                entries.append((setting, nil))
            }
        }
        return entries
    }

    private func reconcile(_ setting: ManagedSetting, desired: JSONValue?) -> Status {
        do {
            if let desired {
                let firstWrite = state.originals[setting.id] == nil
                if firstWrite {
                    // Recorded and saved before the first write; if it cannot be saved, the
                    // setting is not changed.
                    state.originals[setting.id] = try setting.capture(for: desired)
                    if let error = saveState() {
                        state.originals[setting.id] = nil
                        return .failed(error)
                    }
                }
                if try setting.matches(desired) { return .unchanged }
                // Whole-file restore stays valid only while the file is exactly the original
                // (first write) or exactly what Soprano Desktop last wrote. Once the user
                // changed it in between, a later restore must revert only Soprano's keys, or
                // it would drop their edits; `written` is cleared for good.
                let before = try setting.contents()
                let untouched = firstWrite || (state.written[setting.id] != nil && before == state.written[setting.id])
                let written = try setting.apply(desired)
                state.written[setting.id] = untouched ? written : nil
                _ = saveState()
                return .applied
            }
            guard let original = state.originals[setting.id] else { return .skipped("not applied") }
            try setting.restore(original, written: state.written[setting.id])
            state.originals[setting.id] = nil
            state.written[setting.id] = nil
            _ = saveState()
            return .restored
        } catch {
            engineLog.error("\(setting.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// Folder colour and tinted icons in the palette's accent; the icon style stays the
    /// user's own unless tinted icons are on. nil when neither is wanted (or macOS has no
    /// such settings).
    private func iconAppearanceValue(folderColor: Bool, tintedIcons: Bool, palette: Palette) -> JSONValue? {
        guard folderColor || tintedIcons else { return nil }
        let base = state.originals["system.iconAppearance"].flatMap(IconAppearance.init(json:))
            ?? dependencies.iconAppearance.read()
        guard let base else { return nil }
        return IconAppearance(
            theme: tintedIcons ? IconAppearance.tintedAutomatic : base.theme,
            tint: IconAppearance.tintOther,
            color: palette.accent
        ).json
    }

    /// Writes the Folio alert sound into `~/Library/Sounds` when it differs; false when it
    /// could not be written (the alert sound is then not selected).
    private func prepareAlertSound() -> Bool {
        let url = paths.alertSoundFile
        let data = AlertSound.aiff()
        if (try? Data(contentsOf: url)) == data { return true }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            engineLog.error("Alert sound: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// The palette's wallpaper rendered at the screen's pixel size; nil when rendering failed.
    private func wallpaperValue(for palette: Palette, screen: ScreenInfo) -> JSONValue? {
        do {
            let url = try WallpaperRenderer.render(
                palette,
                pixelWidth: screen.pixelWidth,
                pixelHeight: screen.pixelHeight,
                scale: screen.scale,
                into: paths.wallpaperDirectory
            )
            let picture = DesktopPicture(
                url: url,
                scaling: 3 /* NSImageScaling.scaleProportionallyUpOrDown */,
                allowClipping: true,
                fillColor: palette.bgBase
            )
            return WallpaperSetting.json(picture)
        } catch {
            engineLog.error("Wallpaper for \(screen.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: Theme files

    /// The theme files of one app, relative to `TargetPaths.themeRoot(for:)`.
    static func files(for target: DesktopTarget, pair: ThemePair) -> [GeneratedFile] {
        switch target {
        case .ghostty: GhosttyTheme.files(for: pair)
        case .neovim: NeovimColorscheme.files(for: pair)
        case .bat: BatTheme.files(for: pair)
        case .fzf: FzfColors.files(for: pair)
        case .chrome: ChromeTheme.files(for: pair)
        case .vscode, .cursor: VSCodeTheme.packageFiles(for: pair, version: "0.0.0")
        }
    }

    private func writeTheme(for target: DesktopTarget, enabled: Bool, pair: ThemePair) async -> Status {
        guard enabled else { return .skipped("switched off") }
        guard isInstalled(target) else { return .skipped("not installed") }
        do {
            switch target {
            case .vscode, .cursor:
                return try await installExtension(for: target, pair: pair)
            default:
                let changed = try writeFiles(Self.files(for: target, pair: pair), under: paths.themeRoot(for: target))
                if target == .bat, let bat = dependencies.apps.executable(named: "bat") {
                    if changed {
                        let result = await dependencies.runner.run(bat, ["cache", "--build"])
                        guard result.succeeded else { return .failed("bat cache --build: \(result.output)") }
                    }
                    // An older bat rejects the light/dark options in its config, so it is
                    // only switched when it understands them (reported as a problem).
                    let version = await dependencies.runner.run(bat, ["--version"])
                    guard let found = Self.batVersion(version.output),
                          found >= Self.minimumBatVersion.0 * 1000 + Self.minimumBatVersion.1
                    else {
                        return .failed("needs bat 0.25 or newer for light and dark themes (found: \(version.output.trimmingCharacters(in: .whitespacesAndNewlines)))")
                    }
                }
                if let hint = target.setupHint, !target.selectsTheme {
                    return .needsSetup(hint)
                }
                return changed ? .applied : .unchanged
            }
        } catch {
            engineLog.error("\(target.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// True when any file changed.
    private func writeFiles(_ files: [GeneratedFile], under root: URL) throws -> Bool {
        var changed = false
        for file in files {
            let url = root.appendingPathComponent(file.path)
            if try TextFile.update(file.contents, at: url) {
                changed = true
            }
        }
        return changed
    }

    /// `bat 0.25.0` → 25 (major × 1000 + minor); nil when there is no version.
    static func batVersion(_ output: String) -> Int? {
        guard let range = output.range(of: #"\d+\.\d+"#, options: .regularExpression) else { return nil }
        let parts = output[range].split(separator: ".").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 1000 + parts[1] : nil
    }

    // MARK: Editor extension

    /// The `code` / `cursor` command inside the app bundle.
    func editorCLI(for target: DesktopTarget) -> URL? {
        let (bundleID, tool) = target == .cursor ? (Self.cursorBundleID, "cursor") : (Self.vscodeBundleID, "code")
        guard let app = dependencies.apps.application(bundleIdentifier: bundleID) else { return nil }
        let cli = app.appendingPathComponent("Contents/Resources/app/bin/\(tool)")
        return FileManager.default.isExecutableFile(atPath: cli.path) ? cli : nil
    }

    /// Builds the .vsix and installs it with the editor's CLI when the theme changed since
    /// the last install, or when the extension is no longer in the editor's extensions
    /// folder. The editor picks the new colours up after Reload Window.
    private func installExtension(for target: DesktopTarget, pair: ThemePair) async throws -> Status {
        guard let cli = editorCLI(for: target) else { return .skipped("not installed") }
        let hash = Self.contentHash(VSCodeTheme.packageFiles(for: pair, version: "0.0.0"))
        if state.packages[target.rawValue] == hash, isExtensionPresent(for: target) {
            return .unchanged
        }
        let version = "1.0.\(Int(Date().timeIntervalSince1970))"
        let vsix = try buildPackage(VSCodeTheme.packageFiles(for: pair, version: version), into: paths.themeRoot(for: target))
        let result = await dependencies.runner.run(cli, ["--install-extension", vsix.path, "--force"])
        guard result.succeeded else {
            return .failed("\(cli.lastPathComponent) --install-extension: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        state.packages[target.rawValue] = hash
        _ = saveState()
        return .applied
    }

    /// Whether `soprano.soprano-theme-<version>` is in the editor's extensions folder.
    private func isExtensionPresent(for target: DesktopTarget) -> Bool {
        let folder = paths.editorExtensionsDirectory(for: target)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.contains { $0.hasPrefix(VSCodeTheme.extensionID + "-") }
    }

    /// Writes the package members into a staging directory and zips them (`ditto`, no
    /// resource forks or extended attributes) to `<directory>/soprano-theme.vsix`.
    func buildPackage(_ files: [GeneratedFile], into directory: URL) throws -> URL {
        let fileManager = FileManager.default
        let staging = fileManager.temporaryDirectory.appendingPathComponent("soprano-desktop-vsix-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: staging) }
        for file in files {
            let url = staging.appendingPathComponent(file.path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let vsix = directory.appendingPathComponent("\(VSCodeTheme.extensionName).vsix")
        try? fileManager.removeItem(at: vsix)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--norsrc", "--noextattr", staging.path, vsix.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw EngineError.packagingFailed }
        return vsix
    }

    static func contentHash(_ files: [GeneratedFile]) -> String {
        var hasher = SHA256()
        for file in files.sorted(by: { $0.path < $1.path }) {
            hasher.update(data: Data(file.path.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(file.contents.utf8))
            hasher.update(data: Data([0]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: State

    /// Writes state.json atomically; the error message when it could not.
    private func saveState() -> String? {
        do {
            let url = paths.stateFile
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try state.encoded().write(to: url, options: .atomic)
            return nil
        } catch {
            engineLog.error("state.json could not be written: \(error.localizedDescription, privacy: .public)")
            return "\(paths.display(paths.stateFile)) could not be saved: \(error.localizedDescription)"
        }
    }
}

enum EngineError: Error, LocalizedError {
    case packagingFailed

    var errorDescription: String? {
        switch self {
        case .packagingFailed: "The editor extension could not be packaged."
        }
    }
}
