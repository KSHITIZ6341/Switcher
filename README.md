# Switcher for macOS

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Switcher is a native macOS app that turns regular app windows into a dedicated sidebar so your communication and work context stays visible while you focus.

Current version: `v1.1.0`

## Why this helps productivity

Most productivity loss comes from context switching:

- You jump between coding/design/docs and Slack/Email/Teams.
- Important messages disappear behind full-size windows.
- You lose time reopening, resizing, and rearranging apps.

Switcher solves this by keeping key windows attached to a screen edge in a stable layout. You keep a persistent "communication lane" while continuing deep work in the rest of the screen.

## How this helps you stay on top of communication and work

- Keep chat, ticket queue, inbox, or notes visible while working.
- Reduce alt-tab friction and window hunting.
- Maintain a repeatable workspace layout across sessions.
- React faster to updates without breaking flow.
- Keep up to three apps stacked on one side for triage workflows.

## Current capabilities

- Native macOS app (`SwiftUI + AppKit + Accessibility APIs`)
- Menu bar utility workflow
- Pick target from installed apps (`/Applications`, `~/Applications`) or running windows
- Pin up to **3** apps stacked on one side
- Resizable sidebar width with per-app persistence
- Pinned-app manager with focus, reorder, unpin, move-left/right, and show/hide controls
- Choose left/right edge and display
- Auto-launch selected app if not already running
- Smooth push-in / pull-out sidebar motion
- Edge toggle handle on the sidebar boundary
- Optional automatic open/close by edge hover
- Optional auto-pin by dragging a window to the screen edge and holding
- Per-app persistence for edge, display, and width defaults
- Launch at login toggle
- Global hotkey: `Control + Option + S` opens the pin flow when idle and toggles the active sidebar when pinned
- Blue floating button mode (for selected apps):
  - `Click` to pin/unpin that window
  - `Click and hold` to choose `Place on Left` or `Place on Right`

## Requirements

- macOS 14+
- Swift 6.2+
- Accessibility permission enabled for Switcher

## Build and run

```bash
git clone https://github.com/KSHITIZ6341/Switcher.git
cd Switcher
swift test
swift run Switcher
```

Alternative launch after build:

```bash
swift build
open "$(swift build --show-bin-path)/Switcher"
```

## First-time setup

1. Launch Switcher.
2. Grant Accessibility permission when prompted.
3. Open Switcher and choose an installed app or running window.
4. Pin an app/window to the preferred edge/display.

## Recommended workflow for communication-heavy work

1. Pin communication tools (Slack/Teams/Email) to the right side.
2. Use center/main screen area for focused tasks (coding, writing, design).
3. Keep alerts visible without switching context every few minutes.
4. Unpin/re-pin quickly as priorities change.
5. Use long-press on blue button when you want to move the sidebar side.

## Notes and limitations

- True system-level always-on-top for arbitrary third-party windows is not reliably available via public APIs.
- Switcher uses best-effort geometry enforcement and bring-forward behavior.
- If a pinned window closes, that window is removed from the sidebar session; the Switcher app itself stays running.
- Launch-at-login uses `SMAppService.mainApp`; unsigned dev binaries may have login-item limitations until packaged/notarized.

## Open source

Switcher is open source under the [MIT License](LICENSE).

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request, follow the [Code of Conduct](CODE_OF_CONDUCT.md), and report security issues through the process in [SECURITY.md](SECURITY.md).
