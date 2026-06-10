# NAS Ultimate V2 Backtest Guide

## Files

- EA: `NasUltimate_SATS_V2_EA.mq5`
- Adaptive core: `NasUltimate_V2_Core.mqh`
- Fast tester preset: `EaPresets/NAS/V2/Backtest/NasUltimate_SATS_V2_Backtest_1to2R.set`
- Live preset: `EaPresets/NAS/V2/Normal/NasUltimate_SATS_V2_Live_1to2R.set`
- FTMO live preset: `EaPresets/NAS/V2/FTMO/NasUltimate_SATS_V2_Live_1to2R_FTMO.set`

V1 remains separate and unchanged by V2.

## Tester Setup

1. Use MT5 Strategy Tester with "Every tick based on real ticks".
2. Start with one symbol and timeframe at a time.
3. Use at least 12 months of data where available.
4. Keep the final 20-30% of data completely out of optimization.
5. Load `NasUltimate_SATS_V2_Backtest_1to2R.set`.
6. Use the custom optimization criterion. `OnTester()` rewards net profit, profit factor and trade count while penalizing relative equity drawdown.

## Walk-Forward Process

1. Train: optimize on the first 60% of the period.
2. Validate: select robust parameter regions on the next 20%.
3. Test: run the untouched final 20% once.
4. Repeat using rolling windows.
5. Reject isolated parameter peaks. Prefer broad neighboring ranges with similar results.

## First Parameters To Optimize

- `InpV2MinimumQualityScore`: 50 to 75, step 5
- `InpV2MinVolatilityRatio`: 0.50 to 0.90, step 0.05
- `InpV2AdaptiveBaseMultiplier`: 2.2 to 3.4, step 0.2
- `InpV2AdaptiveVolatilityWeight`: 0.6 to 1.8, step 0.2
- `InpV2HigherTimeframe`: H1 and H4 in separate runs
- `InpV2BuyMinRsi`: 40 to 50, step 2.5
- `InpV2SellMaxRsi`: 50 to 60, step 2.5
- `InpV2LearnerResolutionBars`: 15 to 60, step 15

Do not optimize every parameter simultaneously. That produces overfit results.

## Causality Guarantees

- HTF confirmation uses only an HTF candle closed by the signal decision time.
- The learner uses only older signals whose TP1/SL result was already knowable.
- A candle touching TP1 and SL in the same bar is counted as a loss.
- Tester fast mode disables dashboard and CSV writes, not execution logic.

V2 defaults are research defaults, not profitability claims. Promote a configuration to live use only after out-of-sample and forward-demo validation.
