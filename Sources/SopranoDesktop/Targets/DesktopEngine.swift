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
        var preferences: GlobalPreferences
        var desktop: DesktopPictures
        var runner: ProcessRunning
        var apps: AppLocating

        static func live() -> Dependencies {
            Dependencies(
                paths: TargetPaths(),
                preferences: LiveGlobalPreferences(),
                desktop: LiveDesktopPictures(),
                runner: LiveProcessRunner(),
                apps: LiveAppLocator()
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

    static let vscodeBundleID = "com.microsoft.VSCode"
    static let cursorBundleID = "com.todesktop.230313mzl4w4u92"
    static let ghosttyBundleID = "com.mitchellh.ghostty"
    static let chromeBundleIDs = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.dev", "com.google.Chrome.canary"]

    let dependencies: Dependencies
    private(set) var state: DesktopState

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        self.state = Self.loadState(at: dependencies.paths.stateFile)
    }

    var paths: TargetPaths { dependencies.paths }

    /// Re-reads state.json (another process — the CLI or the app — may have changed it).
    func reloadState() {
        state = Self.loadState(at: paths.stateFile)
    }

    func apply(settings: DesktopSettings, pair: ThemePair, appearance: Appearance) async -> [ReportItem] {
        reloadState()
        state.active = true
        saveState()
        return await sync(settings: settings, pair: pair, appearance: appearance)
    }

    func restore(settings: DesktopSettings, pair: ThemePair, appearance: Appearance) async -> [ReportItem] {
        reloadState()
        state.active = false
        saveState()
        return await sync(settings: settings, pair: pair, appearance: appearance)
    }

    func sync(settings: DesktopSettings, pair: ThemePair, appearance: Appearance) async -> [ReportItem] {
        reloadState()
        var report: [ReportItem] = []
        let palette = pair.palette(for: appearance)
        for (setting, desired) in registry(settings: settings, palette: palette) {
            report.append(ReportItem(name: setting.label, status: reconcile(setting, desired: desired)))
        }
        if state.active {
            for target in DesktopTarget.allCases {
                report.append(ReportItem(
                    name: target.displayName,
                    status: await writeTheme(for: target, enabled: settings.apps.contains(target), pair: pair)
                ))
            }
        }
        saveState()
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
    private func registry(settings: DesktopSettings, palette: Palette) -> [(ManagedSetting, JSONValue?)] {
        let active = state.active
        var entries: [(ManagedSetting, JSONValue?)] = []
        let preferences = dependencies.preferences

        func wants(_ system: SystemSetting) -> Bool { active && settings.system.contains(system) }
        func wants(_ target: DesktopTarget) -> Bool {
            active && settings.apps.contains(target) && isInstalled(target)
        }

        entries.append((
            GlobalDefaultSetting(id: "system.accentColor", label: SystemSetting.accentColor.displayName,
                                 key: "AppleAccentColor", preferences: preferences),
            wants(.accentColor) ? .number(Double(SystemAccent.nearest(to: palette.accent).rawValue)) : nil
        ))
        entries.append((
            GlobalDefaultSetting(id: "system.highlightColor", label: SystemSetting.highlightColor.displayName,
                                 key: "AppleHighlightColor", preferences: preferences),
            wants(.highlightColor) ? .string(SystemHighlight.value(for: SystemHighlight.color(for: palette))) : nil
        ))
        // One entry per screen on its current Space. Recorded originals of Spaces not
        // visible now are not in the registry, so they stay recorded until their Space is.
        for screen in dependencies.desktop.screens() {
            guard let setting = WallpaperSetting(screen: screen, desktop: dependencies.desktop, fillColor: palette.bgBase) else { continue }
            entries.append((setting, wants(.wallpaper) ? wallpaperValue(for: palette, screen: screen) : nil))
        }

        entries.append((
            LineFileSetting(id: "ghostty:theme", label: "Ghostty theme", file: paths.ghosttyConfigFile,
                            setting: LineSetting(key: "theme", syntax: .ghostty)),
            wants(.ghostty) ? .string(GhosttyTheme.themeSetting) : nil
        ))

        for (target, file) in [(DesktopTarget.vscode, paths.vscodeSettingsFile), (.cursor, paths.cursorSettingsFile)] {
            let values: [(String, JSONValue)] = [
                ("window.autoDetectColorScheme", .bool(true)),
                ("workbench.preferredLightColorTheme", .string(ThemeNames.light)),
                ("workbench.preferredDarkColorTheme", .string(ThemeNames.dark)),
            ]
            for (key, value) in values {
                entries.append((
                    JSONCFileSetting(id: "\(target.rawValue):\(key)", label: "\(target.displayName) \(key)", file: file, key: key),
                    wants(target) ? value : nil
                ))
            }
        }

        // `auto:system` picks --theme-light / --theme-dark from macOS's appearance, also when
        // bat's output is not a terminal (plain `auto` then falls back to bat's default).
        let batValues: [(String, String)] = [
            ("theme", "auto:system"),
            ("theme-light", "\"\(ThemeNames.light)\""),
            ("theme-dark", "\"\(ThemeNames.dark)\""),
        ]
        for (key, value) in batValues {
            entries.append((
                LineFileSetting(id: "bat:\(key)", label: "bat --\(key)", file: paths.batConfigFile,
                                setting: LineSetting(key: key, syntax: .argument)),
                wants(.bat) ? .string(value) : nil
            ))
        }
        return entries
    }

    private func reconcile(_ setting: ManagedSetting, desired: JSONValue?) -> Status {
        do {
            if let desired {
                let current = try setting.read()
                if state.originals[setting.id] == nil {
                    // Recorded and saved before the first write, so a crash cannot lose it.
                    state.originals[setting.id] = current
                    saveState()
                }
                guard current != .value(desired) else { return .unchanged }
                try setting.write(.value(desired))
                return .applied
            }
            guard let original = state.originals[setting.id] else { return .skipped("not applied") }
            try setting.write(original)
            state.originals[setting.id] = nil
            saveState()
            return .restored
        } catch {
            engineLog.error("\(setting.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
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
            let picture = DesktopPicture(url: url, scaling: 3 /* NSImageScaling.scaleProportionallyUpOrDown */, allowClipping: true)
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
                if target == .bat, changed, let bat = dependencies.apps.executable(named: "bat") {
                    let result = await dependencies.runner.run(bat, ["cache", "--build"])
                    guard result.succeeded else { return .failed("bat cache --build: \(result.output)") }
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

    // MARK: Editor extension

    /// The `code` / `cursor` command inside the app bundle.
    func editorCLI(for target: DesktopTarget) -> URL? {
        let (bundleID, tool) = target == .cursor ? (Self.cursorBundleID, "cursor") : (Self.vscodeBundleID, "code")
        guard let app = dependencies.apps.application(bundleIdentifier: bundleID) else { return nil }
        let cli = app.appendingPathComponent("Contents/Resources/app/bin/\(tool)")
        return FileManager.default.isExecutableFile(atPath: cli.path) ? cli : nil
    }

    /// Builds the .vsix and installs it with the editor's CLI when the theme changed since
    /// the last install. The editor picks the new colours up after Reload Window.
    private func installExtension(for target: DesktopTarget, pair: ThemePair) async throws -> Status {
        guard let cli = editorCLI(for: target) else { return .skipped("not installed") }
        let hash = Self.contentHash(VSCodeTheme.packageFiles(for: pair, version: "0.0.0"))
        if state.packages[target.rawValue] == hash {
            return .unchanged
        }
        let version = "1.0.\(Int(Date().timeIntervalSince1970))"
        let vsix = try buildPackage(VSCodeTheme.packageFiles(for: pair, version: version), into: paths.themeRoot(for: target))
        let result = await dependencies.runner.run(cli, ["--install-extension", vsix.path, "--force"])
        guard result.succeeded else {
            return .failed("\(cli.lastPathComponent) --install-extension: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        state.packages[target.rawValue] = hash
        saveState()
        return .applied
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

    // MARK: State

    private static func loadState(at url: URL) -> DesktopState {
        guard let data = try? Data(contentsOf: url) else { return DesktopState() }
        do {
            return try DesktopState.decode(data)
        } catch {
            engineLog.error("state.json could not be read: \(error.localizedDescription, privacy: .public)")
            return DesktopState()
        }
    }

    private func saveState() {
        do {
            let url = paths.stateFile
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try state.encoded().write(to: url, options: .atomic)
        } catch {
            engineLog.error("state.json could not be written: \(error.localizedDescription, privacy: .public)")
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
