# Earnings Edge Dataset + Candidate Selection

This pipeline converts bar-level earnings data into deterministic event-level rows and then applies strict filters to produce `trade_candidates.csv`.

It is designed to align with `earnings_volatility_strategy` preset logic.

## Inputs

- Prepared bars CSV (recommended): `data/historical/*_earnings.csv`
- Or Databento fetch path via script arguments (`--start`, `--end`)

Required bar-level columns:

- `open`, `high`, `low`, `close`, `volume`
- `earnings_event`, `days_to_earnings`, `is_pre_earnings_day`, `next_earnings_date`, `planned_exit_date`
- `iv_front`, `iv_back`, `iv_45d`, `iv30`, `rv30`, `volume30`

## Run (from existing prepared CSV)

```bash
python scripts/build_earnings_edge_dataset.py \
  --symbol AAPL \
  --timeframe M15 \
  --preset default \
  --input-csv data/historical/AAPL_M15_20240101_20241231_earnings.csv
```

## Run (fetch + build in one command)

```bash
python scripts/build_earnings_edge_dataset.py \
  --symbol AAPL \
  --timeframe M15 \
  --preset default \
  --start 2024-01-01 \
  --end 2024-12-31 \
  --earnings-csv data/earnings_calendar.csv
```

## Outputs

In `data/historical/`:

- `*_earnings_events.csv`
- `*_trade_candidates.csv`

## Event-level output schema

- `symbol`
- `entry_day`, `event_day`, `exit_day`
- `signal_ts`, `entry_ts_target`, `exit_ts`
- `entry_ref_price`, `exit_price`
- `expected_move_pct`, `expected_move_abs`
- `realized_move_pct`, `realized_move_abs`
- `edge_pct`, `edge_abs`
- `iv_front`, `iv_back`, `iv_45d`, `iv30`, `rv30`
- `iv30_rv30_ratio`, `term_structure_slope`, `volume30`

## Candidate selection rules

Rules mirror preset thresholds from `strategy_registry.py`:

- `term_structure_slope <= term_structure_max_slope`
- `volume30 >= min_avg_volume30`
- `iv30_rv30_ratio >= min_iv30_rv30_ratio`
- `edge_pct >= min_edge_pct` (CLI parameter, default `0.0`)

Candidate CSV adds:

- `rule_term_structure`
- `rule_volume30`
- `rule_iv30_rv30`
- `rule_edge`
- `selected`
- `selection_score` (0-4)
