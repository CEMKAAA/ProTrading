"""
Live data connectors for options-edge scans.

Phase 2.2 (backend-only):
- Polygon REST connector for stock snapshot + option chain snapshot
- Converts live responses into normalized universe + chain dataframes
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from datetime import date, datetime, timedelta, timezone
from io import StringIO
import math
import os
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import httpx
import numpy as np
import pandas as pd

from .scan_engine import normalize_universe_dataframe
from .strategy_builder import normalize_option_chain_dataframe


SP500_FALLBACK_SYMBOLS: List[str] = [
    "AAPL", "MSFT", "NVDA", "AMZN", "META", "GOOGL", "TSLA", "BRK.B", "JPM", "LLY",
    "V", "XOM", "UNH", "MA", "JNJ", "PG", "HD", "COST", "MRK", "ABBV",
    "AVGO", "ADBE", "PEP", "KO", "CRM", "WMT", "BAC", "NFLX", "AMD", "MCD",
    "CVX", "TMO", "ORCL", "ACN", "CSCO", "QCOM", "INTU", "ABT", "IBM", "LIN",
    "GE", "AMAT", "CAT", "DIS", "SPGI", "GS", "MS", "PLTR", "BKNG", "ISRG",
]

SP500_REMOTE_SOURCES: List[str] = [
    "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/main/data/constituents.csv",
    "https://raw.githubusercontent.com/datasets/s-and-p-500-companies/main/data/constituents_symbols.txt",
]


def _safe_float(v: Any, default: float = np.nan) -> float:
    try:
        if v is None:
            return float(default)
        f = float(v)
        if math.isnan(f) or math.isinf(f):
            return float(default)
        return f
    except Exception:
        return float(default)


def _clamp(v: float, lo: float, hi: float) -> float:
    return float(max(lo, min(hi, v)))


def _get_nested(obj: Dict[str, Any], path: str, default: Any = None) -> Any:
    cur: Any = obj
    for key in path.split("."):
        if not isinstance(cur, dict) or key not in cur:
            return default
        cur = cur[key]
    return cur


def _mask_api_key(key: Optional[str]) -> Optional[str]:
    if not key:
        return None
    if len(key) <= 8:
        return "*" * len(key)
    return f"{key[:4]}...{key[-4:]}"


def _read_env_file_value(var_name: str) -> Optional[str]:
    """
    Lightweight .env lookup without requiring python-dotenv at runtime.
    Search order:
    1) dashboard/.env
    2) .env (repo root)
    """
    repo_root = Path(__file__).resolve().parents[4]
    candidates = [
        repo_root / "dashboard" / ".env",
        repo_root / ".env",
    ]
    for p in candidates:
        if not p.exists():
            continue
        try:
            for raw in p.read_text(encoding="utf-8").splitlines():
                line = raw.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                if k.strip() != var_name:
                    continue
                val = v.strip().strip("\"").strip("'")
                if val:
                    return val
        except Exception:
            continue
    return None


def resolve_polygon_api_key() -> Optional[str]:
    return os.getenv("POLYGON_API_KEY") or _read_env_file_value("POLYGON_API_KEY")


@dataclass
class LiveOptionsDataset:
    universe_df: pd.DataFrame
    chain_df: pd.DataFrame
    metadata: Dict[str, Any]


class PolygonOptionsConnector:
    """
    Polygon REST connector for options-edge live scans.
    """

    def __init__(
        self,
        api_key: Optional[str] = None,
        base_url: str = "https://api.polygon.io",
        timeout_sec: float = 25.0,
    ):
        self.api_key = api_key or resolve_polygon_api_key()
        self.base_url = base_url.rstrip("/")
        self.timeout_sec = float(timeout_sec)
        self._fund_cache: Dict[str, Dict[str, Any]] = {}
        self._earnings_calendar_cache: Optional[pd.DataFrame] = None
        self._iv_history_cache: Optional[pd.DataFrame] = None

    def status(self) -> Dict[str, Any]:
        configured = bool(self.api_key)
        return {
            "provider": "polygon",
            "configured": configured,
            "api_key_masked": _mask_api_key(self.api_key),
            "base_url": self.base_url,
            "warnings": [] if configured else ["POLYGON_API_KEY missing"],
        }

    def _probe_endpoint(self, name: str, path: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        if not self.api_key:
            return {
                "name": name,
                "path": path,
                "ok": False,
                "status_code": None,
                "access": "missing_key",
                "message": "POLYGON_API_KEY missing",
            }

        url = f"{self.base_url}{path}"
        q = dict(params or {})
        q.setdefault("apiKey", self.api_key)
        try:
            with httpx.Client(timeout=self.timeout_sec) as client:
                res = client.get(url, params=q)
            msg = ""
            try:
                body = res.json()
                msg = str(body.get("message") or body.get("error") or body.get("status") or "")
            except Exception:
                msg = res.text[:240]

            code = int(res.status_code)
            if code < 300:
                access = "ok"
            elif code == 401:
                access = "invalid_key"
            elif code == 403:
                access = "not_entitled"
            elif code == 429:
                access = "rate_limited"
            else:
                access = "error"
            return {
                "name": name,
                "path": path,
                "ok": bool(code < 300),
                "status_code": code,
                "access": access,
                "message": msg[:240],
            }
        except Exception as e:
            return {
                "name": name,
                "path": path,
                "ok": False,
                "status_code": None,
                "access": "network_error",
                "message": str(e)[:240],
            }

    def probe_entitlements(self, symbol: str = "AAPL") -> Dict[str, Any]:
        sym = str(symbol or "AAPL").upper().strip() or "AAPL"
        checks = [
            ("stock_ticker_overview", f"/v3/reference/tickers/{sym}", {"limit": 1}),
            ("stock_snapshot", f"/v2/snapshot/locale/us/markets/stocks/tickers/{sym}", {}),
            ("options_chain_snapshot", f"/v3/snapshot/options/{sym}", {"limit": 1}),
        ]
        results = [self._probe_endpoint(name, path, params) for (name, path, params) in checks]
        return {
            "provider": "polygon",
            "symbol": sym,
            "configured": bool(self.api_key),
            "api_key_masked": _mask_api_key(self.api_key),
            "results": results,
        }

    def get_daily_bars(self, symbol: str, start_date: str, end_date: str) -> pd.DataFrame:
        """Fetch daily OHLCV bars from Polygon aggregates endpoint."""
        if not self.api_key:
            raise RuntimeError("POLYGON_API_KEY missing")
        sym = str(symbol or "").upper().strip()
        if not sym:
            raise ValueError("symbol is required")
        start_s = str(start_date or "").strip()
        end_s = str(end_date or "").strip()
        if not start_s or not end_s:
            raise ValueError("start_date and end_date are required (YYYY-MM-DD)")

        url = f"{self.base_url}/v2/aggs/ticker/{sym}/range/1/day/{start_s}/{end_s}"
        params = {
            "adjusted": "true",
            "sort": "asc",
            "limit": 50000,
            "apiKey": self.api_key,
        }
        with httpx.Client(timeout=max(self.timeout_sec, 30.0)) as client:
            res = client.get(url, params=params)
        if res.status_code >= 300:
            msg = res.text[:300]
            raise RuntimeError(f"polygon_daily_bars HTTP {res.status_code}: {msg}")
        body = res.json()
        rows = body.get("results") if isinstance(body, dict) else None
        if not isinstance(rows, list) or len(rows) == 0:
            return pd.DataFrame(columns=["date", "open", "high", "low", "close", "volume"])

        out = []
        for r in rows:
            if not isinstance(r, dict):
                continue
            ts_ms = _safe_float(r.get("t"), np.nan)
            if not np.isfinite(ts_ms):
                continue
            dt = datetime.fromtimestamp(ts_ms / 1000.0, tz=timezone.utc).date()
            out.append(
                {
                    "date": dt,
                    "open": _safe_float(r.get("o"), np.nan),
                    "high": _safe_float(r.get("h"), np.nan),
                    "low": _safe_float(r.get("l"), np.nan),
                    "close": _safe_float(r.get("c"), np.nan),
                    "volume": _safe_float(r.get("v"), np.nan),
                }
            )
        df = pd.DataFrame(out)
        if df.empty:
            return pd.DataFrame(columns=["date", "open", "high", "low", "close", "volume"])
        df = df.sort_values("date")
        return df

    def get_sp500_symbols(self, limit: int = 475) -> List[str]:
        """
        Resolve S&P500 universe symbols from local file, fallback to embedded liquid set.
        Expected local file: dashboard/data/options/sp500_symbols.csv with column `symbol`.
        """
        lim = max(1, min(int(limit), 600))
        repo_root = Path(__file__).resolve().parents[4]
        csv_candidates = [
            repo_root / "dashboard" / "data" / "options" / "sp500_symbols.csv",
            repo_root / "dashboard" / "data" / "sp500_symbols.csv",
            repo_root / "data" / "sp500_symbols.csv",
        ]
        for p in csv_candidates:
            if not p.exists():
                continue
            try:
                raw = pd.read_csv(p)
                cols = [str(c).strip().lower() for c in raw.columns]
                raw.columns = cols
                if "symbol" not in cols:
                    continue
                syms = []
                for s in raw["symbol"].tolist():
                    t = str(s or "").upper().strip()
                    if t:
                        syms.append(t)
                syms = sorted(list(dict.fromkeys(syms)))
                if syms:
                    return syms[:lim]
            except Exception:
                continue
        remote = self._fetch_remote_sp500_symbols(limit=lim)
        if remote:
            return remote
        return SP500_FALLBACK_SYMBOLS[: min(lim, len(SP500_FALLBACK_SYMBOLS))]

    def _fetch_remote_sp500_symbols(self, limit: int) -> List[str]:
        lim = max(1, min(int(limit), 600))
        for src in SP500_REMOTE_SOURCES:
            try:
                with httpx.Client(timeout=min(self.timeout_sec, 20.0)) as client:
                    res = client.get(src)
                    if res.status_code >= 300:
                        continue
                    text = str(res.text or "")
                syms: List[str] = []
                if src.endswith(".csv"):
                    rows = pd.read_csv(StringIO(text))
                    cols = [str(c).strip().lower() for c in rows.columns]
                    rows.columns = cols
                    if "symbol" not in cols:
                        continue
                    for s in rows["symbol"].tolist():
                        t = str(s or "").upper().strip()
                        if t:
                            syms.append(t)
                else:
                    syms = [line.strip().upper() for line in text.splitlines() if line.strip()]
                syms = sorted(list(dict.fromkeys(syms)))
                if syms:
                    return syms[:lim]
            except Exception:
                continue
        return []

    def _request_json(self, path_or_url: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        if not self.api_key:
            raise RuntimeError("POLYGON_API_KEY missing")

        params = dict(params or {})
        if path_or_url.startswith("http://") or path_or_url.startswith("https://"):
            url = path_or_url
            if "apiKey=" not in url:
                params.setdefault("apiKey", self.api_key)
        else:
            url = f"{self.base_url}{path_or_url}"
            params.setdefault("apiKey", self.api_key)

        with httpx.Client(timeout=self.timeout_sec) as client:
            res = client.get(url, params=params)
            if res.status_code >= 400:
                body = res.text[:400]
                raise RuntimeError(f"Polygon HTTP {res.status_code}: {body}")
            data = res.json()
            if isinstance(data, dict) and str(data.get("status", "")).upper() == "ERROR":
                raise RuntimeError(str(data.get("error", "Polygon returned ERROR")))
            return data

    def _fetch_ticker_overview_sector(self, symbol: str) -> str:
        """
        Prefer coarse sector-ish field when available.
        """
        try:
            data = self._request_json(f"/v3/reference/tickers/{symbol}")
            res = data.get("results") or {}
            # Polygon docs expose sic_description reliably on ticker overview.
            sector = (res.get("sic_description") or "").strip()
            return sector or "UNKNOWN"
        except Exception:
            return "UNKNOWN"

    def _fetch_ticker_details(self, symbol: str) -> Dict[str, Any]:
        try:
            data = self._request_json(f"/v3/reference/tickers/{symbol}")
            res = data.get("results")
            return res if isinstance(res, dict) else {}
        except Exception:
            return {}

    def _fetch_financial_rows(self, symbol: str, limit: int = 8) -> List[Dict[str, Any]]:
        """
        Best-effort financial statement fetch.
        Polygon has changed financial endpoints over time; try common variants.
        """
        attempts: List[Tuple[str, Dict[str, Any]]] = [
            (
                "/vx/reference/financials",
                {
                    "ticker": symbol,
                    "timeframe": "annual",
                    "order": "desc",
                    "sort": "filing_date",
                    "limit": int(max(1, min(limit, 20))),
                },
            ),
            (
                "/vX/reference/financials",
                {
                    "ticker": symbol,
                    "timeframe": "annual",
                    "order": "desc",
                    "sort": "filing_date",
                    "limit": int(max(1, min(limit, 20))),
                },
            ),
            (f"/v2/reference/financials/{symbol}", {"limit": int(max(1, min(limit, 20)))}),
        ]
        for path, params in attempts:
            try:
                data = self._request_json(path, params=params)
                rows = data.get("results")
                if isinstance(rows, list) and rows:
                    return [r for r in rows if isinstance(r, dict)]
            except Exception:
                continue
        return []

    @staticmethod
    def _extract_number(value: Any) -> float:
        if isinstance(value, dict):
            if "value" in value:
                return _safe_float(value.get("value"), np.nan)
            for k in ("amount", "raw", "reported_value"):
                if k in value:
                    return _safe_float(value.get(k), np.nan)
            return float(np.nan)
        return _safe_float(value, np.nan)

    @classmethod
    def _statement_value(cls, financials: Dict[str, Any], statement: str, keys: List[str]) -> float:
        st = financials.get(statement) if isinstance(financials, dict) else None
        if not isinstance(st, dict):
            return float(np.nan)
        for key in keys:
            if key in st:
                v = cls._extract_number(st.get(key))
                if np.isfinite(v):
                    return float(v)
        # fallback: token search
        for k, raw in st.items():
            lk = str(k).lower()
            if any(token in lk for token in [x.lower() for x in keys]):
                v = cls._extract_number(raw)
                if np.isfinite(v):
                    return float(v)
        return float(np.nan)

    def _fetch_price_vs_sma200(self, symbol: str, spot_price: Optional[float] = None) -> float:
        try:
            end = datetime.now(timezone.utc).date()
            start = end - timedelta(days=420)
            data = self._request_json(
                f"/v2/aggs/ticker/{symbol}/range/1/day/{start.isoformat()}/{end.isoformat()}",
                params={"adjusted": "true", "sort": "asc", "limit": 2000},
            )
            rows = data.get("results") if isinstance(data, dict) else None
            if not isinstance(rows, list) or len(rows) < 60:
                return float(np.nan)
            closes = [ _safe_float(r.get("c"), np.nan) for r in rows if isinstance(r, dict) ]
            closes = [c for c in closes if np.isfinite(c) and c > 0]
            if len(closes) < 60:
                return float(np.nan)
            s = pd.Series(closes, dtype=float)
            sma200 = _safe_float(s.tail(200).mean(), np.nan)
            spot = _safe_float(spot_price, np.nan)
            if not (np.isfinite(spot) and spot > 0):
                spot = _safe_float(s.iloc[-1], np.nan)
            if not (np.isfinite(spot) and np.isfinite(sma200) and sma200 > 0):
                return float(np.nan)
            return float((spot - sma200) / sma200 * 100.0)
        except Exception:
            return float(np.nan)

    def get_csp_fundamentals(
        self,
        symbol: str,
        *,
        spot_price: Optional[float] = None,
        include_price_vs_sma200: bool = False,
    ) -> Dict[str, Any]:
        """
        Build best-effort CSP fundamentals snapshot for one symbol from Polygon endpoints.
        """
        sym = str(symbol or "").upper().strip()
        if not sym:
            return {}
        if sym in self._fund_cache and not include_price_vs_sma200:
            return dict(self._fund_cache[sym])

        details = self._fetch_ticker_details(sym)
        fin_rows = self._fetch_financial_rows(sym, limit=8)
        annual_rows = [r for r in fin_rows if isinstance(r, dict)]

        def _sort_key(r: Dict[str, Any]) -> str:
            return str(r.get("fiscal_year") or r.get("end_date") or r.get("filing_date") or "")
        annual_rows = sorted(annual_rows, key=_sort_key, reverse=True)

        revenues: List[float] = []
        net_incomes: List[float] = []
        eps_values: List[float] = []
        latest_assets = float(np.nan)
        latest_liabilities = float(np.nan)
        latest_fcf = float(np.nan)

        for i, row in enumerate(annual_rows):
            financials = row.get("financials") if isinstance(row.get("financials"), dict) else row
            rev = self._statement_value(financials, "income_statement", ["revenues", "revenue", "total_revenues"])
            ni = self._statement_value(financials, "income_statement", ["net_income_loss", "net_income"])
            eps = self._statement_value(
                financials,
                "income_statement",
                ["basic_earnings_per_share", "diluted_earnings_per_share", "earnings_per_share_basic"],
            )
            if np.isfinite(rev):
                revenues.append(float(rev))
            if np.isfinite(ni):
                net_incomes.append(float(ni))
            if np.isfinite(eps):
                eps_values.append(float(eps))

            if i == 0:
                latest_assets = self._statement_value(financials, "balance_sheet", ["assets", "total_assets"])
                latest_liabilities = self._statement_value(financials, "balance_sheet", ["liabilities", "total_liabilities"])
                op_cf = self._statement_value(
                    financials,
                    "cash_flow_statement",
                    ["net_cash_flow_from_operating_activities", "net_cash_from_operating_activities", "operating_cash_flow"],
                )
                capex = self._statement_value(
                    financials,
                    "cash_flow_statement",
                    ["capital_expenditure", "capital_expenditures"],
                )
                if np.isfinite(op_cf):
                    cap = abs(capex) if np.isfinite(capex) else 0.0
                    latest_fcf = float(op_cf - cap)

        revenue_growth_pct = float(np.nan)
        if len(revenues) >= 2 and abs(revenues[1]) > 1e-9:
            revenue_growth_pct = float((revenues[0] / revenues[1] - 1.0) * 100.0)

        # Use net_income growth instead of per-share EPS growth to avoid
        # stock-split distortion (e.g. NVDA 10:1, AMZN 20:1 make pre-split
        # EPS appear much larger than post-split, yielding false negative growth).
        eps_growth_5y_pct = float(np.nan)
        ni_clean = [v for v in net_incomes if np.isfinite(v) and v > 0]
        if len(ni_clean) >= 2:
            old = float(ni_clean[min(len(ni_clean) - 1, 4)])
            new = float(ni_clean[0])
            years = float(min(5, len(ni_clean) - 1))
            if old > 0 and years > 0:
                eps_growth_5y_pct = float(((new / old) ** (1.0 / years) - 1.0) * 100.0)

        eps_growth_fwd_pct = float(np.nan)
        for key in ("projected_eps_growth", "eps_growth", "earnings_growth", "eps_growth_fwd_pct"):
            v = _safe_float(details.get(key), np.nan)
            if np.isfinite(v):
                eps_growth_fwd_pct = float(v * 100.0) if abs(v) <= 1.0 else float(v)
                break
        if not np.isfinite(eps_growth_fwd_pct):
            seeds = [x for x in [revenue_growth_pct, eps_growth_5y_pct] if np.isfinite(x)]
            if len(seeds) > 0:
                eps_growth_fwd_pct = float(np.mean(seeds) * 0.6)

        profit_margin_pct = float(np.nan)
        if len(net_incomes) > 0 and len(revenues) > 0 and abs(revenues[0]) > 1e-9:
            profit_margin_pct = float((net_incomes[0] / revenues[0]) * 100.0)

        pe_current = float(np.nan)
        for key in ("pe_ratio", "price_earnings_ratio", "trailing_pe"):
            v = _safe_float(details.get(key), np.nan)
            if np.isfinite(v):
                pe_current = float(v)
                break
        spot = _safe_float(spot_price, np.nan)
        if not np.isfinite(pe_current) and np.isfinite(spot):
            # Financial rows are annual. Using the sum of multiple annual EPS values
            # understates P/E materially. Fallback to the latest annual EPS only.
            eps_latest = float(eps_values[0]) if len(eps_values) > 0 else float(np.nan)
            if np.isfinite(eps_latest) and abs(eps_latest) > 1e-9:
                pe_current = float(spot / eps_latest)

        pe_5y_avg = _safe_float(details.get("pe_5y_avg"), np.nan)
        pe_10y_avg = _safe_float(details.get("pe_10y_avg"), np.nan)

        price_vs_sma200 = float(np.nan)
        if include_price_vs_sma200:
            price_vs_sma200 = self._fetch_price_vs_sma200(sym, spot_price=spot if np.isfinite(spot) else None)

        out = {
            "symbol": sym,
            "sector": str(details.get("sic_description") or details.get("sector") or "UNKNOWN"),
            "industry": str(details.get("sic_description") or details.get("industry") or ""),
            "revenue_growth_pct": float(revenue_growth_pct) if np.isfinite(revenue_growth_pct) else np.nan,
            "eps_growth_5y_pct": float(eps_growth_5y_pct) if np.isfinite(eps_growth_5y_pct) else np.nan,
            "eps_growth_fwd_pct": float(eps_growth_fwd_pct) if np.isfinite(eps_growth_fwd_pct) else np.nan,
            "profit_margin_pct": float(profit_margin_pct) if np.isfinite(profit_margin_pct) else np.nan,
            "total_assets": float(latest_assets) if np.isfinite(latest_assets) else np.nan,
            "total_liabilities": float(latest_liabilities) if np.isfinite(latest_liabilities) else np.nan,
            "free_cash_flow": float(latest_fcf) if np.isfinite(latest_fcf) else np.nan,
            "pe_current": float(pe_current) if np.isfinite(pe_current) else np.nan,
            "pe_5y_avg": float(pe_5y_avg) if np.isfinite(pe_5y_avg) else np.nan,
            "pe_10y_avg": float(pe_10y_avg) if np.isfinite(pe_10y_avg) else np.nan,
            "price_vs_sma200": float(price_vs_sma200) if np.isfinite(price_vs_sma200) else np.nan,
        }
        self._fund_cache[sym] = dict(out)
        return out

    def get_csp_fundamentals_batch(
        self,
        symbols: List[str],
        spot_by_symbol: Optional[Dict[str, float]] = None,
        include_price_vs_sma200: bool = False,
    ) -> Dict[str, Dict[str, Any]]:
        out: Dict[str, Dict[str, Any]] = {}
        for raw in symbols:
            sym = str(raw or "").upper().strip()
            if not sym:
                continue
            spot = None
            if isinstance(spot_by_symbol, dict):
                spot = spot_by_symbol.get(sym)
            try:
                out[sym] = self.get_csp_fundamentals(
                    sym,
                    spot_price=spot,
                    include_price_vs_sma200=bool(include_price_vs_sma200),
                )
            except Exception:
                out[sym] = {"symbol": sym}
        return out

    def _fetch_stock_snapshot_price(self, symbol: str) -> float:
        data = self._request_json(f"/v2/snapshot/locale/us/markets/stocks/tickers/{symbol}")
        t = data.get("ticker") or {}
        # Fallback chain for spot.
        candidates = [
            _get_nested(t, "day.c"),
            _get_nested(t, "min.c"),
            _get_nested(t, "lastTrade.p"),
            _get_nested(t, "prevDay.c"),
        ]
        for c in candidates:
            v = _safe_float(c, np.nan)
            if np.isfinite(v) and v > 0:
                return float(v)
        raise RuntimeError(f"Unable to resolve spot price for {symbol}")

    def _fetch_hv30(self, symbol: str, lookback_days: int = 45) -> float:
        hv30, _trend20 = self._fetch_hv30_and_trend20(symbol, lookback_days=lookback_days)
        return hv30

    def _fetch_hv30_and_trend20(self, symbol: str, lookback_days: int = 45) -> Tuple[float, float]:
        end = datetime.now(timezone.utc).date()
        start = end - timedelta(days=max(35, int(lookback_days)))
        data = self._request_json(
            f"/v2/aggs/ticker/{symbol}/range/1/day/{start.isoformat()}/{end.isoformat()}",
            params={"adjusted": "true", "sort": "asc", "limit": 5000},
        )
        rows = data.get("results") or []
        closes = []
        for r in rows:
            c = _safe_float(r.get("c"), np.nan)
            if np.isfinite(c) and c > 0:
                closes.append(c)
        if len(closes) < 31:
            return float(np.nan), float(np.nan)
        s = pd.Series(closes, dtype=float)
        ret = np.log(s / s.shift(1)).dropna()
        trend20 = float(np.nan)
        if len(s) >= 21:
            base = _safe_float(s.iloc[-21], np.nan)
            now = _safe_float(s.iloc[-1], np.nan)
            if np.isfinite(base) and np.isfinite(now) and abs(base) > 1e-9:
                trend20 = float((now / base) - 1.0)
        if len(ret) < 20:
            return float(np.nan), trend20
        hv = ret.tail(30).std(ddof=1) * math.sqrt(252.0)
        hv30 = float(hv) if np.isfinite(hv) else float(np.nan)
        return hv30, trend20

    def _load_earnings_calendar(self) -> pd.DataFrame:
        if self._earnings_calendar_cache is not None:
            return self._earnings_calendar_cache
        repo_root = Path(__file__).resolve().parents[4]
        candidates = [
            repo_root / "dashboard" / "data" / "earnings_calendar.csv",
            repo_root / "data" / "earnings_calendar.csv",
        ]
        for p in candidates:
            if not p.exists():
                continue
            try:
                df = pd.read_csv(p)
                cols = [str(c).strip().lower() for c in df.columns]
                df.columns = cols
                if "symbol" not in cols or "earnings_date" not in cols:
                    continue
                df["symbol"] = df["symbol"].astype(str).str.upper().str.strip()
                df["earnings_date"] = pd.to_datetime(df["earnings_date"], errors="coerce").dt.date
                df = df.dropna(subset=["earnings_date"])
                self._earnings_calendar_cache = df
                return df
            except Exception:
                continue
        self._earnings_calendar_cache = pd.DataFrame(columns=["symbol", "earnings_date"])
        return self._earnings_calendar_cache

    def _iv_history_path(self) -> Path:
        repo_root = Path(__file__).resolve().parents[4]
        return repo_root / "dashboard" / "data" / "options" / "iv30_history.csv"

    def _load_iv_history(self) -> pd.DataFrame:
        if self._iv_history_cache is not None:
            return self._iv_history_cache.copy()
        p = self._iv_history_path()
        if not p.exists():
            self._iv_history_cache = pd.DataFrame(columns=["symbol", "date", "iv30"])
            return self._iv_history_cache.copy()
        try:
            df = pd.read_csv(p)
            cols = [str(c).strip().lower() for c in df.columns]
            df.columns = cols
            for required in ("symbol", "date", "iv30"):
                if required not in cols:
                    self._iv_history_cache = pd.DataFrame(columns=["symbol", "date", "iv30"])
                    return self._iv_history_cache.copy()
            df = df[["symbol", "date", "iv30"]].copy()
            df["symbol"] = df["symbol"].astype(str).str.upper().str.strip()
            df["date"] = pd.to_datetime(df["date"], errors="coerce").dt.date
            df["iv30"] = pd.to_numeric(df["iv30"], errors="coerce")
            df = df.dropna(subset=["symbol", "date", "iv30"])
            self._iv_history_cache = df
            return df.copy()
        except Exception:
            self._iv_history_cache = pd.DataFrame(columns=["symbol", "date", "iv30"])
            return self._iv_history_cache.copy()

    def _save_iv_history(self, df: pd.DataFrame) -> None:
        p = self._iv_history_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        out = df[["symbol", "date", "iv30"]].copy()
        out["symbol"] = out["symbol"].astype(str).str.upper().str.strip()
        out["date"] = pd.to_datetime(out["date"], errors="coerce").dt.date
        out["iv30"] = pd.to_numeric(out["iv30"], errors="coerce")
        out = out.dropna(subset=["symbol", "date", "iv30"])
        out = out.sort_values(["symbol", "date"]).drop_duplicates(["symbol", "date"], keep="last")
        out = out.groupby("symbol", group_keys=False).tail(400).reset_index(drop=True)
        out["date"] = out["date"].astype(str)
        tmp = p.with_suffix(".tmp")
        out.to_csv(tmp, index=False)
        tmp.replace(p)
        self._iv_history_cache = pd.DataFrame(
            {
                "symbol": out["symbol"].astype(str).str.upper().str.strip(),
                "date": pd.to_datetime(out["date"], errors="coerce").dt.date,
                "iv30": pd.to_numeric(out["iv30"], errors="coerce"),
            }
        )

    def _apply_true_iv_rank_252(
        self,
        universe_rows: List[Dict[str, Any]],
        *,
        asof_date: Optional[date] = None,
    ) -> int:
        if not universe_rows:
            return 0
        asof = asof_date or datetime.now(timezone.utc).date()
        asof_s = asof.isoformat()
        batch_rows: List[Dict[str, Any]] = []
        for row in universe_rows:
            sym = str(row.get("symbol") or "").upper().strip()
            iv30 = _safe_float(row.get("iv30"), np.nan)
            if not sym or not np.isfinite(iv30) or iv30 <= 0:
                continue
            batch_rows.append({"symbol": sym, "date": asof_s, "iv30": float(iv30)})
        if len(batch_rows) == 0:
            return 0

        hist = self._load_iv_history()
        merged = pd.concat([hist, pd.DataFrame(batch_rows)], axis=0, ignore_index=True)
        merged["symbol"] = merged["symbol"].astype(str).str.upper().str.strip()
        merged["date"] = pd.to_datetime(merged["date"], errors="coerce").dt.date
        merged["iv30"] = pd.to_numeric(merged["iv30"], errors="coerce")
        merged = merged.dropna(subset=["symbol", "date", "iv30"])
        merged = merged[merged["iv30"] > 0]
        if merged.empty:
            return 0
        merged = merged.sort_values(["symbol", "date"]).drop_duplicates(["symbol", "date"], keep="last")

        true_rank_count = 0
        for row in universe_rows:
            sym = str(row.get("symbol") or "").upper().strip()
            iv30 = _safe_float(row.get("iv30"), np.nan)
            if not sym or not np.isfinite(iv30):
                continue
            s = merged[merged["symbol"] == sym]
            if s.empty:
                continue
            window = pd.to_numeric(s["iv30"], errors="coerce").dropna().tail(252)
            if len(window) < 30:
                continue
            rank = float((window <= iv30).mean())
            if np.isfinite(rank):
                row["iv_rank_252"] = _clamp(rank, 0.0, 1.0)
                true_rank_count += 1

        self._save_iv_history(merged)
        return true_rank_count

    def _fetch_days_to_earnings(
        self,
        symbol: str,
        *,
        ticker_details: Optional[Dict[str, Any]] = None,
        default_days_to_earnings: float = 999.0,
    ) -> Tuple[float, Optional[str]]:
        # First try ticker-level fields (if provider exposes them).
        det = ticker_details if isinstance(ticker_details, dict) else {}
        date_candidates = [
            det.get("next_earnings_date"),
            det.get("earnings_date"),
            det.get("earnings_release_date"),
            det.get("next_earnings_report_date"),
        ]
        today = datetime.now(timezone.utc).date()
        for raw in date_candidates:
            try:
                if raw is None:
                    continue
                d = pd.to_datetime(str(raw), errors="coerce").date()
                if d:
                    return float((d - today).days), d.isoformat()
            except Exception:
                continue

        # Fallback: local earnings calendar used by earnings-volatility module.
        try:
            cal = self._load_earnings_calendar()
            sym = str(symbol or "").upper().strip()
            if not cal.empty and sym:
                c = cal[cal["symbol"] == sym]
                if not c.empty:
                    future = sorted([d for d in c["earnings_date"].tolist() if isinstance(d, date) and d >= today])
                    if len(future) > 0:
                        d = future[0]
                        return float((d - today).days), d.isoformat()
        except Exception:
            pass
        return float(default_days_to_earnings), None

    @staticmethod
    def _extract_borrow_rate(details: Optional[Dict[str, Any]]) -> float:
        det = details if isinstance(details, dict) else {}
        for key in ("borrow_rate", "short_borrow_rate", "stock_loan_fee", "loan_fee_rate"):
            v = _safe_float(det.get(key), np.nan)
            if np.isfinite(v):
                # Normalize percent-looking values.
                return float(v / 100.0) if abs(v) > 1.0 else float(v)
        return float(np.nan)

    def _fetch_recent_news(self, symbol: str, limit: int = 3) -> List[Dict[str, Any]]:
        lim = max(0, min(int(limit), 10))
        if lim == 0:
            return []
        try:
            data = self._request_json(
                "/v2/reference/news",
                params={
                    "ticker": symbol,
                    "limit": lim,
                    "order": "desc",
                    "sort": "published_utc",
                },
            )
            rows = data.get("results") or []
            out: List[Dict[str, Any]] = []
            for r in rows[:lim]:
                out.append({
                    "title": str(r.get("title") or "").strip(),
                    "publisher": str((r.get("publisher") or {}).get("name") or "").strip(),
                    "published_utc": str(r.get("published_utc") or ""),
                    "article_url": str(r.get("article_url") or ""),
                })
            return out
        except Exception:
            return []

    def _fetch_analyst_summary(self, symbol: str) -> Dict[str, Any]:
        """
        Best-effort analyst summary hook.
        Polygon options plan may not expose analyst endpoints; this function degrades gracefully.
        """
        # Placeholder contract for UI/reporter integration.
        return {
            "available": False,
            "source": "polygon",
            "reason": "analyst_ratings_endpoint_unavailable_or_not_entitled",
            "buy": None,
            "hold": None,
            "sell": None,
            "consensus": None,
        }

    def _fetch_option_chain(self, symbol: str, min_dte: int, max_dte: int) -> Tuple[pd.DataFrame, Dict[str, float]]:
        chain_rows: List[Dict[str, Any]] = []
        spot_candidates: List[float] = []
        today = datetime.now(timezone.utc).date()
        window_start = (today + timedelta(days=max(0, int(min_dte)))).isoformat()
        window_end = (today + timedelta(days=max(int(min_dte), int(max_dte)))).isoformat()
        url = f"/v3/snapshot/options/{symbol}"
        params: Optional[Dict[str, Any]] = {
            "limit": 250,
            # Server-side DTE window filter keeps payloads small and avoids scanning irrelevant expiries.
            "expiration_date.gte": window_start,
            "expiration_date.lte": window_end,
        }
        pages = 0
        seen_page_keys: set = set()

        while url and pages < 20:
            data = self._request_json(url, params=params)
            pages += 1
            results = data.get("results") or []
            page_key = (
                str(url),
                str(params.get("cursor")) if isinstance(params, dict) and params.get("cursor") else "",
                int(len(results)),
            )
            if page_key in seen_page_keys:
                # Defensive stop on repeated page loop.
                break
            seen_page_keys.add(page_key)
            for r in results:
                details = r.get("details") or {}
                greeks = r.get("greeks") or {}
                quote = r.get("last_quote") or {}
                last_trade = r.get("last_trade") or {}
                day = r.get("day") or {}
                under = r.get("underlying_asset") or {}

                for c in [
                    under.get("price"),
                    under.get("last_price"),
                    r.get("underlying_price"),
                ]:
                    v = _safe_float(c, np.nan)
                    if np.isfinite(v) and v > 0:
                        spot_candidates.append(float(v))

                expiry = details.get("expiration_date")
                strike = _safe_float(details.get("strike_price"), np.nan)
                ctype = str(details.get("contract_type") or "").lower()
                if ctype == "call":
                    option_type = "C"
                elif ctype == "put":
                    option_type = "P"
                else:
                    continue

                if not expiry or not np.isfinite(strike):
                    continue
                try:
                    dte = (pd.Timestamp(expiry).date() - datetime.now(timezone.utc).date()).days
                except Exception:
                    continue
                if dte < int(min_dte) or dte > int(max_dte):
                    continue

                bid = _safe_float(quote.get("bid"), np.nan)
                ask = _safe_float(quote.get("ask"), np.nan)
                if not np.isfinite(bid):
                    bid = 0.0
                if not np.isfinite(ask):
                    ask = bid
                if bid <= 0 and ask <= 0:
                    # Delayed/off-session snapshots can have empty quotes.
                    # Fallback to last trade/day close so strategy builder can still form structures.
                    # Use tight synthetic spread (0.5%) matching typical liquid mega-cap ATM options.
                    px = _safe_float(last_trade.get("price"), np.nan)
                    if not np.isfinite(px) or px <= 0:
                        px = _safe_float(day.get("close"), np.nan)
                    if np.isfinite(px) and px > 0:
                        bid = float(px * 0.9975)
                        ask = float(px * 1.0025)

                chain_rows.append(
                    {
                        "symbol": symbol,
                        "expiry_date": expiry,
                        "option_type": option_type,
                        "strike": float(strike),
                        "bid": float(max(0.0, bid)),
                        "ask": float(max(0.0, ask)),
                        "delta": _safe_float(greeks.get("delta"), np.nan),
                        "theta": _safe_float(greeks.get("theta"), np.nan),
                        "vega": _safe_float(greeks.get("vega"), np.nan),
                        "volume": _safe_float(day.get("volume"), 0.0),
                        "oi": _safe_float(r.get("open_interest"), 0.0),
                        "implied_volatility": _safe_float(r.get("implied_volatility"), np.nan),
                    }
                )

            next_url = data.get("next_url")
            next_cursor = data.get("next_cursor")
            if not isinstance(next_cursor, str) or not next_cursor:
                next_cursor = data.get("cursor")

            if isinstance(next_url, str) and next_url:
                if "cursor=" not in next_url and isinstance(next_cursor, str) and next_cursor:
                    sep = "&" if "?" in next_url else "?"
                    next_url = f"{next_url}{sep}cursor={next_cursor}"
                url = next_url
                params = None
            elif isinstance(next_cursor, str) and next_cursor:
                # Some payloads provide cursor token without a full next_url.
                url = f"/v3/snapshot/options/{symbol}"
                params = {
                    "limit": 250,
                    "cursor": next_cursor,
                    "expiration_date.gte": window_start,
                    "expiration_date.lte": window_end,
                }
            else:
                url = ""
                params = None

        raw_df = pd.DataFrame(chain_rows)
        if raw_df.empty:
            return raw_df, {
                "spot_price": np.nan,
                "iv30": np.nan,
                "avg_opt_volume_30d": np.nan,
                "avg_oi_30d": np.nan,
                "avg_bid_ask_pct": np.nan,
                "iv_rank_252": np.nan,
                "put_call_skew": np.nan,
            }

        norm_chain = normalize_option_chain_dataframe(raw_df)
        if norm_chain.empty:
            return norm_chain, {
                "spot_price": np.nan,
                "iv30": np.nan,
                "avg_opt_volume_30d": np.nan,
                "avg_oi_30d": np.nan,
                "avg_bid_ask_pct": np.nan,
                "iv_rank_252": np.nan,
                "put_call_skew": np.nan,
            }

        # Summary metrics for universe row (proxy-based from current chain snapshot).
        # Volume/OI: use SUM across all contracts (gate expects total daily option activity).
        avg_oi = float(np.nansum(norm_chain["oi"].values.astype(float)))
        avg_vol = float(np.nansum(norm_chain["volume"].values.astype(float)))
        # Notional liquidity proxies (USD): more stable for cross-symbol comparisons.
        mid_px = pd.to_numeric(norm_chain["mid"], errors="coerce")
        vol_cnt = pd.to_numeric(norm_chain["volume"], errors="coerce")
        oi_cnt = pd.to_numeric(norm_chain["oi"], errors="coerce")
        vol_notional = float(np.nansum((vol_cnt * mid_px * 100.0).values.astype(float)))
        oi_notional = float(np.nansum((oi_cnt * mid_px * 100.0).values.astype(float)))
        # If market is closed and day volume is near zero, use a conservative OI-turnover proxy.
        liquidity_notional = max(vol_notional, oi_notional * 0.03)
        # Bid-ask spread: use MEDIAN of liquid contracts (mid >= $0.50) for representative tightness.
        md = (norm_chain["bid"] + norm_chain["ask"]) / 2.0
        spread_pct = (norm_chain["ask"] - norm_chain["bid"]) / md.replace(0.0, np.nan)
        liquid_mask = md >= 0.50
        liquid_spreads = spread_pct[liquid_mask]
        if liquid_spreads.notna().sum() > 0:
            avg_bid_ask_pct = float(np.nanmedian(liquid_spreads.values.astype(float)))
        else:
            avg_bid_ask_pct = float(np.nanmedian(spread_pct.values.astype(float)))

        # iv30 proxy: near-30D contracts from snapshot implied_volatility.
        iv_source = raw_df.copy()
        expiry_ts = pd.to_datetime(iv_source["expiry_date"], errors="coerce")
        iv_source["dte"] = (expiry_ts - pd.Timestamp(datetime.now(timezone.utc).date())).dt.days
        if "implied_volatility" not in iv_source.columns:
            iv30 = float(np.nan)
        else:
            iv_slice = iv_source.copy()
            near = iv_slice[
                (pd.to_numeric(iv_slice["dte"], errors="coerce") >= 24)
                & (pd.to_numeric(iv_slice["dte"], errors="coerce") <= 38)
            ]
            src = near if not near.empty else iv_slice
            iv30 = float(np.nanmedian(pd.to_numeric(src["implied_volatility"], errors="coerce").values))

        # iv_rank proxy when true 252-day IV history is unavailable.
        # Use tighter range (0.12-0.50) so moderate-IV stocks get realistic rank estimates.
        iv_rank = float(np.nan)
        if np.isfinite(iv30):
            iv_rank = _clamp((iv30 - 0.12) / (0.50 - 0.12), 0.0, 1.0)

        # Put-call skew proxy from near 25-delta IV.
        put_call_skew = float(np.nan)
        try:
            tmp = raw_df.copy()
            tmp["delta_num"] = pd.to_numeric(tmp.get("delta"), errors="coerce")
            tmp["iv_num"] = pd.to_numeric(tmp.get("implied_volatility"), errors="coerce")
            p = tmp[(tmp["option_type"] == "P") & tmp["delta_num"].notna() & tmp["iv_num"].notna()]
            c = tmp[(tmp["option_type"] == "C") & tmp["delta_num"].notna() & tmp["iv_num"].notna()]
            if not p.empty and not c.empty:
                p_sel = p.iloc[(p["delta_num"] + 0.25).abs().argsort()[:5]]
                c_sel = c.iloc[(c["delta_num"] - 0.25).abs().argsort()[:5]]
                p_iv = float(np.nanmedian(pd.to_numeric(p_sel["iv_num"], errors="coerce").values))
                c_iv = float(np.nanmedian(pd.to_numeric(c_sel["iv_num"], errors="coerce").values))
                if np.isfinite(p_iv) and np.isfinite(c_iv):
                    put_call_skew = float(p_iv - c_iv)
        except Exception:
            put_call_skew = float(np.nan)

        spot_price = float(np.nan)
        if len(spot_candidates) > 0:
            spot_price = float(np.nanmedian(np.array(spot_candidates, dtype=float)))

        return norm_chain, {
            "spot_price": spot_price,
            "iv30": iv30,
            "avg_opt_volume_30d": avg_vol,
            "avg_oi_30d": avg_oi,
            "avg_opt_notional_30d": vol_notional,
            "liquidity_notional_proxy": liquidity_notional,
            "avg_bid_ask_pct": avg_bid_ask_pct,
            "iv_rank_252": iv_rank,
            "put_call_skew": put_call_skew,
        }

    def build_live_dataset(
        self,
        symbols: List[str],
        min_dte: int = 21,
        max_dte: int = 55,
        lookback_days: int = 45,
        default_days_to_earnings: float = 999.0,
        include_news: bool = False,
        include_analyst: bool = False,
        news_limit: int = 3,
    ) -> LiveOptionsDataset:
        cleaned = []
        for s in symbols:
            t = str(s or "").upper().strip()
            if t:
                cleaned.append(t)
        cleaned = sorted(list(dict.fromkeys(cleaned)))
        if not cleaned:
            raise ValueError("symbols list is empty")

        universe_rows: List[Dict[str, Any]] = []
        all_chain: List[pd.DataFrame] = []
        errors: Dict[str, str] = {}
        symbol_chain_debug: Dict[str, Any] = {}
        symbol_insights: Dict[str, Any] = {}

        def _process_symbol(sym: str) -> Dict[str, Any]:
            details = self._fetch_ticker_details(sym)
            sector = str(details.get("sic_description") or details.get("sector") or "UNKNOWN")
            chain_df, chain_summary = self._fetch_option_chain(sym, min_dte=min_dte, max_dte=max_dte)
            if chain_df.empty:
                raise RuntimeError("empty option chain in dte window")

            try:
                type_counts = chain_df["option_type"].value_counts().to_dict()
            except Exception:
                type_counts = {}
            try:
                mid_positive = int((pd.to_numeric(chain_df["mid"], errors="coerce") > 0).sum())
            except Exception:
                mid_positive = 0
            try:
                dte_top = chain_df["dte"].value_counts().head(5).to_dict()
            except Exception:
                dte_top = {}
            debug_obj = {
                "rows": int(len(chain_df)),
                "type_counts": type_counts,
                "mid_positive_rows": mid_positive,
                "dte_top": dte_top,
                "strike_min": _safe_float(pd.to_numeric(chain_df["strike"], errors="coerce").min(), np.nan),
                "strike_max": _safe_float(pd.to_numeric(chain_df["strike"], errors="coerce").max(), np.nan),
            }

            spot = _safe_float(chain_summary.get("spot_price"), np.nan)
            if not (np.isfinite(spot) and spot > 0):
                try:
                    spot = self._fetch_stock_snapshot_price(sym)
                except Exception:
                    spot = float(np.nan)
            if not (np.isfinite(spot) and spot > 0):
                strikes = pd.to_numeric(chain_df.get("strike"), errors="coerce")
                spot = float(np.nanmedian(strikes.values.astype(float)))
            if not (np.isfinite(spot) and spot > 0):
                raise RuntimeError("unable to derive spot price from options snapshot")

            hv30, trend20 = self._fetch_hv30_and_trend20(sym, lookback_days=lookback_days)
            iv30 = _safe_float(chain_summary.get("iv30"), np.nan)
            ivr = _safe_float(chain_summary.get("iv_rank_252"), np.nan)
            if not np.isfinite(ivr):
                ivr = 0.50

            dte_earnings, earnings_date = self._fetch_days_to_earnings(
                sym,
                ticker_details=details,
                default_days_to_earnings=default_days_to_earnings,
            )
            borrow_rate = self._extract_borrow_rate(details)

            row_obj = {
                "symbol": sym,
                "sector": sector,
                "price": float(spot),
                "iv30": float(iv30) if np.isfinite(iv30) else 0.35,
                "hv30": float(hv30) if np.isfinite(hv30) else 0.25,
                "iv_rank_252": float(ivr),
                "avg_opt_volume_30d": float(_safe_float(chain_summary.get("avg_opt_volume_30d"), 0.0)),
                "avg_oi_30d": float(_safe_float(chain_summary.get("avg_oi_30d"), 0.0)),
                "avg_opt_notional_30d": float(_safe_float(chain_summary.get("avg_opt_notional_30d"), 0.0)),
                "liquidity_notional_proxy": float(_safe_float(chain_summary.get("liquidity_notional_proxy"), 0.0)),
                "avg_bid_ask_pct": float(_safe_float(chain_summary.get("avg_bid_ask_pct"), 0.05)),
                "days_to_earnings": float(dte_earnings),
                "earnings_date": earnings_date,
                "borrow_rate": float(borrow_rate) if np.isfinite(borrow_rate) else np.nan,
                "trend_20d_return": float(trend20) if np.isfinite(trend20) else np.nan,
                "put_call_skew": float(_safe_float(chain_summary.get("put_call_skew"), np.nan)),
            }

            insight_obj: Dict[str, Any] = {}
            if include_news:
                insight_obj["news"] = self._fetch_recent_news(sym, limit=news_limit)
            if include_analyst:
                insight_obj["analyst"] = self._fetch_analyst_summary(sym)
            return {
                "symbol": sym,
                "row": row_obj,
                "chain_df": chain_df,
                "debug": debug_obj,
                "insight": insight_obj,
            }

        max_workers = max(1, min(len(cleaned), int(_safe_float(os.getenv("OPTIONS_EDGE_LIVE_MAX_WORKERS"), 4.0))))
        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            fut_map = {pool.submit(_process_symbol, sym): sym for sym in cleaned}
            for fut in as_completed(fut_map):
                sym = fut_map[fut]
                try:
                    data = fut.result()
                    universe_rows.append(data["row"])
                    all_chain.append(data["chain_df"])
                    symbol_chain_debug[sym] = data["debug"]
                    if data["insight"]:
                        symbol_insights[sym] = data["insight"]
                except Exception as e:
                    errors[sym] = str(e)[:200]
                    continue

        iv_rank_true_count = 0
        try:
            iv_rank_true_count = int(self._apply_true_iv_rank_252(universe_rows))
        except Exception:
            iv_rank_true_count = 0

        universe_df = normalize_universe_dataframe(pd.DataFrame(universe_rows))
        chain_df = (
            pd.concat(all_chain, axis=0, ignore_index=True)
            if len(all_chain) > 0
            else pd.DataFrame()
        )
        chain_df = normalize_option_chain_dataframe(chain_df) if not chain_df.empty else chain_df

        metadata = {
            "provider": "polygon",
            "requested_symbols": cleaned,
            "loaded_symbols": sorted(universe_df["symbol"].tolist()) if not universe_df.empty else [],
            "failed_symbols": errors,
            "universe_rows": int(len(universe_df)),
            "chain_rows": int(len(chain_df)) if not chain_df.empty else 0,
            "default_days_to_earnings_used": float(default_days_to_earnings),
            "parallel_workers": int(max_workers),
            "earnings_known_count": int(pd.to_numeric(universe_df.get("days_to_earnings"), errors="coerce").replace([np.inf, -np.inf], np.nan).lt(float(default_days_to_earnings)).sum()) if not universe_df.empty else 0,
            "borrow_known_count": int(pd.to_numeric(universe_df.get("borrow_rate"), errors="coerce").replace([np.inf, -np.inf], np.nan).notna().sum()) if not universe_df.empty else 0,
            "iv_rank_true_count": int(iv_rank_true_count),
            "symbol_chain_debug": symbol_chain_debug,
            "symbol_insights": symbol_insights,
        }
        return LiveOptionsDataset(universe_df=universe_df, chain_df=chain_df, metadata=metadata)
