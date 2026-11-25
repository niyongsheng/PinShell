---
name: pinshell
description: Show and update live HTML panels on the user's macOS desktop with the PinShell command line. Use when a visual, interactive, always-on-top, or live-updating response would be clearer than chat — progress, status, comparisons, choices, confirmations, alerts, or dashboards — and PinShell MCP tools are unavailable.
---

# PinShell CLI

PinShell is a macOS menu-bar app that hosts local HTML in a transparent, always-on-top panel. The `PinShell` command talks to the running app over a local Unix socket. If the app is not running, the command launches it and waits for the socket.

Use this skill in shell-capable agents. If the session already exposes `pinshell_*` MCP tools, prefer those: they add event waiting, shared state, and template management. The CLI shares the same control channel and is enough to show a panel, update it, and exchange events.

## Setup check

```bash
command -v PinShell
```

If nothing is printed, use the full path:

```bash
/Applications/PinShell.app/Contents/MacOS/PinShell --help
```

Or ask the user to open **PinShell Console (⌃⌥C) → CLI** and install the command-line tool. Every command auto-starts the app; no server or MCP configuration is required.

Exit codes: `0` success, `1` usage, `2` app unavailable, `3` command failed. Most commands accept `--json` for machine-readable output.

## Core workflow

1. Write a complete HTML file. A temporary file is fine, for example `/tmp/pinshell-panel.html`.
2. Show it and wait until the page has loaded:

   ```bash
   PinShell show /tmp/pinshell-panel.html --wait --json
   ```

3. Read page events. `listen` is a long-running stream, one JSON object per line:

   ```bash
   PinShell listen --json
   ```

4. Update the panel without reloading:

   ```bash
   PinShell eval 'document.querySelector("#detail").textContent = "3 of 5 steps"'
   PinShell emit agent:message '{"text":"Step 3 is running"}'
   ```

5. Close the panel when the user no longer needs it:

   ```bash
   PinShell close
   ```

The app shows one panel at a time. A new `show` replaces the current file.

## HTML contract

The window itself is transparent. Draw your own background, padding, and rounded corners.

```html
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Build status</title>
  <meta name="description" content="Current build progress">
  <meta name="pinshell:size" content="320x120">
  <meta name="pinshell:position" content="bottom-right">
  <style>
    html, body {
      margin: 0;
      width: 100%;
      height: 100%;
      background: transparent;
      overflow: hidden;
    }
    body {
      font: 13px -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
      color: #fff;
      user-select: none;
    }
    .card {
      box-sizing: border-box;
      width: 100%;
      height: 100%;
      padding: 14px 16px;
      border-radius: 16px;
      background: rgba(28, 28, 30, 0.92);
    }
    .bar {
      height: 5px;
      margin-top: 10px;
      border-radius: 3px;
      background: rgba(255, 255, 255, 0.16);
      overflow: hidden;
    }
    .bar > i {
      display: block;
      height: 100%;
      width: 40%;
      background: #0a84ff;
      transition: width 0.25s ease;
    }
    button {
      margin-top: 10px;
      font: inherit;
      color: #fff;
      background: rgba(255, 255, 255, 0.14);
      border: 0;
      border-radius: 7px;
      padding: 5px 10px;
      cursor: pointer;
    }
    button:focus-visible { outline: 2px solid #0a84ff; outline-offset: 2px; }
    button:disabled { opacity: 0.45; cursor: default; }
  </style>
</head>
<body>
  <div class="card">
    <strong id="title">Building…</strong>
    <div id="detail">2 of 5 steps</div>
    <div class="bar"><i id="fill"></i></div>
    <button id="cancel">Cancel</button>
  </div>
  <script>
    const cancel = document.getElementById("cancel");

    cancel.addEventListener("click", () => {
      cancel.disabled = true;
      // Shorthand for window.pinshell.emit("ui:submit", data).
      window.pinshell.submit({ action: "cancel" });
    });

    window.pinshell.on("agent:message", (data) => {
      if (data && data.text) {
        document.getElementById("detail").textContent = data.text;
      }
    });

    window.pinshell.ready({ at: Date.now() });
  </script>
</body>
</html>
```

Relative CSS, JS, and image files next to the HTML file work. Inline them when the panel should be self-contained. Keep the declared window small and avoid layout shift.

### Window metadata

Put these in `<head>`:

```html
<meta name="pinshell:size" content="320x120">
<meta name="pinshell:position" content="bottom-right">
<meta name="pinshell:passthrough" content="false">
<meta name="pinshell:opacity" content="0.92">
<meta name="pinshell:radius" content="18">
```

`position` accepts `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right`, or `x,y`. CLI flags on `show` override metadata for that session. Use `--passthrough on` only for purely decorative panels.

### Page bridge

`window.pinshell` provides:

- `emit(name, data)` — send an event to the agent. Prefer namespaced names (`ui:*`, `state:*`, or a template namespace).
- `on(name, callback)` — receive events sent by the agent with `PinShell emit`.
- `ready(data)`, `input(data)`, `submit(data)`, `cancel(data)` — shorthand for `ui:ready`, `ui:input`, `ui:submit`, `ui:cancel`.
- `setState(state)`, `patchState(patch)`, `getState()` — shared panel state. `patchState` applies an RFC 7386 merge patch.
- `setSize(w, h)`, `setPosition(...)`, `setPassthrough(bool)`, `setOpacity(0...1)`, `setRadius(px)` — update the window.
- `log(...)` — forward text to the agent as a log event.
- `fetch(url, options)` — HTTPS-only GET, 15 s timeout, 2 MB cap.

Page-to-agent events carry `{ event, seq, ts, session, type, name, data }`. `type` is the prefix before the first colon (`ui`, `state`, `lifecycle`, `log`, or a template namespace). Events without a prefix are treated as `ui`.

## Commands

| Command | Purpose |
|---|---|
| `PinShell show <file> [options]` | Show a local HTML file. Options: `--size WxH`, `--position`, `--passthrough on/off`, `--opacity 0..1`, `--radius px`, `--watch`, `--wait`, `--json`. |
| `PinShell set [options]` | Update the current window without reloading the page. Same window options as `show`. |
| `PinShell reload` | Reload the current file. |
| `PinShell eval <js> [--json]` | Evaluate JavaScript in the page and print the result. |
| `PinShell emit <event> [json] [--json]` | Dispatch an event into the page. `data` must be valid JSON. |
| `PinShell listen [--json]` | Stream page events until interrupted. |
| `PinShell status [--json]` | Print `file`, `frame`, `visible`, `passthrough`, `watching`, `opacity`, and `radius`. |
| `PinShell templates [--json]` | List installed templates with name, description, size, and path. |
| `PinShell close [--json]` | Hide the overlay. The app keeps running. |
| `PinShell mcp` | Run the MCP 2.0 stdio server. Not needed when using this skill. |

Examples:

```bash
# Replace a running panel and keep watching the file
PinShell show ./panel.html --watch --json

# Move and resize the current window
PinShell set --size 360x140 --position top-right

# Read the panel's shared state
PinShell eval 'window.pinshell.getState()' --json

# Send a UI update, then wait for the page to submit
PinShell emit agent:message '{"text":"Waiting for your choice"}'
PinShell listen --json
```

`listen` is blocking. Run it as a background process and parse each line; keep it running while the user interacts, then stop it when the panel closes. To wait for one event, you can pipe through `grep -m1` (for example `grep -m1 '"type":"ui"'`), but a background stream is easier to keep healthy.

## Events in practice

Page → agent:

```json
{"event":"emit","name":"ui:submit","data":{"action":"cancel"},"type":"ui","seq":12,"session":"…"}
```

Agent → page:

```bash
PinShell emit agent:message '{"text":"Canceled. Cleaning up…"}'
```

Useful event names:

- `ui:ready`, `ui:input`, `ui:submit`, `ui:cancel` — UI lifecycle.
- `lifecycle:loaded`, `lifecycle:error` — page load results.
- `state:snapshot`, `state:delta` — shared state changes.
- `log` — page logs.
- Template namespaces such as `pet:*`, `todo-list:*`, `pomodoro:*` when reusing a template.

## Templates

`PinShell templates --json` lists installed templates under the app's templates folder. Prefer reusing a template when it fits; read the file with the agent's file tools if you need to learn its event protocol. The CLI cannot install or edit library templates — ask the user to install them from the Console's online library.

## Guardrails

- Be proactive when a panel genuinely helps, but do not panel every answer. Do not duplicate the same text in chat and on screen.
- Keep panels compact and readable at their declared size. Respect `prefers-reduced-motion`; keep sound brief, quiet, and optional.
- Reply to the user in their language. Write on-screen copy in the app language when available (`window.pinshell.templateLanguage`, then `window.pinshell.languages`, then `window.pinshell.language`); otherwise match the user's reply language.
- Use real buttons and controls, with a visible keyboard focus state. Make the primary action obvious.
- Close the panel with `PinShell close` when the task is done, and remove any temporary HTML files you created.
- Never use the CLI to run destructive commands or to modify files outside the panel task. Trigger page interactions, not shell actions, from the panel.
