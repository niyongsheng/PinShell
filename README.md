# PinShell

A lightweight macOS overlay shell. Pin any local HTML file as a global, always-on-top floating window with click-through support — built for screen-recording overlays (OBS, Cap, QuickTime) and live-streaming badges.

![PinShell preview](screenshots/preview.png)

All UI, carousels, and animations live in your HTML/CSS/JS. PinShell is a thin native wrapper (NSPanel + WKWebView) — no built-in business logic.

## Features

- Always-on-top overlay across all Spaces
- Click-through mode: mouse events pass to the window below
- Load any local HTML file via menu bar (⌘O) or CLI
- Remembers window position, size, last file, and click-through state
- No Dock icon — lives in the menu bar

## Quick Start

Requires macOS 13+ and Xcode command-line tools.

```bash
make build      # compile release binary
make run        # build, assemble, and launch
make install    # install to /Applications and launch
make universal  # build for both arm64 and x86_64
```

## Usage

Launch PinShell, then use the menu bar icon:

| Menu item | Shortcut | Action |
|---|---|---|
| Templates… | ⌘L | Open the built-in template gallery |
| Choose HTML File… | ⌘O | Display a local HTML file |
| Click-Through: On/Off | ⌘T | Toggle click-through (off = draggable) |
| Reset Window Position | ⌘0 | Move window back to bottom-right |
| Reload HTML | ⌘R | Reload the current file |
| Quit PinShell | ⌘Q | Quit |

### Built-in templates

The gallery (⌘L) ships four ready-to-use overlays:

![Badge Carousel](screenshots/template-badge-carousel.png) ![Social Capsule Rail](screenshots/template-social-rail.png) ![Watermark Badge](screenshots/template-watermark.png)

- **Badge Carousel** — rotating social badges (X / WeChat / Bilibili), 5s carousel
- **LIVE Status Dot** — pulsing recording-status pill
- **Social Capsule Rail** — a static row of account capsules
- **Watermark Badge** — low-contrast clock, date, and contact info

On first launch, templates are copied to `~/Library/Application Support/PinShell/templates/` — that's the editable copy. Edit the HTML/CSS freely, then hit Reload HTML (⌘R) — no rebuild needed. Add your own by dropping in an HTML file plus a `manifest.json` entry (id / name / description / file / size); delete the folder to restore the built-ins.

Drag the window from anywhere to move it; resize from the bottom-right grip (min 80×40).

### CLI

```bash
PinShell ./my-overlay.html
PinShell --help
# or
open -a PinShell examples/badge-carousel.html
```

If PinShell is already running, the file loads immediately in the existing window; otherwise the app launches and loads it.

## HTML Authoring

- Local `file://` files only — no remote URLs
- `html, body { background: transparent; overflow: hidden; }` — the window is transparent
- Relative css/js/images in the same folder work out of the box
- In click-through mode all mouse events pass through — don't rely on HTML clicks
- Reuse `examples/design-tokens.css` for the design system

## Structure

```
Sources/PinShell/   AppKit source (menu bar, overlay panel, template gallery, WebView, CLI)
Resources/          Info.plist, app icon, built-in templates, localizations
scripts/            icon generator (logo.svg → .icns)
examples/           design tokens + carousel badge demo
```

Regenerate the app icon after editing `Resources/logo.svg`: `make icon` (background: `make icon ICON_BG=272729`).

## License

[Apache License 2.0](LICENSE)
