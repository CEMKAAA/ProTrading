# Options Edge Phase 1 Usage

## Endpoint
- `POST /api/v1/options-edge/scan/run`

## Request (inline universe)
```json
{
  "top_n": 8,
  "max_sector_fraction": 0.35,
  "gate_config": {
    "min_iv_rank": 0.40,
    "min_iv_hv_spread": 0.03,
    "min_option_volume_30d": 1000,
    "min_option_oi_30d": 2000,
    "max_bid_ask_pct": 0.015,
    "min_days_to_earnings": 10,
    "max_borrow_rate": 0.08
  },
  "score_weights": {
    "vol_edge": 0.40,
    "liquidity": 0.30,
    "event_timing": 0.15,
    "risk": 0.15
  },
  "universe": [
    {
      "symbol": "AAPL",
      "sector": "Technology",
      "price": 190,
      "iv30": 0.35,
      "hv30": 0.22,
      "iv_rank_252": 0.72,
      "avg_opt_volume_30d": 25000,
      "avg_oi_30d": 120000,
      "avg_bid_ask_pct": 0.008,
      "days_to_earnings": 25,
      "borrow_rate": 0.01
    }
  ]
}
```

## Request (CSV file)
```json
{
  "csv_file": "sp500_options_snapshot.csv",
  "top_n": 8,
  "max_sector_fraction": 0.35
}
```

CSV lookup paths:
- `dashboard/data/options/{csv_file}`
- `dashboard/data/historical/{csv_file}`
- `dashboard/data/{csv_file}`

## Read Results
- `GET /api/v1/options-edge/scan/{scan_id}`
- `GET /api/v1/options-edge/scan/{scan_id}/candidates?selected_only=true`
- `GET /api/v1/options-edge/scans?limit=20`

## Phase 2 (Strategy Builder)
`POST /api/v1/options-edge/scan/run` now supports option-chain input:

```json
{
  "csv_file": "sp500_options_snapshot.csv",
  "chain_csv_file": "sp500_option_chain_snapshot.csv",
  "build_strategies": true,
  "builder_config": {
    "structure_mode": "auto",
    "target_delta_abs": 0.25,
    "preferred_dte_min": 30,
    "preferred_dte_max": 45
  }
}
```

You can also pass chain rows inline via `option_chain`.

Read built strategy cards:
- `GET /api/v1/options-edge/scan/{scan_id}/trades`
- `GET /api/v1/options-edge/scan/{scan_id}/trades?symbol=AAPL`

Builder diagnostics per selected symbol are now returned in:
- `GET /api/v1/options-edge/scan/{scan_id}/candidates?selected_only=true`
Fields:
- `builder_status`: `built` / `rejected` / `skipped`
- `builder_policy`: which auto-policy selected the structure
- `builder_reasons`: deterministic rejection reasons when no structure was built

Expected chain columns (aliases supported):
- `symbol`, `expiry_date`, `option_type` (`C/P`), `strike`, `bid`, `ask`
- Optional: `delta`, `theta`, `vega`, `volume`, `oi`, `dte`

Optional universe columns for auto policy:
- `trend_20d_return` (directional bias)
- `put_call_skew` (skew-based directional fallback)

## Phase 2.2 (Live Connector)
Provider status:
- `GET /api/v1/options-edge/providers/polygon/status`
- `GET /api/v1/options-edge/providers/polygon/probe?symbol=AAPL` (entitlement matrix: stock vs options access)

Run live scan (Polygon REST -> deterministic scan pipeline):
- `POST /api/v1/options-edge/scan/run-live`

Example request:
```json
{
  "provider": "polygon",
  "symbols": ["AAPL", "MSFT", "NVDA", "TSLA"],
  "min_dte": 21,
  "max_dte": 55,
  "lookback_days": 45,
  "default_days_to_earnings": 999,
  "build_strategies": true,
  "top_n": 8,
  "max_sector_fraction": 0.35
}
```

Environment:
- `POLYGON_API_KEY` in `dashboard/.env` (or process env)

Note:
- Flat-file/S3 access is not required for this flow.
- Current live connector computes IV/HV/liquidity metrics from REST snapshots and aggregates;
  earnings timing defaults to `default_days_to_earnings` unless you enrich it separately.
