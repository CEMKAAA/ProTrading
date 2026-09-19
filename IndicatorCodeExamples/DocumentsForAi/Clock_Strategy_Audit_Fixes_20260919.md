# Clock, saved strategy and audit-data fixes

## Dashboard and saved strategies

- ORB / ORB StrategyLibrary: top-right `TIMEZONE SETTINGS` opens a modal selector.
- Select broker UTC offset, broker clock profile, broker season, exchange season,
  and optionally BIST cash. Click `APPLY TIMEZONE`, then `SAVE STRATEGY` in the
  StrategyLibrary EA to retain it. Applying queues a new historical audit.
- Broker offset is NOT exchange local time. A GMT0 broker stays GMT0 when trading
  BIST. BIST cash selection uses 10:00-10:15 Turkey local time (UTC+3), ending at
  18:00. This is not a futures, auction, holiday or half-day calendar.
- Existing built-ins and old user files retain their previous default clock.
  No saved strategy files are bulk-migrated or rewritten by deployment.
- Named broker profiles supply their own base offsets. The fixed/legacy profile
  uses the selected offset. Forced standard/daylight applies to ALL audited dates.
- The older standalone Channel EA retains its F7 clock inputs; the new modal is
  in the main ORB and StrategyLibrary variants, which already support channels.
- MA user strategies now store INDEPENDENT/LEGACY and MAX SERIES. Old files without
  this metadata default to LEGACY/1; unknown old values cannot be reconstructed.
  Re-save an old independent preset once with its intended settings.
- SAVE with a matching user-strategy name (case insensitive, trimmed) atomically
  updates that slot/identity under the existing cross-terminal save lock.
  Built-in strategies are read-only. Use a different name for their custom copy.
- Mode/clock settings are included in saved-strategy metrics keys.
- Liq normal, invert, Sol and Advanced, including channel variants, scale their
  dashboard objects to chart dimensions. Very small charts necessarily reduce
  text size; maximize the chart for readability. No signal formulas changed.

## Audit and SOLUSDm observation

CopyTicksRange can return a positive count with a synchronization timeout.
Previously the audit could consume/cache that partial range as complete.
Tick reads now reject errors and partial responses. Pending ranges are DATA,
not a fabricated W/L. OHLC fallback also checks errors and the signal-bar prefix.
The ADV disk index schema is bumped so potentially incomplete old indexes are
not reused. First rebuild may cost more; subsequent complete indexes are reused.

This is not a claim that a broker's successfully returned data is perfect or that
the two screenshot trades have been fully reconstructed. The supplied screenshots
show SOLUSDm sells on September 3. An isolated quote probe observed a $1.20 Ask-Bid
spread: at 06:05 Bid=100.0898, Ask=101.2898. One read returned 30,045 ticks with no
error; later reads returned the same count WITH error 4403, confirming why count
alone is not a completeness guarantee.

BUY enters Ask and exits Bid; SELL enters Bid and exits Ask. A Bid chart touching
a sell target is not proof of an executable TP. White history lines deliberately
remain simulated fills, NOT candle closes. Their tooltip now explains this;
moving them onto the candle would hide spread/gaps and misrepresent geometry.

## Verification

`scripts/validate_clock_save_ui.ps1 -RunProbes` compiles the EAs in an isolated
build directory. It runs order-free probes, creating/removing only uniquely named
test presets, never attaching or starting a trading EA.

- MA save/load/update: 11 checks.
- ORB clock metadata, BIST conversion and same-name updates: 210 checks.
- Calendar/legacy offset regression: 40,311 checks.

Compilation and these probes are not live-order, full strategy-campaign, or
visual click-through certification. Install script verifies hashes and keeps
backups; existing chart instances must be reloaded separately by the user.

References:
- https://www.mql5.com/en/docs/series/copyticksrange
- https://www.borsaistanbul.com/en/markets/equity-market/trading-hours
