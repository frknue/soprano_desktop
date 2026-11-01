import Foundation

/// Code-highlighting roles every editor generator (VS Code/Cursor, Neovim, bat) maps from one
/// palette, so code looks the same in each of them.
///
/// The accent (sienna in Folio) is not a syntax colour: Folio keeps it for the caret, the
/// cursor and the keyboard-focus mark, so generators use it only there.
public struct SyntaxPalette: Equatable, Sendable {
    public var foreground: RGB
    /// Italic in every generator.
    public var comment: RGB
    public var keyword: RGB
    public var string: RGB
    /// Numbers, booleans, `nil`, enum cases and other constants.
    public var constant: RGB
    public var function: RGB
    public var type: RGB
    public var variable: RGB
    public var property: RGB
    public var `operator`: RGB
    public var punctuation: RGB
    /// Markup tags (HTML/XML/JSX).
    public var tag: RGB
    public var attribute: RGB
    /// Escapes and regex.
    public var special: RGB
    public var error: RGB
    public var warning: RGB
    public var info: RGB
    public var hint: RGB
    public var inserted: RGB
    public var deleted: RGB
    public var changed: RGB

    public init(_ palette: Palette) {
        foreground = palette.textPrimary
        comment = palette.textMuted
        keyword = palette.magenta
        string = palette.success
        constant = palette.yellow
        function = palette.blue
        type = palette.cyan
        variable = palette.textPrimary
        property = palette.textPrimary
        `operator` = palette.textMuted
        punctuation = palette.textMuted
        tag = palette.terminal.red
        attribute = palette.yellow
        special = palette.cyan
        error = palette.danger
        warning = palette.yellow
        info = palette.blue
        hint = palette.cyan
        inserted = palette.success
        deleted = palette.danger
        changed = palette.yellow
    }
}
