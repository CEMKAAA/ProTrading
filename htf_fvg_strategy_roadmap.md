# HTF FVG Liquidity Reclaim Strategy — Build Roadmap

**Goal:** Build `htf_fvg_liquidity_reclaim_strategy` as a full `BacktestStrategy` subclass
that can be backtested via the UI, optimized with presets, and eventually run live.

**Current state:** The sweep gate logic exists only inside the agent's `run_mtf_analysis`
tool in `simulation_routes.py`. It gates/validates setups but doesn't generate entries.
This roadmap turns it into a standalone strategy.

---

## Strategy Concept (What It Does)

**Edge:** Price sweeps a liquidity pool (clustered equal highs/lows), rejects strongly,
then retraces into a higher-timeframe fair value gap. Entry is on the LTF retracement
into the FVG, with stop behind the sweep extreme.

**Entry sequence:**
1. HTF (H4/H1): Identify unfilled FVG zones — these are magnets for price
2. LTF (M15/M5): Detect liquidity pool near FVG → wait for sweep + rejection
3. Confirmation: Sweep rejection_ratio > 0.30, close back inside pool boundary
4. Entry trigger: Price retraces into FVG zone on execution timeframe
5. SL: Behind sweep extreme + buffer
6. TP: Opposite side of FVG zone, or next liquidity level, whichever gives better R:R

**Key difference from existing `liquidity_sweep_strategy`:**
- Existing: Sweeps session highs/lows (structural levels), FVG is optional confirmation
- New: FVG is the primary setup zone, sweep is the confirmation/gate mechanism
- Existing: Single timeframe
- New: Multi-timeframe (HTF structure + LTF entry)

---

## Architecture Decision: Multi-Timeframe in Backtest Engine

**Problem:** The backtest engine provides only ONE timeframe to `find_setup()`. This
strategy needs HTF (H4/H1) for FVG structure and LTF (M15/M5) for entry timing.

**Solution:** Run the strategy on the LTF (M15 recommended) and resample to HTF internally.

```python
def initialize_day(self, date, daily_df, intraday_df):
    # intraday_df is M15 bars (all history up to today)
    # Resample M15 → H1 and H4 for HTF analysis
    self._h1_df = intraday_df.resample("1h").agg(OHLCV_AGG).dropna()
    self._h4_df = intraday_df.resample("4h").agg(OHLCV_AGG).dropna()
    # Scan HTF FVGs and liquidity pools once per day
    self._htf_fvgs = self._scan_htf_fvgs(self._h4_df, self._h1_df)
    self._liquidity_pools = self._scan_liquidity_pools(intraday_df)
```

This is how `keltner_breakout_strategy` and `bb_squeeze_strategy` handle needing
200+ bars of history — they compute everything from the single intraday df passed in.

---

## Phase 1: Core Strategy Class (Estimated: ~500 lines)

### Step 1.1 — Create strategy file

**File:** `dashboard/backend/core/strategies/htf_fvg_liquidity_reclaim_strategy.py`

```python
class HTFFVGLiquidityReclaimStrategy(BacktestStrategy):
    """
    HTF FVG + Liquidity Sweep Reclaim strategy.

    Identifies higher-timeframe fair value gaps, waits for liquidity sweeps
    near those gaps, and enters on price reclaiming into the FVG zone
    after a strong rejection.
    """
```

**Methods to implement:**

#### `initialize_day(date, daily_df, intraday_df) -> DayContext`
- Resample intraday (M15) → H1 and H4
- Compute ATR(14) on intraday
- Determine daily bias from H4 EMA50 slope (or daily close vs EMA)
- Scan HTF FVGs on H4 and H1 — store as `self._active_fvgs`
- Scan liquidity pools on M15 — store as `self._active_pools`
- Compute session levels (asian range, previous day H/L) from intraday_df
- Return DayContext with bias, ATR, levels

#### `find_setup(bar, df, day_context, current_bar_index) -> Optional[TradeSetup]`
- **Gate 1 — Active FVG nearby:**
  - Find HTF FVGs within 2x ATR of current price
  - FVG must be unfilled (current price hasn't closed through it)
  - Direction: bullish FVG (gap up) for longs, bearish FVG (gap down) for shorts

- **Gate 2 — Liquidity pool near FVG:**
  - Find clustered equal-highs/lows within 1.5x ATR of FVG boundary
  - Pool must have min_touches (default: 2)

- **Gate 3 — Sweep + rejection:**
  - Recent bar swept the pool (wick beyond pool boundary)
  - Close back inside pool (rejection)
  - rejection_ratio > threshold (default: 0.30, measured from pool boundary not ref)
  - Sweep within freshness window (default: 4 hours)

- **Gate 4 — Entry trigger:**
  - After sweep rejection, price retraces into FVG zone
  - Entry at bar open when price is inside FVG [bottom, top]
  - Bias alignment: bullish FVG requires bullish or neutral bias

- **Setup construction:**
  - direction: "BUY" for bullish FVG reclaim, "SELL" for bearish
  - entry_price: bar open (standard)
  - stop_loss: sweep extreme - buffer (ATR * sl_buffer_atr)
  - take_profit: opposite FVG boundary, clamped to min R:R ratio
  - confidence: composite of rejection_ratio, FVG size, pool touches, bias strength
  - metadata: fvg dict, sweep dict, pool dict, rejection_ratio, htf_timeframe

#### `should_close_early(bar, df, position, day_context) -> Optional[str]`
- **FVG invalidation:** Price closes through the FVG against trade direction
- **Sweep invalidation:** Price retakes the sweep level decisively (close beyond sweep extreme)
- **Momentum fade:** Held > 30 bars with < 0.5R profit
- **Time decay:** End-of-session close (optional, configurable)
- **Trailing stop:** After 1.5R profit, trail at 1R (use position.strategy_metadata for state)

#### `get_required_lookback_bars() -> int`
- Return 500 (need enough M15 bars to resample meaningful H4 data)

### Step 1.2 — Shared analysis functions

**File:** `dashboard/backend/core/workbench/analysis_utils.py` (new)

Extract reusable logic from both `liquidity_tool.py` and `fvg_tool.py` so the
backtest strategy and the agent planner use the same detection code:

```python
def detect_fvg_zones(df, config) -> List[Dict]:
    """Detect fair value gaps. Used by FVGTool.scan() and strategy."""

def detect_liquidity_pools(highs, lows, closes, config) -> List[Dict]:
    """Detect equal-high/low clusters. Used by LiquidityTool.scan() and strategy."""

def evaluate_sweep_rejection(pool, sweep_bar, is_high) -> Dict:
    """Compute rejection_ratio from pool BOUNDARY (not ref). Used everywhere."""

def filter_sweep_candidates(sweeps, entry_price, direction, atr, config) -> List[Dict]:
    """Filter by freshness, distance, direction. Rank by composite score."""
```

This is the key architectural decision: shared functions prevent the strategy
from reimplementing what the workbench tools already do, and ensure the
rejection_ratio geometry fix (F1 from sweep_gate_roadmap.md) applies everywhere.

### Step 1.3 — Register in factory

**File:** `dashboard/backend/core/strategies/factory.py`

```python
# Add to imports
from .htf_fvg_liquidity_reclaim_strategy import HTFFVGLiquidityReclaimStrategy

# Add to STRATEGY_CLASSES dict
"htf_fvg_liquidity_reclaim_strategy": HTFFVGLiquidityReclaimStrategy,
```

### Step 1.4 — Register in strategy_registry.py

**Add `HTF_FVG_LIQUIDITY_RECLAIM_STRATEGY` StrategyDefinition:**

```python
HTF_FVG_LIQUIDITY_RECLAIM_STRATEGY = StrategyDefinition(
    id="htf_fvg_liquidity_reclaim_strategy",
    name="HTF FVG + Liquidity Reclaim",
    description="Enters on LTF retracement into HTF fair value gaps after "
                "liquidity sweep confirmation. Combines structural FVG zones "
                "with sweep rejection quality gating.",
    version="1.0",
    author="ProTradingSystem",
    parameters=[
        # User-visible params (UI dropdowns)
        ParameterDefinition("symbol", "Symbol", ParameterType.SELECT, "XAUUSD", ...),
        ParameterDefinition("timeframe", "Timeframe", ParameterType.SELECT, "M15",
            options=[
                {"value": "M5", "label": "M5 (aggressive)"},
                {"value": "M15", "label": "M15 (recommended)"},
                {"value": "M30", "label": "M30 (conservative)"},
            ]),
        ParameterDefinition("initial_balance", ...),
        ParameterDefinition("preset", ...),
    ],
    presets=[
        StrategyPreset("conservative", "Conservative",
            "Strict sweep quality + single daily trade", {
                "risk_percent": 0.5,
                "max_daily_trades": 1,
                "max_daily_loss_usd": -75.0,
                "min_rejection_ratio": 0.45,
                "require_fvg_unfilled": True,
                "min_rr_ratio": 3.0,
                "sweep_freshness_hours": 3.0,
                "min_pool_touches": 3,
                "bias_min_strength": 40,
            }),
        StrategyPreset("default", "Default",
            "Balanced sweep + FVG quality", {
                "risk_percent": 0.75,
                "max_daily_trades": 2,
                "max_daily_loss_usd": -100.0,
                "min_rejection_ratio": 0.30,
                "require_fvg_unfilled": True,
                "min_rr_ratio": 2.5,
                "sweep_freshness_hours": 4.0,
                "min_pool_touches": 2,
                "bias_min_strength": 30,
            }),
        StrategyPreset("aggressive", "Aggressive",
            "Looser gates, more setups", {
                "risk_percent": 1.0,
                "max_daily_trades": 3,
                "max_daily_loss_usd": -150.0,
                "min_rejection_ratio": 0.25,
                "require_fvg_unfilled": False,
                "min_rr_ratio": 2.0,
                "sweep_freshness_hours": 6.0,
                "min_pool_touches": 2,
                "bias_min_strength": 20,
            }),
        # Symbol-specific presets
        StrategyPreset("xauusd_m15", "XAUUSD M15 Tuned",
            "Gold-optimized parameters", {
                "risk_percent": 0.75,
                "max_daily_trades": 2,
                "max_daily_loss_usd": -100.0,
                "min_rejection_ratio": 0.35,
                "sweep_distance_atr": 0.50,
                "htf_timeframe": "H4",
                "sl_buffer_atr": 0.25,
                "min_rr_ratio": 2.5,
            }, symbols=["XAUUSD"]),
        StrategyPreset("nas100_m15", "NAS100 M15 Tuned",
            "Index-optimized parameters", {
                "risk_percent": 0.75,
                "max_daily_trades": 2,
                "max_daily_loss_usd": -150.0,
                "min_rejection_ratio": 0.30,
                "sweep_distance_atr": 0.30,
                "htf_timeframe": "H1",
                "sl_buffer_atr": 0.30,
                "min_rr_ratio": 3.0,
            }, symbols=["NAS100"]),
    ],
    optimal_parameters={
        # Technical defaults (not shown in UI)
        "htf_timeframe": "H4",
        "htf_fvg_lookback_bars": 100,
        "htf_fvg_min_gap_atr": 0.15,
        "ltf_pool_lookback_bars": 420,
        "ltf_pool_pivot_span": 3,
        "min_pool_touches": 2,
        "sweep_freshness_hours": 4.0,
        "sweep_freshness_min_bars": 4,
        "sweep_distance_atr": 0.50,
        "min_rejection_ratio": 0.30,
        "sl_buffer_atr": 0.25,
        "min_rr_ratio": 2.5,
        "max_rr_cap": 8.0,
        "fvg_max_age_bars": 200,
        "fvg_max_fill_ratio": 0.70,
        "fvg_proximity_atr": 2.0,
        "pool_proximity_atr": 1.5,
        "trailing_activation_r": 1.5,
        "trailing_lock_r": 1.0,
        "momentum_fade_bars": 30,
        "momentum_fade_min_r": 0.5,
        "max_spread_usd": 0.40,
        "min_sl_usd": 1.0,
        "max_sl_usd": 15.0,
        "require_fvg_unfilled": True,
        "require_bias_alignment": True,
    },
    instrument_overrides={
        "XAUUSD": {
            "max_sl_usd": 12.0,
            "sweep_distance_atr": 0.50,
            "htf_fvg_min_gap_atr": 0.10,
        },
        "NAS100": {
            "max_spread_usd": 3.0,
            "min_sl_usd": 5.0,
            "max_sl_usd": 25.0,
            "sweep_distance_atr": 0.30,
            "htf_timeframe": "H1",
        },
        "US500": {
            "max_spread_usd": 2.0,
            "min_sl_usd": 3.0,
            "max_sl_usd": 15.0,
            "sweep_distance_atr": 0.30,
            "htf_timeframe": "H1",
        },
    },
)
```

---

## Phase 2: Tests + Validation (~200 lines)

### Step 2.1 — Unit tests

**File:** `tests/test_htf_fvg_liquidity_reclaim_strategy.py`

Tests needed:
1. `test_initialize_day_computes_htf_resampled_data` — verify H1/H4 bars created from M15
2. `test_find_setup_returns_none_without_htf_fvg` — no FVG = no setup
3. `test_find_setup_returns_none_without_sweep` — FVG exists but no sweep = no setup
4. `test_find_setup_returns_none_on_weak_rejection` — sweep with ratio < threshold = blocked
5. `test_find_setup_returns_setup_on_strong_sweep_into_fvg` — full happy path
6. `test_stop_loss_behind_sweep_extreme` — SL = sweep_price - buffer
7. `test_take_profit_at_fvg_boundary` — TP = opposite FVG edge
8. `test_should_close_early_on_fvg_invalidation` — close through FVG = exit
9. `test_should_close_early_on_momentum_fade` — stale trade = exit
10. `test_bias_alignment_blocks_counter_trend` — bullish FVG + bearish bias = skip
11. `test_rejection_ratio_uses_pool_boundary_not_ref` — F1 fix validation
12. `test_preset_configs_merge_correctly` — registry preset + instrument overrides

### Step 2.2 — Integration test with backtest engine

**File:** `tests/test_htf_fvg_strategy_backtest.py`

1. `test_strategy_runs_through_engine_without_errors` — 30-day XAUUSD M15 backtest
2. `test_no_lookahead_violations` — FutureDataGuard doesn't raise
3. `test_trade_count_within_expected_range` — not 0 trades, not 500 trades

### Step 2.3 — Shared analysis_utils tests

**File:** `tests/test_analysis_utils.py`

1. `test_rejection_ratio_from_boundary_not_ref` — wide pool geometry
2. `test_sweep_candidate_ranking_uses_quality` — strong > moderate at equal distance
3. `test_fvg_detection_matches_fvg_tool` — same results as workbench FVGTool

---

## Phase 3: Optimization + Presets

### Step 3.1 — Batch backtest

Run via `batch_backtest.py`:
```bash
python batch_backtest.py \
  --strategy htf_fvg_liquidity_reclaim_strategy \
  --symbols XAUUSD NAS100 US500 \
  --timeframes M15 M5 \
  --presets conservative default aggressive \
  --start 2025-01-01 --end 2026-01-01
```

### Step 3.2 — Analyze results, tune presets

Target metrics (from strategy_optimization_results.md):
- Win rate: 40-50%
- Profit factor: > 1.3
- Sharpe: > 1.0
- Max drawdown: < 15%
- Min 2:1 R:R on all trades

### Step 3.3 — Symbol-specific presets

Based on batch results, create tuned presets:
- `xauusd_m15_tuned` — Gold-specific thresholds
- `nas100_m15_tuned` — Index-specific thresholds
- Kill configurations that don't meet DEPLOY thresholds

---

## Phase 4: Wire to Agent + Live

### Step 4.1 — Agent can select this strategy

The workbench agent already runs MTF analysis. Wire it so the agent can:
- Reference the strategy's preset configs for consistency
- Use the same shared analysis_utils for sweep/FVG detection
- Report which strategy preset the current setup matches

### Step 4.2 — Live execution path

Once backtested and a DEPLOY preset exists:
- Strategy appears in "Start Live" dropdown
- TradeExecutor uses the strategy's find_setup() in real-time
- Watchdog monitors using the same sweep gate logic
- Telegram notifications include sweep_gate diagnostics

---

## File Map

| File | Action | Phase |
|------|--------|-------|
| `strategies/htf_fvg_liquidity_reclaim_strategy.py` | CREATE (~500 lines) | 1 |
| `workbench/analysis_utils.py` | CREATE (~200 lines) | 1 |
| `strategies/factory.py` | EDIT (2 lines) | 1 |
| `strategy_registry.py` | EDIT (~150 lines) | 1 |
| `workbench/liquidity_tool.py` | EDIT (use analysis_utils) | 1 |
| `workbench/fvg_tool.py` | EDIT (use analysis_utils) | 1 |
| `tests/test_htf_fvg_liquidity_reclaim_strategy.py` | CREATE (~300 lines) | 2 |
| `tests/test_htf_fvg_strategy_backtest.py` | CREATE (~100 lines) | 2 |
| `tests/test_analysis_utils.py` | CREATE (~150 lines) | 2 |
| `simulation_routes.py` | EDIT (use analysis_utils) | 4 |

---

## Dependencies & Risks

### Must fix first (from sweep_gate_roadmap.md):
- **F1: Rejection ratio geometry** — currently measures from ref, must use pool boundary.
  If we build the strategy with the wrong geometry, all backtest results are invalid.
  Fix this in `analysis_utils.py` from the start.

### Risk: Multi-timeframe resampling accuracy
- M15 → H4 resampling works well for FVG detection (structural gaps)
- M15 → H4 resampling may miss exact H4 candle boundaries if M15 data has gaps
- Mitigation: validate resampled H4 bar count matches expected (6h/15min = 16 bars per H4)

### Risk: Trade frequency
- This strategy has 4 sequential gates (FVG + pool + sweep + entry trigger)
- Could produce very few trades (< 50/year), making statistical validation hard
- Mitigation: start with M15 (more bars, more opportunities), test on 12+ months of data

### Risk: Overfitting to Gold
- Most of the sweep gate design was calibrated for XAUUSD
- NAS100/US500 have different microstructure (wider gaps, different sweep behavior)
- Mitigation: instrument_overrides in registry, separate preset tuning per symbol

---

## Implementation Order (recommended)

```
1. Fix F1 rejection geometry       (prerequisite — do before any backtest)
2. Create analysis_utils.py        (shared detection functions)
3. Create strategy class           (Phase 1.1)
4. Register in factory + registry  (Phase 1.3 + 1.4)
5. Write unit tests                (Phase 2.1)
6. Run first backtest              (verify trades generate, no crashes)
7. Write integration tests         (Phase 2.2)
8. Batch optimize                  (Phase 3)
9. Create DEPLOY presets           (Phase 3.3)
10. Wire to agent                  (Phase 4)
```

Steps 1-6 should be done together as a single implementation block.
Steps 7-10 depend on backtest results from step 6.
