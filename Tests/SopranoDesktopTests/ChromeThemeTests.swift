import AppKit
import Testing
@testable import SopranoDesktopCore

struct ChromeThemeTests {
    private func parse(_ manifest: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: Data(manifest.utf8))
        return try #require(object as? [String: Any])
    }

    private func colors(_ manifest: [String: Any]) throws -> [String: [Int]] {
        let theme = try #require(manifest["theme"] as? [String: Any])
        return try #require(theme["colors"] as? [String: [Int]])
    }

    private func components(_ colour: RGB) -> [Int] {
        [colour.red, colour.green, colour.blue].map { Int(($0 * 255).rounded()) }
    }

    @Test func eachSlotIsAnUnpackedManifestV3ThemeNamedAfterTheSlot() throws {
        let files = ChromeTheme.files(for: TestPalettes.folio)

        #expect(files.map(\.path) == ["chrome/soprano-light/manifest.json", "chrome/soprano-dark/manifest.json"])
        let light = try parse(files[0].contents)
        let dark = try parse(files[1].contents)
        #expect(light["manifest_version"] as? Int == 3)
        #expect(light["version"] as? String == "1.0")
        #expect(light["name"] as? String == ThemeNames.light)
        #expect(dark["name"] as? String == ThemeNames.dark)
    }

    @Test func everyColourIsAnRGBTripleAndTheChromeSitsOnPanelAndPaper() throws {
        let paper = TestPalettes.paper
        let colors = try colors(parse(ChromeTheme.manifest(for: paper, name: ThemeNames.light)))

        for (key, value) in colors {
            #expect(value.count == 3 && value.allSatisfy { (0...255).contains($0) }, "\(key)")
        }
        #expect(colors["frame"] == components(paper.bgPanel))
        #expect(colors["toolbar"] == components(paper.bgBase))
        #expect(colors["ntp_background"] == components(paper.bgBase))
        #expect(colors["tab_text"] == components(paper.textPrimary))
        #expect(colors["tab_background_text"] == components(paper.textMuted))
        #expect(colors["omnibox_text"] == components(paper.textPrimary))
    }

    @Test func lightAndDarkManifestsDifferButAPinnedPairStillYieldsBothNames() throws {
        let folio = ChromeTheme.files(for: TestPalettes.folio)
        #expect(try colors(parse(folio[0].contents))["toolbar"] != colors(parse(folio[1].contents))["toolbar"])

        let pinned = ChromeTheme.files(for: ThemePair(light: TestPalettes.paper, dark: TestPalettes.paper))
        #expect(try parse(pinned[0].contents)["name"] as? String == ThemeNames.light)
        #expect(try parse(pinned[1].contents)["name"] as? String == ThemeNames.dark)
        #expect(try colors(parse(pinned[0].contents)) == colors(parse(pinned[1].contents)))
    }
}
