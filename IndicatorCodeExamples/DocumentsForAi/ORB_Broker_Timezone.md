# ORB broker clock profiles (2026-09-17)

## Compatibility
Default: InpBrokerClockProfile=Legacy, both season inputs=Auto, UTC+0.
Legacy uses exactly the previous conversion and saved strategy offset.
No saved strategy files are rewritten. Signal and opening-time rules are unchanged.
These are native MT5 Inputs dropdowns, not a dashboard popup.

## Setup
- Existing GMT0 broker: leave defaults unchanged.
- Different fixed broker: choose Fixed, then InpBrokerTimezone.
- UTC+2/+3 following US DST: choose New York Close, season Auto.
- Other automatic profiles: New York, Chicago, London, Central Europe,
  Eastern Europe (EU calendar), Sydney, Adelaide, Auckland.
- Tokyo broker: Fixed UTC+9. Hong Kong broker: Fixed UTC+8.
- Manual: Fixed/Custom, InpBrokerGmtOffsetHours. Offsets range -12 to +14.
  The dropdown has 105 choices in 15-minute increments, including fractions.

InpBrokerClockSeason: Auto / Force Standard / Force Daylight.
This applies to seasonal profiles only; Fixed and Legacy never shift.
Auto calculates the offset for each historical date, not from today's clock.
Manual season overrides affect ALL dates in the audit, not just today.

InpExchangeClockSeason independently controls seasonal exchange clocks.
Auto preserves the existing InpAutoNewYorkDst setting: keep it true for NY DST.
Tokyo and Hong Kong remain UTC+9/+8; they do not gain DST from these controls.
UTC00 override retains its existing behavior.

US 09:30 local opens at 13:30 UTC in summer and 14:30 UTC in winter.
A fixed UTC+2 broker shows 15:30/16:30; NY-close UTC+2/+3 shows 16:30 in both.
Japanese exchange opening has a fixed UTC time, but its broker-chart time
can change if the BROKER changes offset.

## Strategy and cache behavior
Broker profile is an installation input. Loading a strategy does not silently
replace it. A non-Legacy profile overrides the saved fixed offset. This allows
using the strategy on another broker. Legacy preserves saved timezone behavior.
Non-default policies enter the audit cache key and ML configuration identity.
Default cache key is unchanged. Dashboard displays effective broker offset.

## Limits
This is not a full IANA historical/political timezone database. Automatic rules
target the modern trading-history period (2016 onward). Unknown broker policy
changes, Morocco Ramadan exceptions and abolished historic DST require a custom
historical calendar, which is NOT included. Do not assume a broker's office
location determines its server clock. Fixed/manual offsets cover current clock
values, not every historical clock policy in the world.
Repeated autumn server timestamps cannot identify which occurrence was meant:
standard-time occurrence is chosen. Nonexistent spring timestamps return zero.
Different broker price feeds, daily bar boundaries and spreads can still change
results. Time alignment alone cannot guarantee identical broker backtests.

## Verification and deployment
scripts/validate_orb_timezone.ps1 compiles three EAs and runs 40,311 checks:
legacy offsets, daily identity/roundtrips for 2016-2026, US/EU transition
boundaries, southern seasons, manual overrides and DST gaps/folds.
This is clock regression coverage, NOT all-strategy outcome or live testing.
-InstallDemo backs up and SHA-256 verifies dependencies and EX5 files at
C:\MT5\DEMO\MQL5\Experts\orb and the workspace orb mirror.
It does not restart or attach trading instances. Logs: logs/orb_timezone.

Sources:
https://www.nist.gov/pml/time-and-frequency-division/popular-links/daylight-saving-time-dst
https://www.govt.nz/browse/recreation-and-the-environment/daylight-saving/
https://www.nsw.gov.au/about-nsw/daylight-saving
https://www.mql5.com/en/docs/runtime/testing

Pretrained Legacy/R7 campaign manifests do not bind the new seasonal policy.
They are rejected under non-default clock policies rather than silently reused.
Config-specific models use the new clock fingerprint; vanilla/Legacy behavior is unchanged.
