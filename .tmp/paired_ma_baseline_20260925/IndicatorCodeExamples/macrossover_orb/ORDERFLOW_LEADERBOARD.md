# Order-flow research leaderboard

Open **OF RESULTS** in the MaCross dashboard header, next to the order-flow
toggle. This is a read-only research panel, not a strategy application control.

The frozen 20-week campaign covers 2026-05-02 through 2026-09-19. It contains
42 complete-data delta-only comparisons: 14 presets x thresholds 0.05, 0.10,
0.20. Two presets lack complete order-flow data and are excluded. Results do
not change with the chart's current audit window or runtime settings.

Filters:
- Delta threshold: all, 0.05, 0.10, 0.20.
- Improved net R only (default enabled).
- Improved closed-trade drawdown only.
- At least 20 remaining trades (default enabled).
- Exact chart symbol or all symbols.
- At least 25% of baseline trades retained.

Sort by net-R improvement, filtered net R, or drawdown reduction. Rows show
baseline -> filtered trade count, WR, net R, closed-trade DD, and retention.
Use < and > to page and X to close. While open, dashboard events are consumed
by the research panel; trading callbacks continue normally.

The live order-flow gate still combines profile AND activity AND directional
delta. Research delta-only settings are NOT automatically applied. The data
is a broker bid-update activity proxy, not exchange aggressor volume.
Multiple-comparison selection and overlapping strategies prohibit treating
this leaderboard as independent forward validation or portfolio performance.

Verification: EA compiled with 0 errors / 0 warnings; all 462 exported metric
and identity fields match campaign summary.json. DEMO source/include closure
(34 files), EA EX5, worker MQ5 and worker EX5 verified by SHA-256.
Interactive chart clicking has not been verified in this run.

Installed folder: C:\MT5\DEMO\MQL5\Experts\MaCrossOverOrb
Evidence: .tmp/ma_of_leaderboard_20260921_184928/MaCrossOverOrbEA.mq5.log
Campaign: logs/ma_of_20w/20260921_180003_b7a98c
