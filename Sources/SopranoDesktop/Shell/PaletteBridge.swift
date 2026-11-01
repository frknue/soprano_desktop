import AppKit
import SopranoDesktopCore

/// Soprano's AppKit palettes (vendored `Theme.swift`) as Core `Palette`s.
enum PaletteBridge {
    /// Every concrete Soprano palette id (`folio-paper`, `folio-ink`, `gruvbox-dark`, …).
    static var paletteIDs: Set<String> {
        Set(AppTheme.allThemes.map(\.id))
    }

    /// Every id settings.json accepts besides `soprano`: `folio` and the palettes.
    static var knownThemeIDs: Set<String> {
        Set(AppTheme.options.map(\.id))
    }

    /// The palette with `id`; Folio Paper or Ink (by the id) for anything unknown.
    static func palette(id: String) -> Palette {
        let theme = AppTheme.allThemes.first { $0.id == id }
            ?? AppTheme.theme(for: id, appearance: id == ThemePairResolver.folioInkID ? .dark : .light)
        return palette(theme)
    }

    static func pair(theme: String, soprano: SopranoThemeFile) -> ThemePair {
        let ids = ThemePairResolver.paletteIDs(theme: theme, soprano: soprano, paletteIDs: paletteIDs)
        return ThemePair(light: palette(id: ids.light), dark: palette(id: ids.dark))
    }

    static func palette(_ theme: AppTheme) -> Palette {
        let colors = theme.colors
        let terminal = theme.terminalColors
        return Palette(
            id: theme.id,
            name: theme.name,
            isLight: theme.appearance == .light,
            bgBase: rgb(colors.bgBase),
            bgPanel: rgb(colors.bgPanel),
            bgRaised: rgb(colors.bgRaised),
            bgOverlay: rgb(colors.bgOverlay),
            textPrimary: rgb(colors.textPrimary),
            textMuted: rgb(colors.textMuted),
            accent: rgb(colors.accent),
            accentStrong: rgb(colors.accentStrong),
            borderSubtle: rgb(colors.borderSubtle),
            borderStrong: rgb(colors.borderStrong),
            success: rgb(colors.success),
            danger: rgb(colors.danger),
            blue: rgb(colors.blue),
            cyan: rgb(colors.cyan),
            yellow: rgb(colors.yellow),
            gray: rgb(colors.gray),
            terminal: TerminalPalette(
                background: rgb(terminal.background),
                foreground: rgb(terminal.foreground),
                cursor: rgb(terminal.cursor),
                cursorAccent: rgb(terminal.cursorAccent),
                selectionBackground: rgb(terminal.selectionBackground),
                ansi: [
                    terminal.black, terminal.red, terminal.green, terminal.yellow,
                    terminal.blue, terminal.magenta, terminal.cyan, terminal.white,
                    terminal.brightBlack, terminal.brightRed, terminal.brightGreen, terminal.brightYellow,
                    terminal.brightBlue, terminal.brightMagenta, terminal.brightCyan, terminal.brightWhite,
                ].map(rgb)
            )
        )
    }

    static func rgb(_ color: NSColor) -> RGB {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        return RGB(red: Double(srgb.redComponent), green: Double(srgb.greenComponent), blue: Double(srgb.blueComponent))
    }

    static func color(_ rgb: RGB) -> NSColor {
        NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}
