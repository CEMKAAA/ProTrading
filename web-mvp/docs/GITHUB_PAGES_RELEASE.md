# CemkaCapital Deployment

Source of truth: this workspace's web-mvp directory. The public
CEMKAAA/CemkaCapital repository contains only the compiled frontend, not the
workspace history, trading engines, private catalogs, signing keys or databases.

## Live URLs

- Home: https://cemkaaa.github.io/CemkaCapital/
- Studio: https://cemkaaa.github.io/CemkaCapital/studio/
- Legacy Studio: https://cemkaaa.github.io/studio/
- API: https://uvzhrrqzzdjqtmydpvwo.supabase.co/functions/v1/stratum-control

The legacy route is a single same-origin redirect in CEMKAAA.github.io.
It preserves email-confirmation query/hash values locally, and keeps the current
signed MT5 packages' Studio links working. The unrelated root homepage is intact.
Supabase Auth redirects and cloud deployment configuration were not rewritten.

## Architecture

GitHub Pages serves index.html, the Studio HTML, JavaScript, CSS, fonts and public
evidence files. This is a static frontend export, not an offline/static-only
application: runtime requests use Supabase Auth and the existing control Edge
Function. The broker audit/trading engines still run in the authorized MT5
installation. GitHub Pages cannot execute those engines.

Authentication and authorization remain required; publishing does not grant a
subscription, turn trading on or activate payment checkout.

## Build

Run from web-mvp:

```powershell
$env:NEXT_PUBLIC_BASE_PATH = '/CemkaCapital'
$env:NEXT_PUBLIC_CONTROL_API = 'https://uvzhrrqzzdjqtmydpvwo.supabase.co/functions/v1/stratum-control'
npm.cmd run build:pages
```

Entry files: out/index.html and out/studio/index.html.
Next Link prefixes navigation automatically. Favicon and public downloads use
lib/public-path.ts. The export checker rejects missing/unprefixed assets and
private artifacts. Do not publish web-mvp itself or the root EA workspace.
Local development retains an empty base path when the environment is unset.

## Current Release

The 2026-10-09 release is staged in reports/web_publish_20261009/CemkaCapital.
Preparation/publishing scripts intentionally refuse to reinitialize or overwrite
an existing release directory. The publish script's -Resume completes an
interrupted publication only after the build hashes and remote commit match.
Never force-push or republish unrelated root-site assets.

Local evidence:

- reports/web_publish_20261009/release.json: public build file hashes
- reports/web_publish_20261009/deployment.json: remote commit and deployment state
- reports/web_publish_20261009/live-verification.json: live asset and API checks

The local UI tests cover EN/TR/DE rendering, guidance, signed package behavior and
agent authority. Live verification checks all non-hidden public files by SHA-256,
the legacy redirect, backend readiness, CORS preflight and unauthenticated/foreign
origin denial. It does not claim a new broker backtest or visual browser test;
no browser provider was available during this release.
