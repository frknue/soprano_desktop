import AppKit
import Testing
@testable import SopranoDesktopCore

struct ConfigEditsTests {
    private let ghosttyTheme = LineSetting(key: "theme", syntax: .ghostty)
    private let batLight = LineSetting(key: "theme-light", syntax: .argument)

    @Test func ghosttyReadsTheLastActiveThemeLineAndIgnoresCommentsAndSimilarKeys() {
        let text = "# theme = Old\ntheme = \"Gruvbox Dark\"\nthemes-dir = x\ntheme=Nord\n"
        #expect(ghosttyTheme.value(in: text) == "Nord")
    }

    @Test func settingReplacesOnlyTheLineInForceAndKeepsEverythingElse() {
        let text = "font-size = 14\ntheme = A\n# note\ntheme = B\nmacos-option-as-alt = true\n"
        let edited = ghosttyTheme.setting("light:soprano-light,dark:soprano-dark", in: text)
        #expect(edited == "font-size = 14\ntheme = A\n# note\ntheme = light:soprano-light,dark:soprano-dark\nmacos-option-as-alt = true\n")
    }

    @Test func settingAKeyThatIsMissingAppendsOneLineAndRemovingItGivesTheOriginalTextBack() {
        let text = "font-size = 14\n"
        let edited = ghosttyTheme.setting("x", in: text)
        #expect(edited == "font-size = 14\ntheme = x\n")
        #expect(ghosttyTheme.setting(nil, in: edited) == text)
    }

    @Test func batArgumentLinesAcceptBothSeparatorsAndKeepQuotesRaw() {
        #expect(batLight.value(in: "--theme-light=\"GitHub\"\n") == "\"GitHub\"")
        #expect(batLight.value(in: "--theme-light \"GitHub\"\n") == "\"GitHub\"")
        #expect(batLight.value(in: "--theme-lightish=x\n--theme=TwoDark\n") == nil)
        #expect(batLight.setting("\"Soprano Light\"", in: "") == "--theme-light=\"Soprano Light\"\n")
    }

    @Test func jsoncSettingKeepsCommentsAndTreatsDottedKeysAsOneKey() throws {
        let text = "{\n  // keep me\n  \"workbench.colorTheme\": \"Rider\",\n}\n"
        let setting = JSONCSetting(key: "workbench.preferredDarkColorTheme")
        let edited = try setting.setting(.string("Soprano Dark"), in: text)
        #expect(edited.contains("// keep me"))
        #expect(try setting.value(in: edited) == .string("Soprano Dark"))
        #expect(try JSONCSetting(key: "workbench.colorTheme").value(in: edited) == .string("Rider"))
        let removed = try setting.setting(nil, in: edited)
        #expect(try setting.value(in: removed) == nil)
        #expect(removed.contains("// keep me"))
    }

    @Test func jsoncSettingTurnsAnEmptyFileIntoAnObjectAndRejectsNonObjects() throws {
        let edited = try JSONCSetting(key: "window.autoDetectColorScheme").setting(.bool(true), in: "")
        #expect(try JSONCSetting(key: "window.autoDetectColorScheme").value(in: edited) == .bool(true))
        #expect(throws: (any Error).self) { try JSONCSetting(key: "a").setting(.bool(true), in: "[1, 2]") }
    }
}
