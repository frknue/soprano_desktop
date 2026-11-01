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

`DesktopEngine.sync(settings:pair:appearance:)` is the only path that changes anything.

1. A registry lists every `ManagedSetting` with its theme value, or nil when it is not
   wanted (not applied, switched off, app not installed):
   - `system.accentColor`, `system.highlightColor` (global defaults);
   - `system.wallpaper:<display uuid>:<space id>`, one per screen on its current Space
     (read through the private `CGSCopyManagedDisplaySpaces`; screens whose Space is
     unknown or shows a fullscreen app are left alone). macOS keeps one picture per display
     and Space, so each original is read on, and only written back to, its own Space;
     originals of Spaces not visible at Restore stay in `originals` and are put back the
     next time the app sees that Space. A display attached while applied gets its own
     original before the first write;
   - `ghostty:theme` (`light:soprano-light,dark:soprano-dark`);
   - `vscode:` / `cursor:` `window.autoDetectColorScheme`,
     `workbench.preferredLightColorTheme`, `workbench.preferredDarkColorTheme`;
   - `bat:theme` (`auto:system`), `bat:theme-light`, `bat:theme-dark`.
2. Wanted: the current value is recorded in `state.originals[id]` the first time (saved
   before the write), then the theme value is written if it differs.
3. Not wanted but recorded: the original is written back and the record dropped. Restore
   is `active = false` + sync; turning one switch off restores just that setting.
4. While applied, each enabled installed app gets its theme files (written only when the
   content changed). bat rebuilds its cache after a change; VS Code and Cursor get a
   rebuilt .vsix installed with their own CLI when the content hash changed
   (`state.packages`).

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

## Files

- `~/.config/soprano-desktop/settings.json` (`SOPRANO_DESKTOP_CONFIG` overrides)
- `~/Library/Application Support/Soprano Desktop/state.json`, `Wallpapers/`,
  `Extensions/<vscode|cursor>/soprano-theme.vsix`
- `~/.config/ghostty/themes/soprano-{light,dark}`, `~/.local/share/nvim/site/colors/soprano.lua`,
  `~/.config/bat/themes/Soprano {Light,Dark}.tmTheme`,
  `~/.config/soprano-desktop/shell/fzf.sh`, `~/.config/soprano-desktop/chrome/soprano-{light,dark}/`
