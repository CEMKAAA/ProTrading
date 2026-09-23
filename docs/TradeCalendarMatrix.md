# Entry Time Matrix

`orb/OrbUltimateEA_StrategyLibrary.mq5`, `macrossover_orb/MaCrossOverOrbEA.mq5`, and
`SolAdvanced/LiqNarrativeSol_Advanced.mq5` use family-local copies of
`TradeCalendarMatrix.mqh`. The root copy is retained for the standalone probe;
keep all four copies byte-identical when changing the shared calendar logic.

- The `TIME MATRIX` dashboard button opens a modal with weekday WR, hour WR,
  weekday-hour WR, and a weekday-hour leaderboard. The leaderboard defaults to
  at least 10 closed trades per combination; `MIN N` can cycle 1/3/5/10/20.
  Raw views always show smaller samples.
- WR is `W / (W + L)`. Open and DATA rows are excluded. ORB/MaCross also exclude
  flat outcomes; Sol Advanced follows its existing closed-trade W/L decision.
  The sample is the EA's currently selected audit window and active filters.
- Historical hour groups use the signal's available/entry time from the audit,
  not an exact broker fill timestamp. Around an hour boundary, a delayed fill
  may belong to the next live hour. The live entry gate checks the current
  broker time at the final execution boundary.
- ORB and MaCross label/group times in their configured **session-local clock**.
  Sol Advanced uses the MT5 **broker-server clock**. These are not necessarily UTC.
- Under `SELECT TIME`, `DAYS MULTI-SELECT` and `HOURS MULTI-SELECT` stage choices.
  Hours are paged in groups of eight. `APPLY FILTER` commits nonempty selections;
  `FILTER OFF` restores the pre-feature trading behavior. Existing strategies
  start with the filter OFF.
- The final live entry boundary checks the committed schedule before any native
  **entry** order or bridge entry publish. Audit applies the same clock choice
  to entry times. Reverse/exit handling is not time-filtered: a blocked new
  entry may still send a close-only event under existing reversal policy.
- The three MT5 inputs `InpTimeMatrixEnabled`, `InpTimeMatrixDays`, and
  `InpTimeMatrixHours` are fallback defaults for a new chart. Day bits 0..6 mean
  Sunday..Saturday; hour bits 0..23 mean 00:00..23:00. `127`/`16777215` allow all.
  Dashboard changes are stored in one terminal Global Variable scoped by account,
  chart ID, and symbol. Changing the three Inputs explicitly overrides an older
  dashboard selection. Applying a saved strategy does **not** alter this chart's
  time schedule. On a newly created chart, the Inputs are used instead.

These are descriptive historical statistics, not a validated calendar edge.
Picking the highest row after viewing the same audit window is in-sample selection;
test a chosen schedule in a later untouched period before using it live.

Compile the three EAs without modifying an attached robot:

```powershell
& scripts/validate_time_matrix.ps1 -RunProbe
```

The validator stages all required includes, requires 0 errors / 0 warnings,
and runs a 9-check MQL mask/count/persistence probe in an isolated MT5 worker.
It does not install or restart any running EA.
