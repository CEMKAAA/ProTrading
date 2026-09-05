# ORB Strategy Library: Per-Strategy ML Filter

## Scope

EA: `IndicatorCodeExamples/OrbUltimateEA_StrategyLibrary.mq5`, build v6.81.
The ordinary ORB, NAS, Sol and listener sources are not modified by this feature.
The existing setup generator, trade geometry and audit outcome calculations
remain the baseline. ML can reject a new entry; it cannot generate an entry,
change its direction, resize it, or prevent the existing protective exits.

This is an opt-in research/filter implementation, not a promise of profitability
or a completed live production acceptance test. Start in demo with ML OFF.

## Dashboard Workflow

Start the local training worker once per computer session, from the workspace:

```powershell
.\scripts\Start-OrbMLWorker.ps1
```

It runs separately from MT5. No DLL imports, network listener, Python inside a
tick callback or trading API access is required. The dashboard shows WORKER
ONLINE/OFFLINE. Restart this helper after restarting the PC. It does not change
PUB/NAT or enable ML. An offline worker never silently trains or activates a model.

Then the complete user flow is:

1. SEARCH -> choose strategy -> APPLY STRATEGY.
2. CREATE 5Y CSV, or REFRESH to find an already completed export.
3. Choose a CSV with the arrows beside **CSV**. Only exports matching the current
   strategy, symbol, TF and configuration appear.
4. Press **TRAIN MODEL**. The independent worker validates the CSV and trains.
5. The second progress bar follows completed optimizer epochs plus validation,
   test and artifact-write stages. It is work progress, not a promised ETA.
6. Select a training run with the arrows beside **RUN**. The row shows its state,
   test net R versus base, WR and retained fraction. REJECTED is research-only.
7. For a READY result, press **USE RESULT**, then **LOAD MODEL** after PUBLISHED.
8. Enable **ML FILTER ON** explicitly when ready. Training, publishing and loading
   never automatically turn the filter on.

**CANCEL TRAIN** requests cancellation of the selected queued/running job. It is
checked between epochs/stages, not by interrupting a live order. Research files
already written may remain, but a cancelled job cannot be promoted. Interrupted
jobs fail visibly after worker restart and are never silently replayed.

Training runs are stored under `OrbML/Results/<config>/<job-id>`. CSV selectors
and run selectors are scoped; another strategy's artifacts are not shown.
Changing strategy clears the current selectors; an older job may finish in its
own namespace without installing a model for the new strategy.

Dashboard training uses a fixed 400-epoch Adam MLP with the same portable 40x16
ReLU architecture. This permits genuine epoch progress and cancellation via
the public `partial_fit` API. It is not bit-identical to the optional CLI's
L-BFGS optimizer; reports record the solver and epoch budget. Training-loss
stability and the existing validation/test checks are required for promotion.
No validation/test data chooses an epoch count. API reference:
[scikit-learn MLPClassifier](https://scikit-learn.org/stable/modules/generated/sklearn.neural_network.MLPClassifier.html).

## Save Your Own Strategy

Preset application explicitly refreshes the strategy edit fields (SL, volume,
NAS and entry window) from the applied runtime, including saved user presets.
Ordinary dashboard redraws still preserve unfinished edits. v6.81 fixes stale
text such as `100` remaining in the SL field after applying an 8,000-pip preset.
It does not change signal, risk, exit or listener calculations. As with any new
build, the conservative ML build binding requires fresh exports/models rather
than silently reusing a model trained for an earlier executable.

1. Apply the desired dashboard parameters first, including APPLY NAS/other
   parameter-specific APPLY buttons. Unapplied text edits are not live settings.
2. Enter a name in the bottom-right **SAVE CURRENT STRATEGY** section.
3. Press **SAVE STRATEGY**. The EA writes a checksummed record, reads it back and
   compares the full captured strategy state before marking it selected.
4. The saved name is now in the normal SEARCH list and can be favorited, exported
   and trained just like built-in strategies. It gets its own immutable ID.

The original 46 presets are not overwritten. Saved names must be unique; use a
new name for a variant. Simultaneous saves use an exclusive file lock and a
non-overwriting commit. Files persist in Common Files `OrbStrategyUserLibrary`.
Do not manually rename/delete numbered records: a stored identity check prevents
a reused slot from silently restoring a different strategy.

The record covers all captured strategy runtime fields, including NAS wait,
both NAS volume policies, inversion, SL/TP, HC/BE, session/window, macro/RF,
and simulation costs. **Account risk, channel, PUB/ONLY/NAT, magic number and
account safety controls are deliberately not switched by a strategy preset.**
The audit display window and audit-engine preference also stay independent.

Immutable EA Inputs cannot be changed programmatically while an EA is running.
Their signature, exact symbol and chart TF are therefore checked before applying
a user preset. If they differ, application is blocked with an explicit mismatch
message rather than silently approximated; use the same strategy-relevant Inputs
and chart context as at save time. This is not a replacement for a complete MT5
terminal `.set`/account configuration backup.

Saved strategies initially have no measured 1Y library metrics. They are not
assigned invented WR/R/MinCum numbers; clear numeric result filters if necessary
to find an unmeasured strategy. ML must be OFF when saving a new strategy identity.

## First Export

1. Select and APPLY a named strategy from the library on its matching symbol.
2. Wait for the current audit to finish.
3. In the right-hand **STRATEGY ML FILTER** section, press **CREATE 5Y CSV**.
4. Wait for **CSV READY**. The audit window becomes 5Y (the EA's existing
   convention: 260 weeks). The strategy, risk, PUB and NAT are not changed.
5. The Experts log prints the complete CSV path. The directory is:

```text
C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbML\Datasets
```

Keep the `.csv` and its adjacent `.csv.complete` file together. The completion
file binds configuration, row count, dataset identity and the SHA-256 of the
actual CSV bytes. `.partial` files, interrupted exports and altered completed
CSVs are not accepted for training. CANCEL stops the export, not trading.

The progress bar reports audit work first (0-85%), then rows written (85-100%).
It is not an elapsed-time estimate. Missing broker history is reported; the
button does not manufacture five years of unavailable prices. Missing feature
history is marked per row and reported in the final missing count.

An export rebuilds the base audit even when ML is ON. Otherwise rejected setups
would vanish from the training population and bias future datasets. Changing
settings or restarting the audit cancels the in-progress export.

## Optional Command-Line Training

The trainer requires Python, NumPy, pandas and scikit-learn. It does not connect
to terminals or place orders. From the workspace, replace the example filename
with the exported filename:

```powershell
python scripts/orb_ml_filter.py --csv "C:\Users\Cem\AppData\Roaming\MetaQuotes\Terminal\Common\Files\OrbML\Datasets\YOUR_EXPORT.csv"
```

Artifacts go into `Common\Files\OrbML\Models` by default:

- `<configuration SHA>.candidate.model`: numeric research model, NOT loaded by EA.
- `<configuration SHA>.report.json`: splits, exclusions, baseline, retained
  trades, win rate, realized net R and realized peak drawdown in R.
- `<configuration SHA>.vectors.csv`: input/output regression examples.

The first version uses 40 inputs, standardization and 16 ReLU hidden units.
It accepts at least 300 usable trades, with minimum purged partition sizes.
Scaling and weights use the oldest 60% only. The next 20% selects the threshold;
the newest 20% evaluates frozen parameters. Labels crossing a later partition
are removed, with a default 24-hour embargo. No random time-series split.

The report must be reviewed, including exclusions, retention and net R, not
only WR. Repeatedly choosing models using the same test period turns that period
into development data. Reserve genuinely new forward data, particularly when
comparing all 46 strategies. A classifier score is not a calibrated guarantee.

## Publish and Enable

1. After reviewing the research report, run the same command with `--publish`.
2. Publishing requires convergence, positive validation net R no worse than
   its baseline, and sufficient retained, positive-net-R test trades. Failure
   leaves an existing active model unchanged. These are minimum safeguards,
   not proof that the model improves the strategy.
3. On the EA press **LOAD MODEL**, then **ML FILTER ON**. These operations wait
   until the instance has no active/pending lifecycle. Training/publishing alone
   never enables trading or the filter.
4. The EA finds `<configuration SHA>.model` automatically. There is no model
   path to type into cTrader, NinjaTrader or Quantower.

Only new signals after the dataset's research cutoff can use the model. Existing
reverse-close handling runs before the ML entry veto. Rejected entries are not
published to listeners and are not opened natively. Risk/channel configuration
and listener CSV formats are unchanged.

ML defaults OFF. Its explicit ON/OFF choice is persisted for the chart/account.
If ON is restored but the model is missing, corrupt, mismatched or its features
cannot be built, new entries are blocked. It never silently bypasses an enabled
filter. Existing exit management continues. Changing strategies does not reuse
an unrelated model: export/train/load the matching configuration first.

The on-chart historical W/L/PNL remains the **base strategy audit**, not a replay
of ML-filtered execution. Offline selected-trade metrics are label-subset
metrics, not a simulation of all changed position-overlap/reversal effects.
That portfolio-level replay and real forward demo testing are separate checks.

## Data Contract

One row is one base historical simulated trade that survives the strategy's
existing filters, not necessarily a real broker fill. Entry, SL, TP, actual
simulated net R, cost R, exit time and exit reason come from the existing audit.
Unresolved/invalid labels are kept but excluded from training; missing data is
not converted to a losing label. `label_win` means net R > 0.

Only the `f_` columns are model inputs. Raw observations and outcome columns are
not automatically included in training. Export and live inference call the
same feature function at the original closed signal bar, including for a later
retest entry. Features do not read the eventual fill/exit or future candles.

Feature families:

- Candle body, range, wicks and returns normalized by ATR.
- ATR14, RSI14, EMA20/50 distances, slope and crossover; volatility ratio.
- Tick-volume ratio, price efficiency and historical spread/ATR.
- Broker-hour and weekday cyclic encodings.
- Six regime flags, regime age, trend/volatility depth, transition state and RF index.
- ORB range, relative distances, elapsed time from ORB end, direction and inversion.

ATR/RSI use Wilder smoothing; EMAs are seeded at the start of an exactly
256-closed-bar observation window. These bounded-warmup indicators deliberately
use identical seeding in training export and inference, rather than claiming
identity with an indicator initialized over all available history. Raw OHLC,
ATR and EMA observations are also exported for inspection.

All timestamps are explicitly **broker time**, not GMT. Historical DST offsets
are not inferred from today's broker offset. Causal regime availability is
checked; current regimes are never substituted for missing historical regimes.

## Configuration and Rebuilds

Model identity includes preset, symbol, broker, chart/signal TF, strategy/filter
settings, simulation costs, feature schema, source fingerprint and compilation
timestamp. Audit display window and risk sizing are not used to select models.
Incompatible settings fail closed rather than silently loading a nearby model.

Recompiling creates a new model binding even if the source appears unchanged.
Export, train and use the same compiled EX5. Deploy that EX5 and its associated
includes/source together for provenance; after a rebuild, create and validate
a fresh dataset/model. Runtime audit spread also belongs to the binding. If
`InpBacktestSpreadPts=0`, restarting with a different observed spread can require
a new model; explicit stable audit costs avoid that ambiguity. Do not remove
cost binding merely to make an old model load.

Developer build order:

```powershell
.\scripts\build_orb_ml_contract.ps1
# Compile OrbUltimateEA_StrategyLibrary.mq5 in MetaEditor, NOT the .mqh files.
python -m pytest -q tests/test_orb_ml_filter.py
.\scripts\validate_orb_strategy_library.ps1 -OriginalGitRef 6061c4b536200c60e86e476c956efdeeb35cd1d2
```

Run `scripts/build_orb_user_strategy_contract.ps1` before the ML contract generator
when strategy runtime fields change. Run both ML test files, including
`tests/test_orb_ml_worker.py`, for dashboard queue/strategy persistence changes.

The numeric model has strict schema/config/checksum checks and no executable
pickle loading. A custom model trainer must implement this exact numeric
40x16 ReLU contract; arbitrary Python/Torch model files are not interchangeable.
The `NoronAglari` project was inspected as a reference, not modified.

## Verification Boundaries

The regression suite covers completion checksums, causal columns, purged time
splits, test-set isolation, portable prediction parity, mismatched models and
entry-gate placement. The source comparator checks 38 original signal/audit
function bodies (excluding three explicit observer hooks) and eight unchanged
Backtest functions against the pinned baseline.

A compiled MQL5 numeric-model probe passed 37 vectors, including malformed-model
rejection, with maximum Python/MQL5 probability difference about 2e-16. This
verifies inference arithmetic, not trading performance. No live account orders
or terminal restarts are part of these tests. No trained strategy model is
automatically deployed or enabled by this implementation.
