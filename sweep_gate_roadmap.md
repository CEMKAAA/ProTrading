# Sweep Gate V2 — Roadmap

**Status:** Phase 1 complete. Integrated into `run_mtf_analysis` (agent MTF planner).
**Not** a standalone backtest strategy — lives in `simulation_routes.py`.

---

## Already Fixed (Opus Audit — This Session)

| # | Severity | Issue | Fix |
|---|----------|-------|-----|
| A1 | HIGH | Freshness formula used `max(8,...)` instead of agreed `max(4, ceil(240/tf_min))` — H4 got 32h window instead of 16h | Changed to `max(4,...)` in `_agent_sweep_freshness_bars()` |
| A2 | HIGH | No sweep + weak FVG did blanket 50% derate instead of hard block — traded structurally invalid setups | Added `fvg_weak = bool(ltf_gas_low or ltf_mov_state == "exhausted")` check; weak → hard block |
| A3 | MEDIUM | Default gate mode was `"assist"` instead of agreed `"hybrid"` | Fixed default to `"hybrid"` |
| A4 | CRITICAL | JS duplicate `const` declarations in load function — `SyntaxError` crashes entire workbench | Removed duplicate declarations |
| A5 | CRITICAL | JS save function `getAgentWatchdogConfigFromUI()` referenced undeclared element variables — `ReferenceError` on config save | Added element declarations to save function scope |

---

## Open Findings (Codex Audit + Opus Observations)

### P0 — Must Fix Before Live Use

#### F1: Rejection ratio geometry is inflated (HIGH)
**Files:** `liquidity_tool.py:258-261`
**Problem:** `wick_beyond` is measured from `ref` (cluster average) instead of pool boundary (`z_top`/`z_bottom`). For wide pools, this overstates the rejection by including the pool's own width in the numerator.
**Impact:** Marginal sweeps that barely clip the pool edge get labeled "moderate" or "strong" and pass the gate at `simulation_routes.py:7982`. False-positive sweep confirmations lead to trades behind structurally weak liquidity.
**Example:**
```
Pool: touches at 2920, 2922, 2924 → ref=2922, z_top≈2924.5
Sweep bar: high=2925, low=2918, close=2919
Current:  wick_beyond = 2925-2922 = 3.0,  ratio = 3/7 = 0.43 → "moderate" (PASSES)
Correct:  wick_beyond = 2925-2924.5 = 0.5, ratio = 0.5/7 = 0.07 → "weak" (BLOCKED)
```
**Fix:** Change `wick_beyond` to measure from `z_top` (high sweeps) / `z_bottom` (low sweeps) instead of `ref`. Expose both `pool_boundary` and `ref_price` in sweep output so downstream can verify.

#### F2: Sweep candidate ranking ignores rejection quality (MEDIUM-HIGH)
**File:** `simulation_routes.py:7961-7966`
**Problem:** Candidates sorted by `(distance_to_entry, age_bars)` only. A barely-valid sweep (ratio 0.31) closer to entry outranks a materially better rejection (ratio 0.85) slightly farther away. The weaker sweep then drives both stop anchor placement and reported setup confidence.
**Fix:** Use composite scoring: `score = w_distance * norm_distance + w_age * norm_age + w_quality * norm_rejection_ratio`. Suggested weights: distance 0.4, age 0.3, quality 0.3. Or simpler: sort by `(rejection_quality_tier, distance, age)` so strong > moderate within distance tolerance.

### P1 — Should Fix

#### F3: `_agent_sweep_quality_label()` is dead code (MEDIUM)
**File:** `simulation_routes.py:7477-7484`
**Problem:** Function exists and computes "strong"/"moderate"/"weak" labels, but is never called anywhere. The gate logic at line 7982 uses raw `rejection_ratio <= 0.30` instead. The quality label could enable tiered risk scaling (strong=100%, moderate=75%) instead of the current binary pass/fail.
**Fix:** Wire quality label into gate logic. Strong → full risk, moderate → 75% risk, weak → block.

#### F4: Per-symbol override map name is misleading (LOW-MEDIUM)
**Files:** `simulation_routes.py:7362, 7382, 7396`
**Problem:** Config key `mtf_liquidity_sweep_distance_atr_by_symbol` implies broker-symbol granularity (XAUUSDm vs XAUUSD.r), but both keys and lookups normalize to base instrument. In practice this is correct behavior — you want the same distance for XAUUSD regardless of broker suffix — but the naming misleads.
**Fix:** Rename to `mtf_liquidity_sweep_distance_atr_by_instrument` or document that normalization is intentional. No functional change needed.

#### F5: FVG weakness proxy is coarse (LOW-MEDIUM)
**File:** `simulation_routes.py:8003`
**Problem:** `fvg_weak = bool(ltf_gas_low or ltf_mov_state == "exhausted")` is a binary heuristic. It doesn't score FVG zone quality (size, fill ratio, distance from price, age). A large unfilled FVG near price is materially different from a small half-filled one far away.
**Fix:** Phase 2 work — add FVG quality scoring when the FVG tool already computes fill_ratio and gap_size. For now the binary proxy is safe (conservative: blocks when uncertain).

---

## Phase 2 — Enhancements (After P0/P1)

### E1: Tiered risk scaling by sweep quality
Instead of binary pass/fail at 0.30 threshold:
- Strong (>0.60): 100% risk
- Moderate (0.30-0.60): 75% risk
- Weak (<=0.30): hard block

Wire through `_agent_sweep_quality_label()` (currently dead code, see F3).

### E2: "Strict" gate mode
Currently only `hybrid` and `assist` modes have implementation logic. Add `strict` mode that hard-blocks without sweep confirmation (no 50% derate fallback).

### E3: FVG quality scoring
Replace binary `fvg_weak` with multi-factor FVG quality:
- Gap size relative to ATR
- Fill ratio (unfilled % remaining)
- Distance from current price
- Age (bars since formation)

Feed composite FVG score into hybrid gate for proportional risk adjustment.

### E4: Backtestable strategy class
Create `htf_fvg_liquidity_reclaim_strategy.py` as a `BacktestStrategy` subclass to get real performance numbers. Requires extracting sweep gate + FVG gate logic into reusable functions that both the agent planner and the backtest engine can call.

---

## Phase 3 — Research / Future

### R1: Order flow validation (Databento)
Use real buy/sell volume asymmetry to validate sweep legitimacy. A sweep with volume confirmation is structurally different from a thin-liquidity wick.

### R2: Multi-timeframe sweep confirmation chain
Does D1 sweep + H4 sweep + M15 sweep align? Weighted scoring across timeframes, flag sweep conflicts.

### R3: Dynamic parameter learning
Auto-adjust distance/freshness thresholds per instrument based on live gate hit-rate and outcome tracking.

### R4: Sweep pattern memory
Cache rejected sweep patterns. Detect replays of same level + weak rejection → auto-block. Whitelist historically high-win-rate patterns.

---

## Implementation Priority Order

```
1. F1 (rejection geometry)     — fixes false positives, highest impact
2. F2 (candidate ranking)      — ensures best sweep drives stop anchor
3. F3 (quality label wiring)   — enables E1 tiered risk scaling
4. F4 (naming cleanup)         — documentation only
5. F5 (FVG proxy)              — safe as-is, improve later
6. E1-E4                       — after validation on live data
7. R1-R4                       — research phase
```

---

## Test Coverage

Current: 91 tests across 5 test files (all passing).

Tests needed for P0 fixes:
- F1: Update `test_workbench_liquidity_tool.py` — wide pool where ref-based ratio passes but boundary-based ratio blocks
- F2: Add test in `test_workbench_agent_phase4_critical.py` — two candidates, closer-but-weaker vs farther-but-stronger, verify stronger wins
- F3: Add test for tiered risk scaling when wired
