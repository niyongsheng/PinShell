# Template Contribution Guide

**English** · [简体中文](./template-contribution.zh-CN.md)

PinShell's online template library is generated from [`website/templates`](../website/templates).
This guide is the contract for contributing a template: file layout, `template.json`, HTML and
i18n rules, design tokens, the agent event protocol, local validation, and the review checklist.
A pull request merged to `main` publishes the template to the website and to the app's online
library automatically.

> The fastest way to learn the format is to copy a small existing template:
> [`goal-progress`](../website/templates/goal-progress) (compact, live data) or
> [`desktop-pet`](../website/templates/desktop-pet) (two-way events).

## 1. What a template is

A template is a single, self-contained HTML document rendered in PinShell's always-on-top,
transparent panel. Users install it from the online library into:

```text
~/Library/Application Support/PinShell/templates/
```

Only `<id>.html` is downloaded. The app seeds two shared sidecars next to it on launch:

- `design-tokens.css` — shared design system and transparent-canvas reset
- `pinshell-i18n.js` — language selection helper

Therefore:

- Inline all CSS and JavaScript in the HTML. Images must be `data:` URIs or `https:` URLs.
- Any other file in the template directory is rejected by the build and would not ship anyway.
- The HTML file must be UTF-8 and no larger than **512 KB (524,288 bytes)**.
- The template must remain useful offline. Remote data is optional, and failures must degrade to
  a clear empty or error state instead of a blank or broken panel.

## 2. Repository layout

```text
website/templates/
└── <id>/
    ├── template.json   # manifest: version, category, author, listing, changelog
    └── <id>.html       # the template itself
```

- The directory name, the manifest `id`, and the HTML basename must all be identical.
- The directory must contain **exactly these two visible files**. The builder rejects extra
  files, including READMEs, screenshots, or local images.
- `<id>` must match `^[a-z0-9]+(-[a-z0-9]+)*$` and be at most 64 characters. Choose a stable,
  descriptive id (`pomodoro`, `system-monitor`). **An id is immutable once published.**
- Do not edit `Resources/templates/design-tokens.css` or `Resources/templates/pinshell-i18n.js`
  in a template PR. They are shared by every template; propose changes separately.

## 3. Manifest: `template.json`

```json
{
  "schemaVersion": 1,
  "id": "example-panel",
  "version": "1.0.0",
  "releaseDate": "2026-11-23",
  "minAppVersion": "1.4.0",
  "category": "productivity",
  "tags": ["example", "starter"],
  "author": {
    "name": "Your Name",
    "url": "https://github.com/your-handle"
  },
  "listing": {
    "zh-Hans": {
      "tagline": "一个最小可用的 PinShell 模板。",
      "highlights": ["单文件 HTML", "中英双语", "Agent 事件示例"]
    },
    "en": {
      "tagline": "A minimal PinShell template.",
      "highlights": ["Single-file HTML", "Chinese and English", "Agent event example"]
    }
  },
  "changelog": {
    "1.0.0": {
      "date": "2026-11-23",
      "notes": {
        "zh-Hans": "首个版本。",
        "en": "First release."
      }
    }
  }
}
```

| Field | Required | Rules |
| --- | --- | --- |
| `schemaVersion` | yes | Must be `1`. |
| `id` | yes | Equal to the directory name. Lowercase slug, ≤ 64 chars, immutable after publishing. |
| `version` | yes | Strict `X.Y.Z`. Bump for every published change. |
| `releaseDate` | recommended | `YYYY-MM-DD`. |
| `minAppVersion` | yes | Strict `X.Y.Z`. Must not be newer than `CFBundleShortVersionString` in `Resources/Info.plist` (currently **1.5.0**). Use the lowest version that actually provides what you use; `1.4.0` covers the APIs in this guide. |
| `category` | yes | One of the ids in [`website/site.json`](../website/site.json): `productivity`, `focus`, `monitoring`, `companion`, `media`, `play`, `social`. |
| `tags` | no | 1–8 unique tags. Each tag is lowercase letters, digits, or hyphens, 1–24 chars. |
| `author.name` | yes | 1–64 characters, single line, no leading or trailing whitespace. |
| `author.url` | no | Optional homepage or profile. Must be HTTPS. |
| `listing` | recommended | Localized marketing copy keyed by language tag. Each entry needs a non-empty `tagline` or `highlights`. Provide both `zh-Hans` and `en`. |
| `changelog` | yes | Must contain an entry keyed by the current `version`. Every key is `X.Y.Z`; every entry should include a `date` and localized `notes`; the current version's notes must include non-empty `zh-Hans` and `en`. |

Notes:

- **Do not put name, description, size, or order in the manifest.** Those are extracted from the
  HTML: the i18n `meta` block and `pinshell:*` meta tags.
- `author` is required so contributions are attributed in the app and on the detail page.
- Keep `listing.tagline` to one sentence and `highlights` to 2–4 short items.
- Every published change needs a new `version` and a matching `changelog` entry. Payloads are
  versioned and immutable: never edit the HTML of a version that has already shipped; publish a
  new version instead.

## 4. HTML contract

### 4.1 Document head

```html
<!doctype html>
<html lang="zh-Hans">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<script type="application/json" id="pinshell:i18n">
{
  "default": "zh-Hans",
  "fallback": "en",
  "languages": {
    "zh-Hans": {
      "meta": { "name": "示例面板", "description": "一个最小可用的 PinShell 模板" }
    },
    "en": {
      "meta": { "name": "Example Panel", "description": "A minimal PinShell template" },
      "ui": { "title": "Example", "hint": "Click the button to notify the agent" }
    }
  }
}
</script>
<title>示例面板</title>
<meta name="description" content="一个最小可用的 PinShell 模板">
<meta name="pinshell:size" content="280x96">
<meta name="pinshell:position" content="bottom-right">
<meta name="pinshell:radius" content="18">
<link rel="stylesheet" href="design-tokens.css">
<style>/* template styles */</style>
</head>
<body>
<!-- template markup -->
<script src="pinshell-i18n.js"></script>
<script>/* template behavior */</script>
</body>
</html>
```

The build enforces all of the following:

| Requirement | Rule |
| --- | --- |
| Encoding | UTF-8, ≤ 512 KB. |
| `<html lang>` | Present and equal to the i18n `default` language. |
| i18n block | Exactly one `<script type="application/json" id="pinshell:i18n">` in the document. |
| `default` | Must be `zh-Hans`. |
| `fallback` | Must be `en`. |
| `languages` | Must declare both `zh-Hans` and `en`; every declared language needs non-empty `meta.name` and `meta.description`. |
| `<title>` | Non-empty. |
| `pinshell:size` | Required, `WIDTHxHEIGHT`, at least `80x40`. This is the initial and preview size. |
| `pinshell:order` | Optional non-negative integer. Must be unique across the whole library; lower sorts first. |

The i18n `meta` is the **single source** for the library name and description. Keep `<title>` and
`<meta name="description">` in the default language as a graceful fallback for direct file use and
for agents that read the HTML.

### 4.2 Window metadata

PinShell applies these before the page loads and re-applies them on show or reload. CLI flags may
override them for a single session.

| Meta tag | Values | Notes |
| --- | --- | --- |
| `pinshell:size` | `280x96` | Required. Initial and preview size; minimum `80x40`. |
| `pinshell:position` | `top-left`, `top`, `top-right`, `left`, `center`, `right`, `bottom-left`, `bottom`, `bottom-right`, or `x,y` | Optional initial anchor. Compact badges usually work best at a corner. |
| `pinshell:passthrough` | `true` / `false` | Optional. Only decorative, non-interactive templates should start click-through. |
| `pinshell:opacity` | `0`–`1` | Optional window opacity. Keep it at or near `1` for text-heavy panels. |
| `pinshell:radius` | pixels | Optional window corner radius. Match the surface radius inside the page. |
| `pinshell:order` | integer ≥ 0 | Optional library sort key; unique across the library. |

### 4.3 Internationalization

The i18n block is required even when the template has no translatable UI copy. The default
language's copy stays inline in the HTML; non-default languages provide a `ui` dictionary.

Static copy:

```html
<span data-i18n="title">示例</span>
<input data-i18n-placeholder="inputPlaceholder" placeholder="输入…">
<button data-i18n-title="actionTitle" title="操作">…</button>
```

Dynamic copy:

```js
PS.t('remaining', '还剩 {n} 项', { n: 3 });
PS.list('lines', ['默认文案']);   // arrays and structured data
PS.get('seed', []);              // raw values
PS.locale;                       // resolved BCP-47 tag
```

Rules:

- Every non-default language must provide a `ui` entry for **every** key referenced by
  `data-i18n`, any `data-i18n-*` attribute, `PS.t`, `PS.list`, or `PS.get`. The build fails on a
  missing key, by design: users should never see mixed languages.
- Additional languages are welcome. Declare them in `languages` with full `meta` and `ui`.
- Default copy lives in the markup; the `zh-Hans` entry usually needs only `meta`.
- Preview a language in a browser by appending `?lang=en` (or `?lang=zh-Hans`) to the payload URL.
- Escape `</script` inside JSON strings as `<\/script`; otherwise the HTML block ends early.
- In the app, the helper resolves the language from `window.pinshell.templateLanguage`, then
  `window.pinshell.languages`, then the system preference. `PS.lang` keeps the legacy short form
  (`zh-Hans` / `en`).
- If the template renders text into a `<canvas>`, query `PS.locale` when drawing; the helper only
  handles DOM text and attributes.

### 4.4 Assets and network

Allowed local references are limited to the two seeded sidecars:

```html
<link rel="stylesheet" href="design-tokens.css">
<script src="pinshell-i18n.js"></script>
```

Everything else must be inline:

- CSS and JavaScript inline in the document.
- Images, icons, and fonts as `data:` URIs or `https:` URLs. Relative image paths will not ship.
- Prefer system fonts and CSS drawing over large base64 assets.
- Remote `https:` scripts are technically accepted by the builder but strongly discouraged:
  they add review surface, break offline use, and are not needed for a typical panel.
- Never embed API keys, tokens, personal data, analytics, or tracking.
- For cross-origin data, prefer `window.pinshell.fetch(url, { headers })`: HTTPS-only GET,
  15-second timeout, 2 MB cap, up to 20 headers. Standard `fetch` may be blocked by CORS from a
  `file://` page.
- Respect the terms of any third-party API or brand you use, and ship sensible attribution.

### 4.5 Window behavior and accessibility

- The window canvas is transparent. Draw your own surface: full-bleed panels commonly use
  `position: absolute; inset: 0`, a background, and `border-radius: var(--ps-radius-lg)`.
- The window is user-resizable (minimum 80×40). Do not assume the declared size is permanent;
  layouts should tolerate a modest resize without clipping controls.
- Hold **⌘** and drag to move the window. Avoid full-window drag handlers that swallow clicks.
- Set `user-select: none` on chrome, and re-enable `user-select: text` on inputs and selectable
  copy.
- Audio autoplay is allowed. Never surprise the user with loud audio on load; prefer
  interaction-triggered sound and provide a mute control for recurring sound.
- Respect `prefers-reduced-motion: reduce`: disable or shorten animations and confetti.
- Keyboard: every action must be reachable without a mouse; show a visible focus ring using
  `--ps-primary-focus`; label icon-only buttons with `aria-label`.
- Do not rely on color alone for status. Keep body text at a 4.5:1 contrast ratio.

## 5. Visual design

Link `design-tokens.css` and build on the `--ps-*` tokens instead of copying colors, radii, or
spacing values. The shared file also provides the transparent-canvas reset and passthrough
behavior.

- **One accent color.** `--ps-primary` (Action Blue) is the only "click me" signal. Do not add a
  second accent. Semantic green/red is fine for data direction (up/down), not for UI chrome.
- **Surfaces and text.** Dark cards use `--ps-surface-tile-1` / `-2` / `-3`; body text uses
  `--ps-body-on-dark`, secondary text `--ps-body-muted`. Hairline borders are typically
  `rgba(255, 255, 255, 0.08)`.
- **Radius grammar.** `xs`/`sm` for compact tools, `lg` for cards, `pill` for capsule actions.
  Do not mix arbitrary radii inside one panel.
- **Type.** Use `--ps-font-text`; body copy in the overlay is usually 12–17 px. Use negative
  letter-spacing only for display-size headings.
- **Spacing.** Stay on the 4/8 px rhythm (`--ps-space-*`). Typical panel padding is 12–18 px.
- **Shadows.** `--ps-shadow-float` (via `.ps-float`) is only visible on inset floating elements.
  A surface that fills the window clips its own shadow; use an inset card if you want depth.
- **Passthrough.** Add `.ps-dim-surface` to surfaces that should dim while the window is in
  passthrough; text stays solid.
- **Taste.** Aim for tactile, calm materials: hairline borders, restrained gradients, real
  typography. Avoid the generic "AI app" look — neon purple glows, glass everywhere, emoji walls,
  and decorative motion that never stops.
- **Performance.** This panel can stay on screen for hours. Avoid perpetual 60 fps canvas work,
  huge DOM trees, and unthrottled timers; pause animation and polling when `document.hidden`.

## 6. Agent event protocol

Templates may be driven by an agent. This is optional, but a good template works standalone and
becomes better when an agent is present. `window.pinshell` is injected at document start inside
the app; it is **absent on the website preview**, so guard it:

```js
const bridge = window.pinshell || { emit() {}, on() {}, log() {} };
```

| API | Direction | Purpose |
| --- | --- | --- |
| `bridge.emit(name, data)` | page → agent | Send a JSON-serializable event. Namespace it, e.g. `todo:changed`. |
| `bridge.on(name, callback)` | agent → page | Handle an event pushed with `pinshell_emit` or `PinShell emit`. |
| `bridge.ready()` / `input()` / `submit()` / `cancel()` | page → agent | Shorthands for `ui:ready` / `ui:input` / `ui:submit` / `ui:cancel`. |
| `bridge.setSize(w, h)` | page → app | Resize the window. Do not fight the user's manual resize. |
| `bridge.setPosition(anchor \| x, y)` | page → app | Move the window. |
| `bridge.setPassthrough(enabled)` | page → app | Toggle click-through. |
| `bridge.setOpacity(value)` / `setRadius(px)` | page → app | Adjust the window chrome. |
| `bridge.getState()` / `setState(state)` / `patchState(patch)` | page ↔ app | Shared panel state. `patchState` applies RFC 7386 merge-patch. |
| `bridge.log(...args)` | page → agent | Forward a diagnostic line. |
| `bridge.fetch(url, { headers })` | page → network | HTTPS-only GET through the native shell. |

Also available: `bridge.version`, `bridge.session`, `bridge.language`,
`bridge.languages`, and `bridge.templateLanguage`.

Conventions:

- Use a namespace for every event: `<id>:ready`, `<id>:changed`, `<id>:set`. The event `type` is
  the prefix before the first colon; names without a namespace are categorized as `ui`.
- Emit a ready event on load (`my-template:ready` with version and capabilities) so an agent can
  connect without scraping the DOM.
- Document both directions in a leading HTML comment titled `AGENT PROTOCOL`. Agents read the
  raw HTML with `pinshell_template_read` and rely on that comment.
- Treat agent input as untrusted: validate types and ranges, and never pass it to `eval`,
  `innerHTML`, or a URL without checks.
- Persist UI preferences in `localStorage` under a namespaced key such as
  `pinshell.<id>.<key>`. Never store secrets.
- Limits: bridge messages ≤ 64 KB, event names ≤ 256 chars, log text ≤ 4,096 chars. Events
  delivered to agents carry `{ seq, ts, session, type, name, data }`.

Example:

```html
<!--
  AGENT PROTOCOL · example-panel

  Agent -> page (pinshell_emit / PinShell emit):
    example:set   { title }   Update the title text
  Page -> agent (pinshell_poll_events):
    example:ready { version }
    example:ping  { at }
-->
```

## 7. Local preview and validation

Build and serve the full site (the preview needs the seeded sidecars):

```bash
make serve-site
# → http://127.0.0.1:8000
```

- Gallery: `http://127.0.0.1:8000/templates/`
- Detail page with live preview: `http://127.0.0.1:8000/templates/<id>/`
- Payload directly, with a forced language:
  `http://127.0.0.1:8000/templates/<id>/<version>/<id>.html?lang=en`

Run the catalog validator exactly as CI does:

```bash
swift run --package-path website TemplateCatalogBuilder --check \
  --site-url https://pinshell.looplooptech.com
```

It builds into a temporary directory and validates the manifest, HTML requirements, i18n
coverage, asset references, payload sizes/hashes, internal links, and generated pages. It exits
non-zero on the first problem. Also run the core tests:

```bash
swift test
```

Install into the real app for an end-to-end check (the app seeds the sidecars on launch):

```bash
cp "website/public/templates/<id>/<version>/<id>.html" \
  "$HOME/Library/Application Support/PinShell/templates/"
```

Then open **Console (⌘K) → Templates**, or run `PinShell show <path-to-html>`. Note that opening
`website/templates/<id>/<id>.html` directly from the source tree will not find the sidecars; use
the built preview or temporarily copy the sidecars next to it (do not commit them).

Before opening a PR, verify:

- [ ] The template directory contains exactly `template.json` and `<id>.html`.
- [ ] The catalog check and `swift test` pass.
- [ ] The panel looks right at its declared size and after resizing.
- [ ] Both `zh-Hans` and `en` render completely; no mixed-language copy.
- [ ] No console errors in the website preview or in the app.
- [ ] Layout survives the absence of `window.pinshell` (website preview).
- [ ] Offline / failed network shows a clear state, not a blank panel.
- [ ] Reduced motion is respected; audio starts only on interaction.
- [ ] Keyboard focus is visible and icon buttons have labels.
- [ ] No tracking, remote code, credentials, or extra assets.
- [ ] Generated `website/public/` is not committed.

## 8. Versioning and compatibility

- **Ids are permanent.** Once `pomodoro` is published, do not rename it or reuse it for a
  different template.
- **Payloads are immutable.** Each version is published at
  `templates/<id>/<version>/<id>.html` with its size and SHA-256. Editing a published file in
  place would break every installed copy's update check. Bump `version`, add a `changelog`
  entry, and publish a new version.
- **`minAppVersion`** must be a shipped app version or lower. Raising it while the app release is
  still pending makes the online catalog require an app that users cannot download yet. If your
  template needs a new PinShell feature, land it after that app release ships.
- **The ten first-party templates at `1.0.0`** have frozen hashes in
  `Resources/legacy-templates.json` for the 1.4 → 1.5 migration. Do not modify those files while
  they are at `1.0.0`; bump the version first, and coordinate with the maintainers if you are
  changing an existing first-party template.
- **Categories** live in `website/site.json`. To add one, send a separate PR with bilingual
  names; do not invent a category in a template manifest.

## 9. Submitting a template

1. Fork `niyongsheng/PinShell` and create a branch, e.g. `template/<id>`.
2. Add `website/templates/<id>/template.json` and `website/templates/<id>/<id>.html`.
3. Run the checks in section 7 and fix every error.
4. Open a pull request titled `feat(template): add <id>` (or
   `feat(template): update <id> to <version>`).
5. Include in the description: what the template does, category and tags, declared size,
   supported languages, the event protocol (if any), screenshots in both languages, and a
   confirmation that it has no tracking or remote code.
6. Keep one template per PR. Do not modify shared sidecars, other templates, or unrelated code.

Review focuses on: passing validation, self-contained offline behavior, complete bilingual copy,
correct use of design tokens, accessibility and reduced motion, performance in a long-running
panel, security (no tracking, no remote code, no credentials), and content quality and licensing.

After merge, the Pages workflow rebuilds the website and `library.json`. The app's online library
picks it up on its next refresh; no app release is needed unless the template requires an app
version that has not shipped yet. Users always choose whether to install or update; PinShell
never installs a library template automatically.

## 10. Appendix: a minimal working template

`website/templates/example-panel/example-panel.html`:

```html
<!doctype html>
<html lang="zh-Hans">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<script type="application/json" id="pinshell:i18n">
{
  "default": "zh-Hans",
  "fallback": "en",
  "languages": {
    "zh-Hans": {
      "meta": { "name": "示例面板", "description": "一个最小可用的 PinShell 模板" }
    },
    "en": {
      "meta": { "name": "Example Panel", "description": "A minimal PinShell template" },
      "ui": {
        "title": "Example",
        "hint": "Click the button to notify the agent",
        "action": "Ping agent"
      }
    }
  }
}
</script>
<title>示例面板</title>
<meta name="description" content="一个最小可用的 PinShell 模板">
<meta name="pinshell:size" content="280x96">
<meta name="pinshell:position" content="bottom-right">
<meta name="pinshell:radius" content="18">
<link rel="stylesheet" href="design-tokens.css">
<style>
  .panel {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 0 16px;
    box-sizing: border-box;
    color: var(--ps-body-on-dark);
    background: var(--ps-surface-tile-1);
    border: 1px solid rgba(255, 255, 255, 0.08);
    border-radius: var(--ps-radius-lg);
    user-select: none;
  }
  .copy { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 3px; }
  .title { font-size: 13px; font-weight: 600; }
  .hint { font-size: 11px; color: var(--ps-body-muted); }
  button {
    font: inherit;
    color: #fff;
    cursor: pointer;
    padding: 6px 12px;
    border: 0;
    border-radius: var(--ps-radius-pill);
    background: var(--ps-primary);
  }
  button:active { transform: var(--ps-press-scale); }
</style>
</head>
<body>
<div class="panel">
  <div class="copy">
    <div class="title" data-i18n="title">示例</div>
    <div class="hint" data-i18n="hint">点击按钮通知 Agent</div>
  </div>
  <button id="ping" data-i18n="action">通知 Agent</button>
</div>
<script src="pinshell-i18n.js"></script>
<script>
  var bridge = window.pinshell || { emit: function () {}, on: function () {} };

  document.getElementById('ping').addEventListener('click', function () {
    bridge.emit('example:ping', { at: Date.now() });
  });

  bridge.on('example:set', function (data) {
    document.querySelector('.title').textContent =
      (data && data.title) || PS.t('title', '示例');
  });

  bridge.emit('example:ready', { version: '1.0.0' });
</script>
</body>
</html>
```

The matching `template.json` is the example in section 3; replace the author, category, and
changelog values with your own, and keep `id` equal to the directory name.

## 11. License

PinShell is licensed under Apache-2.0. By submitting a template you confirm that you own or have
the rights to the code, artwork, and copy, and you agree to license the contribution under the
same license. Attribution stays in `author`; third-party assets must be compatible and credited
where required.
