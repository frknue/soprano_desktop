# Roadmap

What Soprano Desktop deliberately leaves out of stage 1, in the order it would come.

## Stage 2: surfaces Soprano Desktop draws itself

Needs Accessibility permission; no SIP change.

- Folio menu bar replacing the auto-hidden system menu bar (app menus, status items,
  clock), drawn with `Chrome.swift`.
- Focus border: a 2-pt sienna rule around the focused window (Folio's focus mark), like
  JankyBorders. Window frames from the Accessibility API; may need private CGS/SkyLight
  calls for ordering, which can break on macOS updates.
- Optional launcher replacing the Dock (or hand the job to Soprano Cast).

## More apps

- Zed (`~/.config/zed/themes/soprano.json`, `theme: { mode: "system", light, dark }`): left
  out because Zed is not installed on Furkan's Mac.
- lazygit (`gui.theme` in its config.yml), Obsidian (per-vault CSS snippet), Slack (sidebar
  colour string), Xcode (`.xccolortheme`), `LS_COLORS`/eza.
- Pointer colours (Accessibility → Display → Pointer): `com.apple.universalaccess` is
  TCC-protected; needs a check whether it is writable without Full Disk Access.
- Folio alert sound in `~/Library/Sounds`, a Folio screen saver.

## Later: SIP-off experiment (todo, not started)

Goal: find out whether native AppKit/SwiftUI apps (Finder, Notes, Mail, System Settings)
and the Dock can be recoloured to Folio by loading a library into them. Nothing here is
verified on macOS 27; treat it as an experiment.

Rules:

- Only on a spare or test Mac, never on Furkan's work Mac (Valkental admin logins, `gh`
  org access, Shopify CLI, SSH keys to abtool and shop-monitor).
- Opt-in module, off by default; Soprano Desktop never changes SIP itself.

Steps (Apple Silicon, macOS 13+, from yabai's guide, updated 2026-04-18:
<https://github.com/asmvik/yabai/wiki/Disabling-System-Integrity-Protection>):

1. Shut down; hold the power button until "Loading startup options"; Options → Continue.
2. Utilities → Terminal: `csrutil enable --without fs --without debug --without nvram`.
3. Reboot; `sudo nvram boot-args=-arm64e_preview_abi`; reboot again.
4. Undo: same Recovery path, `csrutil enable`, and `sudo nvram -d boot-args`.

What yabai's scripting addition proves with these steps: code injected into Dock.app can
move/create Spaces, remove shadows, change window transparency, layers and stickiness. It
does not prove recolouring of anything.

Open questions the prototype must answer:

1. Can a library loaded into one native app (Notes) override `NSColor` system colours
   (`windowBackgroundColor`, `controlAccentColor`, `selectedContentBackgroundColor`, …) so
   the app draws Folio colours? Do SwiftUI views follow?
2. Which protections must be off for that on macOS 27: are the yabai steps enough, or does
   library validation in hardened / platform apps need more (e.g. AMFI)? Measure, do not
   assume.
3. What does Liquid Glass (materials, the menu bar, Control Center) take its colours from,
   and can any of it be reached?
4. What breaks: iPhone/iPad apps, Apple Pay, apps that check system integrity, point
   updates.

Only if 1 works with an acceptable answer to 2 and 4 is a full module worth building.
