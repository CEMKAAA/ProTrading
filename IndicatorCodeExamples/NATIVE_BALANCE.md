# Native Risk Reference Balance

ORB, MaCross, Entry Engine Lab: BALANCE / APPLY BAL is in the right strategy
panel, above SAVE CURRENT STRATEGY. Sol Advanced: open STRATEGIES; the same
controls are above SAVE CURRENT STRATEGY when the search results are closed.

- 0 keeps the previous account/input capital basis unchanged.
- A positive value supplies reference capital for native percentage-risk sizing.
- 30 at 1% requests a 0.30 risk budget in the account currency, USD on a USD account.
- APPLY commits the current edit text, persists per EA family/account/chart,
  and refreshes the audit's monetary display. Typing alone does not apply it.
- Real account margin, equity and drawdown guards remain real account guards.
- The budget is capped by actual account balance. Minimum-lot overshoot is
  rejected rather than rounded up. ATR/portfolio constraints may reduce sizing.
- This is planned entry-to-SL risk, not a guarantee on broker fills, stop gaps,
  slippage, commissions or swap. Existing positions are not resized or closed.
- ORB MONEY mode takes priority over percentage-reference sizing.
- Risk controls stay separate from strategies, as in the existing strategy UI.
- Listener percentage and original payload capital/budget remain unchanged.

Closed audit arrows are green only when modeled net R after configured costs
is positive. Open/invalid/flat trades have separate colors. Audit costs are not
a claim that every historical broker commission/swap has been reconstructed.

Validation scripts: scripts/validate_native_balance.ps1 and
scripts/deploy_native_balance.ps1. Deployment requires all four clean builds,
passing isolated probes and current-source/staged-source hash equality.

Verified 2026-10-01: `.tmp/native_balance_20261001_192915`.
All four production EAs and their probes compiled with 0 errors / 0 warnings.
MaCross, ORB and Entry Lab each passed 26 checks; Sol Advanced passed 23.
The tests exercised the main Apply event routes without placing real orders.
Deployment manifest: `.tmp/native_balance_deploy_backup_20261001_200804/manifest.txt`.
All 170 deployed source/dependency/binary file hashes matched their sources.
