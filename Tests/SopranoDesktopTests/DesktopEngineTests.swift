import AppKit
import Testing
@testable import SopranoDesktop
@testable import SopranoDesktopCore

/// The global domain in `values`, other domains in `domains`.
private final class FakePreferences: PreferencesStore {
    var values: [String: Any] = [:]
    var domains: [String: [String: Any]] = [:]
    var posted: [PreferenceNotification] = []
    /// Domains that refuse writes, like macOS's protected ones.
    var refused: Set<String> = []

    func value(forKey key: String, domain: String) -> Any? {
        domain == PreferencesDomain.global ? values[key] : domains[domain]?[key]
    }

    func setValue(_ value: Any?, forKey key: String, domain: String) throws {
        if refused.contains(domain) { throw PreferencesError.refused(domain: domain) }
        if domain == PreferencesDomain.global {
            values[key] = value
        } else {
            domains[domain, default: [:]][key] = value
        }
    }

    func post(_ notification: PreferenceNotification) { posted.append(notification) }
}

/// Keeps the tint colour at six decimals, as SkyLight persists and reports it
/// (`AppleIconAppearanceCustomTintColor` = "0.878431 0.541176 0.321569 1.000000").
@MainActor
private final class FakeIconAppearance: IconAppearanceStore {
    var current: IconAppearance? = IconAppearance(theme: 2, tint: 0, color: nil)
    var writes = 0

    func read() -> IconAppearance? { current }
    func write(_ appearance: IconAppearance) throws {
        func sixDecimals(_ value: Double) -> Double { (value * 1_000_000).rounded() / 1_000_000 }
        var stored = appearance
        stored.color = appearance.color.map {
            RGB(red: sixDecimals($0.red), green: sixDecimals($0.green), blue: sixDecimals($0.blue))
        }
        current = stored
        writes += 1
    }
}

@MainActor
private final class FakeFolderIcons: FolderIconStore {
    /// Folder path → the Folio icon set on it; `userIcon` marks folders with their own icon.
    var icons: [String: FolioFolder] = [:]
    var userIcon: Set<String> = []

    func hasCustomIcon(_ folder: URL) -> Bool { icons[folder.path] != nil || userIcon.contains(folder.path) }
    func setIcon(_ folder: FolioFolder?, at url: URL) throws { icons[url.path] = folder }
}

/// Screens with a current Space each; macOS-like, one picture per screen and Space.
@MainActor
private final class FakeDesktop: DesktopPictures {
    /// Screen id → its current Space (nil: unknown).
    var currentSpace: [String: String?] = ["A": "1"]
    var pictures: [String: DesktopPicture] = ["A:1": FakeDesktop.picture("beach")]

    static func picture(_ name: String) -> DesktopPicture {
        DesktopPicture(url: URL(fileURLWithPath: "/Users/me/\(name).jpg"), scaling: 3, allowClipping: true)
    }

    func shown(screen: String, space: String) -> String? {
        pictures["\(screen):\(space)"]?.url.lastPathComponent
    }

    func screens() -> [ScreenInfo] {
        currentSpace.keys.sorted().map { id in
            ScreenInfo(id: id, name: "Screen \(id)", spaceID: currentSpace[id] ?? nil, pixelWidth: 64, pixelHeight: 40, scale: 1)
        }
    }

    func picture(forScreen id: String) -> DesktopPicture? {
        guard let space = currentSpace[id] ?? nil else { return nil }
        return pictures["\(id):\(space)"]
    }

    func setPicture(_ picture: DesktopPicture, forScreen id: String) throws {
        guard let space = currentSpace[id] ?? nil else { return }
        pictures["\(id):\(space)"] = picture
    }
}

/// Records calls; `bat --version` reports 0.25.0, and an editor install drops the extension
/// folder where the editor would.
private final class FakeRunner: ProcessRunning, @unchecked Sendable {
    var calls: [[String]] = []
    /// Executable names that exit 1.
    var failing: Set<String> = []
    var batVersion = "bat 0.25.0"
    var extensionsDirectory: URL?

    func run(_ executable: URL, _ arguments: [String]) async -> ProcessResult {
        let name = executable.lastPathComponent
        calls.append([name] + arguments)
        if failing.contains(name) { return ProcessResult(status: 1, output: "failed") }
        if name == "bat", arguments == ["--version"] { return ProcessResult(status: 0, output: batVersion) }
        if arguments.contains("--install-extension"), let extensionsDirectory {
            try? FileManager.default.createDirectory(
                at: extensionsDirectory.appendingPathComponent("\(VSCodeTheme.extensionID)-1.0.0"),
                withIntermediateDirectories: true
            )
        }
        return ProcessResult(status: 0, output: "")
    }
}

private struct FakeApps: AppLocating {
    let root: URL

    func application(bundleIdentifier: String) -> URL? {
        switch bundleIdentifier {
        case DesktopEngine.ghosttyBundleID: root.appendingPathComponent("Ghostty.app")
        case DesktopEngine.vscodeBundleID: root.appendingPathComponent("Code.app")
        default: nil
        }
    }

    func executable(named name: String) -> URL? {
        name == "bat" ? root.appendingPathComponent("bin/bat") : nil
    }
}

@MainActor
struct DesktopEngineTests {
    @MainActor
    private struct Fixture {
        let home: URL
        let preferences = FakePreferences()
        let desktop = FakeDesktop()
        let runner = FakeRunner()
        let iconAppearance = FakeIconAppearance()
        let folderIcons = FakeFolderIcons()
        let engine: DesktopEngine

        init() throws {
            home = FileManager.default.temporaryDirectory.appendingPathComponent("soprano-desktop-tests-\(UUID().uuidString)")
            let apps = home.appendingPathComponent("Apps")
            let cli = apps.appendingPathComponent("Code.app/Contents/Resources/app/bin/code")
            try FileManager.default.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\n".write(to: cli, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cli.path)
            let paths = TargetPaths(home: home, environment: [:])
            try FileManager.default.createDirectory(at: paths.ghosttyConfigFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "font-size = 14\ntheme = \"Gruvbox Dark\"\n".write(to: paths.ghosttyConfigFile, atomically: true, encoding: .utf8)
            try FileManager.default.createDirectory(at: paths.vscodeSettingsFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "{\n  // mine\n  \"workbench.colorTheme\": \"Rider Dark\"\n}\n".write(to: paths.vscodeSettingsFile, atomically: true, encoding: .utf8)
            preferences.values = ["AppleAccentColor": -1, "AppleHighlightColor": "0.000000 0.340099 0.514652 Other"]
            runner.extensionsDirectory = paths.editorExtensionsDirectory(for: .vscode)
            engine = DesktopEngine(dependencies: .init(
                paths: paths,
                preferences: preferences,
                desktop: desktop,
                runner: runner,
                apps: FakeApps(root: apps),
                iconAppearance: iconAppearance,
                folderIcons: folderIcons,
                screenSaver: nil
            ))
        }

        var paths: TargetPaths { engine.paths }

        func text(_ url: URL) throws -> String {
            try String(contentsOf: url, encoding: .utf8)
        }
    }

    @Test func applyingPutsMacOSAndTheInstalledAppsOnTheThemeAndRestoringPutsEveryUserValueBack() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let originalGhostty = try fixture.text(fixture.paths.ghosttyConfigFile)
        let originalVSCode = try fixture.text(fixture.paths.vscodeSettingsFile)

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(fixture.preferences.values["AppleAccentColor"] as? Int == SystemAccent.orange.rawValue)
        #expect(fixture.preferences.values["AppleHighlightColor"] as? String == SystemHighlight.value(for: TestPalettes.ink.terminal.selectionBackground))
        #expect(fixture.desktop.shown(screen: "A", space: "1")?.contains("folio-ink") == true)
        #expect(try fixture.text(fixture.paths.ghosttyConfigFile).contains("theme = \(GhosttyTheme.themeSetting)"))
        let vscode = try fixture.text(fixture.paths.vscodeSettingsFile)
        #expect(vscode.contains("\"workbench.preferredDarkColorTheme\": \"Soprano Dark\""))
        #expect(vscode.contains("// mine"))
        #expect(fixture.runner.calls.contains { $0.first == "code" && $0.contains("--install-extension") })
        #expect(FileManager.default.fileExists(atPath: fixture.paths.themeRoot(for: .ghostty).appendingPathComponent("themes/soprano-dark").path))

        _ = await fixture.engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(fixture.preferences.values["AppleAccentColor"] as? Int == -1)
        #expect(fixture.preferences.values["AppleHighlightColor"] as? String == "0.000000 0.340099 0.514652 Other")
        #expect(fixture.desktop.shown(screen: "A", space: "1") == "beach.jpg")
        #expect(try fixture.text(fixture.paths.ghosttyConfigFile) == originalGhostty)
        #expect(try fixture.text(fixture.paths.vscodeSettingsFile) == originalVSCode)
        #expect(fixture.engine.state.active == false)
        #expect(fixture.engine.state.originals.isEmpty)
        #expect(fixture.engine.state.written.isEmpty)
    }

    @Test func reapplyingAfterAnAppearanceChangeKeepsTheUsersOriginalNotTheEarlierThemeValue() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .light)
        #expect(fixture.preferences.values["AppleHighlightColor"] as? String == SystemHighlight.value(for: TestPalettes.paper.terminal.selectionBackground))
        _ = await fixture.engine.sync(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.preferences.values["AppleHighlightColor"] as? String == SystemHighlight.value(for: TestPalettes.ink.terminal.selectionBackground))

        _ = await fixture.engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.preferences.values["AppleHighlightColor"] as? String == "0.000000 0.340099 0.514652 Other")
    }

    @Test func switchingOneSettingOffWhileAppliedRestoresJustThatSetting() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        var settings = DesktopSettings.defaults
        settings.system.remove(.accentColor)
        _ = await fixture.engine.sync(settings: settings, pair: TestPalettes.folio, appearance: .dark)

        #expect(fixture.preferences.values["AppleAccentColor"] as? Int == -1)
        #expect(fixture.preferences.values["AppleHighlightColor"] as? String == SystemHighlight.value(for: TestPalettes.ink.terminal.selectionBackground))
        #expect(fixture.engine.state.originals["system.accentColor"] == nil)
        #expect(fixture.engine.state.active)
    }

    @Test func aKeyThatWasAbsentBeforeApplyingIsRemovedAgainOnRestore() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        fixture.preferences.values["AppleAccentColor"] = nil

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .light)
        #expect(fixture.preferences.values["AppleAccentColor"] as? Int == SystemAccent.orange.rawValue)
        _ = await fixture.engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .light)

        #expect(fixture.preferences.values["AppleAccentColor"] == nil)
        // bat had no config file: Restore removes the one Apply created.
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.batConfigFile.path))
    }

    @Test func theEditorExtensionIsReinstalledOnlyWhenTheThemeChanges() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        func installs() -> Int { fixture.runner.calls.filter { $0.contains("--install-extension") }.count }

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        _ = await fixture.engine.sync(settings: .defaults, pair: TestPalettes.folio, appearance: .light)
        #expect(installs() == 1)

        _ = await fixture.engine.sync(settings: .defaults, pair: ThemePair(light: TestPalettes.ink, dark: TestPalettes.ink), appearance: .light)
        #expect(installs() == 2)
    }

    @Test func nothingChangesWhileSopranoDesktopIsNotApplied() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let ghostty = try fixture.text(fixture.paths.ghosttyConfigFile)

        _ = await fixture.engine.sync(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(fixture.preferences.values["AppleAccentColor"] as? Int == -1)
        #expect(try fixture.text(fixture.paths.ghosttyConfigFile) == ghostty)
        #expect(fixture.runner.calls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.themeRoot(for: .ghostty).appendingPathComponent("themes").path))
    }

    @Test func eachSpaceGetsItsOwnWallpaperBackEvenWhenRestoredFromAnotherSpace() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        fixture.desktop.pictures["A:2"] = FakeDesktop.picture("forest")

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        fixture.desktop.currentSpace["A"] = "2"
        _ = await fixture.engine.sync(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.desktop.shown(screen: "A", space: "2")?.contains("folio-ink") == true)

        _ = await fixture.engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.desktop.shown(screen: "A", space: "2") == "forest.jpg")
        #expect(fixture.desktop.shown(screen: "A", space: "1")?.contains("folio-ink") == true)
        #expect(fixture.engine.state.originals.keys.contains("system.wallpaper:A:1"))

        fixture.desktop.currentSpace["A"] = "1"
        _ = await fixture.engine.sync(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.desktop.shown(screen: "A", space: "1") == "beach.jpg")
        #expect(fixture.engine.state.originals.isEmpty)
    }

    @Test func aScreenAttachedWhileAppliedKeepsItsOwnOriginal() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .light)

        fixture.desktop.currentSpace["B"] = "7"
        fixture.desktop.pictures["B:7"] = FakeDesktop.picture("mountain")
        _ = await fixture.engine.sync(settings: .defaults, pair: TestPalettes.folio, appearance: .light)
        #expect(fixture.desktop.shown(screen: "B", space: "7")?.contains("folio-paper") == true)

        _ = await fixture.engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .light)
        #expect(fixture.desktop.shown(screen: "B", space: "7") == "mountain.jpg")
        #expect(fixture.desktop.shown(screen: "A", space: "1") == "beach.jpg")
    }

    @Test func anEditorWhoseExtensionDidNotInstallIsNotSwitchedToTheMissingTheme() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        fixture.runner.failing = ["code"]
        let original = try fixture.text(fixture.paths.vscodeSettingsFile)

        let report = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(try fixture.text(fixture.paths.vscodeSettingsFile) == original)
        #expect(report.contains { $0.name == "VS Code" && { if case .failed = $0.status { true } else { false } }($0) })

        fixture.runner.failing = []
        _ = await fixture.engine.sync(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(try fixture.text(fixture.paths.vscodeSettingsFile).contains("Soprano Dark"))
    }

    @Test func aScreenWhoseSpaceIsUnknownIsNeverGivenTheWallpaper() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        fixture.desktop.currentSpace["A"] = .some(nil)

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(fixture.desktop.shown(screen: "A", space: "1") == "beach.jpg")
        #expect(!fixture.engine.state.originals.keys.contains { $0.hasPrefix(WallpaperSetting.idPrefix) })
    }

    @Test func restoringAnUntouchedSettingsFileGivesItBackByteForByteIncludingATrailingComment() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let original = "\u{FEFF}{\n  \"a\": 1,\n  \"b\": 2 // last one\n}"
        try TextFile.write(original, to: fixture.paths.vscodeSettingsFile)

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(try TextFile.read(fixture.paths.vscodeSettingsFile)?.contains("Soprano Dark") == true)
        _ = await fixture.engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(try TextFile.read(fixture.paths.vscodeSettingsFile) == original)
    }

    @Test func anEditFollowedByAReapplyIsStillKeptByRestore() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        // The user changes the font size and the theme; the next sync puts the theme back.
        try "font-size = 16\ntheme = Nord\n".write(to: fixture.paths.ghosttyConfigFile, atomically: true, encoding: .utf8)
        _ = await fixture.engine.sync(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(try fixture.text(fixture.paths.ghosttyConfigFile) == "font-size = 16\ntheme = \(GhosttyTheme.themeSetting)\n")

        _ = await fixture.engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(try fixture.text(fixture.paths.ghosttyConfigFile) == "font-size = 16\ntheme = \"Gruvbox Dark\"\n")
    }

    @Test func afterTheUserEditedTheFileRestoreRevertsOnlySopranosKeysAndKeepsTheEdit() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        let applied = try fixture.text(fixture.paths.ghosttyConfigFile)
        try (applied + "cursor-style = bar\n").write(to: fixture.paths.ghosttyConfigFile, atomically: true, encoding: .utf8)

        _ = await fixture.engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(try fixture.text(fixture.paths.ghosttyConfigFile) == "font-size = 14\ntheme = \"Gruvbox Dark\"\ncursor-style = bar\n")
    }

    @Test func aFileAppliedUnderAnotherEnvironmentIsStillRestoredFromItsOwnRecord() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let cliConfig = fixture.home.appendingPathComponent("elsewhere/bat.conf")
        try TextFile.write("--theme=TwoDark\n", to: cliConfig)
        try TextFile.write("--theme=GitHub\n", to: fixture.paths.batConfigFile)
        let cli = DesktopEngine(dependencies: .init(
            paths: TargetPaths(home: fixture.home, environment: ["BAT_CONFIG_PATH": cliConfig.path]),
            preferences: fixture.preferences,
            desktop: fixture.desktop,
            runner: fixture.runner,
            apps: fixture.engine.dependencies.apps,
            iconAppearance: fixture.iconAppearance,
            folderIcons: fixture.folderIcons,
            screenSaver: nil
        ))

        _ = await cli.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        _ = await fixture.engine.sync(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        _ = await fixture.engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(try fixture.text(cliConfig) == "--theme=TwoDark\n")
        #expect(try fixture.text(fixture.paths.batConfigFile) == "--theme=GitHub\n")
    }

    @Test func whileAnotherProcessHoldsTheStateLockTheAppBacksOffWithoutChangingAnything() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let other = StateLock(url: fixture.paths.stateLockFile)
        #expect(other.lock(wait: false))

        let report = await fixture.engine.run(.apply, settings: .defaults, pair: TestPalettes.folio, appearance: .dark, waitForLock: false)
        #expect(report == nil)
        #expect(fixture.preferences.values["AppleAccentColor"] as? Int == -1)

        other.unlock()
        let retried = await fixture.engine.run(.apply, settings: .defaults, pair: TestPalettes.folio, appearance: .dark, waitForLock: false)
        #expect(retried != nil)
        #expect(fixture.preferences.values["AppleAccentColor"] as? Int == SystemAccent.orange.rawValue)
    }

    @Test func anUnreadableStateFileStopsEveryChangeAndIsLeftAsItIs() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        try TextFile.write("{ not json", to: fixture.paths.stateFile)

        let report = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(report.count == 1)
        #expect(fixture.preferences.values["AppleAccentColor"] as? Int == -1)
        #expect(try fixture.text(fixture.paths.stateFile) == "{ not json")
    }

    @Test func whenStateCannotBeSavedNothingIsChanged() async throws {
        let fixture = try Fixture()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.paths.supportDirectory.path)
            try? FileManager.default.removeItem(at: fixture.home)
        }
        try FileManager.default.createDirectory(at: fixture.paths.supportDirectory, withIntermediateDirectories: true)
        // The lock file must exist before the folder turns read-only.
        FileManager.default.createFile(atPath: fixture.paths.stateLockFile.path, contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.paths.supportDirectory.path)

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(fixture.preferences.values["AppleAccentColor"] as? Int == -1)
        #expect(try fixture.text(fixture.paths.ghosttyConfigFile).contains("Gruvbox Dark"))
    }

    @Test func theUsersWallpaperComesBackWithItsOwnFillColour() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        fixture.desktop.pictures["A:1"]?.fillColor = RGB(hex: "#112233")

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.desktop.pictures["A:1"]?.fillColor == TestPalettes.ink.bgBase)
        _ = await fixture.engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(fixture.desktop.pictures["A:1"]?.fillColor == RGB(hex: "#112233"))
    }

    @Test func aScreenWhoseCurrentWallpaperCannotBeReadIsLeftUnchanged() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        fixture.desktop.pictures["A:1"] = nil

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(fixture.desktop.pictures["A:1"] == nil)
        #expect(fixture.engine.state.originals["system.wallpaper:A:1"] == nil)
    }

    @Test func anOlderBatGetsTheThemeFilesButItsConfigIsNotSwitched() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        fixture.runner.batVersion = "bat 0.24.0"

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(!FileManager.default.fileExists(atPath: fixture.paths.batConfigFile.path))
        #expect(DesktopEngine.batVersion("bat 0.25.0 (abc)") == 25)
    }

    @Test func anExtensionTheUserUninstalledIsInstalledAgain() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        func installs() -> Int { fixture.runner.calls.filter { $0.contains("--install-extension") }.count }

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        try FileManager.default.removeItem(at: fixture.paths.editorExtensionsDirectory(for: .vscode))
        _ = await fixture.engine.sync(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(installs() == 2)
    }

    @Test func foldersTakeTheIconTintKeepingTheUsersIconStyleAndRestoreGivesItBack() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .light)
        #expect(fixture.iconAppearance.current?.json == IconAppearance(theme: 2, tint: IconAppearance.tintOther, color: TestPalettes.paper.iconTint).json)

        // What macOS reports back counts as the tint already set: no second write.
        let writes = fixture.iconAppearance.writes
        _ = await fixture.engine.sync(settings: .defaults, pair: TestPalettes.folio, appearance: .light)
        #expect(fixture.iconAppearance.writes == writes)

        _ = await fixture.engine.sync(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.iconAppearance.current?.json == IconAppearance(theme: 2, tint: IconAppearance.tintOther, color: TestPalettes.ink.iconTint).json)

        _ = await fixture.engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.iconAppearance.current == IconAppearance(theme: 2, tint: 0, color: nil))
    }

    @Test func folderIconsGoOnlyOnFoldersWithoutAnIconOfTheirOwnAndComeOffOnRestore() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let desktop = FolioFolder.desktop.url(home: fixture.home)
        let documents = FolioFolder.documents.url(home: fixture.home)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        fixture.folderIcons.userIcon = [documents.path]

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.folderIcons.icons[desktop.path] == .desktop)
        #expect(fixture.folderIcons.icons[fixture.home.path] == .home)
        #expect(fixture.folderIcons.icons[documents.path] == nil)

        _ = await fixture.engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.folderIcons.icons.isEmpty)
        #expect(fixture.folderIcons.userIcon == [documents.path])
    }

    @Test func theAlertSoundIsWrittenAndSelectedAndRestoreFallsBackToTheSystemDefault() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.preferences.values["com.apple.sound.beep.sound"] as? String == fixture.paths.alertSoundFile.path)
        #expect(try Data(contentsOf: fixture.paths.alertSoundFile) == AlertSound.aiff())
        #expect(fixture.preferences.posted.contains(.distributed("com.apple.sound.settingsChangedNotification")))

        _ = await fixture.engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.preferences.values["com.apple.sound.beep.sound"] == nil)
    }

    @Test func theCalmDesktopHidesDesktopIconsAndDockRecentsButLeavesTheMenuBarByDefault() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        fixture.preferences.domains["com.apple.dock"] = ["show-recents": true]

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.preferences.domains["com.apple.WindowManager"]?["StandardHideDesktopIcons"] as? Bool == true)
        #expect(fixture.preferences.domains["com.apple.dock"]?["show-recents"] as? Bool == false)
        #expect(fixture.preferences.posted.contains(.darwin("com.apple.dock.prefchanged")))
        #expect(fixture.preferences.values["_HIHideMenuBar"] == nil)

        var hidden = DesktopSettings.defaults
        hidden.desktop.insert(.hideMenuBar)
        _ = await fixture.engine.sync(settings: hidden, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.preferences.values["_HIHideMenuBar"] as? Bool == true)
        #expect(fixture.preferences.domains["com.apple.controlcenter"]?["AutoHideMenuBarOption"] as? Int == 0)

        _ = await fixture.engine.restore(settings: hidden, pair: TestPalettes.folio, appearance: .dark)
        #expect(fixture.preferences.domains["com.apple.WindowManager"]?["StandardHideDesktopIcons"] == nil)
        #expect(fixture.preferences.domains["com.apple.dock"]?["show-recents"] as? Bool == true)
        #expect(fixture.preferences.values["_HIHideMenuBar"] == nil)
        #expect(fixture.preferences.domains["com.apple.controlcenter"]?["AutoHideMenuBarOption"] == nil)
    }

    @Test func aRefusedPreferenceIsReportedAndRecordsNothingToRestore() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        fixture.preferences.refused = ["com.apple.dock"]

        let report = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(report.contains { if case .failed = $0.status { $0.name == DesktopBehavior.hideDockRecents.displayName } else { false } })
        #expect(fixture.preferences.values["AppleAccentColor"] as? Int == SystemAccent.orange.rawValue)
    }

    @Test func theScreenSaverIsInstalledAndRemovedAgainWhenItWasNotThereBefore() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        let saver = fixture.home.appendingPathComponent("Bundle/Soprano.saver")
        try FileManager.default.createDirectory(at: saver.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        try Data("saver-v1".utf8).write(to: saver.appendingPathComponent("Contents/MacOS/Soprano"))
        let engine = DesktopEngine(dependencies: .init(
            paths: fixture.paths, preferences: fixture.preferences, desktop: fixture.desktop, runner: fixture.runner,
            apps: fixture.engine.dependencies.apps, iconAppearance: fixture.iconAppearance,
            folderIcons: fixture.folderIcons, screenSaver: saver
        ))

        _ = await engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        let installed = fixture.paths.screenSaverBundle.appendingPathComponent("Contents/MacOS/Soprano")
        #expect(try Data(contentsOf: installed) == Data("saver-v1".utf8))

        try Data("saver-v2".utf8).write(to: saver.appendingPathComponent("Contents/MacOS/Soprano"))
        _ = await engine.sync(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(try Data(contentsOf: installed) == Data("saver-v2".utf8))

        _ = await engine.restore(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)
        #expect(!FileManager.default.fileExists(atPath: fixture.paths.screenSaverBundle.path))
    }
}
