import AppKit
import Testing
@testable import SopranoDesktopCore

struct VSCodeThemeTests {
    private func object(_ text: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }

    private func file(_ path: String, in files: [GeneratedFile]) throws -> GeneratedFile {
        try #require(files.first { $0.path == path })
    }

    private func colors(_ palette: Palette) throws -> [String: String] {
        let theme = try object(VSCodeTheme.colorTheme(for: palette, name: ThemeNames.light))
        return try #require(theme["colors"] as? [String: String])
    }

    @Test func thePackageContainsExactlyTheVsixMembersCodeInstallsFrom() {
        let paths = VSCodeTheme.packageFiles(for: TestPalettes.folio, version: "1.2.3").map(\.path)
        #expect(paths.sorted() == [
            "[Content_Types].xml",
            "extension.vsixmanifest",
            "extension/package.json",
            "extension/themes/soprano-dark-color-theme.json",
            "extension/themes/soprano-light-color-theme.json",
        ])
    }

    @Test func packageJsonContributesSopranoLightAndDarkPointingAtFilesInThePackage() throws {
        let files = VSCodeTheme.packageFiles(for: TestPalettes.folio, version: "1.2.3")
        let manifest = try object(file("extension/package.json", in: files).contents)
        #expect(manifest["name"] as? String == "soprano-theme")
        #expect(manifest["publisher"] as? String == "soprano")
        #expect(manifest["version"] as? String == "1.2.3")
        #expect((manifest["engines"] as? [String: String])?["vscode"] == "^1.70.0")
        #expect(VSCodeTheme.extensionID == "soprano.soprano-theme")

        let contributes = try #require(manifest["contributes"] as? [String: Any])
        let themes = try #require(contributes["themes"] as? [[String: String]])
        #expect(themes.map { $0["label"] } == [ThemeNames.light, ThemeNames.dark])
        #expect(themes.map { $0["uiTheme"] } == ["vs", "vs-dark"])
        for theme in themes {
            let path = try #require(theme["path"])
            let member = "extension/" + path.replacingOccurrences(of: "./", with: "")
            let document = try object(file(member, in: files).contents)
            #expect(document["name"] as? String == theme["label"])
        }
    }

    @Test func theVsixManifestIsWellFormedXmlNamingTheExtensionAndItsPackageJson() throws {
        let files = VSCodeTheme.packageFiles(for: TestPalettes.folio, version: "2.0.1")
        let manifest = try XMLDocument(xmlString: file("extension.vsixmanifest", in: files).contents)
        let identity = try #require(manifest.nodes(forXPath: "//*[local-name()='Identity']").first as? XMLElement)
        #expect(identity.attribute(forName: "Id")?.stringValue == "soprano-theme")
        #expect(identity.attribute(forName: "Publisher")?.stringValue == "soprano")
        #expect(identity.attribute(forName: "Version")?.stringValue == "2.0.1")
        let asset = try #require(manifest.nodes(forXPath: "//*[local-name()='Asset']").first as? XMLElement)
        #expect(asset.attribute(forName: "Type")?.stringValue == "Microsoft.VisualStudio.Code.Manifest")
        #expect(asset.attribute(forName: "Path")?.stringValue == "extension/package.json")
        _ = try XMLDocument(xmlString: file("[Content_Types].xml", in: files).contents)
    }

    @Test func workbenchSlotsFollowFolioWithTheAccentOnlyAsCursorAndFocusMark() throws {
        let paper = TestPalettes.paper
        let colors = try colors(paper)
        #expect(colors["editor.background"] == paper.bgBase.hex)
        #expect(colors["editor.foreground"] == paper.textPrimary.hex)
        #expect(colors["editorCursor.foreground"] == paper.accent.hex)
        #expect(colors["terminalCursor.foreground"] == paper.accent.hex)
        #expect(colors["focusBorder"] == paper.accent.hex)
        #expect(colors["tab.activeBorderTop"] == paper.accent.hex)
        #expect(colors["activityBarBadge.background"] == paper.accent.hex)
        #expect(colors["statusBar.background"] == paper.bgPanel.hex)
        #expect(colors["sideBar.background"] == paper.bgPanel.hex)
        #expect(colors["button.background"] == paper.textPrimary.hex)
        #expect(colors["button.foreground"] == paper.bgBase.hex)
        #expect(colors["tab.inactiveForeground"] == paper.textMuted.hex)
    }

    @Test func allSixteenTerminalColoursComeFromThePalettesTerminal() throws {
        let ink = TestPalettes.ink
        let colors = try colors(ink)
        let names = ["Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White"]
        let keys = names.map { "terminal.ansi\($0)" } + names.map { "terminal.ansiBright\($0)" }
        #expect(keys.map { colors[$0] } == ink.terminal.ansi.map(\.hex))
        #expect(colors["terminal.background"] == ink.terminal.background.hex)
        #expect(colors["terminal.selectionBackground"] == ink.terminal.selectionBackground.hex)
    }

    @Test func lightSelectionIsASiennaWashWhileDarkSelectionIsTheNeutralInkFill() throws {
        let paper = try colors(TestPalettes.paper)
        let ink = try colors(TestPalettes.ink)
        #expect(paper["editor.selectionBackground"]?.hasPrefix(TestPalettes.paper.accent.hex) == true)
        #expect(ink["editor.selectionBackground"]?.hasPrefix(TestPalettes.ink.textPrimary.hex) == true)
        #expect(paper["editor.background"] != ink["editor.background"])
    }

    @Test func syntaxColoursComeFromTheSharedSyntaxPaletteWithItalicCommentsAndNoAccent() throws {
        let paper = TestPalettes.paper
        let syntax = SyntaxPalette(paper)
        let theme = try object(VSCodeTheme.colorTheme(for: paper, name: ThemeNames.light))
        #expect(theme["type"] as? String == "light")
        #expect(theme["semanticHighlighting"] as? Bool == true)

        let rules = try #require(theme["tokenColors"] as? [[String: Any]])
        let comment = try #require(rules.first { ($0["scope"] as? [String])?.contains("comment") == true })
        let settings = try #require(comment["settings"] as? [String: String])
        #expect(settings["foreground"] == syntax.comment.hex)
        #expect(settings["fontStyle"] == "italic")
        let keyword = rules.first { ($0["scope"] as? [String])?.contains("keyword") == true }
        #expect((keyword?["settings"] as? [String: String])?["foreground"] == syntax.keyword.hex)

        let semantic = try #require(theme["semanticTokenColors"] as? [String: Any])
        #expect(semantic["function"] as? String == syntax.function.hex)
        #expect(semantic["type"] as? String == syntax.type.hex)
        #expect((semantic["comment"] as? [String: Any])?["italic"] as? Bool == true)

        let syntaxJSON = String(describing: rules) + String(describing: semantic)
        #expect(!syntaxJSON.contains(paper.accent.hex))
    }

    @Test func aPinnedDarkPairStillContributesBothNamesAsDarkThemes() throws {
        let pinned = ThemePair(light: TestPalettes.ink, dark: TestPalettes.ink)
        let files = VSCodeTheme.packageFiles(for: pinned, version: "1.0.0")
        let manifest = try object(file("extension/package.json", in: files).contents)
        let themes = try #require((manifest["contributes"] as? [String: Any])?["themes"] as? [[String: String]])
        #expect(themes.map { $0["label"] } == [ThemeNames.light, ThemeNames.dark])
        #expect(themes.map { $0["uiTheme"] } == ["vs-dark", "vs-dark"])

        let light = try object(file("extension/themes/soprano-light-color-theme.json", in: files).contents)
        #expect(light["name"] as? String == ThemeNames.light)
        #expect(light["type"] as? String == "dark")
    }
}
