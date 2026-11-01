import Foundation

/// bat's `Soprano Light` and `Soprano Dark` TextMate themes (`.tmTheme` XML property lists).
/// bat picks them up after `bat cache --build`; its theme name is the file name.
public enum BatTheme {
    /// "themes/Soprano Light.tmTheme" and "themes/Soprano Dark.tmTheme" (relative to
    /// `bat --config-dir`).
    public static func files(for pair: ThemePair) -> [GeneratedFile] {
        [
            GeneratedFile(path: "themes/\(ThemeNames.light).tmTheme", contents: tmTheme(for: pair.light, name: ThemeNames.light)),
            GeneratedFile(path: "themes/\(ThemeNames.dark).tmTheme", contents: tmTheme(for: pair.dark, name: ThemeNames.dark)),
        ]
    }

    public static func tmTheme(for palette: Palette, name: String) -> String {
        let theme: [String: Any] = [
            "name": name,
            "author": "Soprano Desktop (generated from \(palette.name); overwritten on theme changes)",
            "colorSpaceName": "sRGB",
            "settings": [["settings": globalSettings(for: palette)]] + scopeRules(for: palette),
        ]
        guard
            let data = try? PropertyListSerialization.data(fromPropertyList: theme, format: .xml, options: 0),
            let xml = String(data: data, encoding: .utf8)
        else {
            preconditionFailure("A tmTheme of strings, arrays and dictionaries always serializes")
        }
        return xml
    }

    private static func globalSettings(for palette: Palette) -> [String: String] {
        let bg = palette.bgBase
        return [
            "background": bg.hex,
            "foreground": palette.textPrimary.hex,
            "caret": palette.accent.hex,
            "lineHighlight": bg.mixed(with: palette.textPrimary, amount: 0.05).hex,
            "selection": palette.selection.hex,
            "gutter": bg.hex,
            "gutterForeground": palette.gray.hex,
            "invisibles": palette.borderStrong.hex,
            "findHighlight": bg.mixed(with: palette.accent, amount: 0.22).hex,
            "findHighlightForeground": palette.textPrimary.hex,
        ]
    }

    private static func scopeRules(for palette: Palette) -> [[String: Any]] {
        let s = SyntaxPalette(palette)
        func rule(_ name: String, _ scopes: [String], _ color: RGB?, _ fontStyle: String? = nil) -> [String: Any] {
            var settings: [String: String] = [:]
            if let color { settings["foreground"] = color.hex }
            if let fontStyle { settings["fontStyle"] = fontStyle }
            return ["name": name, "scope": scopes.joined(separator: ", "), "settings": settings]
        }
        return [
            rule("Comment", ["comment", "punctuation.definition.comment"], s.comment, "italic"),
            rule("String", ["string", "punctuation.definition.string"], s.string),
            rule(
                "Constant",
                ["constant.numeric", "constant.language", "constant.character", "constant.other", "support.constant"],
                s.constant
            ),
            rule("Keyword", ["keyword", "keyword.control", "storage", "storage.type", "storage.modifier", "variable.language"], s.keyword),
            rule("Operator", ["keyword.operator"], s.operator),
            rule("Punctuation", ["punctuation.separator", "punctuation.terminator", "punctuation.section", "meta.brace"], s.punctuation),
            rule("Function", ["entity.name.function", "support.function", "variable.function", "meta.function-call entity.name.function"], s.function),
            rule(
                "Type",
                ["entity.name.type", "entity.name.class", "entity.name.struct", "entity.name.enum",
                 "entity.name.interface", "entity.other.inherited-class", "support.type", "support.class"],
                s.type
            ),
            rule("Variable", ["variable", "variable.other"], s.variable),
            rule("Parameter", ["variable.parameter"], s.variable, "italic"),
            rule("Property", ["variable.other.member", "variable.other.property", "support.variable.property", "meta.property-name"], s.property),
            rule("Tag", ["entity.name.tag"], s.tag),
            rule("Attribute", ["entity.other.attribute-name"], s.attribute),
            rule("Escape and regex", ["constant.character.escape", "string.regexp", "constant.other.placeholder"], s.special),
            rule("Invalid", ["invalid", "invalid.illegal"], s.error),
            rule("Deprecated", ["invalid.deprecated"], s.warning),
            rule("Heading", ["markup.heading", "entity.name.section"], s.function, "bold"),
            rule("Bold", ["markup.bold"], nil, "bold"),
            rule("Italic", ["markup.italic"], nil, "italic"),
            rule("Raw", ["markup.raw", "markup.inline.raw"], s.string),
            rule("Link", ["markup.link", "markup.underline.link", "string.other.link"], s.function, "underline"),
            rule("Quote", ["markup.quote"], s.comment, "italic"),
            rule("List", ["markup.list punctuation.definition.list"], s.special),
            rule("Inserted", ["markup.inserted", "meta.diff.header.to-file", "punctuation.definition.inserted"], s.inserted),
            rule("Deleted", ["markup.deleted", "meta.diff.header.from-file", "punctuation.definition.deleted"], s.deleted),
            rule("Changed", ["markup.changed", "punctuation.definition.changed"], s.changed),
            rule("Diff header", ["meta.diff.header", "meta.diff.index"], s.info, "bold"),
            rule("Diff range", ["meta.diff.range"], s.special),
        ]
    }
}
