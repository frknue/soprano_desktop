# Soprano Desktop

Puts macOS and the apps around Soprano on Soprano's theme: Folio Paper in light mode,
Folio Ink in dark mode (or whichever theme Soprano uses). A menu-bar app; nothing changes
until you choose **Apply**, and **Restore macOS** puts every setting it changed back to
your own value.

## What it changes

| | What | How it follows light/dark |
|---|---|---|
| macOS accent | The closest system accent (Orange for Folio's sienna) | – |
| Text selection | The theme's selection colour | rewritten on each switch |
| Wallpaper | A rendered Folio paper with one sienna pencil tick, per screen | rewritten on each switch |
| Folder colour | Folder colour in a muted tint of the theme's accent (a warm grey in Folio); app icons keep your icon & widget style | tint rewritten on each switch |
| Folder icons | Folio icons on Home, Desktop, Documents, Downloads (folders with their own icon are left alone) | – |
| Alert sound | `~/Library/Sounds/Soprano.aiff`, a soft pencil tap | – |
| Screen saver | `~/Library/Screen Savers/Soprano.saver`: paper, clock, date (pick it once in System Settings → Screen Saver) | the saver |
| Desktop | Desktop icons hidden, no recent apps in the Dock; optional auto-hiding menu bar | – |
| Folio menu bar | Folio strip over the app menus of the menu bar; status items stay native (needs Accessibility) | live |
| Ghostty | `themes/soprano-light`, `soprano-dark`; `theme = light:soprano-light,dark:soprano-dark` | Ghostty |
| VS Code, Cursor | "Soprano" extension with Soprano Light/Dark; `window.autoDetectColorScheme` + preferred themes | the editor |
| bat | `Soprano Light/Dark.tmTheme`; `--theme=auto:system` + light/dark themes | bat |
| Neovim | `colors/soprano.lua` (both palettes, follows `background`) | Neovim |
| fzf | `~/.config/soprano-desktop/shell/fzf.sh` | at shell start |
| Chrome | unpacked themes in `~/.config/soprano-desktop/chrome/` | – (pick one) |

Neovim, fzf and Chrome need one step from you; the menu's **Apps** submenu copies it:

```lua
vim.cmd.colorscheme("soprano")                       -- init.lua
```
```sh
source ~/.config/soprano-desktop/shell/fzf.sh        # ~/.zshrc
```

Chrome: `chrome://extensions` → Developer mode → Load unpacked →
`~/.config/soprano-desktop/chrome/soprano-dark` (or `soprano-light`).

After Apply, use Reload Window in VS Code/Cursor and reload Ghostty's config (⌘⇧,).
macOS keeps a wallpaper per screen and Space; each Space gets the Folio one when you first
visit it while Soprano Desktop runs, and Restore puts each Space's own wallpaper back —
Spaces you are not on at that moment get theirs back when you next visit them (keep the
app running for that). Keep it running (Launch at Login) so light/dark switches are
followed too.

What macOS does not allow without turning off System Integrity Protection (other apps'
window chrome, the Dock, the system font) is out of scope; see `docs/ROADMAP.md`.

## Settings

`~/.config/soprano-desktop/settings.json`, created on first launch with every key
documented: `theme` (`soprano`, `folio` or a Soprano theme id), `system.*`, `apps.*`,
`app.startAtLogin`. Edits apply immediately.

## Command line

```
SopranoDesktop apply | restore | status | export <dir> | version
```

The binary is `/Applications/Soprano Desktop.app/Contents/MacOS/SopranoDesktop`.

## Build

See `AGENTS.md` → Commands. `./scripts/install.sh` installs to `/Applications`.
