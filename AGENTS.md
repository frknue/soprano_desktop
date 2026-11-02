# Soprano Desktop

Puts macOS and other apps on the Soprano family's theme (Folio Paper light, Folio Ink dark,
or whatever Soprano uses): macOS accent, highlight colour and wallpaper, plus generated
"Soprano Light"/"Soprano Dark" themes for Ghostty, VS Code, Cursor, bat, Neovim, fzf and
Chrome. Every change is restorable. Swift 6 + programmatic AppKit, SPM, macOS 14+,
menu-bar app (no Dock icon) that doubles as a CLI. No SIP changes.

Goal, state, next steps: `docs/STATUS.md`. Contract: `docs/ARCHITECTURE.md`. Left out and
the SIP-off todo: `docs/ROADMAP.md`. Keep all three current.

## Template

Soprano Mix (`~/git/private/soprano-mix`) and Soprano Tab (`~/git/private/soprano-tab`)
are the template for layout, scripts and conventions:

- `Sources/SopranoDesktopCore/` pure logic, Foundation only, everything `public`;
  `Sources/SopranoDesktop/System/` the only code that touches macOS (CFPreferences,
  NSWorkspace, processes, SkyLight's icon appearance), behind the protocols in
  `System/SystemContracts.swift` and the store protocols next to them.
- `Sources/SopranoDesktop/Surfaces/`: the Folio menu bar strip (Accessibility API);
  geometry in Core's `SurfaceGeometry.swift`.
- `Saver/`: the Soprano screen saver, built by `scripts/build-saver.sh` (called by
  `dev.sh`/`install.sh`) and packaged into `Contents/Resources/Soprano.saver`.
- Chrome, `Theme.swift` and `JSONCText` are vendored from Soprano
  (`~/git/private/soprano`) by `scripts/sync-soprano-chrome.sh`; never edit vendored files
  here. `scripts/render-app-icon.swift` is a local copy with the `desktop` glyph.
- Bundle id `com.soprano.desktop` (dev `com.soprano.desktop.dev`), settings
  `~/.config/soprano-desktop/settings.json` (`SOPRANO_DESKTOP_CONFIG` overrides), state
  `~/Library/Application Support/Soprano Desktop/state.json`.
- New theme generator: a caseless enum in Core returning `[GeneratedFile]`, syntax colours
  from `SyntaxPalette`, a `DesktopTarget` case, its path in `TargetPaths.themeRoot`, its
  theme selection (if any) in `DesktopEngine.registry`.

## Commands

Homebrew Swift on the Command Line Tools macOS 26 SDK:

```bash
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk
export DEVELOPER_DIR=/Library/Developer/CommandLineTools
export PATH="/opt/homebrew/opt/swift/bin:$PATH"
swift build
swift test
.build/debug/SopranoDesktop status            # read-only
.build/debug/SopranoDesktop export /tmp/sd    # every theme file, the .vsix, wallpapers; changes nothing else
.build/debug/SopranoDesktop snapshot-surfaces --out /tmp/sds   # Folio menu bar PNGs, Paper and Ink
./scripts/build-saver.sh debug                # .build/debug/Soprano.saver
./scripts/render-app-icon.sh [png]            # AppIcon.icns
./scripts/dev.sh --build-only                 # .build/debug/Soprano Desktop Dev.app
./scripts/install.sh                          # release build → /Applications/Soprano Desktop.app
```

`ld: warning: building for macOS-14.0 …` link warnings are expected.

## Verification

- Source changes: `swift build` and `swift test`. Tests never touch the real global
  defaults, wallpaper, app configs or installed extensions (fakes + a scratch home).
- Generators: `export` to /tmp, then validate with the real tool in a scratch location:
  `ghostty +validate-config --config-file=…`, `nvim --headless --clean --cmd 'set rtp^=…'`,
  bat with `BAT_CONFIG_DIR`/`BAT_CACHE_PATH`/`BAT_CONFIG_PATH` in /tmp,
  `code|cursor --user-data-dir /tmp/… --extensions-dir /tmp/… --install-extension`.
- Never run `apply`/`restore`, launch the app, or run `dev.sh` without `--build-only`
  unless Furkan asks: Apply changes his global macOS settings, wallpaper, folder colours,
  icons, Dock, desktop, Ghostty, VS Code, Cursor and bat configs.
- Surfaces: check the drawing through `snapshot-surfaces` (read the PNGs).
- After a verified change to the app or packaging, run `./scripts/install.sh` (authorized;
  it does not restart a running copy).

## Commits and changelog

- Push, open PRs or create tags only when Furkan asks.
- Short imperative subjects with `feat:` / `fix:` / `docs:` / `test:` / `chore:`.
- `CHANGELOG.md` (Keep a Changelog, `## [Unreleased]`) for user-visible changes.
