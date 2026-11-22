# PinShell

**English** · [简体中文](./README.zh-CN.md)

[![Release](https://img.shields.io/github/v/tag/niyongsheng/PinShell?style=flat&label=Release&color=FD3532)](https://github.com/niyongsheng/PinShell/releases)
[![Platform](https://img.shields.io/badge/macOS-13%2B-black?style=flat&logo=apple&logoColor=white)](https://github.com/niyongsheng/PinShell#install)

![logo](./Resources/logo.svg)

**A real-time desktop window built for AI.** PinShell gives agents an always-on-top HTML interface on the user's screen for real-time communication, presentation, questions, and responses. The interface is built with HTML/CSS/JS; PinShell itself is only a lightweight native shell (NSPanel + WKWebView).

https://github.com/user-attachments/assets/61bfb0b1-b815-4895-a0f8-fcaf64ad3d0c

## Features

- Always-on-top HTML overlay across Spaces, with click-through, opacity, radius, and hot reload.
- MCP server and CLI share one control socket; pages can push events back to the agent.
- Control console (⌘K): templates, live preview, template editor, MCP info, About.
- Ten starter templates: badges, goals, LIVE dot, todo, system monitor, desktop pet, pomodoro, watermark, social rail, decision maker.
- Menu-bar only, no Dock icon; update check against GitHub Releases, with in-app installer download (SHA-256 verified) handed off to the system Installer.

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
| Check for Updates… | ⌘U | Check GitHub Releases; download and install updates |
| Quit PinShell | ⌘Q | Quit |

Click and type inside the overlay; hold **⌘** and drag to move it; resize from the bottom-right grip (min 80×40). Passthrough sends mouse events to the app below.

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

Tools cover window/content (`pinshell_html`, `pinshell_show`), page interaction (`pinshell_eval`, `pinshell_emit`, `pinshell_poll_events`, `pinshell_await_event`, `pinshell_state`), and templates. MCP prompts package common workflows; the server and CLI share `~/Library/Application Support/PinShell/control.sock`.

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
PinShell show ./panel.html --watch
PinShell eval 'document.querySelector("#status").textContent = "done"'
PinShell emit agent:message '{"text":"next step"}'
PinShell listen --json
PinShell mcp
```

Run `PinShell --help` for commands, options, and exit codes.

## HTML authoring

Local `file://` files only. Use `html, body { background: transparent; overflow: hidden; }`; relative CSS/JS/images in the same folder work. Hold **⌘** to drag the window; audio autoplay is allowed.

Window metadata (applied before load, re-applied on show/reload):

```html
<title>Subscriber Goal</title>
<meta name="description" content="Shows the subscriber goal and current progress">
<meta name="pinshell:size" content="280x64">
<meta name="pinshell:position" content="bottom-right">
<meta name="pinshell:passthrough" content="false">
<meta name="pinshell:opacity" content="0.85">
<meta name="pinshell:radius" content="18">
<meta name="pinshell:order" content="10">
```

Position accepts `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right`, or `x,y`. CLI flags override metadata for the session.

Reuse `Resources/templates/design-tokens.css` for the shared design system.

## License

[Apache License 2.0](LICENSE)
