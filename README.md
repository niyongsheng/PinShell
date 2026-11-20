# PinShell

[![Release](https://img.shields.io/github/v/tag/niyongsheng/PinShell?style=flat&label=Release&color=FD3532)](https://github.com/niyongsheng/PinShell/releases)
[![Platform](https://img.shields.io/badge/macOS-13%2B-black?style=flat&logo=apple&logoColor=white)](https://github.com/niyongsheng/PinShell#install)

![logo](./Resources/logo.svg)

**A live desktop window for AI.** PinShell gives agents an always-on-top HTML surface on the user's screen — to communicate, present, ask, and respond in real time. UI lives in HTML/CSS/JS; PinShell is a thin native shell (NSPanel + WKWebView).

![PinShell preview](https://github.com/user-attachments/assets/01c4796f-1f02-4f2c-b099-61d2eeb9bc3a)

## Features

- Always-on-top HTML overlay across Spaces, with click-through, opacity, radius, and hot reload.
- MCP server and CLI share one control socket; pages can push events back to the agent.
- Control console (⌘K): templates, live preview, template editor, MCP info, About.
- Nine starter templates: badges, goals, LIVE dot, todo, system monitor, desktop pet, pomodoro, watermark, social rail.
- Menu-bar only, no Dock icon; update check against GitHub Releases.

## Install

Download `PinShell-<version>-mac-universal.pkg` from [Releases](https://github.com/niyongsheng/PinShell/releases/latest), or use the stable alias `https://github.com/niyongsheng/PinShell/releases/latest/download/PinShell.pkg`.

The `.pkg` installs to `/Applications` and clears quarantine. Builds are ad-hoc signed, not notarized; if macOS blocks it, use **System Settings → Privacy & Security → Open Anyway** or:

```bash
xattr -dr com.apple.quarantine ~/Downloads/PinShell-*.pkg
```

## Build

macOS 13+ with Xcode command-line tools.

```bash
make build      # release binary
make run        # build, assemble, launch
make install    # install to /Applications and launch
make pkg        # package build/PinShell.pkg (run make app first)
make universal  # arm64 + x86_64
```

## Usage

Launch PinShell, then use the menu-bar icon:

| Menu item | Shortcut | Action |
|---|---|---|
| Console | ⌘K | Open the console |
| Window Position ▸ | ⌘0 | Place the overlay in a screen corner (⌘0 = bottom-right) |
| Window State: Interactive / Passthrough | ⌘T | Toggle click-through |
| Check for Updates… | ⌘U | Check GitHub Releases |
| Quit PinShell | ⌘Q | Quit |

Click and type inside the overlay; hold **⌘** and drag to move it; resize from the bottom-right grip (min 80×40). Passthrough sends mouse events to the app below.

### Console

⌘K opens the control console — native sidebar + detail layout, Liquid Glass on macOS 26+.

- **Templates** (⌘1) — search, preview, apply. Files live in `~/Library/Application Support/PinShell/templates/`; edits refresh the sidebar automatically.
- **MCP** (⌘2) / **About** (⌘3) — stdio config, tools, control-channel path, version and links.
- **Template editor** (⌘E) — edit title, subtitle, size, position, passthrough, opacity, radius, order; changes are written back to the HTML `<meta>` tags.
- **Toolbar** — show/hide overlay, reload, edit, reveal in Finder, restore deleted built-ins.

Metadata comes from the HTML: `<title>`, `<meta name="description">`, and `<meta name="pinshell:*">`. Nine starter templates are seeded on first launch without overwriting existing copies; templates can be deleted, and removed built-ins restored from the toolbar.

## MCP

Open **Console → MCP** to copy the config, or add it manually:

```json
{
  "mcpServers": {
    "pinshell": {
      "command": "/Applications/PinShell.app/Contents/MacOS/PinShell",
      "args": ["mcp"]
    }
  }
}
```

Tools cover window/content (`pinshell_html`, `pinshell_show`, `pinshell_set`, `pinshell_status`, `pinshell_close`), page interaction (`pinshell_eval`, `pinshell_emit`, `pinshell_poll_events`), and templates (`pinshell_templates`, `pinshell_template_read`, `pinshell_template_write`, `pinshell_template_delete`, `pinshell_template_show`). Template writes are limited to flat `.html`/`.htm` files inside the templates folder, capped at 512 KB; the console refreshes and a shown template reloads in place.

MCP prompts (`create-panel`, `interactive-panel`, `live-monitor`, `edit-template`, `authoring-guide`) package common workflows into one step; Claude Code exposes them as `/pinshell:create-panel` and similar. The server and CLI share `~/Library/Application Support/PinShell/control.sock`.

Typical loop: `pinshell_html` → `pinshell_poll_events` → `pinshell_eval` / `pinshell_emit` / `pinshell_template_write`.

## CLI

If the app is not running, the command launches it and waits for the control socket.

```bash
PinShell show ./panel.html --watch --json
PinShell set --size 240x80 --position bottom-right
PinShell eval 'document.querySelector("#status").textContent = "done"'
PinShell emit agent:message '{"text":"下一步"}'
PinShell listen --json
PinShell mcp
PinShell close | quit
```

Options: `--size WxH`, `--position <anchor|x,y>`, `--passthrough on|off`, `--opacity 0..1`, `--radius px`, `--watch`, `--wait`, `--json`. Exit codes: `0` ok, `1` usage, `2` app unavailable, `3` command failed.

## HTML authoring

Local `file://` files only. Use `html, body { background: transparent; overflow: hidden; }`; relative CSS/JS/images in the same folder work. Hold **⌘** to drag the window; audio autoplay is allowed.

Window metadata (applied before load, re-applied on show/reload):

```html
<title>订阅进度</title>
<meta name="description" content="显示订阅目标与当前进度">
<meta name="pinshell:size" content="280x64">
<meta name="pinshell:position" content="bottom-right">
<meta name="pinshell:passthrough" content="false">
<meta name="pinshell:opacity" content="0.85">
<meta name="pinshell:radius" content="18">
<meta name="pinshell:order" content="10">
```

Position accepts `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right`, or `x,y`. CLI flags override metadata for the session.

JavaScript bridge:

```js
pinshell.setSize(320, 120)
pinshell.setPosition('bottom-right')     // or setPosition(x, y)
pinshell.setPassthrough(true)
pinshell.setOpacity(0.8)
pinshell.setRadius(18)
pinshell.emit('submit', { value: 1 })    // → CLI `listen` / MCP events
pinshell.on('agent:message', fn)         // ← CLI `emit` / MCP `pinshell_emit`
pinshell.log('debug message')

// Native fetch proxy: https only, 15s timeout, 2 MB cap, custom headers allowed
const data = await pinshell.fetch('https://api.example.com/stats', {
  headers: { Referer: 'https://example.com/' }
})
```

Reuse `Resources/templates/design-tokens.css` for the shared design system.

## License

[Apache License 2.0](LICENSE)
