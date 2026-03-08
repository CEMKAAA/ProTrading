# Experiments Integration — Implementation Plan for Codex

## Overview

Integrate reusable algorithms from `Experiments/` into the Trader's Workbench. Four features, ordered by priority. Each feature has precise file references, formulas, and integration points.

**CRITICAL RULES:**
- Frontend is **Flask + Jinja2 + vanilla JS** (NOT React). Templates in `dashboard/frontend/templates/`, JS in `dashboard/frontend/static/js/`.
- Follow the existing `WorkbenchTool` ABC pattern in `dashboard/backend/core/workbench/tool_base.py` for any new chart tools.
- Register new tools in `dashboard/backend/core/workbench/__init__.py` (singleton in `WORKBENCH_TOOLS` dict).
- All new backend code must be importable with `python -m py_compile`. All new JS must pass `node --check`.
- Do NOT modify the FVG tool (`fvg_tool.py`) or the indicator system already in `workbench.js`.
- Read the referenced Experiments files THOROUGHLY before coding — match their formulas exactly.

---

## Feature 1: Spread-Aware Cost Model for Paper Trades

**Priority:** HIGH — directly improves realism of all Workbench paper trading.

### Source Reference
- `Experiments/IterativeBase.py` lines 67-122: `buy_instrument()`, `sell_instrument()`, `close_pos()`
- `Experiments/ConBacktester.py` lines 59-63: vectorized turnover cost (`trades = position.diff().abs(); strategy -= trades * tc`)
- `Experiments/MeanRevBacktester.py` lines 90-93: same turnover cost pattern

### What to Build

A cost model that applies to Workbench paper trades (both manual entries and copilot AUTO_PAPER_ENTRY/EXIT). Two cost components:

1. **Spread cost per fill**: When a paper trade opens or closes, apply half-spread to the fill price.
   - Buy fills at `ask = mid + spread/2`
   - Sell fills at `bid = mid - spread/2`
   - Source: `IterativeBase.py:72` (buy), `IterativeBase.py:85` (sell), `IterativeBase.py:114` (close)

2. **Turnover cost per round-trip**: Proportional cost deducted from PnL on each position change.
   - Cost = `|position_change| × tc_rate`
   - Source: `ConBacktester.py:60-63`

### Default Spread Table (per instrument)

```python
INSTRUMENT_SPREAD = {
    "XAUUSD": 0.30,    # 30 cents Gold
    "NAS100": 1.5,     # 1.5 points NAS
    "US500":  0.5,     # 0.5 points S&P
    "GBPUSD": 0.00015, # 1.5 pips
    "EURUSD": 0.00012, # 1.2 pips
}
DEFAULT_TC_RATE = 0.0001  # 0.01% proportional turnover cost
```

### Backend Changes

#### File: `dashboard/backend/core/workbench/cost_model.py` (NEW)

Create a simple cost model class (NOT a WorkbenchTool — this doesn't scan bars):

```python
class WorkbenchCostModel:
    """Spread + turnover cost model for Workbench paper trades."""

    def __init__(self, symbol: str, spread: float | None = None, tc_rate: float | None = None):
        self.symbol = symbol
        self.spread = spread if spread is not None else INSTRUMENT_SPREAD.get(symbol, 0.30)
        self.tc_rate = tc_rate if tc_rate is not None else DEFAULT_TC_RATE

    def apply_fill_spread(self, mid_price: float, direction: str) -> float:
        """Return the fill price after spread. direction = 'buy' or 'sell'."""
        half = self.spread / 2.0
        if direction == "buy":
            return mid_price + half   # ask
        else:
            return mid_price - half   # bid

    def compute_turnover_cost(self, position_change: float, price: float) -> float:
        """Proportional turnover cost for a position change."""
        return abs(position_change) * price * self.tc_rate

    def cost_summary(self, entry_price: float, exit_price: float, direction: str, lot_size: float) -> dict:
        """Full round-trip cost breakdown."""
        entry_fill = self.apply_fill_spread(entry_price, "buy" if direction == "long" else "sell")
        exit_fill = self.apply_fill_spread(exit_price, "sell" if direction == "long" else "buy")
        spread_cost = abs(entry_fill - entry_price) + abs(exit_fill - exit_price)
        spread_cost_total = spread_cost * lot_size
        turnover_entry = self.compute_turnover_cost(lot_size, entry_price)
        turnover_exit = self.compute_turnover_cost(lot_size, exit_price)
        total_cost = spread_cost_total + turnover_entry + turnover_exit
        return {
            "entry_mid": entry_price,
            "entry_fill": round(entry_fill, 5),
            "exit_mid": exit_price,
            "exit_fill": round(exit_fill, 5),
            "spread_per_side": round(self.spread / 2.0, 5),
            "spread_cost_total": round(spread_cost_total, 2),
            "turnover_cost": round(turnover_entry + turnover_exit, 2),
            "total_cost": round(total_cost, 2),
            "cost_as_points": round(spread_cost, 5),
        }
```

#### File: `dashboard/backend/api/simulation_routes.py`

In the existing paper trade open/close handlers (search for `AUTO_PAPER_ENTRY` and `AUTO_PAPER_EXIT` and the manual trade endpoints), apply the cost model:

1. When a paper trade is OPENED: adjust `entry_price` to include spread.
2. When a paper trade is CLOSED: adjust `exit_price` to include spread, deduct turnover cost from PnL.
3. Store cost breakdown in the trade record (add `cost_breakdown` JSON field to the response).

**Integration points** (search these in simulation_routes.py):
- `open_positions` creation — apply spread to entry fill
- Trade close / PnL calculation — apply spread to exit fill, subtract turnover
- Return `cost_breakdown` dict alongside existing trade fields

### Frontend Changes

#### File: `dashboard/frontend/templates/workbench.html`

Add a small "Cost Model" collapsible panel in the left sidebar (below the FVG tool settings area). Contents:

```html
<div class="card mt-2" id="cost-model-panel">
    <div class="card-header py-1 px-2" data-bs-toggle="collapse" data-bs-target="#cost-model-body">
        <i class="bi bi-currency-dollar me-1"></i> Cost Model
    </div>
    <div class="collapse show" id="cost-model-body">
        <div class="card-body py-2 px-2">
            <div class="mb-1">
                <label class="form-label mb-0" style="font-size:0.75rem;">Spread</label>
                <input type="number" step="0.01" class="form-control form-control-sm" id="cost-spread">
            </div>
            <div class="mb-1">
                <label class="form-label mb-0" style="font-size:0.75rem;">TC Rate (%)</label>
                <input type="number" step="0.001" class="form-control form-control-sm" id="cost-tc-rate" value="0.01">
            </div>
            <div id="cost-summary" style="font-size:0.72rem; color:#94a3b8;"></div>
        </div>
    </div>
</div>
```

#### File: `dashboard/frontend/static/js/workbench.js`

- Read `cost-spread` and `cost-tc-rate` inputs.
- When displaying paper trade PnL (in the Trade Log panel), show the cost-adjusted PnL alongside raw PnL.
- After each trade close, update `#cost-summary` with the last trade's cost breakdown.
- Auto-populate `cost-spread` default from the session's symbol using the same INSTRUMENT_SPREAD table.

---

## Feature 2: Mean Reversion Lens Tool

**Priority:** HIGH — new analysis tool for the chart, follows existing WorkbenchTool pattern.

### Source Reference
- `Experiments/MeanRevBacktester.py` lines 54-61, 68-75, 81-86: Bollinger Bands + state machine
- The key state machine: band breach → entry signal, mean cross → exit signal, ffill for hold

### What to Build

A new `WorkbenchTool` subclass that scans bars and returns **mean-reversion zone annotations**:
- **Overextension zones**: Price below lower band (buy zone) or above upper band (sell zone)
- **Mean-cross signals**: When price crosses back through SMA (exit/flatten signal)
- **Z-score track**: Current z-score = (price - SMA) / std, as metadata

### Backend Changes

#### File: `dashboard/backend/core/workbench/mean_rev_tool.py` (NEW)

```python
"""Mean Reversion Lens tool for the Trader's Workbench."""

from typing import Any, Dict, List
import pandas as pd
from .tool_base import WorkbenchTool

class MeanRevTool(WorkbenchTool):

    @property
    def tool_id(self) -> str:
        return "mean_rev"

    @property
    def display_name(self) -> str:
        return "Mean Reversion Lens"

    @property
    def icon(self) -> str:
        return "bi-arrow-left-right"

    @property
    def description(self) -> str:
        return "Detects Bollinger Band overextensions and mean-cross flatten signals."

    def get_default_config(self) -> Dict[str, Any]:
        return {
            "sma_period": 30,        # SMA lookback (from MeanRevBacktester default)
            "deviation": 2.0,         # Band width in std devs
            "strictness": 3,
            "show_exit_signals": True, # Show mean-cross flatten markers
        }

    def scan(self, df: pd.DataFrame, config: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Scan bars for mean-reversion entry/exit signals.

        Algorithm (from Experiments/MeanRevBacktester.py:81-86):
        1. SMA = price.rolling(period).mean()
        2. Upper = SMA + std * deviation
        3. Lower = SMA - std * deviation
        4. distance = price - SMA
        5. Entry: price < Lower → buy_zone; price > Upper → sell_zone
        6. Exit: distance sign change → mean_cross_flatten
        """
        # Implementation: iterate over bars, detect band breaches and mean crosses.
        # Return list of zone dicts with type, price levels, bar_index, timestamps.
        # Types: "buy_zone" (overextended low), "sell_zone" (overextended high),
        #        "mean_cross" (flatten signal)
        ...
```

**Zone dict format** (match FVG pattern for renderer compatibility):
```python
{
    "type": "buy_zone" | "sell_zone" | "mean_cross",
    "top": float,          # Upper band or SMA (for rendering)
    "bottom": float,       # Lower band or SMA
    "bar_index": int,
    "start_time": str,
    "start_time_unix": int,
    "end_time": str,       # Same as start for point signals
    "end_time_unix": int,
    "z_score": float,      # (price - SMA) / std at detection
    "sma_value": float,
    "upper_band": float,
    "lower_band": float,
    "signal_strength": float, # abs(z_score) / deviation — how far past the band
}
```

**Implementation details for scan():**

Compute rolling SMA, std, upper/lower bands. Then iterate:

```python
closes = df["close"].values
sma = df["close"].rolling(sma_period).mean()
std = df["close"].rolling(sma_period).std()
upper = sma + deviation * std
lower = sma - deviation * std
distance = df["close"] - sma

zones = []
for i in range(sma_period, len(df)):
    # Band breach detection (MeanRevBacktester.py:82-83)
    if closes[i] < lower.iloc[i]:
        zones.append({"type": "buy_zone", ...})
    elif closes[i] > upper.iloc[i]:
        zones.append({"type": "sell_zone", ...})

    # Mean-cross flatten signal (MeanRevBacktester.py:84)
    if i > 0 and (distance.iloc[i] * distance.iloc[i-1] < 0):
        zones.append({"type": "mean_cross", ...})
```

Also add a `compute_current_state()` method (like FVG's `compute_trend_context`) that returns the latest z-score, band positions, and whether price is in a zone — this feeds into the coach and copilot.

#### File: `dashboard/backend/core/workbench/__init__.py`

Register the new tool:

```python
from .mean_rev_tool import MeanRevTool

WORKBENCH_TOOLS: Dict[str, WorkbenchTool] = {
    "fvg": FVGTool(),
    "mean_rev": MeanRevTool(),
}
```

### Frontend Changes

#### File: `dashboard/frontend/templates/workbench.html`

Add a Mean Reversion section in the tools panel (mirror the FVG tool pattern):
- Toggle checkbox: `tool-mean-rev-toggle`
- Settings when enabled: SMA period input, deviation input, strictness slider, show exit signals checkbox
- Scan button: `btn-mean-rev-scan`
- Zone inspector panel (like FVG inspector): shows detected buy/sell zones and mean-cross signals
- Current z-score badge (like the FVG strength badge)

#### File: `dashboard/frontend/static/js/workbench.js`

Add `toolStates.mean_rev` to the state init (same pattern as `toolStates.fvg`).

Add a `scanMeanRev()` function that:
1. Reads config from UI inputs
2. POSTs to `/api/simulation/sessions/${sessionId}/tools/mean_rev/scan`
3. Renders zones on chart using `zoneRenderer` (buy_zone = green band, sell_zone = red band, mean_cross = yellow marker)
4. Updates inspector panel
5. Calls `updateIndicatorsOnChart()` if needed

Wire event handlers: toggle, scan button, settings changes.

#### File: `dashboard/backend/api/simulation_routes.py`

No changes needed for the scan endpoint — the existing generic `POST /sessions/{session_id}/tools/{tool_id}/scan` endpoint already works for any registered WorkbenchTool. The `tool_id` path parameter dispatches to the correct tool via `get_tool(tool_id)`.

**However**, if you want the copilot to auto-scan mean_rev (like it does FVG), you need to:
1. Search for the copilot auto-scan logic (around line 620-670 in the copilot scan path).
2. Add mean_rev alongside FVG in the auto-scan tool list.
3. Store mean_rev zones in `tool_state` alongside FVG zones.

### Coach Integration

#### File: `dashboard/backend/core/workbench/coach.py`

In `_coach_knowledge_block()` and `_deterministic_report()`, add mean_rev consumption (same pattern as FVG):
- Extract `tool_state.get("mean_rev_zones_preview")` and `tool_state.get("mean_rev_current_state")`
- Add coach doctrine rules: "When z-score > 2, price is overextended — watch for reversion. When mean cross detected, consider flattening."
- In deterministic report: penalize `execution` score if trader enters in the direction of overextension (buying when z > 2, selling when z < -2).

---

## Feature 3: Research Parameter Optimizer (Sandbox Mode)

**Priority:** MEDIUM — useful for indicator/parameter research but NOT for live execution.

### Source Reference
- `Experiments/SMABacktester.py` lines 92-121: `optimize_parameters()` grid search
- `Experiments/MeanRevBacktester.py` lines 113-143: same pattern for (SMA, deviation)

### What to Build

A backend-only research endpoint that runs parameter sweeps on the current session's data. Returns a results table + heatmap data. This is clearly labeled "Research Only" and does NOT affect live/paper trading defaults.

### Backend Changes

#### File: `dashboard/backend/core/workbench/parameter_optimizer.py` (NEW)

```python
"""Parameter grid search for Workbench research mode."""

from itertools import product
from typing import Any, Dict, List, Tuple
import pandas as pd

def optimize_sma_crossover(
    df: pd.DataFrame,
    fast_range: Tuple[int, int, int],  # (start, stop, step)
    slow_range: Tuple[int, int, int],
    tc: float = 0.0001,
) -> Dict[str, Any]:
    """
    Grid search SMA crossover parameters.
    Source: Experiments/SMABacktester.py:92-121

    Returns:
        optimal: (fast_period, slow_period)
        best_performance: float (cumulative return multiple)
        results: list of {fast, slow, performance, outperformance}
    """
    ...

def optimize_mean_reversion(
    df: pd.DataFrame,
    sma_range: Tuple[int, int, int],
    dev_range: Tuple[float, float, float],  # (start, stop, step) for deviation
    tc: float = 0.0001,
) -> Dict[str, Any]:
    """
    Grid search mean reversion (Bollinger band) parameters.
    Source: Experiments/MeanRevBacktester.py:113-143

    Returns:
        optimal: (sma_period, deviation)
        best_performance: float
        results: list of {sma, dev, performance, outperformance}
    """
    ...
```

**Implementation**: For each parameter combination:
1. Compute signals using the strategy logic
2. Calculate returns with turnover costs (from Feature 1's cost model)
3. Track cumulative performance
4. Return sorted results + optimal

#### File: `dashboard/backend/api/simulation_routes.py`

Add a new endpoint:

```python
@router.post("/sessions/{session_id}/tools/research/optimize")
def workbench_research_optimize(session_id: int, req: ResearchOptimizeRequest, db: Session = Depends(get_db)):
    """Run parameter optimization on session data. Research only — does not affect trading."""
    ...
```

Request model:
```python
class ResearchOptimizeRequest(BaseModel):
    strategy_type: str  # "sma_crossover" | "mean_reversion"
    params: Dict[str, Any] = {}  # range specs
    tc_rate: float = 0.0001
```

Response: `{ optimal, best_performance, results[], total_combinations, elapsed_ms }`

### Frontend Changes

#### File: `dashboard/frontend/templates/workbench.html`

Add a "Research" tab/button in the toolbar area (near the Indicators button). Clicking opens a modal:

```
Research Optimizer (Sandbox)
┌─────────────────────────────────┐
│ Strategy: [SMA Crossover ▼]     │
│ Fast SMA: [10] to [60] step [5] │
│ Slow SMA: [50] to [250] step [10]│
│ TC Rate: [0.01] %               │
│                                 │
│ [Run Optimization]              │
│                                 │
│ Results:                        │
│ Optimal: SMA(25, 120) = 1.45x  │
│ ┌───────────────────────────┐   │
│ │ fast │ slow │ perf │ outperf│  │
│ │  25  │ 120  │ 1.45 │ +0.32 │  │
│ │  30  │ 100  │ 1.38 │ +0.25 │  │
│ │ ...  │ ...  │ ...  │  ...  │  │
│ └───────────────────────────┘   │
│                                 │
│ ⚠️ Research only — not live     │
└─────────────────────────────────┘
```

#### File: `dashboard/frontend/static/js/workbench.js`

Add `runResearchOptimize()` function that POSTs to the optimize endpoint, then renders the results table in the modal. Include a loading spinner during computation.

---

## Feature 4: ML Feature Hygiene Diagnostic (Research Only)

**Priority:** LOW — informational diagnostic, no execution impact.

### Source Reference
- `Experiments/MLBacktester.py` lines 54-79, 81-129: train/test split, feature scaling, prediction pipeline

### What to Build

A read-only diagnostic panel that shows:
1. Feature statistics on the current session's visible bars (mean, std of returns, lagged features)
2. Train/test split quality check: are statistics consistent between first half and second half?
3. Warning if feature distributions are significantly different (potential regime change)

This is NOT a trading tool — it's a data quality diagnostic for research.

### Backend Changes

#### File: `dashboard/backend/core/workbench/ml_diagnostic.py` (NEW)

```python
"""ML feature hygiene diagnostic for Workbench research mode."""

def compute_feature_diagnostic(df: pd.DataFrame, lags: int = 5) -> Dict[str, Any]:
    """
    Analyze feature distributions for data quality.
    Source: Experiments/MLBacktester.py:54-72 (feature prep + scaling pattern)

    Returns:
        features: list of { name, train_mean, train_std, test_mean, test_std, drift_pct }
        split_ratio: float (train portion)
        regime_warning: bool (true if any feature drifts > 50%)
        summary: str
    """
    ...
```

Implementation:
1. Create lagged return features (like MLBacktester.py:58-61)
2. Split at 70% mark (like MLBacktester.py:95)
3. Compute mean/std on train portion
4. Compute mean/std on test portion using TRAIN stats (the hygiene check — MLBacktester.py:78)
5. Report drift between halves

### Frontend Changes

Add a small "ML Diagnostic" card in the Research modal (from Feature 3). Shows:
- Feature drift table
- Green/yellow/red regime warning badge
- "This is a data quality check, not a trading signal" disclaimer

---

## Execution Order

| Phase | Feature | Files Created | Files Modified |
|-------|---------|---------------|----------------|
| 1 | Cost Model | `cost_model.py` | `simulation_routes.py`, `workbench.html`, `workbench.js` |
| 2 | Mean Reversion Lens | `mean_rev_tool.py` | `__init__.py`, `coach.py`, `workbench.html`, `workbench.js` |
| 3 | Research Optimizer | `parameter_optimizer.py` | `simulation_routes.py`, `workbench.html`, `workbench.js` |
| 4 | ML Diagnostic | `ml_diagnostic.py` | `workbench.html`, `workbench.js` |

**Between each phase**: Run `python -m py_compile` on all changed Python files and `node --check` on workbench.js. Fix any errors before proceeding.

## Files You MUST Read Before Starting

1. `Experiments/IterativeBase.py` — FULL FILE (spread logic)
2. `Experiments/ConBacktester.py` — FULL FILE (turnover cost)
3. `Experiments/MeanRevBacktester.py` — FULL FILE (mean reversion state machine)
4. `Experiments/SMABacktester.py` — FULL FILE (parameter optimization)
5. `Experiments/MLBacktester.py` — FULL FILE (feature scaling hygiene)
6. `dashboard/backend/core/workbench/tool_base.py` — WorkbenchTool ABC interface
7. `dashboard/backend/core/workbench/__init__.py` — tool registration pattern
8. `dashboard/backend/core/workbench/fvg_tool.py` — reference implementation (DO NOT MODIFY)
9. `dashboard/backend/core/workbench/coach.py` — coach integration pattern
10. `dashboard/frontend/static/js/workbench.js` — existing indicator + FVG + zone system (DO NOT break existing features)
11. `dashboard/frontend/templates/workbench.html` — existing layout (add to, don't restructure)

## Validation Checklist

After each phase, verify:
- [ ] `python -m py_compile <all changed .py files>` passes
- [ ] `node --check dashboard/frontend/static/js/workbench.js` passes
- [ ] Backend starts without import errors: `python -m uvicorn dashboard.backend.main:app --port 8000`
- [ ] Frontend serves without errors: `cd dashboard/frontend && python app.py`
- [ ] New UI elements appear correctly in the Workbench page
- [ ] Existing FVG tool, indicators, and copilot still work (regression check)
