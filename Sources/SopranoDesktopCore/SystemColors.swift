import Foundation

/// macOS's fixed accent colours: the `AppleAccentColor` values of the global domain. The
/// key is absent for Multicolor, which Soprano Desktop never picks.
public enum SystemAccent: Int, CaseIterable, Sendable {
    case graphite = -1
    case red = 0
    case orange = 1
    case yellow = 2
    case green = 3
    case blue = 4
    case purple = 5
    case pink = 6

    public var name: String {
        switch self {
        case .graphite: "Graphite"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        }
    }

    /// Hue (degrees) of each chromatic accent as macOS draws it in light mode.
    private var hue: Double? {
        switch self {
        case .graphite: nil
        case .red: 3
        case .orange: 35
        case .yellow: 48
        case .green: 129
        case .blue: 211
        case .purple: 280
        case .pink: 349
        }
    }

    /// The accent closest in hue to `color`; Graphite for nearly grey colours. Folio's
    /// sienna (Paper `#a34a17`, Ink `#e08a52`) is Orange.
    public static func nearest(to color: RGB) -> SystemAccent {
        let hsb = color.hsb
        guard hsb.saturation >= 0.2, hsb.brightness >= 0.15 else { return .graphite }
        let chromatic = allCases.compactMap { accent in accent.hue.map { (accent, $0) } }
        return chromatic.min { lhs, rhs in
            hueDistance(lhs.1, hsb.hue) < hueDistance(rhs.1, hsb.hue)
        }!.0
    }

    private static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }
}

/// The text-selection colour (`AppleHighlightColor`): `"<r> <g> <b> <name>"`, components
/// 0–1 with six decimals; `Other` marks a custom colour, as System Settings writes it.
public enum SystemHighlight {
    public static func value(for color: RGB) -> String {
        String(format: "%.6f %.6f %.6f Other", color.red, color.green, color.blue)
    }

    /// The palette's text selection: the terminal selection colour, Paper's sienna wash
    /// (`#e4cdbc`) in light mode and Ink's dark sienna (`#483325`) in dark mode.
    public static func color(for palette: Palette) -> RGB {
        palette.terminal.selectionBackground
    }
}
