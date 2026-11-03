import Foundation

/// An sRGB colour with components in 0...1. Core's stand-in for `NSColor`, which Core cannot
/// import; the app converts Soprano's `AppTheme` palettes into these.
public struct RGB: Equatable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
    }

    /// `#rrggbb` or `rrggbb`; nil for anything else.
    public init?(hex: String) {
        var text = Substring(hex)
        if text.hasPrefix("#") { text = text.dropFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255
        )
    }

    /// `#rrggbb`, lowercase.
    public var hex: String {
        "#" + hexDigits
    }

    /// `rrggbb`, lowercase, without the `#` (Ghostty, tmTheme-free formats).
    public var hexDigits: String {
        String(format: "%02x%02x%02x", Self.byte(red), Self.byte(green), Self.byte(blue))
    }

    /// `#rrggbbaa` with `alpha` in 0...1 (VS Code, Zed).
    public func hex(alpha: Double) -> String {
        hex + String(format: "%02x", Self.byte(Self.clamp(alpha)))
    }

    /// Linear blend in sRGB: `amount` 0 is `self`, 1 is `other`.
    public func mixed(with other: RGB, amount: Double) -> RGB {
        let t = Self.clamp(amount)
        return RGB(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t
        )
    }

    /// Hue in degrees (0..<360), saturation and brightness in 0...1 (HSB/HSV).
    public var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        let saturation = maxValue == 0 ? 0 : delta / maxValue
        guard delta > 0 else { return (0, saturation, maxValue) }
        var hue: Double
        if maxValue == red {
            hue = (green - blue) / delta
        } else if maxValue == green {
            hue = (blue - red) / delta + 2
        } else {
            hue = (red - green) / delta + 4
        }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, saturation, maxValue)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func byte(_ value: Double) -> Int {
        Int((value * 255).rounded())
    }
}

/// The 16 ANSI colours plus the terminal's own colours, as Soprano's `TerminalColors`.
public struct TerminalPalette: Equatable, Sendable {
    public var background: RGB
    public var foreground: RGB
    public var cursor: RGB
    public var cursorAccent: RGB
    public var selectionBackground: RGB
    /// Exactly 16 entries: black, red, green, yellow, blue, magenta, cyan, white, then the
    /// bright variants in the same order.
    public var ansi: [RGB]

    public init(
        background: RGB,
        foreground: RGB,
        cursor: RGB,
        cursorAccent: RGB,
        selectionBackground: RGB,
        ansi: [RGB]
    ) {
        precondition(ansi.count == 16, "A terminal palette has exactly 16 ANSI colours")
        self.background = background
        self.foreground = foreground
        self.cursor = cursor
        self.cursorAccent = cursorAccent
        self.selectionBackground = selectionBackground
        self.ansi = ansi
    }

    public var black: RGB { ansi[0] }
    public var red: RGB { ansi[1] }
    public var green: RGB { ansi[2] }
    public var yellow: RGB { ansi[3] }
    public var blue: RGB { ansi[4] }
    public var magenta: RGB { ansi[5] }
    public var cyan: RGB { ansi[6] }
    public var white: RGB { ansi[7] }
}

/// One concrete Soprano palette (Folio Paper, Folio Ink, Gruvbox Dark, …): the chrome tokens
/// of `ThemeColors` and the terminal colours, by their Soprano names.
public struct Palette: Equatable, Sendable {
    /// Soprano's theme id, e.g. `folio-paper`.
    public var id: String
    /// Soprano's display name, e.g. `Folio Paper`.
    public var name: String
    public var isLight: Bool

    public var bgBase: RGB
    public var bgPanel: RGB
    public var bgRaised: RGB
    public var bgOverlay: RGB
    public var textPrimary: RGB
    public var textMuted: RGB
    /// Sienna in Folio: the one pencil mark (focus, caret, cursor, matches).
    public var accent: RGB
    public var accentStrong: RGB
    public var borderSubtle: RGB
    public var borderStrong: RGB
    public var success: RGB
    public var danger: RGB
    public var blue: RGB
    public var cyan: RGB
    public var yellow: RGB
    public var gray: RGB

    public var terminal: TerminalPalette

    public init(
        id: String,
        name: String,
        isLight: Bool,
        bgBase: RGB,
        bgPanel: RGB,
        bgRaised: RGB,
        bgOverlay: RGB,
        textPrimary: RGB,
        textMuted: RGB,
        accent: RGB,
        accentStrong: RGB,
        borderSubtle: RGB,
        borderStrong: RGB,
        success: RGB,
        danger: RGB,
        blue: RGB,
        cyan: RGB,
        yellow: RGB,
        gray: RGB,
        terminal: TerminalPalette
    ) {
        self.id = id
        self.name = name
        self.isLight = isLight
        self.bgBase = bgBase
        self.bgPanel = bgPanel
        self.bgRaised = bgRaised
        self.bgOverlay = bgOverlay
        self.textPrimary = textPrimary
        self.textMuted = textMuted
        self.accent = accent
        self.accentStrong = accentStrong
        self.borderSubtle = borderSubtle
        self.borderStrong = borderStrong
        self.success = success
        self.danger = danger
        self.blue = blue
        self.cyan = cyan
        self.yellow = yellow
        self.gray = gray
        self.terminal = terminal
    }

    /// Soprano's derived `selection` token: a sienna wash on light palettes, an 11 % ink
    /// fill on dark ones, flattened onto `bgBase` (generators that need alpha use
    /// `accent`/`textPrimary` with their own alpha instead).
    public var selection: RGB {
        isLight ? bgBase.mixed(with: accent, amount: 0.12) : bgBase.mixed(with: textPrimary, amount: 0.11)
    }

    /// Folder colour and tinted icons: the accent 70 % of the way to `textMuted`, so folders
    /// and app icons carry a quiet tint instead of the full accent (Folio: Paper `#76543d`,
    /// Ink `#b39279`). Rounded to whole bytes, the precision the setting is kept at.
    public var iconTint: RGB {
        let tint = accent.mixed(with: textMuted, amount: 0.7)
        return RGB(hex: tint.hex) ?? tint
    }

    /// Magenta is not a chrome token; generators take it from the terminal palette.
    public var magenta: RGB { terminal.magenta }
}

/// The palette the desktop shows in light mode and the one it shows in dark mode. Equal
/// when Soprano's theme is pinned (a third-party theme, or Folio with a pinned appearance).
///
/// Every generated theme is named after the slot, not the palette (`Soprano Light`,
/// `Soprano Dark`), so an app configured once keeps following Soprano when its theme
/// changes; Soprano Desktop only rewrites the files.
public struct ThemePair: Equatable, Sendable {
    public var light: Palette
    public var dark: Palette

    public init(light: Palette, dark: Palette) {
        self.light = light
        self.dark = dark
    }

    public func palette(for appearance: Appearance) -> Palette {
        appearance == .light ? light : dark
    }
}

/// macOS's effective appearance, reduced to light or dark.
public enum Appearance: String, CaseIterable, Codable, Sendable {
    case light
    case dark
}

/// The names every generated theme uses.
public enum ThemeNames {
    public static let light = "Soprano Light"
    public static let dark = "Soprano Dark"
    /// File-name stems (`soprano-light`, `soprano-dark`).
    public static let lightSlug = "soprano-light"
    public static let darkSlug = "soprano-dark"
}

/// One file a generator produces, relative to the target's root directory.
public struct GeneratedFile: Equatable, Sendable {
    /// Relative path with `/` separators, e.g. `themes/soprano-dark`.
    public var path: String
    public var contents: String

    public init(path: String, contents: String) {
        self.path = path
        self.contents = contents
    }
}
