import AppKit
import Testing
@testable import SopranoDesktopCore

struct GhosttyThemeTests {
    /// The `key = value` lines of a theme file; `palette` entries keyed as `palette N`.
    private func settings(_ theme: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in theme.split(separator: "\n") where !line.hasPrefix("#") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0] == "palette" {
                let entry = parts[1].split(separator: "=", maxSplits: 1).map(String.init)
                result["palette \(entry[0])"] = entry[1]
            } else {
                result[parts[0]] = parts[1]
            }
        }
        return result
    }

    @Test func theFilesAreTheLightAndDarkThemesUnderTheSlugNamesThatThemeSettingRefersTo() {
        let files = GhosttyTheme.files(for: TestPalettes.folio)

        #expect(files.map(\.path) == ["themes/soprano-light", "themes/soprano-dark"])
        #expect(files[0].contents == GhosttyTheme.theme(for: TestPalettes.paper))
        #expect(files[1].contents == GhosttyTheme.theme(for: TestPalettes.ink))
        #expect(GhosttyTheme.themeSetting == "light:soprano-light,dark:soprano-dark")
    }

    @Test func theThemeMapsTheTerminalColoursTheSiennaCursorAndAllSixteenAnsiSlots() {
        let paper = TestPalettes.paper
        let values = settings(GhosttyTheme.theme(for: paper))

        #expect(values["background"] == paper.terminal.background.hex)
        #expect(values["foreground"] == paper.terminal.foreground.hex)
        #expect(values["cursor-color"] == paper.accent.hex)
        #expect(values["cursor-text"] == paper.terminal.cursorAccent.hex)
        #expect(values["split-divider-color"] == paper.borderStrong.hex)
        for index in 0..<16 {
            #expect(values["palette \(index)"] == paper.terminal.ansi[index].hex)
        }
    }

    @Test func lightThemesSelectWithASiennaWashAndDarkThemesWithTheNeutralFill() {
        let light = settings(GhosttyTheme.theme(for: TestPalettes.paper))
        let dark = settings(GhosttyTheme.theme(for: TestPalettes.ink))

        #expect(light["selection-background"] == TestPalettes.paper.terminal.selectionBackground.hex)
        #expect(dark["selection-background"] == TestPalettes.ink.selection.hex)
        #expect(light["background"] != dark["background"])
    }

    @Test func aPinnedPairStillWritesBothSlotsWithTheSamePalette() {
        let pinned = ThemePair(light: TestPalettes.ink, dark: TestPalettes.ink)
        let files = GhosttyTheme.files(for: pinned)

        #expect(files.map(\.path) == ["themes/soprano-light", "themes/soprano-dark"])
        #expect(files[0].contents == files[1].contents)
    }
}
