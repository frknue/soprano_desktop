# Architecture

Soprano Desktop puts macOS and other apps on Soprano's theme without SIP changes: it
changes the macOS settings Apple exposes, and writes theme files plus one theme selection
per app. Everything it changes it can put back.

## Targets

`Sources/SopranoDesktopCore/` — Foundation only, everything `public`, fully unit-tested:

- `Palette.swift`: `RGB`, `TerminalPalette`, `Palette` (Soprano's `ThemeColors` +
  `TerminalColors` by name), `ThemePair` (light slot, dark slot), `ThemeNames`
  (`Soprano Light` / `Soprano Dark`), `GeneratedFile`.
- `ThemePairResolver`: settings.json `theme` + Soprano's `theme`/`appearance` → the two
  palette ids. `SopranoThemeFile` reads Soprano's two keys.
- `SyntaxPalette`: the code-highlighting roles every editor generator shares.
- Generators, one caseless enum each, pure `ThemePair → [GeneratedFile]`:
  `GhosttyTheme`, `NeovimColorscheme`, `VSCodeTheme` (VS Code and Cursor, .vsix members),
  `BatTheme`, `FzfColors`, `ChromeTheme`.
- `SystemColors`: `SystemAccent.nearest(to:)` (`AppleAccentColor`), `SystemHighlight`
  (`AppleHighlightColor`).
- `ConfigEdits`: `LineSetting` (Ghostty `key = value`, bat `--key=value`) and
  `JSONCSetting` (one top-level key through the vendored `JSONCText`), both editing in
  place so comments and every other line survive.
- `DesktopState` (state.json), `JSONValue`, settings model/resolver/template/editor.

`Sources/SopranoDesktop/` — AppKit:

- `Shell/`: `SettingsFile`/`SettingsCenter` (settings.json, live reload, as in Soprano Mix),
  `ThemeCenter` (pair + macOS appearance, watches Soprano's settings.json),
  `PaletteBridge` (vendored `AppTheme` → `Palette`).
- `System/`: the only code that touches macOS — `LiveGlobalPreferences` (CFPreferences on
  the global domain + the two CoreUI colour notifications), `LiveDesktopPictures`
  (NSWorkspace desktop images), `LiveProcessRunner`, `LiveAppLocator`, behind the protocols
  in `SystemContracts.swift`; `WallpaperRenderer`.
- `Targets/`: `TargetPaths` (every app's file locations), `ManagedSettings` (one class per
  kind of restorable value), `DesktopEngine`.
- `App/`: `main.swift` (CLI before NSApplication), `CLI`, `AppDelegate`,
  `SyncCoordinator`, `MenuBarController`, `LoginItem`.
- `Vendored/`: Soprano's `Theme.swift`, `Chrome.swift`, `NSColor+Hex.swift`,
  `AppVersion.swift` (and `JSONCText.swift` in Core), copied by
  `scripts/sync-soprano-chrome.sh`. Never edit them here.

## Sync

`DesktopEngine.run(_:settings:pair:appearance:waitForLock:)` (sync, apply, restore) is the
only path that changes anything. It holds an exclusive `flock` on `state.lock` for the whole
operation and re-reads state.json under it, so the CLI and the running app never
interleave (the CLI waits; the app backs off and retries after a second). An unreadable
state.json stops every change (it may hold originals) until it is fixed or removed.

1. While applied, each enabled installed app gets its theme files first (written only when
   the content changed). bat rebuilds its cache after a change and is only switched from
   0.25 on; VS Code and Cursor get a rebuilt .vsix installed with their own CLI when the
   content hash changed (`state.packages`) or the extension is missing from the editor's
   extensions folder. An app whose themes failed is not switched (or is switched back).
2. A registry lists every `ManagedSetting` with its theme value, or nil when it is not
   wanted (not applied, switched off, app not installed, its themes failed):
   - `system.accentColor`, `system.highlightColor` (global defaults, followed by the two
     CoreUI colour notifications);
   - `system.iconAppearance`: folder colour through SkyLight's
     `SLSIconAppearanceConfiguration` (`fetchCurrentIconAppearanceConfiguration`, setters,
     `save`; persisted as `AppleIconAppearance*` in the global domain). Values found by
     flipping System Settings → Appearance on macOS 27: theme RegularDark 2, TintedAutomatic
     6, TintedLight 7, TintedDark 8; tint Automatic 0, Orange 3, Other 10 + custom colour.
     The record is the whole configuration; the icon & widget style stays the user's own;
   - `system.folderIcon:<path>` for Home, Desktop, Documents, Downloads (`NSWorkspace.setIcon`,
     a folder with its own `Icon\r` is never registered);
   - `system.alertSound` (`com.apple.sound.beep.sound` → `~/Library/Sounds/Soprano.aiff`,
     synthesised by `AlertSound`, plus `com.apple.sound.settingsChangedNotification`);
   - `system.screenSaver`: copies the packaged `Soprano.saver` to `~/Library/Screen Savers`
     when its executable hash differs; removed on Restore if it was not there before;
   - `desktop.*`: `com.apple.WindowManager StandardHideDesktopIcons`, `com.apple.dock
     show-recents` (+ Darwin `com.apple.dock.prefchanged`), and for `hideMenuBar`
     `com.apple.controlcenter AutoHideMenuBarOption` 0, `_HIHideMenuBar`,
     `AppleMenuBarVisibleInFullscreen` (+ `AppleInterfaceMenuBarHidingChangedNotification`);
     keys and notification names read from the Desktop & Dock, Menu Bar and Sound settings
     extensions;
   - `system.wallpaper:<display uuid>:<space id>`, one per screen on its current Space
     (read through the private `CGSCopyManagedDisplaySpaces`; screens whose Space is
     unknown, that show a fullscreen app, or whose picture macOS does not report are left
     alone). macOS keeps one picture per display and Space, so each original (with its
     scaling and fill colour) is read on, and only written back to, its own Space;
     originals of Spaces not visible at Restore stay in `originals` and are put back the
     next time the app sees that Space. A display attached while applied gets its own
     original before the first write;
   - `<app>:<file path>` for Soprano's keys in one config file: Ghostty `theme`
     (`light:soprano-light,dark:soprano-dark`, in the last of Ghostty's config files that
     exists), VS Code / Cursor `window.autoDetectColorScheme` and the preferred light/dark
     themes, bat `--theme=auto:system` and `--theme-light/-dark`. The path is part of the
     id, and the record carries path, format, the whole original text and each key's
     value, so a file another process or environment applied is restored from its record.
3. Wanted: the record is captured and saved the first time (if it cannot be saved,
   nothing is written), then the theme value is written if it differs. For files the
   written text is kept in `state.written`.
4. Not wanted but recorded: put back and the record dropped. A config file that is
   exactly what Soprano Desktop last wrote gets its original text back byte-for-byte (or
   is removed if it did not exist); one the user edited since gets only Soprano's keys
   reverted. Whole-file restore is dropped for good (`written` cleared) the moment a
   re-apply finds the file differing from what was last written, so an edit followed by a
   re-apply is never rolled back. Restore is `active = false` + sync; turning one switch
   off restores just that setting.

Theme files and the installed extension stay after Restore: they are inert once no
setting selects them, and lines the user added by hand (Neovim, fzf) keep working.

Values depend on the appearance only where macOS has one value for both modes: the
highlight colour and the wallpaper are rewritten on every light/dark switch. Apps that
switch by themselves (Ghostty, VS Code, Cursor, bat, Neovim via `background`) get both
themes once.

## Triggers

`SyncCoordinator` runs one operation at a time on the main actor: settings.json changes,
Soprano's settings.json changes, the macOS appearance, screen changes, Space changes (macOS
sets a desktop picture per Space; each Space gets the wallpaper when first visited) and
the CLI's `com.soprano.desktop.state-changed` distributed notification. A pending
Apply/Restore is never replaced by a plain sync.

## Surfaces

Drawn by Soprano Desktop itself while applied and switched on (`AppDelegate.updateSurfaces`);
it needs Accessibility and waits for it (`AccessibilityTrustWatcher` polls every 2 s).

- `FolioMenuBarController`: a Folio strip over the app-menu part of each visible menu bar.
  Titles come from the frontmost app's `AXMenuBar` and are drawn at the native items' x
  positions, so a click (`AXPress` on the real item) opens the native menu in place. The
  strip ends left of the leftmost status item, found through Quartz status-level windows,
  else every app's `AXExtrasMenuBar`, else 55 % of the width. Off while `hideMenuBar` is on.
- Geometry (AX top-left ↔ AppKit bottom-left, strip width, title placement) is pure, in
  Core's `SurfaceGeometry.swift`; `snapshot-surfaces` renders the strip offscreen.

A focus border around the focused window was built and removed (2026-11-02): it did not
look right on macOS's window shapes.

## Files

- `~/.config/soprano-desktop/settings.json` (`SOPRANO_DESKTOP_CONFIG` overrides)
- `~/Library/Application Support/Soprano Desktop/state.json`, `Wallpapers/`,
  `Extensions/<vscode|cursor>/soprano-theme.vsix`
- `~/.config/ghostty/themes/soprano-{light,dark}`, `~/.local/share/nvim/site/colors/soprano.lua`,
  `~/.config/bat/themes/Soprano {Light,Dark}.tmTheme`,
  `~/.config/soprano-desktop/shell/fzf.sh`, `~/.config/soprano-desktop/chrome/soprano-{light,dark}/`
