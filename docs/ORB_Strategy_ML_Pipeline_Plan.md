# ORB Strategy Library ML Filter

## Scope and Safety

Only the experimental `OrbUltimateEA_StrategyLibrary.mq5` gains this pipeline.
Production ORB, NAS, Sol and listeners remain unchanged. The model can veto a
new entry, never invent a signal, change direction/geometry/risk, or veto a
protective exit. ML defaults OFF. Model scores are estimates, not guarantees.

## Tasks

- [x] Inspect current audit, strategy presets and NoronAglari reference.
- [x] Add deterministic closed-bar feature extraction shared by export and inference.
- [x] Add 5Y CSV export using existing audit results, completion marker and real progress.
- [x] Bind artifacts to preset, symbol, broker, chart/signal TF, configuration and feature schema.
- [x] Add chronological, purged train/validation/test workflow and portable neural-network model.
- [x] Add dashboard export/cancel/load/filter controls; fail closed for enabled invalid models.
- [x] Verify OFF source parity, causal guards, parser rejection cases, temporal splits and inference parity.
- [x] Compile, document usage and report verification limits.

## Verification Record (2026-09-05)

- Usage: `docs/ORB_Strategy_ML_Filter.md`.
- Final Python regression suite: 22 passed. Three warnings remain: one dependency
  deprecation and two synthetic-fixture convergence warnings. Real-data training
  converged; nonconverged deployment candidates are rejected by the trainer.
- 38 original signal/audit bodies unchanged except three named observer hooks;
  eight Backtest backend functions unchanged. Pinned baseline is recorded in the guide.
- Final EA compiled with 0 errors, 0 warnings in a staging directory; the resulting
  EX5 was copied back to the workspace. Live terminal copies were not replaced.
- Compiled MQL5 model probe: 37 vectors, zero failures, max probability error 2e-16.
- Real cached JP225m/M5 260-week export probe: 1,204 rows, zero missing features,
  1,676,335 bytes, completion checksum accepted by the Python reader.
- A real export caught FILE_TXT's CRLF conversion; the exporter now writes
  canonical UTF-8 bytes in binary mode. A regression guard covers this fix.
- Real-data training converged: 721 train / 241 validation / 241 test; one label
  purged; Python portable probability max error 1.67e-16.
- This is a technical acceptance example, not a winning-model campaign. Its test
  subset net R was +7.328 versus base +10.125; the candidate was NOT published.
- The export probe runs copied source with trading lifecycle handlers unregistered,
  tester I/O guards enabled and historical calculation entry explicitly allowed.
  It is not a live tick/order test or a dashboard visual acceptance test.
- No actual listener orders were sent. No trained model was enabled. Live demo
  forward testing and user dashboard acceptance remain deployment prerequisites.

## Dataset Contract

One row per base-strategy candidate surviving existing filters. These are
historical simulated trades, not a claim of broker fills. Export remains
unfiltered by ML so rejected candidates cannot disappear from future training.
Existing audit PnL/exit-time/exit-reason calculations are reused unchanged.
Unresolved/data-invalid rows remain visible but are ineligible for training.
Missing features are explicit, never converted into loss labels.

`f_` columns are the only model inputs. Features use closed bars at the original
signal's availability time, including deterministic bounded-warmup ATR/RSI/EMA,
price/volume context and causal regime snapshots. Outcome/exit/PnL columns are
labels only. Broker time is labeled as broker time; historical UTC is not guessed
using today's server offset.

Export requests the EA's existing 260-week (5Y UI convention) audit and changes
the audit display window to 5Y. It does not change strategy, PUB, NAT or risk.
Configuration changes/cancellation must invalidate an in-flight export rather
than silently combine settings. Missing broker history blocks completion.
Files are local Common Files artifacts, not internet downloads.

## Training and Activation

Training runs outside the terminal; no Python/HTTP dependency on the live entry
path. A small standardized ReLU MLP is exported as strictly validated numeric
weights and evaluated in MQL5. No executable pickle is loaded into the EA.
Training/scaling use the oldest partition only; validation selects the score
threshold, and the last chronological partition is untouched evaluation.
Labels overlapping later partitions are purged. No random train/test splitting.

The model bundle records dataset SHA-256, configuration SHA-256, schema and time
boundaries. Load/enable is explicit. ON with a missing, corrupt, mismatched or
not-yet-out-of-sample model blocks new entries; exits keep working. An existing
position or pending entry prevents changing the model toggle. Applying another
strategy never silently reuses the previous strategy's model.

Five years of one daily setup is still a modest sample for a neural network.
Report retention, net R, drawdown and baseline comparison, not WR alone. Running
46 strategy experiments is multiple testing; an untouched forward period is
still required before capital allocation. No profitability claims are implied.
