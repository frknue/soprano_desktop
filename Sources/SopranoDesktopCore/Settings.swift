import Foundation

/// The macOS settings Soprano Desktop keeps on the Soprano theme (`system.*` in settings.json).
public enum SystemSetting: String, CaseIterable, Sendable {
    /// `AppleAccentColor`: the closest of macOS's fixed accents (Orange for Folio's sienna).
    case accentColor
    /// `AppleHighlightColor`: the palette's text-selection colour, per appearance.
    case highlightColor
    /// A rendered Folio wallpaper on every screen, swapped with the appearance.
    case wallpaper
    /// Folders everywhere in the theme's muted icon tint (Appearance → Folder colour → custom).
    case folderColor
    /// Tinted icon & widget style in the theme's muted icon tint (Appearance → Icon & widget
    /// style → Tinted, Auto); app icons, widgets and folders take the tint.
    case tintedIcons
    /// Folio icons on Home, Desktop, Documents and Downloads.
    case folderIcons
    /// A soft Folio alert sound in `~/Library/Sounds`, selected as the alert sound.
    case alertSound
    /// The Soprano screen saver installed in `~/Library/Screen Savers` (selected once by
    /// the user in System Settings → Screen Saver).
    case screenSaver

    public var displayName: String {
        switch self {
        case .accentColor: "Accent colour"
        case .highlightColor: "Highlight colour"
        case .wallpaper: "Wallpaper"
        case .folderColor: "Folder colour"
        case .tintedIcons: "Tinted icons"
        case .folderIcons: "Folder icons"
        case .alertSound: "Alert sound"
        case .screenSaver: "Screen saver"
        }
    }
}

/// Calmer desktop behaviour (`desktop.*` in settings.json).
public enum DesktopBehavior: String, CaseIterable, Sendable {
    /// Hide the files on the desktop (Desktop & Dock → Show items → On Desktop).
    case hideDesktopIcons
    /// No suggested and recent apps in the Dock.
    case hideDockRecents
    /// Automatically hide and show the menu bar. Off by default: the Folio menu bar sits on
    /// the visible menu bar and is not shown while this is on.
    case hideMenuBar

    public var displayName: String {
        switch self {
        case .hideDesktopIcons: "Hide desktop icons"
        case .hideDockRecents: "Hide recent apps in Dock"
        case .hideMenuBar: "Hide menu bar"
        }
    }

    public static let defaults: Set<DesktopBehavior> = [.hideDesktopIcons, .hideDockRecents]
}

/// Surfaces Soprano Desktop draws itself (`surfaces.*`); they need Accessibility.
public enum Surface: String, CaseIterable, Sendable {
    /// A Folio strip over the app-menu part of the menu bar.
    case menuBar

    public var displayName: String {
        switch self {
        case .menuBar: "Folio menu bar"
        }
    }
}

/// The apps Soprano Desktop writes themes for (`apps.*` in settings.json).
public enum DesktopTarget: String, CaseIterable, Sendable {
    case ghostty
    case neovim
    case vscode
    case cursor
    case bat
    case fzf
    case chrome

    public var displayName: String {
        switch self {
        case .ghostty: "Ghostty"
        case .neovim: "Neovim"
        case .vscode: "VS Code"
        case .cursor: "Cursor"
        case .bat: "bat"
        case .fzf: "fzf"
        case .chrome: "Chrome"
        }
    }

    /// Whether applying also selects the Soprano theme in the app's own config. For the
    /// others Soprano Desktop keeps the theme files current and `setupHint` names the one
    /// line the user adds once.
    public var selectsTheme: Bool {
        switch self {
        case .ghostty, .vscode, .cursor, .bat: true
        case .neovim, .fzf, .chrome: false
        }
    }

    /// The one-time step for apps Soprano Desktop does not configure itself.
    public var setupHint: String? {
        switch self {
        case .neovim: "vim.cmd.colorscheme(\"soprano\")"
        case .fzf: "source ~/.config/soprano-desktop/shell/fzf.sh"
        case .chrome: "~/.config/soprano-desktop/chrome/soprano-dark"
        case .ghostty, .vscode, .cursor, .bat: nil
        }
    }

    /// Where `setupHint` goes.
    public var setupHintPlace: String? {
        switch self {
        case .neovim: "init.lua"
        case .fzf: "~/.zshrc"
        case .chrome: "chrome://extensions → Developer mode → Load unpacked"
        case .ghostty, .vscode, .cursor, .bat: nil
        }
    }
}

/// Resolved settings.json.
public struct DesktopSettings: Equatable, Sendable {
    /// `soprano` (follow Soprano), `folio` (follow macOS) or a Soprano palette id.
    public var theme: String = ThemePairResolver.followSopranoID
    public var system: Set<SystemSetting> = Set(SystemSetting.allCases)
    public var desktop: Set<DesktopBehavior> = DesktopBehavior.defaults
    public var surfaces: Set<Surface> = Set(Surface.allCases)
    public var apps: Set<DesktopTarget> = Set(DesktopTarget.allCases)
    public var startAtLogin = true

    public init() {}

    public static let defaults = DesktopSettings()
}

/// A problem in settings.json: the document is unreadable (`.error`) or one value was
/// ignored (`.warning`). Never stops the app (Soprano's `ConfigIssue`).
public struct ConfigIssue: Equatable, Identifiable, Sendable {
    public enum Severity: Equatable, Sendable {
        /// The document could not be read at all; the last good settings stay in force.
        case error
        /// One key was ignored; everything else applied.
        case warning
    }

    public let severity: Severity
    public let message: String
    /// 1-based line in settings.json, when the problem has a position.
    public var line: Int?

    public init(severity: Severity, message: String, line: Int? = nil) {
        self.severity = severity
        self.message = message
        self.line = line
    }

    public var id: String { "\(severity)|\(line.map(String.init) ?? "-")|\(message)" }
}

public struct SettingsResolution: Equatable, Sendable {
    /// nil when the document could not be parsed (keep the last good settings); `issues`
    /// then holds one `.error`.
    public var settings: DesktopSettings?
    public var issues: [ConfigIssue]

    public init(settings: DesktopSettings?, issues: [ConfigIssue]) {
        self.settings = settings
        self.issues = issues
    }
}

/// A settings.json edit that could not be applied, positioned in the original text.
public struct SettingsEditError: Error, Equatable, Sendable {
    public let message: String
    /// 1-based line in the edited document.
    public let line: Int

    public init(message: String, line: Int) {
        self.message = message
        self.line = line
    }
}

/// Surgical writes into settings.json that keep the user's comments and layout.
public enum SettingsEditor {
    /// Sets `value` at `path`, creating missing objects and keeping comments and key order
    /// (vendored `JSONCText`). Throws `SettingsEditError` when the document is not a JSON
    /// object.
    public static func setting(_ value: Any, at path: [String], in text: String) throws -> String {
        do {
            return try JSONCText.setting(value, at: path, in: text)
        } catch let error as JSONCText.ParseError {
            throw SettingsEditError(message: error.message, line: error.line)
        }
    }
}
