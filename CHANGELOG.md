# Changelog

All notable changes to Soprano Desktop are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Menu-bar app that puts macOS and your apps on Soprano's theme: Apply changes them, Restore puts every setting Soprano Desktop changed back to your own value.
- Follows Soprano's theme and appearance (`theme: "soprano"`), or Folio with macOS (`"folio"`), or one pinned Soprano theme; light and dark mode switches are followed live.
- macOS: the closest system accent colour (Orange for Folio's sienna), the theme's text-selection colour per appearance, and a rendered Folio wallpaper on every screen (`system.*`).
- "Soprano Light" and "Soprano Dark" themes for Ghostty, VS Code, Cursor, bat (switched automatically) and Neovim, fzf, Chrome (one setup line, copied from the Apps menu) (`apps.*`).
- Folders and icons in the theme's accent: folder colour plus the Tinted icon & widget style (`system.folderColor`, `system.tintedIcons`).
- Folio icons on Home, Desktop, Documents and Downloads; folders with an icon of their own are left alone (`system.folderIcons`).
- A soft Folio alert sound (`system.alertSound`) and the Soprano screen saver with paper, clock and date, picked once in System Settings → Screen Saver (`system.screenSaver`).
- Calmer desktop: hidden desktop icons and no recent apps in the Dock, optionally an auto-hiding menu bar (`desktop.*`).
- Focus border: a 2-pt accent rule around the focused window, and a Folio strip over the app menus of the menu bar (`surfaces.*`, need Accessibility).
- `SopranoDesktop apply | restore | status | export <dir> | snapshot-surfaces` on the command line.
