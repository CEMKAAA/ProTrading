# Audit Modes And Native Position Recovery / 2026-10-03

## Scope

This follow-up directly compares current Normal/legacy and ADV paths. The earlier acceleration campaign compared frozen pre-change ADV with accelerated ADV, which is a different regression question. Sol has one current audit engine; its accelerated/reference-loop comparisons are documented in `audit_acceleration_20261003.md`.

Only verification scripts, probes and this report were added. No production EA/header/binary, listener, strategy, account filter or broker position was changed. Probes do not invoke production OnInit, entries, position closes or bridge publishers. Native recovery uses deterministic API fixtures, not newly placed demo orders.

## Direct Mode Parity

- Orb / USDJPYm: 96 paired exact tick cases.
- MaCross / BTCUSDm: 96 paired exact tick cases.
- Entry Lab / XAUUSDm: 96 paired exact tick cases.
- Each pair compares every HistResult field with exact equality, not just W/L totals or an R tolerance. Cases vary direction, inversion, 0.5R/1R/3.5R, pip distance, commission, slippage, HC and a forced reverse-exit time.
- Both engines must successfully use tick history for every case. No OHLC fallback, DATA result, shadow-parity fallback or result substitution counts as a passed pair.
- Fixture ticks are explicitly synchronized before comparison. An initial USDJPY run had one unavailable cold read and was rejected, despite matching its other 95 pairs; the complete readiness-guarded rerun passed all 96.
- Current full MaCross and Entry Lab pipelines were also compared over 2W of XAUUSDm M1 Close/Reverse source events. Both engines read the same 220 raw events and fixed cutoff.

| Family / Target | Normal | ADV | Chronological Trace Comparison |
| --- | --- | --- | --- |
| MaCross / 1R | 215 trades, 107W/108L/0O, -1R | Identical | 215 rows match exactly |
| MaCross / 0.5R | 218 trades, 141W/77L/0O, -6.5R | Identical | 218 rows match exactly |
| Entry Lab / 1R | 215 trades, 107W/108L/0O, -1R | Identical | 215 rows match exactly |
| Entry Lab / 0.5R | 218 trades, 141W/77L/0O, -6.5R | Identical | 218 rows match exactly |

All pipeline runs have DATA=0. Each trace comparison preserves original order and includes source/entry/exit times, side, validity, closure, win flag, fill, SL, TP, exit price, net R, outcome and reason. Total: 866 paired pipeline trades plus 288 paired direct tick cases, with no differences in these workloads. This is not an exhaustive all-strategy/all-symbol proof.

## Restart Ownership

All four families identify native positions by symbol and RuntimeMagic. The chart-scoped magic depends on the saved ChartID and input magic; the Orb-derived families also have a risk-scoped magic convention. Reopening the same account and saved chart/profile with the same identity settings preserves ownership. Creating a new chart, changing magic/scope settings, or switching accounts is not equivalent to restarting the same instance.

The counter reads actual MT5 open positions, not the persisted consecutive-signal count. Positions closed by the broker while the EA is offline naturally disappear from the count. A newly created chart must not silently adopt foreign positions.

| Fixture Family | Checks | Failures |
| --- | ---: | ---: |
| MaCross | 13 | 0 |
| Entry Lab | 13 | 0 |
| SolAdvanced | 6 | 0 |
| Orb | 3 | 0 |

Fixtures test preserved magic on the same chart, different magic on a new chart, exclusion of foreign-magic positions and restored ownership counts. MaCross/Entry Lab additionally round-trip the existing independent-order state file with open exposure and verify that even a stored sequence count of 876 cannot block entry when actual OPEN occupancy is below MAX. Sol tests its per-direction cap and acceptance/rejection boundary. Orb tests ownership, not an Independent mode it does not expose.

MaCross/Entry Lab MAX currently limits total simultaneous instance-owned positions; Sol's NAS/Positions setting limits same-direction positions. These semantics were not changed. MaCross/Entry Lab still require supported independent geometry, native execution, PUB OFF and a hedging account. Missing/corrupt state or an ambiguous broker order remains fail-closed; these tests do not claim automatic recovery from every crash or deleted state file.

## Recorded BTC Sell

Read-only evidence:

- `C:\MT5\DEMO\MQL5\Files\ORB15_TradeAudit_20261003.csv`
- `C:\MT5\DEMO\logs\20261003.log`
- `C:\MT5\DEMO\MQL5\Profiles\Charts\Default\chart02.chr`
- `C:\MT5\DEMO\MQL5\Files\MaIndependent_8079593755012956550.state`

On October 3, broker time 09:35:02 (local computer 12:35:02), MaCross successfully opened SELL 0.01 BTCUSDm, `series=1 max=10`, retcode 10009. Its native position/order identifier is 2498295742. The later 14:45:02 broker-time SELL candidate (local 17:45:02) was recorded as `time_matrix_block`, not a capacity/order rejection. That is the specific later sell established by available logs; an unrecorded different event cannot be identified from these files alone.

The saved BTC chart ID is 63427768952448, InpMagic is 16092601, and the position/state magic is 4000016092601952448. This matches the current risk-scoped chart-magic calculation. Its independent state is confirmed (`uncertain=0`).

Independent/MAX does not bypass TIME MATRIX, NAS, direction, daily-loss/win limits, risk sizing, margin or broker validation. A setup arrow is not proof of a broker fill: the live accepted-signal visual can be drawn before the final execution guard, and historical arrows are audit results rather than native orders. The recorded TIME MATRIX rejection was not disabled or overridden.

## Files And Reproduction

- `scripts/validate_audit_modes_recovery.ps1`
- `tests/mql5/AuditNormalAdvParityProbe.mq5`
- `tests/mql5/NativePositionRecoveryProbe.mq5`
- Existing `tests/mql5/AuditPerfMaProbe.mq5` is reused by the isolated Pipeline mode without changing it.

Modes: Parity (Orb/Ma/Lab), Recovery (all four), Pipeline (Ma/Lab). Staged compiled sources, compile logs, results and traces are retained under `.tmp/audit_modes_recovery_*`. All final probe compilations require 0 errors and 0 warnings. No test replaces or deploys production files.

Read-only hash inspection compared 196 existing corresponding deployed MQ5/MQH/EX5 files with canonical workspace files: zero mismatches. This is a consistency check, not a new deployment.
