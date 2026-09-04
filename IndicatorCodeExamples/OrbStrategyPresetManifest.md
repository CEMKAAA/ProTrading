# ORB Screenshot Strategy Library

## Scope

- Experimental EA: `OrbUltimateEA_StrategyLibrary.mq5`
- Preset data: `OrbStrategyPresetLibrary.mqh`
- Production EA `OrbUltimateEA.mq5` is intentionally unchanged.
- The library contains 46 unique ORB presets reconstructed from the screenshot tree under `NikkeiHighAccuracy`.
- Two screenshots were excluded because they show the NasUltimate cockpit rather than ORB: `usdjpy0.4R.png` and `usdjpyEdge.png`.

## Safety Boundary

Applying a strategy changes only strategy-defining fields: signal TF/delay, target geometry, entry/exit model, pip SL distance, ORB filters, session/window policy, regimes, RF rules and NAS strategy controls.

It never changes account or execution ownership settings:

- risk percentage or risk-capital mode
- EA enable state
- PUB / ONLY / NAT
- bridge channel
- magic / ownership scope
- FTMO or account guards
- audit window

Application is rejected while a native position, bridge lifecycle, NAS-managed lifecycle or historical audit is active. A symbol-family mismatch is also rejected. If PUB is on and the selected preset changes Signal TF, application is rejected until PUB is disabled; this prevents a listener with an old `Source TF Filter` from silently missing the new stream.

## Dashboard Flow

The dashboard uses two columns: trading controls on the left, strategy search
and favorites on the right. The Backtest Engine UI is hidden; its backend,
data structures and execution hooks are unchanged. The 704-pixel layout scales to the available
chart width and height when the chart is resized. Maximize a small chart for
larger text. The search popup stays directly below the search/filter controls;
its `X` button closes it without applying or clearing a strategy.

1. Type part of a PNG/strategy name in `STRATEGIES`.
2. Optionally enter minimum values in `R >=`, `WR >=` and `MC >=`.
3. Press `APPLY FILTER`; active criteria are combined with `AND`.
4. Press `SEARCH` or finish editing with Enter.
5. Select one result from the popup.
6. Verify `PICK`.
7. Press `APPLY STRATEGY`.
8. Verify `CURRENT` and the normal dashboard settings.

Selecting a row alone never changes trading behavior. Only a successful apply does so. Manual changes to a strategy field turn `CURRENT` into `CUSTOM`.

### Favorites

- Click `+` beside a result to save it; `*` means saved. Click `*` to remove it.
- Switch `ALL STRATEGIES` to `FAVORITES ONLY` to browse saved strategies without typing a name.
- Switching this view clears the name search but retains the metric filters. Favorites still must match those filters.
- Favorites survive EA/terminal restarts. Each stable preset ID has its own marker under `Terminal\Common\Files\OrbStrategyLibraryFavorites\`; charts do not overwrite a shared list. Strategy Tester runs do not change these preferences.
- Favorites only affect browsing. Saving/removing a favorite never applies a strategy, changes risk, or publishes an event.
- Popup controls now remain allocated during tick/timer refreshes. An overlay click guard also prevents clicks inside the popup from activating covered dashboard controls.

`CLEAR` removes all three metric filters. An empty metric field disables that criterion. `MC >= -3`, for example, keeps strategies whose worst cumulative 1Y result did not fall below `-3R`.

## Frozen 1Y Metrics

Every dropdown result includes `R`, `MC` and `WR`:

- `R`: total net R over the benchmark window
- `MC`: minimum cumulative R reached during that same run
- `WR`: wins divided by resolved wins plus losses

The 46 presets were audited individually with the EA's exact advanced audit lifecycle and then frozen into `OrbStrategyPresetLibrary.mqh` as presentation/search metadata.

- Benchmark end: `2026-09-02 23:50` broker time
- Window: `52 weeks`
- Engine: `ADV_EXACT`
- Source symbols: `JP225m`, `USDJPYm`, `USTECm`, selected by preset family
- Audit output: `tmp/orb_strategy_preset_metrics_1y.csv`

These frozen values do not participate in signal generation, execution, bridge publication, risk sizing or trade lifecycle decisions.

## Presets

### JP225

1. `0.5RsetupAdvanced`
2. `2RModeljp225`
3. `jp2250.5RSetupV2`
4. `jp2250.5RUltimateSetup`
5. `jp225HighProbaLongWait`
6. `jp225HolyGrail`
7. `JP225nOFilter1R`
8. `0.25RFiltersNone`
9. `jp2250.5Model`
10. `jp2250.5RHighFrequencyIfYouDontWannaWait`
11. `jp225Nas0.25RNewMode`
12. `jp225Use8000pips`
13. `jp225VeryHighWRWithGateState`
14. `jp225WithNas`
15. `veryHighWRjp225OrbNasNewMode`
16. `4Kaybetmeden4KazanmaChallengeModeli`
17. `DISP1RModelIsSolid`
18. `FirstTF5ChartJP225`
19. `JP2251RSetup`
20. `JP225DISP_ON_IBM1_SETUP_Edge`
21. `LiqNarrative1.5RModel`
22. `LiqNarrativeFvgONRetestVolOn1.5RSetup`
23. `Muhtesem4lu #1`
24. `NikkeiOrbBestSoFar`
25. `0.20RStarJp225`
26. `0.5RSetupJp225GateOn`
27. `jp225O.5RStar`

### USDJPY

1. `0.5RGoodUsdjpy`
2. `40pipusdjpyMasterSystem`
3. `goodPractice`
4. `HolyGrail [USDJPY]`
5. `usdjpyOrbGM0Edge`
6. `0.20R [USDJPY]`
7. `0.25RUsdJpy`
8. `0.10R_Setup`
9. `0.25RYildiz`
10. `1RAlternatif`
11. `1RYildiz`
12. `usdjpyGateStateOn`
13. `ProUsdJpySetup`
14. `UsdJpyUse`
15. `usdjpyWorthTrying`
16. `Muhtesem4lu #2`
17. `Muhtesem4lu #3`
18. `Muhtesem4lu #4`

### USTEC

1. `DISPONUsefullFirstTimeUstecOrb0.5R`

## Legacy Screenshot Mapping

Older screenshots contain one `NAS VOL` control. The current ORB architecture separates this into State Volume and Flow Volume. For those screenshots, the same legacy ON/OFF and multiplier are applied to both current policies. This preserves the behavior of the old single-volume implementation instead of guessing a new split configuration.

Exact values and source-image paths are versioned in `OrbStrategyPresetLibrary.mqh`. Run `scripts/validate_orb_strategy_library.ps1` after any preset or EA change.
