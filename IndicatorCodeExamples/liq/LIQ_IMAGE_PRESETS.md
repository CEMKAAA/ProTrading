# Liq screenshot presets

## Scope

Reviewed the headers of all 97 images under `ORB0.5`, then read all nine
Liquidity Narrative screenshots at full size. Source paths and SHA-256 hashes
are recorded in `LiqImagePresets.sources.json`.

Presets appear automatically in SEARCH for the exact photographed symbol and
EA family, including that family's Channel edition. No automatic cross-broker
symbol substitution: pip specifications may differ. SolVersion has no matching
screenshot in this directory; Advanced presets must not silently become Sol
presets because their signal engines differ.

| Preset | EA family | Symbol | HTF / Entry | Base R | Invert | Pip SL | DUP | Audit |
|---|---|---|---|---:|---|---:|---|---|
| LiqNarrative1.5RUstec | Normal | USTECm | H2 / M15 | 1.5 | OFF | 20000 | ON | 2W |
| ustec1RLiqSetup | Normal | USTECm | H2 / M15 | 1 | OFF | 30000 | ON | 2W |
| US500LIQNarrative | Normal | US500m | H2 / M15 | 1 | OFF | 3000 | ON | 20W |
| US30ReverseWorthTrying | Normal | US30m | H2 / M15 | 2 | ON | 600 | ON | 2W |
| SPX5001.5R | Advanced | US500m | H1 / H1 | 1.5 | OFF | 2000 | OFF | 10W |
| spx500AdvancedModelLiquidity | Advanced | US500m | H1 / H1 | 1.5 | OFF | 3000 | OFF | 2W |
| btcgoon | Advanced | BTCUSDm | H4 / H1 | 1 | OFF | 30000 | ON | 2W |
| BTCUSDLiqNarrative | Advanced | BTCUSDm | H2 / H1 | 1.5 | OFF | 20000 | ON | 2W |
| MightBeNewEdge | Advanced | JP225m | H1.5 / M15 | 2 | OFF | 4000 | ON | 10W |

All nine: Swing 5, HC OFF, weekly OFF, LEGACY entry, FVG1 stop,
FIX target, IRL/SWEEP/DISP/ASIA/SMT OFF, TGT ON, SL distance 100%,
ATR buffer 10%, pip SL ON. Advanced: RF master OFF, all six macro
regimes ALLOW, all twelve RF rules BLOCK (inactive while master OFF).
US30 keeps TP4 plus inversion ON, not TP1: its effective swapped ratio is 0.5R.

The files `LiqNarrative1.5RModel.png` and
`LiqNarrativeFvgONRetestVolOn1.5RSetup.png` actually show ORB15 COCKPIT.
They are deliberately not imported as Liq presets.

## Limits and safety

These are dashboard-setting presets, not reconstructions of hidden MT5 Inputs.
Unseen Inputs remain those of the current instance. The separate brute-force
BACKTEST ENGINE controls and historical performance figures are not imported.
No claim of identical historical PnL is made across builds, data feeds or Inputs.

Selecting a preset does not change risk, execution enable switches, bridge paths,
channels, ownership or account. Existing apply guards remain in force.
The nine built-ins are immutable; SAVE with the same name creates a user override.
An existing valid same-name user record wins. User files retain their input-contract
validation and are not overwritten by installation. Favorites are local files.

## Search regression

MQL's `StringFind(name, "")` rejected every record in the original empty-query
scan. The scan now bypasses substring filtering for an empty query. Zero matches
show `0 results`, not the misleading `1 / 1`. A successful SAVE clears search and
favorites restrictions and opens the results. Runtime tests cover save/read,
empty search, exact search, favorites, row rendering, symbol/family isolation and
the JP225 H1.5 preset.
