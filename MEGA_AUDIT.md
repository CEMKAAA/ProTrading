# Repeatable Native Mega Audit

Double-click `Run-Mega-Audit.bat` in the project root.

- If a campaign is already running, the BAT attaches a live monitor. It does not stop or duplicate the campaign.
- Otherwise it rescans the actual MT5 Common strategy libraries for all four frontier EAs, including newly saved and updated records. There is no fixed strategy-count limit.
- It runs all nine windows: 2W, 5W, 10W, 20W, 1Y, 2Y, 3Y, 4Y, 5Y.
- Each published window must match the native dashboard audit trade by trade. Verified values are written to the existing `WindowMetrics` folders that the EA strategy SEARCH reads.
- All windows in one campaign use one captured endpoint. A later campaign captures a new endpoint and current saved settings. Do not change a saved strategy while its campaign runs; snapshot mismatches fail safely instead of auditing mixed settings.
- Original immutable MEGA archives remain untouched. Repeated runs update CURRENT only.
- The existing isolated research terminal and verified compiled wrappers are reused. No terminal, history or dependency-tree copies are created.

## Live Progress

The monitor refreshes every five seconds and shows:

- Processed strategies / discovered strategies, with a percent bar based on processed windows.
- Fully successful strategies (all nine windows verified and written).
- Verified windows / requested windows and their separate success percentage.
- Partial strategies, confirmed unavailable broker-data windows, failed verification windows, pending windows and current strategy.

DATA and failed verification are never counted as profitable or successful results. Unresolved windows receive two bounded retry passes. A failure report is retained rather than claiming completion.

Ctrl+C closes the monitor only; the hidden background campaign continues. Reopen the BAT to reattach.

## Commands

```powershell
.\Run-Mega-Audit.bat -StatusOnly
.\Run-Mega-Audit.bat -InventoryOnly
.\Run-Mega-Audit.bat -MonitorOnly
.\Run-Mega-Audit.bat -MonitorOnly -Once
```

`-InventoryOnly` scans without starting MT5 or altering strategy/metric files.

New campaign reports reuse `reports/verification_build/mega_campaign`. The currently running original corrected campaign remains in `reports/verification_build/audit_failures`. Its manifest is not rewritten during execution; strategies added meanwhile enter the next newly started campaign.

The import must validate every saved input profile. Corrupt or unknown profiles are reported, not silently substituted or omitted. Approved JP225 broker-symbol substitutions are retained. If the canonical EA engine changes, reverify its compiled research build before rerunning: old engine-parity evidence is not accepted as proof for new code.

When automatic rolling refresh owns the research worker, a manual campaign waits for that audit to finish naturally. The automatic worker yields at an idle boundary and its scheduled task is restarted afterward. Native trading in the user's terminal is not stopped or changed.
