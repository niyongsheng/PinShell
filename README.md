# PinShell

**English** · [简体中文](./README.zh-CN.md)

[![Release](https://img.shields.io/github/v/tag/niyongsheng/PinShell?style=flat&label=Release&color=FD3532)](https://github.com/niyongsheng/PinShell/releases)
[![Platform](https://img.shields.io/badge/macOS-13%2B-black?style=flat&logo=apple&logoColor=white)](https://github.com/niyongsheng/PinShell#install)

![logo](./Resources/logo.svg)

**A real-time desktop window built for AI.** PinShell gives agents an always-on-top HTML interface on the user's screen for real-time communication, presentation, questions, and responses. The interface is built with HTML/CSS/JS; PinShell itself is only a lightweight native shell (NSPanel + WKWebView).

![PinShell preview](https://github.com/user-attachments/assets/61bfb0b1-b815-4895-a0f8-fcaf64ad3d0c)

## Features

- Always-on-top HTML overlay across Spaces, with click-through, opacity, radius, and hot reload.
- MCP server and CLI share one control socket; pages can push events back to the agent.
- Control console (⌘K): templates, live preview, template editor, MCP info, About.
- Ten starter templates: badges, goals, LIVE dot, todo, system monitor, desktop pet, pomodoro, watermark, social rail, decision maker.
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
| Show Window | ⌘H | Toggle the overlay (checked = shown) |
| Check for Updates… | ⌘U | Check GitHub Releases |
| Quit PinShell | ⌘Q | Quit |

Click and type inside the overlay; hold **⌘** and drag to move it; resize from the bottom-right grip (min 80×40). Passthrough sends mouse events to the app below.

### Console

⌘K opens the control console — native sidebar + detail layout, Liquid Glass on macOS 26+.

- **Templates** (⌘1) — search, preview, apply. Files live in `~/Library/Application Support/PinShell/templates/`; edits refresh the sidebar automatically.
- **MCP** (⌘2) / **About** (⌘3) — stdio config, tools, control-channel path, version and links.
- **Template editor** (⌘E) — edit title, subtitle, size, position, passthrough, opacity, radius, order; changes are written back to the template's i18n block (or legacy `<meta>` tags). Title and subtitle are edited in the template's current language, so other translations are preserved.
- **Toolbar** — show/hide overlay, reload, edit, reveal in Finder, restore deleted built-ins.

Metadata comes from the HTML: `<title>`, `<meta name="description">`, `<meta name="pinshell:*">`, and an optional JSON i18n block. Ten starter templates are seeded on first launch without overwriting existing copies; templates can be deleted, and removed built-ins restored from the toolbar. To pick up an updated built-in, delete its file and relaunch to reseed it from the app bundle.

### Template localization

Built-in templates declare one JSON block in `<head>`:

```html
<script type="application/json" id="pinshell:i18n">
{
  "default": "zh-Hans",
  "fallback": "en",
  "languages": {
    "zh-Hans": { "meta": { "name": "待办事项", "description": "…" } },
    "en": {
      "meta": { "name": "Todo List", "description": "…" },
      "ui": { "title": "Todo List", "clearDone": "Clear completed" }
    }
  }
}
</script>
```

- `meta` drives the console list; `ui` drives the page through `pinshell-i18n.js`.
- The default language's UI copy stays inline in the HTML. Non-default `ui` is merged over `fallback` (English), so missing keys fall back to English, then to the inline copy.
- Language order: app-selected template language → system preferences → fallback. The app injects `window.pinshell.languages` / `templateLanguage`; append `?lang=en` to a file URL to preview a language in a browser.
- Static copy: `data-i18n="key"` and `data-i18n-placeholder|title|aria-label|data-text`. Dynamic copy: `PS.t('key', 'default', { name: value })`; arrays: `PS.list('key', [ … ])`; raw data: `PS.get('key', fallback)`.
- Use `PS.locale` with `Intl` / `toLocaleString`; do not hardcode `en-US` / `zh-CN`.
- Legacy `window.PINSHELL_STRINGS` and `<meta name="pinshell:title" lang="en">` templates still work, but new templates should use the block.

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

MCP prompts (`create-panel`, `interactive-panel`, `live-monitor`, `pet-companion`, `edit-template`, `authoring-guide`) package common workflows into one step; Claude Code exposes them as `/pinshell:create-panel` and similar. The server and CLI share `~/Library/Application Support/PinShell/control.sock`.

Typical loop: `pinshell_html` → `pinshell_poll_events` → `pinshell_eval` / `pinshell_emit` / `pinshell_template_write`.

### Desktop pet

The bundled `desktop-pet.html` is a two-way example: it keeps itself alive with moods, idle behaviors, petting, and sleep, and an agent can drive it over the event channel.

```bash
PinShell emit pet:hello '{"name":"Claude"}'
PinShell emit pet:mood '{"mood":"thinking"}'
PinShell emit pet:task '{"label":"Running tests","progress":0.4,"status":"running"}'
PinShell emit pet:say '{"text":"Two cases left","mood":"working"}'
PinShell emit pet:celebrate '{"text":"All green 🎉"}'
```

Agent events: `pet:hello`, `pet:say`, `pet:mood`, `pet:task`, `pet:animate`, `pet:celebrate`, `pet:alert`, `pet:reply`, `pet:reset`. Page events: `pet:ready`, `pet:tap`, `pet:pet`, `pet:ask`, `pet:sleep`, `pet:wake`. The pet's chat box emits `pet:ask { requestId, text }`; answer within ~10 seconds with `pet:reply { requestId, text }`, otherwise it falls back to a local line. The `pet-companion` MCP prompt wires the whole loop up.

## CLI

If the app is not running, the command launches it and waits for the control socket.

```bash
PinShell show ./panel.html --watch --json
PinShell set --size 240x80 --position bottom-right
PinShell eval 'document.querySelector("#status").textContent = "done"'
PinShell emit agent:message '{"text":"next step"}'
PinShell listen --json
PinShell mcp
PinShell close | quit
```

Options: `--size WxH`, `--position <anchor|x,y>`, `--passthrough on|off`, `--opacity 0..1`, `--radius px`, `--watch`, `--wait`, `--json`. Exit codes: `0` ok, `1` usage, `2` app unavailable, `3` command failed.

## HTML authoring

Local `file://` files only. Use `html, body { background: transparent; overflow: hidden; }`; relative CSS/JS/images in the same folder work. Hold **⌘** to drag the window; audio autoplay is allowed.

Window metadata (applied before load, re-applied on show/reload):

```html
<title>Subscriber Goal</title>
<meta name="description" content="Shows the subscriber goal and current progress">
<!-- Add the <script id="pinshell:i18n"> block here for multiple languages; see "Template localization". -->
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
