import AppKit
import Testing
@testable import SopranoDesktop
@testable import SopranoDesktopCore

struct ThemeResolutionTests {
    private let palettes: Set<String> = ["folio-paper", "folio-ink", "nord"]

    @Test func followingSopranoWithFolioAndTheSystemAppearanceGivesPaperAndInk() {
        let ids = ThemePairResolver.paletteIDs(theme: "soprano", soprano: SopranoThemeFile(), paletteIDs: palettes)
        #expect(ids == ("folio-paper", "folio-ink"))
    }

    @Test func aPinnedSopranoAppearanceOrPaletteFillsBothSlots() {
        let pinnedDark = ThemePairResolver.paletteIDs(
            theme: "soprano", soprano: SopranoThemeFile(themeID: "folio", appearance: .dark), paletteIDs: palettes
        )
        #expect(pinnedDark == ("folio-ink", "folio-ink"))
        let nord = ThemePairResolver.paletteIDs(
            theme: "soprano", soprano: SopranoThemeFile(themeID: "nord", appearance: .light), paletteIDs: palettes
        )
        #expect(nord == ("nord", "nord"))
    }

    @Test func desktopsOwnThemeOverridesSopranoAndUnknownIdsFallBackToFolio() {
        let nordSoprano = SopranoThemeFile(themeID: "nord")
        #expect(ThemePairResolver.paletteIDs(theme: "folio-ink", soprano: nordSoprano, paletteIDs: palettes) == ("folio-ink", "folio-ink"))
        #expect(ThemePairResolver.paletteIDs(theme: "folio", soprano: nordSoprano, paletteIDs: palettes) == ("folio-paper", "folio-ink"))
        #expect(ThemePairResolver.paletteIDs(theme: "gone", soprano: nordSoprano, paletteIDs: palettes) == ("folio-paper", "folio-ink"))
    }

    @Test func folioSiennaMapsToOrangeAndGreysToGraphite() {
        #expect(SystemAccent.nearest(to: TestPalettes.paper.accent) == .orange)
        #expect(SystemAccent.nearest(to: TestPalettes.ink.accent) == .orange)
        #expect(SystemAccent.nearest(to: RGB(hex: "#88c0d0")!) == .blue)
        #expect(SystemAccent.nearest(to: RGB(hex: "#777777")!) == .graphite)
    }

    @Test func highlightValueUsesSystemSettingsFormat() {
        #expect(SystemHighlight.value(for: RGB(red: 1, green: 0.5, blue: 0)) == "1.000000 0.500000 0.000000 Other")
    }

    @Test func theTemplateResolvesToTheDefaultsWithoutIssues() {
        let resolution = SettingsResolver.resolve(text: SettingsTemplate.text, knownThemeIDs: PaletteBridge.knownThemeIDs)
        #expect(resolution.settings == .defaults)
        #expect(resolution.issues.isEmpty)
    }

    @Test func badValuesKeepTheirDefaultsAndWarnWithTheirPath() {
        let text = """
        { "theme": "nope", "system": { "wallpaper": false, "accentColor": 1 }, "apps": { "zed": true, "bat": false } }
        """
        let resolution = SettingsResolver.resolve(text: text, knownThemeIDs: PaletteBridge.knownThemeIDs)
        let settings = try! #require(resolution.settings)
        #expect(settings.theme == "soprano")
        #expect(!settings.system.contains(.wallpaper))
        #expect(settings.system.contains(.accentColor))
        #expect(!settings.apps.contains(.bat))
        let messages = resolution.issues.map(\.message)
        #expect(messages.contains { $0.hasPrefix("theme:") })
        #expect(messages.contains { $0.hasPrefix("system.accentColor:") })
        #expect(messages.contains("Unknown setting \"apps.zed\"."))
    }

    @Test func aDocumentThatDoesNotParseIsAnErrorWithItsLine() {
        let resolution = SettingsResolver.resolve(text: "{\n  \"theme\": \n}", knownThemeIDs: [])
        #expect(resolution.settings == nil)
        #expect(resolution.issues.first?.severity == .error)
    }

    @Test func folioPalettesBridgedFromSopranoMatchTheTestTranscription() {
        #expect(PaletteBridge.palette(id: "folio-paper") == TestPalettes.paper)
        #expect(PaletteBridge.palette(id: "folio-ink") == TestPalettes.ink)
    }
}
