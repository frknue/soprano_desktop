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
- `SopranoDesktop apply | restore | status | export <dir>` on the command line.
