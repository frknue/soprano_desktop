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
macOS sets a wallpaper per Space; each Space gets it when you first visit it while Soprano
Desktop runs. Keep it running (Launch at Login) so light/dark switches are followed.

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
