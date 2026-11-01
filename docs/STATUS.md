# Status

## Goal

Soprano Desktop: make macOS and the apps around Soprano look like the Soprano family
(Folio Paper / Folio Ink) without disabling SIP. Stage 1 = macOS settings Apple exposes +
generated themes for other apps, all restorable. Stage 2 (own surfaces) and the SIP-off
experiment: `docs/ROADMAP.md`.

## Done (stage 1, 2026-11-01)

- Menu-bar app + CLI (`apply`, `restore`, `status`, `export <dir>`), settings.json with live
  reload, Soprano theme following, login item, app icon (`desktop` glyph).
- macOS: accent (nearest fixed accent; Folio → Orange), highlight colour per appearance,
  rendered Folio wallpaper per screen and appearance, owned per display and Space (each
  Space's original restored on that Space; hot-plugged displays get their own original).
- Apps: Ghostty, VS Code, Cursor, bat (themes + selection switched), Neovim, fzf, Chrome
  (themes; one setup line each).
- Restore: every changed value goes back to the user's own (originals recorded once, saved
  before the first write).

Verified (2026-11-01): `swift build`, `swift test` green; `SopranoDesktop export` output
checked with the real tools — `ghostty +validate-config` on both themes, Neovim headless
(`colorscheme soprano` gives `#f6f2ea` / `#1d1b18` on background switch), bat cache build
in a scratch dir with `--theme=auto:system` picking Soprano Dark, the .vsix installed into
throwaway VS Code and Cursor extension dirs; wallpapers viewed. `status` on this Mac reads
the Odyssey G91F's display UUID and current Space (Space 1) through
`CGSCopyManagedDisplaySpaces` (read-only).

Not yet run on the real system: Apply has not been pressed on this Mac, so the live
accent/highlight change (CoreUI notifications), `NSWorkspace` wallpaper switching and the
real VS Code/Cursor install are unobserved.

## Next

1. Furkan: launch Soprano Desktop, Apply; check accent, selection colour and wallpaper in
   light and dark mode; Reload Window in VS Code/Cursor; reload Ghostty config
   (⌘⇧,); then Restore and check everything is back (Gruvbox Dark in Ghostty, Rider theme
   in VS Code/Cursor, graphite accent, blue highlight, previous wallpaper).
2. Add the Neovim and fzf lines (Apps menu copies them).
3. Stage 2 planning (`docs/ROADMAP.md`).

## Open decisions

- Dark-mode highlight colour: Ink's terminal selection (`#483325`, dark sienna) vs the
  neutral Folio selection fill. Currently `#483325`.
- Whether Restore should also delete the theme files and uninstall the editor extension
  (currently kept, inert).
