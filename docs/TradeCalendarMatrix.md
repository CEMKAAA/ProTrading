# Entry Time Matrix

`orb/OrbUltimateEA_StrategyLibrary.mq5`, `macrossover_orb/MaCrossOverOrbEA.mq5`, and
`SolAdvanced/LiqNarrativeSol_Advanced.mq5` use family-local copies of
`TradeCalendarMatrix.mqh`. The root copy is retained for the standalone probe;
keep all four copies byte-identical when changing the shared calendar logic.

- The `TIME MATRIX` dashboard button opens a modal with weekday WR, hour WR,
  weekday-hour WR, and a leaderboard switchable between `DAYS`, `HOURS`, and
  `DAY x HOUR`. Each category ranks by WR, then sample count. The leaderboard
  defaults to at least 10 closed trades per row; `MIN N` cycles 1/3/5/10/20.
  Raw views always show smaller samples. Each leaderboard row has `+ PICK`:
  selections stay staged while the leaderboard and audit remain unchanged.
  `PICK PAGE` stages only the qualifying rows visible on the current page
  (up to eight); it does not select rows on other pages. You can move to
  another page and stage its rows too.
  `APPLY PICKS` commits all selected rows together and reruns the audit. If the
  filter was off, the new schedule starts with only the picked rows; if it was
  on, the picks extend the active schedule. A day row means all 24 hours of
  that day; an hour row means that hour on all seven days; a day-hour row means
  exactly that combination. Closing the modal without applying discards picks.
- WR is `W / (W + L)`. Open and DATA rows are excluded. ORB/MaCross also exclude
  flat outcomes; Sol Advanced follows its existing closed-trade W/L decision.
  The sample is the EA's currently selected audit window and active filters.
- Historical hour groups use the signal's available/entry time from the audit,
  not an exact broker fill timestamp. Around an hour boundary, a delayed fill
  may belong to the next live hour. The live entry gate checks the current
  broker time at the final execution boundary.
- ORB and MaCross label/group times in their configured **session-local clock**.
  Sol Advanced uses the MT5 **broker-server clock**. These are not necessarily UTC.
- Under `SELECT TIME`, choose a day, then select hours for that day only. Return
  to the day list to configure another day. Hours are paged in groups of eight.
  `CLEAR ALL` on the day list is a quick way to build a sparse schedule from
  scratch; `CLEAR DAY` affects only the open day. `APPLY FILTER` commits any
  schedule with at least one selected day-hour;
  `FILTER OFF` restores the pre-feature trading behavior.
- The final live entry boundary checks the committed schedule before any native
  **entry** order or bridge entry publish. Audit applies the same clock choice
  to entry times. Reverse/exit handling is not time-filtered: a blocked new
  entry may still send a close-only event under existing reversal policy.
- The three MT5 inputs `InpTimeMatrixEnabled`, `InpTimeMatrixDays`, and
  `InpTimeMatrixHours` are fallback defaults for a new chart. Day bits 0..6 mean
  Sunday..Saturday; hour bits 0..23 mean 00:00..23:00. `127`/`16777215` allow all.
  Each day receives its own hour mask. Dashboard changes are stored in a
  committed two-slot set of terminal Global Variables scoped by account, chart
  ID, and symbol. An existing day mask plus shared hour mask is migrated without
  changing its effective schedule. Changing the three Inputs explicitly overrides
  an older dashboard selection. On a newly created chart, the Inputs are used
  instead. Saving a new ORB, MaCross, or SolAdvanced user strategy now records
  filter ON/OFF and all seven per-day hour masks; loading it restores those
  settings and reruns the audit. Strategies saved before this field existed,
  and immutable built-in presets, load with Time Matrix OFF rather than
  inheriting the previously selected strategy's schedule.

These are descriptive historical statistics, not a validated calendar edge.
Picking the highest row after viewing the same audit window is in-sample selection;
test a chosen schedule in a later untouched period before using it live.

Compile the three EAs without modifying an attached robot:

```powershell
& scripts/validate_time_matrix.ps1 -RunProbe
```

The validator stages all required includes, requires 0 errors / 0 warnings,
and runs an MQL per-day mask, migration and persistence probe in an isolated MT5 worker.
It does not install or restart any running EA.
