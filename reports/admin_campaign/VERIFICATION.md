# Shared Strategy Campaign Verification

Completed: 2026-10-10. Scope: the web shared-strategy catalogue and sealed MEGA results, not a new native audit campaign.

## Outcome

- Native catalogue and Supabase: 191/191 records match; no missing, extra or mismatched records remain.
- Families: ORB 70, MaCross 82, Sol Advanced 30, Entry Lab 9.
- Three previously absent records inserted with no user grants and no fabricated campaign results: `btcusd0.02RStrategy`, `jp2250.01H1.5HtfMode`, `jp2250.01HasResearchPotential`.
- Corrected 25 Sol Advanced web runtime mappings: 25 inactive Legacy MAX values and three reverse-exit flags. Original native strategy files and settings were not edited.
- Full configuration, original native snapshot, identity, symbol and source fingerprint compared. The diagnostic `native_snapshot.proposedConfiguration` duplicate is excluded from snapshot comparison.
- Legacy's inactive native MAX=0 is represented as 1 in the validated web configuration; Independent limits retain their saved values.

## Metrics

- 188 sealed MEGA strategies, nine windows each: 1,692 windows.
- 1,616 verified available windows and 76 confirmed unavailable windows.
- All 188 campaign JSON objects read back from Supabase match the imported sealed evidence exactly, including every metric and window status.
- UI displays selected-window total trades, W/L/O, WR, Net R, MinCum, flats, position mode, audited symbol/timeframe and broker-time cutoff.
- WR is W/(W+L); open and flat trades are excluded. Unavailable data remains null, not 0W/0L.
- Recorded cutoff: broker wall-clock `2026-10-09 19:46:57`. These are frozen historical results, not current/live forecasts.
- Changed source fingerprints hide stale performance. Two explicitly approved symbol aliases retain the actual audited symbol.

## Verification

- Automated tests: 35 passed, zero failed. Includes catalogue validation, campaign ingestion, three-language server rendering, auth/grant scope and public-path checks.
- TypeScript `--noEmit --incremental false`: passed.
- Production static build and private-artifact export scan: passed.
- Live Supabase transaction: passed default deny, denied direct table access, rejected forged admin metadata, exact granted metrics, stale fingerprint invalidation, revocation and admin catalogue checks. Test changes rolled back.
- Production has four pre-existing grant records; new strategies have no enabled grants. Grant timestamps remain unchanged, latest `2026-10-08 19:19:29.163046+00`.
- HTTPS control endpoint: correct GitHub origin accepted for preflight (204); unauthenticated strategy request denied (401).
- Root worktree/index and running/scheduled research jobs were not reset or stopped. No native EA files, trading orders or MT5 settings changed.

## Publication

- Studio: https://cemkaaa.github.io/CemkaCapital/studio/
- Repository commit: `5b0593df09b2fdeafaf314044f0b5b8c3d8a7638`.
- GitHub Pages reports the same commit as built successfully.
- All 56 public export files fetched over HTTPS: HTTP 200 and exact SHA-256 match with the verified local build.
- Private configurations, strategy snapshots, SQL uploads and native sources were not committed to the public website repository.
- Evidence: `catalog-comparison.json`, `metrics-comparison.json`, `final-db-verification.json`, `publication.json`, `live-deployment-check.json` in this directory.

## Limits

- The three newly added strategies were not present in the sealed 188-strategy MEGA campaign and have no MEGA metrics yet.
- This check proves catalogue mapping and stored-result transport parity. It is not a fresh 191-strategy native backtest, nor a guarantee of future returns.
- Interactive visual browser verification was unavailable: the computer-use provider exposed no usable browser. Rendering tests and live HTML/CSS/JS/font hash checks passed, but do not substitute for a visual desktop/mobile pass.
- Supabase security advisor reports no ERROR findings. Existing private-schema no-policy INFO notices correspond to intentionally denied direct table access.
- Existing unrelated Auth warning: leaked-password protection is disabled. This work did not change Auth settings. Remediation: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection
