# EntryLab historical tick availability

## Finding

On the connected Exness-MT5Trial15 server, BTCUSDm returned its first quote
at 2026-01-01 00:00:05 when queried from dates in 2021, 2024 and 2025.
The requested older one-hour ranges returned zero ticks with error 0 on
three attempts each. This is evidence of a server/data boundary for this
symbol/account/server, not a general assertion about every Exness server.

## Fresh Download Probe

No-order isolated worker, 2026-10-03. Compile: 0 errors, 0 warnings.
Runtime: 50.359 seconds. Connected throughout the requests.

| Requested broker time | COPY_TICKS_ALL | M1 candles | M5 candles |
| --- | ---: | ---: | ---: |
| 2021-10-04 12:00-13:00 | 0, three attempts, error 0 | 60 | 12 |
| 2024-10-04 12:00-13:00 | 0, three attempts, error 0 | 60 | 12 |
| 2025-10-06 12:00-13:00 | 0, three attempts, error 0 | 60 | 12 |
| 2025-12-15 12:00-13:00 | 0, three attempts, error 0 | 60 | 12 |
| 2026-01-02 12:00-13:00 | 2167, error 0 | 60 | 12 |
| 2026-09-17 12:00-13:00 | 6409, error 0 | 60 | 12 |

The first old-range request spent 28.640 seconds performing history access;
later requests completed immediately. CopyTicks(INFO, old_date, 1) consistently
returned 2026-01-01 00:00:05. Real quote controls in 2026 succeeded.
Evidence: `.tmp/orb_jp225_full_worker/MQL5/Files/EntryLabTickAvailability.txt`.
Probe: `.tmp/EntryLabTickAvailability.mq5`.
Runner: `.tmp/run_entrylab_tick_availability.ps1`.

## Why Longer Candle Audits Can Exist

`EntryEngineLabEA.mq5` checks early tick coverage for `LabPolicyEnabled()`
independently of chart timeframe. Those policy engines require real quote
fills for their additional rule/time exits. Inverted audits also refuse
missing ticks. Non-policy, non-inverted engines retain an existing candle
fallback after tick replay is unavailable. A completed five-year candle or
mixed-data audit is not proof of five years of real tick coverage.

Tick APIs accept symbol/date/flags, not a candle timeframe. M1 and M5 cannot
have different tick histories for the same symbol/server. If otherwise
identical policy settings complete on M5, investigate that exact run rather
than infer that switching timeframe unlocks older ticks. We did not reproduce
the user's five-year M5 configuration in this diagnostic.

## Limits And Outcome

MT5 automatically synchronizes requested tick history from the trade server.
Requests can time out with partial data; such a response is not a completed
download. In this fresh test all cited responses had error 0, older ranges
remained empty after retries, and newer controls succeeded.

References:
- https://www.mql5.com/en/docs/series/copyticks
- https://www.mql5.com/en/docs/series/copyticksrange

Use the available 2026 tick period for strict-policy research, or obtain a
data source with the required historical bid/ask coverage. Another feed is
not automatically execution-equivalent to this broker. Candles cannot recover
the missing quote path or prove exact historical exits. No production source,
compiled EA, strategy, audit semantics or deployment was changed.
