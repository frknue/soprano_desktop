import AppKit
import SopranoDesktopCore

/// Folio Paper and Folio Ink transcribed from Soprano's `Theme.swift`, so Core tests run
/// without AppKit's palettes. `PaletteBridgeTests` checks they still match the vendored file.
enum TestPalettes {
    static func rgb(_ hex: String) -> RGB {
        RGB(hex: hex)!
    }

    static let paper = Palette(
        id: "folio-paper",
        name: "Folio Paper",
        isLight: true,
        bgBase: rgb("#f6f2ea"),
        bgPanel: rgb("#ede7db"),
        bgRaised: rgb("#fcfaf5"),
        bgOverlay: rgb("#e5dece"),
        textPrimary: rgb("#2b2620"),
        textMuted: rgb("#62594d"),
        accent: rgb("#a34a17"),
        accentStrong: rgb("#863a0f"),
        borderSubtle: rgb("#e0d8c9"),
        borderStrong: rgb("#cbc0ad"),
        success: rgb("#456b30"),
        danger: rgb("#ae2f3c"),
        blue: rgb("#2f5f8a"),
        cyan: rgb("#266b66"),
        yellow: rgb("#835f0b"),
        gray: rgb("#857c6e"),
        terminal: TerminalPalette(
            background: rgb("#f6f2ea"),
            foreground: rgb("#2b2620"),
            cursor: rgb("#a34a17"),
            cursorAccent: rgb("#f6f2ea"),
            selectionBackground: rgb("#e4cdbc"),
            ansi: [
                "#2b2620", "#ae2f3c", "#456b30", "#835f0b", "#2f5f8a", "#8a3f78", "#266b66", "#6f665a",
                "#5a5248", "#c0414a", "#557f3b", "#9a7212", "#3d72a3", "#a04f8d", "#2f817b", "#8f8678",
            ].map(rgb)
        )
    )

    static let ink = Palette(
        id: "folio-ink",
        name: "Folio Ink",
        isLight: false,
        bgBase: rgb("#1d1b18"),
        bgPanel: rgb("#181613"),
        bgRaised: rgb("#26231f"),
        bgOverlay: rgb("#2f2b26"),
        textPrimary: rgb("#e2dacb"),
        textMuted: rgb("#a0968a"),
        accent: rgb("#e08a52"),
        accentStrong: rgb("#f0a774"),
        borderSubtle: rgb("#322e29"),
        borderStrong: rgb("#443e37"),
        success: rgb("#97ae76"),
        danger: rgb("#e0707a"),
        blue: rgb("#86a6cb"),
        cyan: rgb("#74b3a9"),
        yellow: rgb("#d6aa4f"),
        gray: rgb("#776f64"),
        terminal: TerminalPalette(
            background: rgb("#1d1b18"),
            foreground: rgb("#e2dacb"),
            cursor: rgb("#e08a52"),
            cursorAccent: rgb("#1d1b18"),
            selectionBackground: rgb("#483325"),
            ansi: [
                "#2a2622", "#e0707a", "#97ae76", "#d6aa4f", "#86a6cb", "#c191b8", "#74b3a9", "#cfc6b5",
                "#7d7469", "#ec8f97", "#b0c592", "#e8c272", "#a3bfdf", "#d5aacd", "#93c9bf", "#f4efe5",
            ].map(rgb)
        )
    )

    static let folio = ThemePair(light: paper, dark: ink)
}
