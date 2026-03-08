# ProTradingSystem - Phase 3-6 Task Board

> **Workflow**: Codex implements, Opus validates (and vice versa per assignment).
> **Updated**: 2026-02-10

---

## Phase 3: Databento Orderflow Hardening + Shadow Mode

| Ticket | Owner | Status | Scope | Target Files | Done Criteria |
|--------|-------|--------|-------|--------------|---------------|
| P3-001-DATABENTO-CONFIG-HARDEN | Codex | TODO | Validate Databento env loading, symbol mapping, fail-open reasons | `databento_orderflow_filter_live.py` | Key/no-key/network cases all return deterministic decision + reason |
| P3-002-OFI-MICROPRICE-TOXICITY-V2 | Codex | TODO | Add OFI + microprice proxy + toxicity score + confidence | `databento_orderflow_filter_live.py` | Decision object includes score, confidence, sample_count |
| P3-003-BASIS-SANITY-GATE | Opus | TODO | Add GC/MGC vs XAUUSD basis mismatch guard | `databento_orderflow_filter_live.py`, `config.py` (ORB + AdvORB) | Trades blocked only when mismatch exceeds configured threshold |
| P3-004-ORB-SHADOW-MODE-WIRING | Codex | TODO | Add shadow mode (log-only) for ORB | `Strategies/ORBStrategy/strategy.py` | Logs contain shadow_allow, shadow_block, shadow_reason without blocking execution |
| P3-005-ADV-ORB-SHADOW-MODE-WIRING | Opus | TODO | Add shadow mode (log-only) for Advanced ORB | `Strategies/AdvancedORBStrategy/strategy.py` | Same as ORB shadow logging fields |
| P3-006-PHASE3-GATE-REPORT | User | TODO | Run controlled demo test and publish gate report | Dashboard + logs | Match rate >=85%, no slippage blow-up, expectancy delta reported |

---

## Phase 4: Signal Meta-Learner

| Ticket | Owner | Status | Scope | Target Files | Done Criteria |
|--------|-------|--------|-------|--------------|---------------|
| P4-001-META-FEATURE-STORE | Codex | TODO | Build feature assembler (signals, confidence, costs, regime, orderflow) | `meta_features.py` | Training dataset generated with schema versioning |
| P4-002-META-MODEL-TRAIN-CALIBRATE | Opus | TODO | Train LightGBM/XGBoost + probability calibration | `meta_learner.py` | Calibrated probabilities with saved model artifact |
| P4-003-LIVE-INFERENCE-HOOK | Codex | TODO | Add take/skip inference call on live ORB paths | `strategy_manager.py`, ORB runtime files | Runtime receives p_win, threshold decision, reason |
| P4-004-META-THRESHOLD-PRESETS | User | TODO | Define threshold policy by preset | Config files + launch presets | Default/conservative/aggressive thresholds approved |
| P4-005-META-MONITORING-API-UI | Opus | TODO | Add API + UI stats for accept/reject + calibration | `routes.py`, live systems UI | Endpoint and UI show recent meta decision quality |
| P4-006-PHASE4-GATE-REPORT | User | TODO | OOS performance gate after costs | Backtest validator/report | Sharpe/expectancy improve, trade-count drop within tolerance |

---

## Phase 5: Portfolio Risk Engine (Kelly + Correlation)

| Ticket | Owner | Status | Scope | Target Files | Done Criteria |
|--------|-------|--------|-------|--------------|---------------|
| P5-001-CORRELATION-HEAT-ENGINE | Codex | TODO | Add cross-strategy correlation heat + directional concentration limits | `portfolio_risk_service.py` | Heat computed and enforced before new starts |
| P5-002-FRACTIONAL-KELLY-SIZER | Opus | TODO | Implement capped fractional Kelly (0.25x-0.5x) | `risk_sizer.py` | Multiplier bounded, fallback to base risk on missing stats |
| P5-003-RISK-MULTIPLIER-WIRING | Codex | TODO | Apply portfolio risk multipliers to live strategy launches | `strategy_manager.py` | Launch and runtime both receive same multiplier |
| P5-004-RISK-POLICY-CONFIG | User | TODO | Approve max heat/DD pause/recovery ladder | Governor config endpoints | Policy stored and visible in UI |
| P5-005-PHASE5-GATE-REPORT | User | TODO | Validate drawdown and tail-risk improvements | Phase validator + MC outputs | DD reduced, p95 MC DD not worse |

---

## Phase 6: Drift Detection + Auto-Degrade + Production Readiness

| Ticket | Owner | Status | Scope | Target Files | Done Criteria |
|--------|-------|--------|-------|--------------|---------------|
| P6-001-DRIFT-MONITOR | Codex | TODO | Rolling Sharpe, WR trend, calibration drift monitors | `drift_monitor.py` | Alerts emitted with timestamps + strategy IDs |
| P6-002-AUTO-DEGRADE-ACTIONS | Opus | TODO | Auto reduce-size/cooldown/disable actions | `strategy_lifecycle.py` | Simulated triggers execute correct actions |
| P6-003-WEEKLY-REVALIDATION-JOB | Codex | TODO | Scheduled purged WF + block-bootstrap + cost stress | `phase_validation.py` | Weekly report generated automatically |
| P6-004-AUDIT-AND-ROLLOUT-CONTROLS | Opus | TODO | Add rollout checklist + audit endpoint | `routes.py` | Capital ramp audit trail complete |
| P6-005-PHASE6-GATE-REPORT | User | TODO | Final production-readiness signoff | Ops report | Demo-live parity stable, incident limits respected |

---

## Owner Legend

- **Codex**: Implements feature
- **Opus**: Validates / implements assigned tickets
- **User**: Approves gate reports, defines policy

## Validation Protocol

1. After Codex completes a ticket → Opus reads all modified files and verifies correctness
2. After Opus completes a ticket → Codex reads all modified files and verifies correctness
3. Gate reports require User sign-off before proceeding to next phase
