import Foundation

/// The commented settings.json written on first launch: the schema is the documentation.
/// Every value is the default, so the template resolves to `DesktopSettings.defaults`.
public enum SettingsTemplate {
    public static let text: String = """
    // Soprano Desktop settings. JSON with comments; saved changes apply immediately.
    // Every key is optional. Unknown keys and bad values are ignored with a warning.
    //
    // Nothing changes until you choose Apply in the menu bar (or run `SopranoDesktop apply`);
    // Restore puts every macOS and app setting Soprano Desktop changed back.
    {
      // "soprano" follows Soprano's theme and appearance (~/.config/soprano/settings.json);
      // "folio" follows macOS (Folio Paper in light mode, Folio Ink in dark mode);
      // or a Soprano theme id: "folio-paper", "folio-ink", "gruvbox-dark", "nord" …
      "theme": "soprano",

      // macOS settings kept on the theme while applied.
      "system": {
        // The macOS accent closest to the theme's accent (Orange for Folio's sienna).
        "accentColor": true,
        // Text selection in the theme's selection colour, switched with light and dark mode.
        "highlightColor": true,
        // A Folio wallpaper rendered for every screen, switched with light and dark mode.
        // macOS sets it on the current Space of each screen.
        "wallpaper": true,
        // Folders everywhere in the theme's accent (Appearance → Folder colour).
        "folderColor": true,
        // Tinted icon & widget style in the theme's accent: app icons, widgets and folders
        // take the tint (Appearance → Icon & widget style → Tinted, Auto).
        "tintedIcons": true,
        // Folio icons on your Home, Desktop, Documents and Downloads folders. A folder that
        // already has its own icon is left alone.
        "folderIcons": true,
        // A soft Folio alert sound, selected as the macOS alert sound.
        "alertSound": true,
        // Installs the Soprano screen saver (paper, clock, date). Pick it once in System
        // Settings → Screen Saver; macOS does not let apps select it.
        "screenSaver": true
      },

      // Calmer desktop behaviour, also put back by Restore.
      "desktop": {
        // Hide the files on the desktop (they stay in ~/Desktop).
        "hideDesktopIcons": true,
        // No suggested and recent apps in the Dock.
        "hideDockRecents": true,
        // Automatically hide and show the menu bar. While on, the Folio menu bar is not
        // shown (it sits on the visible menu bar).
        "hideMenuBar": false
      },

      // Surfaces Soprano Desktop draws itself; they need Accessibility permission
      // (System Settings → Privacy & Security → Accessibility → Soprano Desktop).
      "surfaces": {
        // A Folio strip over the app menus of the menu bar; status items stay native.
        "menuBar": true
      },

      // Apps that get "Soprano Light" and "Soprano Dark" themes, rewritten when the theme
      // changes. Ghostty, VS Code, Cursor and bat are also switched to them; Neovim, fzf and
      // Chrome need one line from you (the menu bar's Apps menu copies it).
      "apps": {
        "ghostty": true,
        "neovim": true,
        "vscode": true,
        "cursor": true,
        "bat": true,
        "fzf": true,
        "chrome": true
      },

      "app": {
        // Start Soprano Desktop when you log in, so it keeps following light and dark mode.
        "startAtLogin": true
      }
    }

    """
}
