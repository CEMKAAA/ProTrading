# Target Cost Gate: Four Production EAs

## Controls

All four canonical families now have `TP COST ON/OFF`, `MAX %`, and `APPLY`
on the right panel, below the balance/margin area. Default: OFF, 20% stored
limit. The controls apply to future entries and recalculate the audit; existing
positions and their protection are not changed. Apply reads the current edit.

The entry condition is:

`100 * estimated_cost_price_distance / planned_profit_price_distance <= MAX %`

Cost uses the observed entry spread plus configured audit slippage and
commission per lot. Commission is converted using broker tick size/value and
account-currency units. A fixed known profit budget is required. Partial
three-leg and half-close configurations use their weighted planned profit
budget. No spread-waiting order or fill-price guarantee was added.

`0%` permits only zero estimated cost. `100%` still enables the filter and
permits cost up to the whole profit budget; OFF is a separate control.

## Integration

- Independent of the old inverse-only GAP% control; both normal and inverse
  trades pass through the new gate.
- Both normal and ADV audit paths check entry quotes before replaying exits.
  Bar fallback uses its existing recorded/configured spread model, not a
  fabricated historical quote.
- Cost rejections are filtered entries, not DATA, W, L or OPEN, and consume no
  Independent capacity. Missing required cost metadata remains DATA.
- Live preflight checks occur before bridge publication and native entry.
  The Orb-derived native sender rechecks before submission/retry. Publication
  and native execution are not atomic across changing markets or listeners.
- No changes to signal generation, entry/SL/TP geometry, net-R calculation,
  existing position exits, bridge schema or MEGA archives.
- Strategy save/load stores an optional TCOST1 suffix. Old strategies load
  OFF with the default stored limit, never inheriting the previous strategy.
  Existing token layouts and default-OFF CURRENT identities are preserved.
- Enabled policies have separate CURRENT/cache keys. Accepted-trade CSV
  context records the active policy without changing the existing columns.

## Validation

Native isolated worker, Algo OFF, no test orders submitted. One existing worker
and fixed verification directories reused; no new terminal/history clones.

| Feature Probe | Checks | Failures |
| --- | ---: | ---: |
| MaCross | 177 | 0 |
| Entry Lab | 177 | 0 |
| ORB | 177 | 0 |
| Sol Advanced | 123 | 0 |

Checks include threshold boundaries, malformed input, commission conversion,
unknown cost/target handling, native planned geometry, normal/ADV rejection,
pre-change OFF simulation parity, actual strategy-file round trips, clearing
the preceding policy on old-strategy load, and dashboard edit/Apply events.
Sol capacity explicitly excludes cost-rejected prior entries. GUI previews
use a fixed test viewport, with chart-size reads instrumented only in probes.

All four canonical production EAs compile with 0 errors and 0 warnings.
The shared TargetCostGate.mqh copies are byte-identical in all four folders.
Existing Time Matrix (343 checks) and timed reverse (600 checks) regressions
also passed before release: 1597 checks in total, zero failures.
Evidence: `reports/verification_build/target_cost`,
`reports/verification_build/time_matrix`, and
`reports/verification_build/timed_reverse`.

## Actual USDJPY Comparison

Saved strategy `usdjpyM50.01Model`, USDJPYm/M5, 0.01R, LEGACY,
600-pip SL, fixed target, reverse/NAS/HC OFF. The same frozen 5Y cutoff
1791915416 was used for both runs. The source strategy and its saved metrics
were not overwritten by this research comparison.

| Metric | Filter OFF | Filter ON, Max 20% |
| --- | ---: | ---: |
| Trades | 1639 | 1603 |
| Wins | 1576 | 1590 |
| Net losses | 62 | 12 |
| OPEN | 1 | 1 |
| DATA | 0 | 0 |
| TP exits with net loss | 51 | 0 |
| SL exits | 11 | 12 |
| Net R | 1.9670 | 1.6855 |
| Total modeled/accounted cost R | 3.3030 | 2.2145 |
| Cost-rejected candidates | 0 | 197 |

The expensive-TP problem was eliminated in this sample, but total profit did
not increase. Admission changes alter later LEGACY occupancy and daily quotas,
so this is not a subtraction of the old 51 losses. No profitability claim is
made. Trade-by-trade aggregation agrees with the audit headline in both runs.

## Limits

Historical bar spread is a model, not an exact executable entry quote. Unknown
commission or future slippage cannot be guaranteed by a pre-entry filter;
configured values are estimates. Future spread changes, funding/swap and
unknown holding time are not bounded. Listener fills on another broker are
not constrained by the unchanged bridge payload. Dynamic exits without a
known fixed profit target are rejected when the filter is enabled.

## Files

Each family has a new `TargetCostGate.mqh`, beside its canonical MQ5/EX5.
Orb-derived changes also cover OrbAdvancedAuditEngine.mqh,
OrbStrategyUserLibrary.mqh, and OrbStrategyUserMetrics.mqh. Sol changes cover
LiqStrategyLibrary.mqh, LiqStrategyWindowMetrics.mqh, LiqSolAdvancedNas.mqh,
and AuditTradeCsvAdapter.mqh. Other EA variants and the universal web/listener
EA are not modified.

Final canonical MQ5/EX5 and changed/required MQH files were deployed to
DEMO/Experts/orb, MaCrossOverOrb, EntryEngineLab and SolAdvanced. All 25
source/destination SHA256 checks matched; see target_cost/deployment.json.
The user terminal was not stopped. Reload an attached EA to ensure it is
executing the updated binary.

Reusable validation: `scripts/validate_target_cost.ps1`; new feature probes
and checks live in `tests/mql5`.
