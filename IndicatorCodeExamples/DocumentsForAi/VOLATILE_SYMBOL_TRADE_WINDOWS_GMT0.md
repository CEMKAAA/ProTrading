# Volatile Symbols And Atomic Trading Windows - GMT0

Assumption: all times are GMT0 / broker server time like Exness GMT0. If broker server time differs, shift these windows by the broker offset. These are practical volatility windows for Atomic-style momentum/regime automation, not guaranteed exchange schedules. Avoid broker rollover / spread-widening windows, especially around 21:55-22:10 GMT0 unless explicitly tested.

## Usage Rules

- Prefer the primary window first; it is usually the cleanest liquidity/volatility zone.
- Use secondary windows only after forward/audit validation on that symbol and timeframe.
- For AtomicRegime, these windows are best used as allowed trade windows, not as signal math filters.
- For very wide-spread symbols, do not trade the first 1-5 minutes of a session if broker spread spikes.
- News can dominate all session logic. For XAU, US indices, GBP/JPY crosses and oil, major macro releases can invalidate normal behavior.

## Best Candidate Symbols

| Symbol / Group | Primary Atomic Window GMT0 | Secondary Window GMT0 | Why It Moves |
|---|---:|---:|---|
| HK50 / HK40 / HSI | 01:30-04:00 | 05:00-08:00 | Hong Kong cash open and post-lunch continuation. Strong intraday volatility, often good for regime/momentum. |
| JP225 / Nikkei | 00:00-02:30 | 03:30-06:00 | Tokyo cash open and continuation. Best early Asia index volatility. |
| AUS200 | 23:50-02:00 | 03:00-05:00 | Australia cash open overlaps late NY/early Asia liquidity. |
| DE30 / GER40 / DAX | 07:00-10:00 | 13:30-16:00 | Frankfurt/London open, then US overlap. Often clean breakout/regime movement. |
| FR40 / CAC | 07:00-10:00 | 13:30-16:00 | Paris/London open and US overlap. Similar to DAX, slightly less explosive. |
| UK100 / FTSE | 07:00-10:00 | 13:30-16:00 | London cash open and US overlap. |
| USTEC / NAS100 / NQ | 13:30-16:30 | 18:00-20:00 | US cash open is strongest. Afternoon continuation can work but is less consistent. |
| US30 / Dow | 13:30-16:30 | 18:00-20:00 | US cash open and post-lunch continuation. |
| US500 / SPX | 13:30-16:30 | 18:00-20:00 | US cash open; smoother than USTEC/US30. |
| XAUUSD | 07:00-10:00 | 13:30-17:00 | London metals flow, then NY macro/COMEX liquidity. |
| XAGUSD | 07:00-10:00 | 13:30-17:00 | Similar to XAU, usually more erratic. |
| GBPJPY | 07:00-10:00 | 13:00-16:00 | London open and London/NY overlap. Very volatile; spread/slippage matters. |
| GBPUSD | 07:00-10:00 | 13:00-16:00 | London open and NY overlap. Cleaner than GBPJPY. |
| GBPAUD | 07:00-10:00 | 00:00-02:00 | London GBP flow; Asia/Australia can also move it. Higher noise risk. |
| EURJPY | 07:00-10:00 | 13:00-16:00 | London and NY overlap. Strong when risk-on/off flows align. |
| USDJPY | 00:00-02:30 | 13:00-16:00 | Tokyo open and US rates/news window. |
| AUDJPY | 23:50-02:30 | 07:00-09:00 | Australia/Tokyo overlap; secondary London repricing. |
| AUDUSD | 23:50-02:30 | 13:00-16:00 | Australia/Asia open and NY USD flow. |
| EURUSD | 07:00-10:00 | 13:00-16:00 | London open and London/NY overlap. Most liquid, lower explosive volatility. |
| USOIL / WTI | 13:00-16:30 | 18:00-20:00 | NY energy session; inventory/news days can be extreme. |
| BTCUSD | 00:00-02:00 | 13:00-17:00 | Asia crypto flow and US risk session. 24/7, but spread/liquidity varies by broker. |
| ETHUSD | 00:00-02:00 | 13:00-17:00 | Similar to BTC, usually more beta/volatility. |

## Shortlist For Atomic Forward Testing

These are the symbols I would prioritize first for Atomic/AtomicRegime because they naturally produce enough volatility for SL/TP geometry:

1. HK50 / HK40: 01:30-04:00 GMT0
2. JP225: 00:00-02:30 GMT0
3. USTEC: 13:30-16:30 GMT0
4. US30: 13:30-16:30 GMT0
5. DE30 / GER40: 07:00-10:00 GMT0
6. XAUUSD: 13:30-17:00 GMT0 and 07:00-10:00 GMT0
7. GBPJPY: 07:00-10:00 GMT0
8. GBPAUD: 07:00-10:00 GMT0, secondary 00:00-02:00 GMT0
9. USOIL: 13:00-16:30 GMT0
10. BTCUSD / ETHUSD: 13:00-17:00 GMT0, secondary 00:00-02:00 GMT0

## Conservative Allowed Windows

If the goal is to reduce noise and avoid overtrading, use these tighter windows:

| Symbol | Conservative Window GMT0 |
|---|---:|
| HK50 / HK40 | 01:30-03:30 |
| JP225 | 00:00-02:00 |
| AUS200 | 23:50-01:30 |
| DE30 / GER40 | 07:00-09:30 |
| FR40 | 07:00-09:30 |
| UK100 | 07:00-09:30 |
| USTEC | 13:30-15:30 |
| US30 | 13:30-15:30 |
| US500 | 13:30-15:30 |
| XAUUSD | 13:30-16:00 |
| GBPJPY | 07:00-09:30 |
| GBPUSD | 07:00-09:30 |
| GBPAUD | 07:00-09:30 |
| USDJPY | 00:00-02:00 |
| AUDUSD | 23:50-02:00 |
| EURUSD | 07:00-09:30 |
| USOIL | 13:00-15:30 |
| BTCUSD | 13:00-16:00 |
| ETHUSD | 13:00-16:00 |

## Aggressive Allowed Windows

If the goal is to capture more signals and accept more chop:

| Symbol | Aggressive Window GMT0 |
|---|---:|
| HK50 / HK40 | 01:30-08:00 |
| JP225 | 00:00-06:00 |
| AUS200 | 23:50-05:00 |
| DE30 / GER40 | 07:00-16:00 |
| FR40 | 07:00-16:00 |
| UK100 | 07:00-16:00 |
| USTEC | 13:30-20:00 |
| US30 | 13:30-20:00 |
| US500 | 13:30-20:00 |
| XAUUSD | 07:00-17:00 |
| GBPJPY | 07:00-16:00 |
| GBPUSD | 07:00-16:00 |
| GBPAUD | 00:00-02:00,07:00-10:00 |
| USDJPY | 00:00-02:30,13:00-16:00 |
| AUDUSD | 23:50-02:30,13:00-16:00 |
| EURUSD | 07:00-16:00 |
| USOIL | 13:00-20:00 |
| BTCUSD | 00:00-02:00,13:00-17:00 |
| ETHUSD | 00:00-02:00,13:00-17:00 |

## Practical Preset Notes

- For `InpDirectMt4AllowedTradeWindowsGmt`, use comma-separated windows when needed, for example: `00:00-02:00,13:00-17:00`.
- Keep `InpDirectMt4NoTradeWindowsGmt=21:55-22:10` unless testing proves broker spread is safe.
- If using The5ers or another GMT+ broker, convert from GMT0. Example: if broker is GMT+3, `13:30-16:30 GMT0` becomes `16:30-19:30 broker time`.
- For Asia indices, exact CFD session availability depends on broker. If chart does not tick during a listed window, use the nearest active cash-open window observed in terminal logs.

## First Forward-Test Basket

Recommended first basket for Atomic/AtomicRegime:

| Basket | Symbols | Window GMT0 | Mode |
|---|---|---:|---|
| Asia Index | HK50/HK40, JP225, AUS200 | 00:00-04:00 | AtomicRegime + RiskLotOnly |
| Europe Index | DE30/GER40, FR40, UK100 | 07:00-10:00 | Atomic + AtomicRegime |
| US Index | USTEC, US30, US500 | 13:30-16:30 | Atomic + AtomicRegime |
| Metals | XAUUSD, XAGUSD | 13:30-17:00 | AtomicRegime preferred |
| GBP/JPY FX | GBPJPY, GBPAUD, GBPUSD, USDJPY | 07:00-10:00 | Atomic with stricter spread guard |
| Crypto | BTCUSD, ETHUSD | 13:00-17:00 | Atomic/Regime, only if broker spread stable |
