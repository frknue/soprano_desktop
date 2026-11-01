import AppKit
import Testing
@testable import SopranoDesktopCore

struct FzfColorsTests {
    /// `slot -> #rrggbb` from a `--color=` spec.
    private func slots(_ spec: String) -> [String: String] {
        var result: [String: String] = [:]
        for entry in spec.dropFirst("--color=".count).split(separator: ",") {
            let parts = entry.split(separator: ":", maxSplits: 1).map(String.init)
            result[parts[0]] = parts[1]
        }
        return result
    }

    /// Runs `script` in `shell` with the generated snippet at `$SNIPPET`; returns stdout.
    private func run(_ shell: String, _ script: String, snippet: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FzfColorsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("fzf.sh")
        try snippet.write(to: file, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-c", script]
        process.environment = ["SNIPPET": file.path, "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .newlines)
    }

    @Test func theSpecMarksMatchesAndThePointerInSiennaAndTheCurrentLineWithTheSelection() {
        let paper = TestPalettes.paper
        let values = slots(FzfColors.colorSpec(for: paper))

        #expect(FzfColors.colorSpec(for: paper).hasPrefix("--color="))
        #expect(values["fg"] == paper.textPrimary.hex)
        #expect(values["bg"] == paper.bgBase.hex)
        #expect(values["hl"] == paper.accent.hex)
        #expect(values["hl+"] == paper.accent.hex)
        #expect(values["pointer"] == paper.accent.hex)
        #expect(values["bg+"] == paper.terminal.selectionBackground.hex)
        #expect(slots(FzfColors.colorSpec(for: TestPalettes.ink))["bg+"] == TestPalettes.ink.selection.hex)
        let accentSlots = values.filter { $0.value == paper.accent.hex }.keys.sorted()
        #expect(accentSlots == ["hl", "hl+", "pointer"])
    }

    @Test func theSnippetCarriesBothSpecsAndPicksDarkFromTheMacAppearance() throws {
        let files = FzfColors.files(for: TestPalettes.folio)
        let snippet = try #require(files.first?.contents)

        #expect(files.map(\.path) == ["shell/fzf.sh"])
        #expect(snippet.contains("AppleInterfaceStyle"))
        let dark = try #require(snippet.range(of: FzfColors.colorSpec(for: TestPalettes.ink)))
        let light = try #require(snippet.range(of: FzfColors.colorSpec(for: TestPalettes.paper)))
        #expect(dark.lowerBound < light.lowerBound, "the dark spec belongs to the \"Dark\" branch")
    }

    @Test func sourcingTheSnippetTwiceKeepsTheUsersOptionsAndAddsOneColourBlockInZshAndBash() throws {
        let snippet = FzfColors.files(for: TestPalettes.folio)[0].contents
        let script = #"FZF_DEFAULT_OPTS="--height 40%"; . "$SNIPPET"; . "$SNIPPET"; echo "$FZF_DEFAULT_OPTS""#

        for shell in ["/bin/zsh", "/bin/bash"] {
            let options = try run(shell, script, snippet: snippet)
            #expect(options.hasPrefix("--height 40% --color="), "\(shell): \(options)")
            #expect(options.components(separatedBy: "--color=").count == 2, "\(shell): \(options)")
            #expect(options.components(separatedBy: "--height").count == 2, "\(shell): \(options)")
        }
    }

    @Test func reSourcingAfterAThemeChangeReplacesTheOldBlockWhereverItSits() throws {
        let snippet = FzfColors.files(for: TestPalettes.folio)[0].contents
        let script = #"""
        export SOPRANO_FZF_COLOR_OPTS='--color=fg:#000000'
        FZF_DEFAULT_OPTS='--a --color=fg:#000000 --b'
        . "$SNIPPET"
        echo "$FZF_DEFAULT_OPTS"
        """#

        let options = try run("/bin/zsh", script, snippet: snippet)
        #expect(options.hasPrefix("--a --b --color="), "\(options)")
        #expect(!options.contains("#000000"))
    }
}
