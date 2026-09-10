# Strategy Library Leaderboard (v6.88)

## Usage

Open **LEADERBOARD**, beside the pair filter in the right strategy panel.
Switch **NO ML FILTER** / **ML FILTERED [RESEARCH]**. Arrows change page; X
closes the overlay. A row directly applies the preset through the SAME
lifecycle/symbol/publisher guards as **APPLY STRATEGY**. No leaderboard action enables ML,
trains a model, changes account risk, changes channels, or opens a trade.

The overlay consumes clicks on covered controls and covered edit events. It
renders at most seven rows and does not scan chart history objects to rank them.

## Ranking

`score = 100 * WilsonLower(wins / trades, z=1.96) / (1 + MaxDD_R)`

Wilson's lower bound discounts small samples. A higher WR and a smaller closed-
trade drawdown increase the score. Ties are deterministic by preset ID. This
score is descriptive, not a profit forecast, selection significance test, or
challenge recommendation. Correlated trades weaken an independent-binomial
interpretation of Wilson's bound. Profitability is shown separately as net R;
a high score does not make a negative-R strategy profitable.

Every row shows score, WR, peak-to-trough closed-trade MaxDD in R, net R and
trade count. Zero-trade models and unavailable models are not artificial winners.
MaxDD is NOT MinCum, floating equity drawdown, monetary drawdown or an EOD
trailing challenge violation count. Different R geometries can rank differently
for structural reasons; inspect geometry and trade retention before comparing.

## Comparable Snapshot, Not Current Audit

The data are the frozen 2026-09-09 campaign's final chronological 20% test,
not all five years of training+validation+test. ML and baseline for each preset
use exactly the same test population and cost assumptions. Test dates differ
across presets and are in each row's tooltip. New strategies without campaign
results are not assigned fabricated ranks. Edited current settings do not
rewrite this historical snapshot. Existing search filters still operate on
their original 1Y library metrics, not this separate leaderboard.

There are 53 baseline rows and 50 presets with a selected research model.
For a preset with both MLP and return candidates, the displayed family is
chosen by validation net-R uplift, never test WR, test DD or final score.
Thus the table need not show the highest hindsight test score from either
family. Ranking on the displayed test does not turn it into new independent
validation; do not optimize repeatedly against this leaderboard.

Every current filtered row is **RESEARCH**. No candidate passed the previous
statistical publication gates. At the user's explicit request v6.87 supports
experimental use of the frozen MLP, ridge and HGB models without retraining.
These rows remain counterfactual veto results, not a stateful live portfolio
replay. Statistical evidence was not upgraded by making inference available.

v6.88 also connects ML ON to the chart's selected historical audit window:
W/L, net R, DD and trade drawings are rebuilt. ML OFF restores the base view.
This does not rewrite the frozen leaderboard snapshot. The chart marks
training-period inference as in-sample and exposes keep/reject/error counts;
the ML status tooltip contains the full summary and post-cutoff W/L/net R.

## Automatic Model Association

On **APPLY STRATEGY**, and on EA initialization, the runtime now attempts to
load the published file for the exact active configuration:

`Common\Files\OrbML\Models\<configuration_hash>.model`

A matching published model does not need retraining every time the strategy
is selected. ML ON/OFF is preserved, not silently enabled. A missing or
mismatched model while ML is ON remains fail-closed for new entries. Existing
protective exits remain independent of an entry veto. Candidate files are
never promoted by this selection handler.

If no published model exists, v6.87 loads the selected experimental campaign
model automatically, without enabling ML. Use **ML FILTER ON** to opt in.
**LOAD TRAINED** reloads it. **USE RESULT**, when no dashboard training job is
selected, resolves the existing campaign model directly; no CSV selection is
required. The dataset row shows the campaign archive, with its full path in
the tooltip. **TRAIN MODEL** is for a new export/training job, not needed to
use the 50 existing trained strategy models. Three strategies did not have
enough data to train; their CSVs exist but no model is fabricated for them.

Experimental models live separately under
`Common\Files\OrbML\CampaignModels\<preset_id>.experimental`.
The adapter preserves original weights, threshold, dataset checksum and
cutoff. MQL inference supports the original 40-feature MLP and the 50-feature
ridge/HGB return models. Return models whose frozen validation decision was
pass-through retain that behavior (`NO VETO`); no new threshold was optimized.

This is a verified, explicit compatibility adapter, not a generic hash bypass.
Build-time checks compare 38 signal/audit bodies, the feature extractor and
six shared source contracts against the training snapshot. A mismatch disables
campaign loading. Runtime checks bind preset ID, broker, symbol, chart TF,
input signature, strategy values, regime/RF switches and model checksum.
Decimal settings are canonicalized to 12 decimals to avoid binary roundtrip
noise; names and legacy inferred family labels are not model features.
Simulator fill-cost observations are not used as live settings identity; all
40 strategy runtime values are checked. Campaign cost assumptions remain
documented, not represented as current broker fill guarantees.

Changing applicable strategy values invalidates the model. Recompiling a
UI-only compatible build does not require fitting those weights again. If
ML is already ON and a load fails, new entries remain blocked, not silently
unfiltered. No assistant tool turned ML ON on an active chart.

## Rebuilding the Snapshot

```powershell
python scripts/build_orb_leaderboard.py --campaign logs/OrbMLCampaign_20260909_v3/training_v1 --header IndicatorCodeExamples/OrbStrategyLeaderboardData.mqh
```

This reads completed datasets/reports; it does not fit anything or activate a
model. Structured details are also saved as `training_v1/leaderboard.json`.
The generated MQL header is a read-only dashboard dependency.

Deployment evidence is in `logs/demo_sync_20260909_v686/` and
`logs/demo_sync_20260909_v687/`: per-EA compile logs,
file plan, backup tree, and final SHA-256 verification manifest. Unmatched
vendor/legacy files are listed separately, not claimed current or deleted.
