# Replaceable Champion Slot (R7)

R7 is now a per-strategy **deployment slot**, not a permanently fixed model family.
The UI keeps the R7 name for continuity. Nothing automatically chooses the highest
backtest score or enables trading. Research promotion remains an explicit decision.

## Supported Providers

- `ORB_R7_LOGISTIC1`: the existing dated logistic/calibration archives, unchanged.
- `ORB_MLP1`: existing 40-feature, 16-hidden-unit ReLU neural network format.

Weights, calibration, threshold, dated states and the active provider can be replaced
without recompiling the EA when they satisfy one of these contracts. A new architecture
(e.g. transformer/HGB) or different feature semantics needs a tested adapter/schema
upgrade first. Arbitrary joblib/pickle/ONNX files are deliberately NOT executed.

## Layout

Under MT5 Common Files:

```text
OrbML/Slots/Artifacts/<sha256>.model
OrbML/Slots/<strategy_id>/Releases/<revision>.slot
OrbML/Slots/<strategy_id>/active.slot
```

Artifacts and release manifests are immutable. Only `active.slot` changes, through
an atomic same-directory replacement. A process-scoped writer lock prevents two
writers racing; a mandatory expected-current revision catches stale promotion commands.
A failed/interrupted replacement leaves the previous pointer intact. Rollback is
the same operation pointing to an existing verified release.

Manifests bind strategy ID, configuration, feature schema/order, dataset checksum,
symbol, broker, chart TF, runtime settings, custom preset hash and input signature.
The artifact SHA-256 is verified independently of the manifest checksum. These are
integrity checks, not digital signatures: the local filesystem/operator is trusted.
Do not allow untrusted users/processes to write the slot directory.

## Dashboard Behavior

1. Select the strategy normally.
2. Choose `MODEL: R7 / CHAMPION SLOT`.
3. `LOAD TRAINED` / `USE RESULT` loads and pins its assigned revision in memory.
4. `ML FILTER ON` remains a separate choice; model selection never enables it.

Revision is loaded on explicit reload, strategy application or EA initialization.
Changing files alone does not hot-swap a running instance. Existing active/pending
trade and export guards block manual reload/switching. Normal position exits continue
unchanged. A failed load makes the slot unavailable, not a silent Legacy fallback.
With ML ON, missing/corrupt/incompatible/expired models block new entries. ML OFF
retains the original strategy. No file I/O was added to per-signal inference.

State chronology is enforced for logistic archives; MLP validity starts more than
24 hours after its last training label. Older history is marked incomplete, not
passed off as OOS. Every package has an explicit end of validity. The migrated R7
packages still expire on **2026-10-01 broker time**; migration does not extend them.

## Package A New Model

Run from the workspace. `binding.json` contains the registered strategy's exact
`id, config, dataset, runtime_hash, custom_hash, symbol, broker, inputs, tf` values.
Do not guess or copy another strategy's identity. Dates below are integer broker
timestamps, consistent with dataset/model timestamps, NOT local Windows time.

```powershell
python scripts/orb_model_slot.py pack --binding binding.json --artifact candidate.model --revision candidate-v2 --valid-from START_EPOCH --valid-until END_EPOCH --output candidate.slot
```

New packages have **no leaderboard metrics by default**, so old model numbers cannot
appear under a new revision. Compute them using the exact bound completed dataset:

```powershell
python scripts/orb_model_slot.py evaluate --manifest candidate.slot --artifact candidate.model --csv strategy.csv --output evaluated.slot
```

Evaluation uses closed/feature-valid rows and rejects missing features in closed trades.
It verifies completion marker, strategy/config/dataset, then recomputes retained
trade count, WR, net R and closed-trade drawdown. This is a retrospective mask of
candidate trades, including training data, **NOT OOS validation or execution replay**.
Promotion must use separate untouched holdout/walk-forward evidence; this tool does
not certify absence of overfitting or choose the best model.

Stage before activating (replace placeholders):

```powershell
$slots = "$env:APPDATA\MetaQuotes\Terminal\Common\Files\OrbML\Slots"
python scripts/orb_model_slot.py stage --root $slots --manifest evaluated.slot --artifact candidate.model
python scripts/orb_model_slot.py list --root $slots
python scripts/orb_model_slot.py activate --root $slots --strategy STRATEGY_ID --revision candidate-v2 --expected r7-20260912
```

Use `--expected NONE` only for a strategy with no active release. Existing revision
IDs cannot be overwritten with changed weights OR changed metrics. Create a new
revision even for refreshed metrics. Activation does not alter the running EA's ML
toggle; use its guarded LOAD/USE RESULT when safe. Other instances remain pinned
until individually reloaded. The slot is strategy-scoped, not account-specific.

Rollback:

```powershell
python scripts/orb_model_slot.py rollback --root $slots --strategy STRATEGY_ID --revision r7-20260912 --expected candidate-v2
```

## Leaderboard

Vanilla / Legacy / R7 tabs remain. R7 reads the assigned revision's metrics on opening
the popup or changing its mode, caches them for rendering/sorting, and requires the
same strategy/config/dataset/date window as the comparison snapshot. Artifact hash
is checked. Missing/incompatible metrics show NO MODEL / unavailable, never zero
profit or the previous revision's score. Tooltip includes provider and revision.

The popup reflects the assigned disk release; the live instance may still be pinned
to an older release until LOAD. Live model identity appears in ML status/logs.
Browsing the leaderboard does not change the live model generation or ML ON/OFF.

## Migration / Validation

`orb_model_slot.py migrate` preserves all 52 original R7 archive bytes and metrics;
it only seeds unassigned slots. It does not overwrite an already assigned release
or Legacy model. Archived revisions consume space only per deliberate deployment,
not per tick. No automatic pruning deletes rollback history.

Relevant implementation: `OrbStrategyModelSlot.mqh`, `OrbStrategyR7Runtime.mqh`,
`scripts/orb_model_slot.py`. Tests: `tests/test_orb_model_slot.py` and the isolated
`scripts/validate_orb_model_slot.ps1` no-order MQL probe.
