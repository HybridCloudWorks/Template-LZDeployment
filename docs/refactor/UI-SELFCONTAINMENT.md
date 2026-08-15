# Refactor gate 6 — UI self-containment

## The one documented command

From a fresh instance of this repository, with no server, no build step, no
package manager, and no network:

```bash
xdg-open site/index.html        # Linux
open site/index.html            # macOS
start site\index.html           # Windows
```

The wizard is three static files (`site/index.html`, `site/app.js`,
`site/styles.css`) in vanilla HTML/CSS/JS. There is no `package.json`,
no bundler, and no devcontainer requirement. A hosted copy is published to
GitHub Pages by `.github/workflows/deploy-pages.yml` for browsers that
restrict `file://` script execution.

## Self-containment is enforced, not asserted

- **CSP:** `default-src 'none'; script-src 'self'; connect-src 'none';
  form-action 'none'` — the page cannot phone home even if code tried.
- **CI gate:** `factory/ci/Test-SiteNoNetwork.ps1` (Factory CI check
  "Site no network") greps `site/` and `frontend/` for `fetch(`,
  `XMLHttpRequest`, `WebSocket`, `EventSource`, `sendBeacon`, dynamic
  `import(`, and any external script/style/media/form URL; any hit fails CI.
- **Draft persistence** uses `localStorage` only.

## Ephemeral Azure infrastructure

The wizard provisions **none**. It makes zero network calls of any kind, so
there is nothing to tear down. (The repository's former `functions/` Azure
Functions stubs were dead code unconnected to the wizard and were deleted in
this refactor — see CLASSIFICATION.md.) Engagement-level teardown of broker-
created estates is `scripts/Dispose-Engagement.ps1`, unchanged.

## The rest of the toolchain

The wizard is the only zero-dependency component. The generator pipeline needs
PowerShell 7 and Terraform ≥ 1.9 (plus `az`/`gh` for delivery), declared in
`factory-version.json` and verified by the entry scripts. That is unchanged by
this refactor and documented in the README's pipeline section.
