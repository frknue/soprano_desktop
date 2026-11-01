import Foundation

/// Which Soprano palettes the desktop shows in light and in dark mode.
public enum ThemePairResolver {
    public static let folioPaperID = "folio-paper"
    public static let folioInkID = "folio-ink"
    /// Follow Soprano's own `theme` and `appearance`.
    public static let followSopranoID = "soprano"
    /// Folio: Paper in light mode, Ink in dark mode.
    public static let folioID = "folio"

    /// The palette ids for Soprano Desktop's `theme` setting.
    ///
    /// - `soprano`: Soprano's theme with Soprano's appearance. Folio with the `system`
    ///   appearance follows macOS (Paper, Ink); with a pinned appearance both slots get that
    ///   palette, so the desktop looks like Soprano even when macOS is in the other mode.
    /// - a palette id (`folio-ink`, `nord`, …): that palette in both slots.
    /// - `folio`, or any unknown id: Paper and Ink.
    public static func paletteIDs(
        theme: String,
        soprano: SopranoThemeFile,
        paletteIDs: Set<String>
    ) -> (light: String, dark: String) {
        if theme == followSopranoID {
            return resolve(soprano.themeID, appearance: soprano.appearance, paletteIDs: paletteIDs)
        }
        return resolve(theme, appearance: .system, paletteIDs: paletteIDs)
    }

    private static func resolve(
        _ id: String,
        appearance: SopranoAppearance,
        paletteIDs: Set<String>
    ) -> (light: String, dark: String) {
        if paletteIDs.contains(id) {
            return (id, id)
        }
        switch appearance {
        case .system: return (folioPaperID, folioInkID)
        case .light: return (folioPaperID, folioPaperID)
        case .dark: return (folioInkID, folioInkID)
        }
    }
}
