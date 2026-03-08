# Earnings IV Crush Data Prep (Databento)

This guide explains how to prepare CSV data for the `earnings_volatility_strategy`.

## What this pipeline now guarantees

- OHLCV comes from Databento (`XNAS.ITCH`, `ohlcv-1m`) and is resampled locally.
- Earnings schedule features are **known-ahead** (CSV or yfinance), not inferred from future bars.
- IV proxy features are deterministic (no random noise) and avoid future-leaking backfills.
- Output is saved directly to `data/historical/` so the backtest engine can load it immediately.

## Install

```bash
pip install databento python-dotenv yfinance
```

## Configure API key

Set your key in `dashboard/.env`:

```env
DATABENTO_API_KEY=YOUR_KEY_HERE
```

Do not commit real keys to source control.

## Run

```bash
python scripts/fetch_earnings_strategy_data.py \
  --symbol AAPL \
  --start 2024-01-01 \
  --end 2024-12-31 \
  --timeframe M15
```

Optional: provide your own earnings calendar (recommended for reproducibility):

```bash
python scripts/fetch_earnings_strategy_data.py \
  --symbol AAPL \
  --start 2024-01-01 \
  --end 2024-12-31 \
  --timeframe M15 \
  --earnings-csv data/earnings_calendar.csv
```

`earnings_csv` format:

- required column: `earnings_date`
- optional column: `symbol`
- optional column: `is_estimated` (for projected future dates)

Example:

```csv
symbol,earnings_date
AAPL,2024-02-01
AAPL,2024-05-02
AAPL,2024-08-01
AAPL,2024-11-01
```

Repository default calendar:

- canonical path: `data/earnings_calendar.csv`
- mirrored for compatibility: `dashboard/data/earnings_calendar.csv`
- includes `AAPL, MSFT, NVDA, AMZN, META, TSLA`
- includes years `2023, 2024, 2025, 2026`
- symbols are normalized without leading/trailing spaces

## Output

Files are written to:

- `data/historical/{SYMBOL}_{TIMEFRAME}_{YYYYMMDD}_{YYYYMMDD}_earnings.csv`

This matches the backend loader conventions.

## Required columns produced

- Price/volume: `open`, `high`, `low`, `close`, `volume`
- Schedule: `earnings_event`, `days_to_earnings`, `is_pre_earnings_day`, `next_earnings_date`, `planned_exit_date`
- Volatility proxies: `iv_front`, `iv_back`, `iv_45d`, `iv30`, `rv30`, `volume30`

## Notes

- Databento OHLCV is used for price/volume.
- Earnings dates are sourced from `--earnings-csv` or yfinance (with limited static fallback for major names).
- If no earnings dates are available, strategy entries may be zero.

## Optional: Build Event-Level Edge Dataset

After generating `*_earnings.csv`, you can build deterministic event rows and pre-filter trade candidates:

```bash
python scripts/build_earnings_edge_dataset.py \
  --symbol AAPL \
  --timeframe M15 \
  --preset default \
  --input-csv data/historical/AAPL_M15_20240101_20241231_earnings.csv
```

See `scripts/README_EARNINGS_EDGE.md` for schema and selector rules.
