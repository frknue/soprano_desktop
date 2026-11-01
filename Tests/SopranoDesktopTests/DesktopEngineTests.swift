import AppKit
import Testing
@testable import SopranoDesktop
@testable import SopranoDesktopCore

private final class FakePreferences: GlobalPreferences {
    var values: [String: Any] = [:]
    var colorChanges = 0

    func value(forKey key: String) -> Any? { values[key] }
    func setValue(_ value: Any?, forKey key: String) { values[key] = value }
    func postColorChange() { colorChanges += 1 }
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

    func setPicture(_ picture: DesktopPicture, fillColor: RGB?, forScreen id: String) throws {
        guard let space = currentSpace[id] ?? nil else { return }
        pictures["\(id):\(space)"] = picture
    }
}

private final class FakeRunner: ProcessRunning, @unchecked Sendable {
    var calls: [[String]] = []

    func run(_ executable: URL, _ arguments: [String]) async -> ProcessResult {
        calls.append([executable.lastPathComponent] + arguments)
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
            engine = DesktopEngine(dependencies: .init(
                paths: paths,
                preferences: preferences,
                desktop: desktop,
                runner: runner,
                apps: FakeApps(root: apps)
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
        #expect(fixture.engine.state == DesktopState(active: false, originals: [:], packages: fixture.engine.state.packages))
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
        #expect(!(try fixture.text(fixture.paths.batConfigFile)).contains("theme-light"))
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

    @Test func aScreenWhoseSpaceIsUnknownIsNeverGivenTheWallpaper() async throws {
        let fixture = try Fixture()
        defer { try? FileManager.default.removeItem(at: fixture.home) }
        fixture.desktop.currentSpace["A"] = .some(nil)

        _ = await fixture.engine.apply(settings: .defaults, pair: TestPalettes.folio, appearance: .dark)

        #expect(fixture.desktop.shown(screen: "A", space: "1") == "beach.jpg")
        #expect(!fixture.engine.state.originals.keys.contains { $0.hasPrefix(WallpaperSetting.idPrefix) })
    }
}
