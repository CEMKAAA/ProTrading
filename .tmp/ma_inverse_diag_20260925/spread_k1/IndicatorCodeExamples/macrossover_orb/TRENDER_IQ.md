# Trender IQ signal mode

Source: `IndicatorCodeExamples/TrendFollow.pine`, Trender [IQ] by Trading-IQ,
Mozilla Public License 2.0. `MaTrendFollowCore.mqh` is the attributed port.

Select **Trender IQ** in the MaCross SIGNAL MODE row (mode ID 5).
The existing five mode IDs and equations are unchanged. Strategy save/load
accepts the new ID; existing presets retain their previous mode.

## Configuration and semantics

This first integration uses the Pine defaults, fixed in this mode:
Balanced speed, Steady pursuit, Close source, Log Geometry ON.
Other Pine speed/pursuit/source configurations are not exposed yet.

- A confirmed transition to rising (green) emits BUY.
- A confirmed transition to falling (purple) emits SELL.
- Holding (gray) emits no entry and no additional exit instruction.
- A persistent rising/falling leg does not emit an entry on every bar.
- Existing MaCross filters, independent/legacy policy, reversal exits and
  geometry still determine admission and management of the raw signal.

Live and audit use the same sequential McPineKernel. Processing is O(N) with
constant kernel state. The live kernel advances only on newly closed bars.
State starts from the broker history origin, not the selected audit-window edge.
The revision participates in the existing audit cache identity.

## Causality and parity limits

The reviewed signal equations use no future prices, lookahead request, or
backdated pivot. Brain initialization uses the first nonzero true range;
therefore changing history origin or broker candles can change the state.
Closed-bar signals are used, not the unfinished candle's provisional color.
Historical bar corrections or newly downloaded earlier data can change replay.

Pine's last-bar ghost forecast is a drawing, not a signal input, and is NOT
used for trading. Its glow, rail graphics, radar and projections are not ported;
the EA uses its existing signal arrows and trade-level drawing.

Tests: 3000 deterministic OHLC bars, 12000 comparisons covering rail price,
state, transition signal, shared-kernel output and flat initialization.
102 transitions match an independent scalar translation of the Pine defaults.
Six prefix checks confirm reference history does not change when extended.
These are equation tests, NOT an exported TradingView-feed parity test.
TradingView/MT5 parity additionally requires identical OHLC, minimum tick,
history origin and the stated Pine settings. Production profitability is not
established by these tests.

Probe: scripts/validate_ma_trender.ps1
Reference: scripts/check_trender_reference.py
Evidence: .tmp/ma_trender_20260921_190052
