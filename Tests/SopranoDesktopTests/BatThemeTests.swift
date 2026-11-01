import AppKit
import Testing
@testable import SopranoDesktopCore

struct BatThemeTests {
    private static func parse(_ contents: String) throws -> [String: Any] {
        let plist = try PropertyListSerialization.propertyList(from: Data(contents.utf8), format: nil)
        return try #require(plist as? [String: Any])
    }

    private static func rules(_ theme: [String: Any]) throws -> [[String: Any]] {
        try #require(theme["settings"] as? [[String: Any]])
    }

    private static func globals(_ theme: [String: Any]) throws -> [String: String] {
        try #require(try rules(theme).first?["settings"] as? [String: String])
    }

    /// The settings of the rule whose comma-separated scope list contains `scope` exactly.
    private static func rule(for scope: String, in theme: [String: Any]) throws -> [String: String] {
        let match = try rules(theme).first { rule in
            (rule["scope"] as? String)?
                .split(separator: ",")
                .contains { $0.trimmingCharacters(in: .whitespaces) == scope } ?? false
        }
        return try #require(match?["settings"] as? [String: String])
    }

    @Test func filesAreNamedLightAndDarkUnderThemesSoBatListsThemByName() throws {
        let files = BatTheme.files(for: TestPalettes.folio)
        #expect(files.map(\.path) == ["themes/Soprano Light.tmTheme", "themes/Soprano Dark.tmTheme"])
        #expect(try Self.parse(files[0].contents)["name"] as? String == ThemeNames.light)
        #expect(try Self.parse(files[1].contents)["name"] as? String == ThemeNames.dark)
    }

    @Test func eachThemeParsesAsAPropertyListWithThePaletteBackgroundAndAnAccentCaret() throws {
        let light = try Self.globals(Self.parse(BatTheme.tmTheme(for: TestPalettes.paper, name: ThemeNames.light)))
        let dark = try Self.globals(Self.parse(BatTheme.tmTheme(for: TestPalettes.ink, name: ThemeNames.dark)))
        #expect(light["background"] == "#f6f2ea")
        #expect(light["foreground"] == "#2b2620")
        #expect(light["caret"] == "#a34a17")
        #expect(light["selection"] == TestPalettes.paper.selection.hex)
        #expect(dark["background"] == "#1d1b18")
        #expect(dark["caret"] == "#e08a52")
        #expect(dark["selection"] == TestPalettes.ink.selection.hex)
    }

    @Test func scopesTakeTheirColoursFromTheSharedSyntaxPaletteWithItalicComments() throws {
        let theme = try Self.parse(BatTheme.tmTheme(for: TestPalettes.paper, name: ThemeNames.light))
        let syntax = SyntaxPalette(TestPalettes.paper)
        let comment = try Self.rule(for: "comment", in: theme)
        #expect(comment["foreground"] == syntax.comment.hex)
        #expect(comment["fontStyle"] == "italic")
        #expect(try Self.rule(for: "keyword", in: theme)["foreground"] == syntax.keyword.hex)
        #expect(try Self.rule(for: "string", in: theme)["foreground"] == syntax.string.hex)
        #expect(try Self.rule(for: "entity.name.function", in: theme)["foreground"] == syntax.function.hex)
        #expect(try Self.rule(for: "markup.inserted", in: theme)["foreground"] == syntax.inserted.hex)
        #expect(try Self.rule(for: "markup.deleted", in: theme)["foreground"] == syntax.deleted.hex)
    }

    @Test func aPinnedPairStillYieldsBothNamedThemesFromTheSamePalette() throws {
        let files = BatTheme.files(for: ThemePair(light: TestPalettes.ink, dark: TestPalettes.ink))
        let themes = try files.map { try Self.parse($0.contents) }
        #expect(themes.map { $0["name"] as? String } == [ThemeNames.light, ThemeNames.dark])
        #expect(try themes.allSatisfy { try Self.globals($0)["background"] == "#1d1b18" })
    }
}
