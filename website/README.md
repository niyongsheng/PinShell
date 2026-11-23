# PinShell Website & Template Library

Static marketing site + online template catalog. Chinese lives at `/`, English at `/en/`.
Everything is generated into `website/public/`; that directory is gitignored and deployed to
GitHub Pages by `.github/workflows/pages.yml`.

## Build

Requires macOS 13+ and Xcode command-line tools.

```bash
# From the repo root
make site        # build into website/public
make serve-site  # build with http://127.0.0.1:8000 and serve it
```

Directly:

```bash
swift run --package-path website TemplateCatalogBuilder \
  --output website/public \
  --site-url https://pinshell.looplooptech.com

swift run --package-path website TemplateCatalogBuilder --check \
  --site-url https://pinshell.looplooptech.com
```

`--check` builds into a temporary directory, validates the catalog, internal links, payload
sizes/hashes, and exits non-zero on problems. CI runs it on every PR.

## Source layout

- `templates/<id>/template.json` — version, min app version, category, tags, marketing listing,
  changelog. **No name/description/size/order**: those come from the HTML.
- `templates/<id>/<id>.html` — flat single-file template. Must keep the `pinshell:i18n` block
  (default `zh-Hans`, fallback `en`) and may reference `design-tokens.css` / `pinshell-i18n.js`.
- `src/pages/` — bilingual home, gallery, detail, and 404 shells.
- `src/partials/` — shared nav/footer/head fragments.
- `src/assets/` — CSS, JS, favicons, OG images, manifest.
- `Sources/TemplateCatalogBuilder/` — SwiftPM executable that reuses `PinShellCore` parsing and
  validation, copies immutable versioned payloads, and renders pages.
- `public/` — generated output (not committed).

## Add or update a template

1. Create `templates/<id>/` with `template.json` and `<id>.html`; the file name must equal `<id>.html`.
2. `id` is immutable after publishing. Bump `version` (strict `X.Y.Z`) and add a matching
   `changelog[version]` entry for every change.
3. Run `swift run --package-path website TemplateCatalogBuilder --check` and fix any validation error.
4. Run `make serve-site`, check both languages, live previews, gallery filters, and detail pages.
5. Commit; the Pages workflow publishes on `main`.

`minAppVersion` must not be newer than `Resources/Info.plist`'s current version. Templates that need
newer PinShell features are published after that app release ships.

The ten migrated templates are pinned to version `1.0.0` and must keep the sha256 recorded in
`Resources/legacy-templates.json`; app 1.4 users' unmodified copies are adopted as `1.0.0` on the
first launch of 1.5. Bump the version before editing those files.

## Catalog contract

`public/library.json` is the app's only remote input. Key fields per template:

- `languages.<tag>.name/description` — extracted from the HTML i18n block
- `payload.url`, `payload.fileName`, `payload.bytes`, `payload.sha256` — immutable HTML payload
- `payload.bundleURL` — optional zip for manual website download (HTML + sidecars)
- `preview` — live preview URL and declared window size
- `pages` — localized website detail page
- `changelog` — localized release notes

The app verifies size and SHA-256 before writing, and never installs automatically. Shared
`design-tokens.css` / `pinshell-i18n.js` stay in the app bundle and are seeded into the user's
templates folder; they are not part of the payload hash.

## Deploy

One-time repo setup: **Settings → Pages → Source: GitHub Actions**, then set **Custom domain** to
`pinshell.looplooptech.com`. After that, pushes to `main` that touch `website/**`, the sidecars,
`Resources/Info.plist`, or the logo rebuild and deploy the site. The generated `CNAME` file pins the
custom domain.

### Cloudflare DNS

The zone uses Cloudflare DNS. For GitHub Pages use a **DNS-only** CNAME (orange cloud off):

```
pinshell.looplooptech.com  CNAME  niyongsheng.github.io  TTL Auto  (proxied: false)
```

If you have a Cloudflare API token with **Zone.Read + Zone.DNS Edit** (or set
`CLOUDFLARE_ZONE_ID` to skip the zone lookup), the repo includes an idempotent helper:

```bash
export CLOUDFLARE_API_TOKEN=...   # do not commit the token
website/scripts/setup-cloudflare-dns.sh
dig +short pinshell.looplooptech.com CNAME   # expect niyongsheng.github.io.
```

Proxying GitHub Pages through Cloudflare can break GitHub's custom-domain certificate issuance and
HTTPS verification, so keep the record DNS-only unless you have deliberately configured Full/Strict
TLS and accept the extra moving parts. If GitHub asks to verify the domain, add the TXT record shown
under **Settings → Pages** (usually `_github-pages-challenge-<owner>`). After GitHub Pages issues the
certificate, enable **Enforce HTTPS** in repo settings.
