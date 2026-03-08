"""CSP lifecycle backtest engine (daily-step simulation)."""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import date
from typing import Any, Dict, List, Optional, Tuple

import numpy as np
import pandas as pd

from .csp_models import CSPBacktestConfig
from .csp_pricing import bs_put_delta, bs_put_price, estimate_pop
from .csp_screener import detect_regime


def _safe_float(v: Any, default: float = np.nan) -> float:
    try:
        if v is None:
            return float(default)
        f = float(v)
        if np.isnan(f) or np.isinf(f):
            return float(default)
        return float(f)
    except Exception:
        return float(default)


@dataclass
class _OpenPosition:
    symbol: str
    open_date: date
    expiry_date: date
    strike: float
    premium_received: float  # per share
    cash_secured: float
    delta_at_open: float
    iv_at_open: float
    regime: str
    dte: int
    rolls: List[Dict[str, Any]]


class CSPLifecycleEngine:
    """Daily-step CSP simulator for research-grade lifecycle testing."""

    def __init__(self, config: Optional[CSPBacktestConfig] = None):
        self.cfg = config or CSPBacktestConfig()

    def estimate_historical_iv(self, market_df: pd.DataFrame, window: int = 30) -> pd.Series:
        close = pd.to_numeric(market_df["close"], errors="coerce")
        ret = np.log(close / close.shift(1))
        rv = ret.rolling(window=window, min_periods=max(5, window // 3)).std() * np.sqrt(252.0)
        iv_proxy = rv * float(self.cfg.iv_premium_factor)
        iv_floor = float(max(0.05, min(2.5, self.cfg.iv_floor)))
        return iv_proxy.bfill().ffill().fillna(iv_floor).clip(lower=iv_floor, upper=2.5)

    @staticmethod
    def _should_roll(initial_premium: float, current_value: float, dte: int) -> bool:
        if initial_premium <= 0.0:
            return False
        value_decay = current_value <= 0.25 * initial_premium
        time_decay = dte <= 7 and current_value <= 0.10 * initial_premium
        return bool(value_decay or time_decay)

    @staticmethod
    def _can_open_cash_secured(available_cash: float, strike: float) -> bool:
        return bool(available_cash >= max(0.0, strike) * 100.0)

    def _pick_trade(
        self,
        *,
        symbol: str,
        dt: date,
        spot: float,
        iv: float,
        regime: str,
    ) -> Optional[Dict[str, Any]]:
        if not np.isfinite(spot) or spot <= 0:
            return None
        iv = float(max(0.05, min(2.5, iv)))
        dte = int(round((self.cfg.target_dte_min + self.cfg.target_dte_max) / 2.0))
        t = dte / 365.0
        target_abs_delta = 0.50 if regime == "aggressive" else 0.25

        step = max(0.5, spot * 0.005)
        strikes = np.arange(max(1.0, spot * 0.70), spot * 1.10 + step, step)
        best = None
        best_gap = float("inf")
        for k in strikes:
            d = bs_put_delta(spot=spot, strike=float(k), years_to_expiry=t, rate=self.cfg.risk_free_rate, sigma=iv)
            gap = abs(abs(d) - target_abs_delta)
            if gap < best_gap:
                best_gap = gap
                best = (float(k), float(d))
        if best is None:
            return None

        strike, delta = best
        premium = bs_put_price(spot=spot, strike=strike, years_to_expiry=t, rate=self.cfg.risk_free_rate, sigma=iv)
        if premium <= 0.0:
            return None

        yield_pct = (premium / max(strike, 1e-9)) * 100.0
        monthly_yield_pct = yield_pct * (30.0 / max(float(dte), 1.0))
        pop = estimate_pop(delta)

        if regime == "aggressive":
            if monthly_yield_pct < self.cfg.aggressive_yield_min_pct or monthly_yield_pct > self.cfg.aggressive_yield_max_pct:
                return None
        else:
            if pop < self.cfg.normal_pop_min or pop > self.cfg.normal_pop_max:
                return None
            if monthly_yield_pct < self.cfg.normal_yield_min_pct or monthly_yield_pct > self.cfg.normal_yield_max_pct:
                return None
            if monthly_yield_pct < self.cfg.hard_min_yield_pct:
                return None

        return {
            "symbol": symbol,
            "open_date": dt,
            "dte": dte,
            "expiry_date": dt + pd.Timedelta(days=dte),
            "strike": strike,
            "premium": float(premium),
            "cash_secured": float(strike * 100.0),
            "delta": float(delta),
            "iv": float(iv),
            "regime": regime,
            "pop": float(pop),
            "yield_pct": float(monthly_yield_pct),
        }

    def run_symbol_backtest(
        self,
        *,
        symbol: str,
        market_df: pd.DataFrame,
        vix_series: Optional[pd.Series] = None,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None,
    ) -> Dict[str, Any]:
        if market_df is None or market_df.empty:
            return {
                "symbol": symbol,
                "status": "FAILED",
                "error": "empty_market_df",
                "metrics": {},
                "equity_curve": [],
                "trade_log": [],
            }

        df = market_df.copy()
        if "date" in df.columns:
            df["date"] = pd.to_datetime(df["date"]).dt.date
            df = df.sort_values("date")
        else:
            df = df.copy()
            df["date"] = pd.to_datetime(df.index).date
            df = df.sort_values("date")
        if "close" not in df.columns:
            raise ValueError("market_df must include close column")

        if start_date is not None:
            df = df[df["date"] >= start_date]
        if end_date is not None:
            df = df[df["date"] <= end_date]
        if df.empty:
            return {
                "symbol": symbol,
                "status": "FAILED",
                "error": "no_data_in_range",
                "metrics": {},
                "equity_curve": [],
                "trade_log": [],
            }

        if "iv_proxy" not in df.columns:
            df["iv_proxy"] = self.estimate_historical_iv(df)
        if "price_vs_sma200" not in df.columns:
            sma200 = pd.to_numeric(df["close"], errors="coerce").rolling(window=200, min_periods=30).mean()
            df["price_vs_sma200"] = ((pd.to_numeric(df["close"], errors="coerce") - sma200) / sma200.replace(0, np.nan) * 100.0).fillna(0.0)

        available_cash = float(self.cfg.initial_capital)
        etf_units = 0.0
        open_pos: Optional[_OpenPosition] = None
        trade_log: List[Dict[str, Any]] = []
        equity_curve: List[Dict[str, Any]] = []
        monthly_premium: Dict[str, float] = {}
        total_premium_collected = 0.0
        assigned_count = 0
        closed_otm_count = 0
        roll_count = 0
        shares_held = 0
        shares_cost_basis = 0.0

        def _equity(spot_px: float) -> float:
            reserved = open_pos.cash_secured if open_pos is not None else 0.0
            shares_mv = shares_held * float(spot_px)
            etf_mv = etf_units * float(spot_px)
            return float(available_cash + reserved + shares_mv + etf_mv)

        prev_month = None
        for i, row in enumerate(df.itertuples(index=False), start=1):
            dt = row.date
            spot = _safe_float(getattr(row, "close", np.nan), np.nan)
            if not np.isfinite(spot) or spot <= 0:
                continue

            ym = f"{dt.year:04d}-{dt.month:02d}"
            if prev_month is None:
                prev_month = ym
            if ym != prev_month:
                premium_month = float(monthly_premium.get(prev_month, 0.0))
                reinvest = 0.5 * max(0.0, premium_month)
                if reinvest > 0.0 and available_cash >= reinvest:
                    available_cash -= reinvest
                    etf_units += reinvest / max(spot, 1e-9)
                prev_month = ym

            vix_val = None
            if isinstance(vix_series, pd.Series):
                try:
                    vix_val = _safe_float(vix_series.loc[pd.to_datetime(dt)], np.nan)
                except Exception:
                    vix_val = np.nan
            regime = detect_regime(
                vix_value=vix_val,
                sma200_distance_pct=_safe_float(getattr(row, "price_vs_sma200", np.nan), np.nan),
                vix_aggressive_threshold=self.cfg.vix_aggressive_threshold,
                sma200_touch_pct=self.cfg.sma200_touch_pct,
            )
            iv = _safe_float(getattr(row, "iv_proxy", 0.25), 0.25)

            if open_pos is not None:
                dte = max(0, (open_pos.expiry_date - dt).days)
                t = dte / 365.0
                current_val = bs_put_price(
                    spot=spot,
                    strike=open_pos.strike,
                    years_to_expiry=t,
                    rate=self.cfg.risk_free_rate,
                    sigma=max(0.05, iv),
                )

                if dte <= 0:
                    if spot >= open_pos.strike:
                        available_cash += open_pos.cash_secured
                        closed_otm_count += 1
                        trade_log.append(
                            {
                                "event": "expire_otm",
                                "date": dt.isoformat(),
                                "symbol": symbol,
                                "strike": open_pos.strike,
                                "premium_total": open_pos.premium_received * 100.0,
                            }
                        )
                    else:
                        assigned_count += 1
                        shares_held += 100
                        shares_cost_basis += open_pos.cash_secured
                        trade_log.append(
                            {
                                "event": "assigned",
                                "date": dt.isoformat(),
                                "symbol": symbol,
                                "strike": open_pos.strike,
                                "assignment_cost": open_pos.cash_secured,
                            }
                        )
                    open_pos = None
                else:
                    if self._should_roll(open_pos.premium_received, current_val, dte):
                        next_trade = self._pick_trade(
                            symbol=symbol,
                            dt=dt,
                            spot=spot,
                            iv=iv,
                            regime=regime,
                        )
                        if next_trade is not None:
                            buyback_cost = current_val * 100.0
                            new_credit = next_trade["premium"] * 100.0
                            net_credit = new_credit - buyback_cost
                            new_reserve = float(next_trade["cash_secured"])
                            cash_after_close = available_cash - buyback_cost + open_pos.cash_secured
                            if net_credit > 0.0 and cash_after_close >= new_reserve:
                                available_cash = cash_after_close - new_reserve + new_credit
                                new_exp_dt = next_trade["expiry_date"]
                                if hasattr(new_exp_dt, "date"):
                                    new_exp_dt = new_exp_dt.date()
                                roll = {
                                    "roll_date": dt.isoformat(),
                                    "old_strike": float(open_pos.strike),
                                    "old_expiry": open_pos.expiry_date.isoformat(),
                                    "new_strike": float(next_trade["strike"]),
                                    "new_expiry": new_exp_dt.isoformat(),
                                    "buyback_cost": float(buyback_cost),
                                    "new_premium": float(new_credit),
                                    "net_credit": float(net_credit),
                                }
                                roll_count += 1
                                total_premium_collected += float(new_credit)
                                monthly_premium[ym] = monthly_premium.get(ym, 0.0) + float(new_credit)
                                rolls = list(open_pos.rolls)
                                rolls.append(roll)
                                open_pos = _OpenPosition(
                                    symbol=symbol,
                                    open_date=dt,
                                    expiry_date=new_exp_dt,
                                    strike=float(next_trade["strike"]),
                                    premium_received=float(next_trade["premium"]),
                                    cash_secured=float(next_trade["cash_secured"]),
                                    delta_at_open=float(next_trade["delta"]),
                                    iv_at_open=float(next_trade["iv"]),
                                    regime=str(next_trade["regime"]),
                                    dte=int(next_trade["dte"]),
                                    rolls=rolls,
                                )
                                trade_log.append(
                                    {
                                        "event": "roll",
                                        "date": dt.isoformat(),
                                        "symbol": symbol,
                                        "net_credit": float(net_credit),
                                        "new_strike": float(next_trade["strike"]),
                                    }
                                )

            if open_pos is None:
                trade = self._pick_trade(symbol=symbol, dt=dt, spot=spot, iv=iv, regime=regime)
                if trade is not None and self._can_open_cash_secured(available_cash, float(trade["strike"])):
                    reserve = float(trade["cash_secured"])
                    credit = float(trade["premium"]) * 100.0
                    available_cash = available_cash - reserve + credit
                    total_premium_collected += credit
                    monthly_premium[ym] = monthly_premium.get(ym, 0.0) + credit
                    exp_dt = trade["expiry_date"]
                    if hasattr(exp_dt, "date"):
                        exp_dt = exp_dt.date()
                    open_pos = _OpenPosition(
                        symbol=symbol,
                        open_date=dt,
                        expiry_date=exp_dt,
                        strike=float(trade["strike"]),
                        premium_received=float(trade["premium"]),
                        cash_secured=float(reserve),
                        delta_at_open=float(trade["delta"]),
                        iv_at_open=float(trade["iv"]),
                        regime=str(trade["regime"]),
                        dte=int(trade["dte"]),
                        rolls=[],
                    )
                    trade_log.append(
                        {
                            "event": "open",
                            "date": dt.isoformat(),
                            "symbol": symbol,
                            "strike": float(trade["strike"]),
                            "premium_total": float(credit),
                            "regime": regime,
                            "pop_est": float(trade["pop"]),
                            "yield_pct": float(trade["yield_pct"]),
                        }
                    )

            equity_curve.append({"i": i, "date": dt.isoformat(), "equity": _equity(spot)})

        if equity_curve:
            eq0 = float(equity_curve[0]["equity"])
            eqn = float(equity_curve[-1]["equity"])
        else:
            eq0 = self.cfg.initial_capital
            eqn = self.cfg.initial_capital

        equity_vals = np.array([_safe_float(e.get("equity"), np.nan) for e in equity_curve], dtype=float)
        equity_vals = equity_vals[np.isfinite(equity_vals)]
        max_drawdown_pct = 0.0
        sharpe_ratio = 0.0
        total_return_pct = 0.0
        if equity_vals.size > 0:
            peaks = np.maximum.accumulate(equity_vals)
            dd = np.where(peaks > 0.0, (equity_vals - peaks) / peaks, 0.0)
            max_drawdown_pct = abs(float(np.min(dd))) * 100.0
            total_return_pct = ((float(equity_vals[-1]) / max(float(equity_vals[0]), 1e-9)) - 1.0) * 100.0
            rets = pd.Series(equity_vals).pct_change().replace([np.inf, -np.inf], np.nan).dropna()
            if len(rets) > 1 and float(rets.std()) > 1e-12:
                sharpe_ratio = float(np.sqrt(252.0) * (rets.mean() / rets.std()))

        resolved = int(closed_otm_count + assigned_count)
        win_rate_pct = (float(closed_otm_count) / float(resolved) * 100.0) if resolved > 0 else 0.0
        open_yields = [float(t.get("yield_pct")) for t in trade_log if t.get("event") == "open" and t.get("yield_pct") is not None]
        avg_open_yield_pct = float(np.mean(open_yields)) if len(open_yields) > 0 else 0.0

        return {
            "symbol": symbol,
            "status": "COMPLETED",
            "metrics": {
                "initial_capital": float(eq0),
                "final_capital": float(eqn),
                "net_profit": float(eqn - eq0),
                "total_events": int(len(trade_log)),
                "assigned_count": int(assigned_count),
                "expired_otm_count": int(closed_otm_count),
                "roll_count": int(roll_count),
                "resolved_positions": int(resolved),
                "win_rate_pct": float(win_rate_pct),
                "total_return_pct": float(total_return_pct),
                "max_drawdown_pct": float(max_drawdown_pct),
                "sharpe_ratio": float(sharpe_ratio),
                "avg_open_yield_pct": float(avg_open_yield_pct),
                "shares_held": int(shares_held),
                "shares_cost_basis": float(shares_cost_basis),
                "total_premium_collected": float(total_premium_collected),
            },
            "equity_curve": equity_curve,
            "trade_log": trade_log,
        }

    def run_portfolio_backtest(
        self,
        *,
        symbol_data: Dict[str, pd.DataFrame],
        symbol_meta: Optional[Dict[str, Dict[str, Any]]] = None,
        start_date: Optional[date] = None,
        end_date: Optional[date] = None,
    ) -> Dict[str, Any]:
        """
        Multi-symbol CSP portfolio simulation using per-symbol lifecycle engines and
        portfolio-level allocation/selection constraints.
        """
        if not isinstance(symbol_data, dict) or len(symbol_data) == 0:
            return {
                "status": "FAILED",
                "error": "empty_symbol_data",
                "metrics": {},
                "equity_curve": [],
                "trade_log": [],
                "symbol_reports": {},
            }

        meta = symbol_meta if isinstance(symbol_meta, dict) else {}
        ranked: List[Tuple[str, float, str]] = []
        for sym, df in symbol_data.items():
            s = str(sym or "").upper().strip()
            if not s or df is None or df.empty:
                continue
            m = meta.get(s, {}) if isinstance(meta.get(s), dict) else {}
            rank = _safe_float(m.get("iv_rank"), np.nan)
            if not np.isfinite(rank):
                rank = _safe_float(m.get("score"), 0.0)
            sector = str(m.get("sector") or "UNKNOWN")
            ranked.append((s, float(rank), sector))
        if len(ranked) == 0:
            return {
                "status": "FAILED",
                "error": "no_valid_symbols",
                "metrics": {},
                "equity_curve": [],
                "trade_log": [],
                "symbol_reports": {},
            }

        ranked = sorted(ranked, key=lambda x: x[1], reverse=True)
        selected: List[str] = []
        sector_counts: Dict[str, int] = {}
        max_symbols = int(max(1, self.cfg.max_concurrent_csps))
        for s, _, sector in ranked:
            if len(selected) >= max_symbols:
                break
            sec = sector or "UNKNOWN"
            if sector_counts.get(sec, 0) >= int(max(1, self.cfg.max_sector_concentration)):
                continue
            selected.append(s)
            sector_counts[sec] = sector_counts.get(sec, 0) + 1
        if len(selected) == 0:
            selected = [ranked[0][0]]

        alloc_cap = float(self.cfg.initial_capital) * (float(self.cfg.max_portfolio_allocation_pct) / 100.0)
        per_symbol_cap_from_portfolio = alloc_cap / max(len(selected), 1)
        per_symbol_cap_from_single = float(self.cfg.initial_capital) * (float(self.cfg.max_single_stock_pct) / 100.0)
        per_symbol_cap = max(0.0, min(per_symbol_cap_from_portfolio, per_symbol_cap_from_single))
        if per_symbol_cap <= 0.0:
            per_symbol_cap = max(0.0, alloc_cap / max(len(selected), 1))
        if per_symbol_cap <= 0.0:
            return {
                "status": "FAILED",
                "error": "invalid_allocation_config",
                "metrics": {},
                "equity_curve": [],
                "trade_log": [],
                "symbol_reports": {},
            }

        reserved_total = per_symbol_cap * len(selected)
        cash_outside_csp = float(self.cfg.initial_capital) - reserved_total
        if cash_outside_csp < 0.0:
            cash_outside_csp = 0.0

        symbol_reports: Dict[str, Dict[str, Any]] = {}
        combined_trade_log: List[Dict[str, Any]] = []
        eq_parts: List[pd.DataFrame] = []

        for sym in selected:
            sub_cfg = replace(self.cfg, initial_capital=float(per_symbol_cap))
            sub_engine = CSPLifecycleEngine(sub_cfg)
            rep = sub_engine.run_symbol_backtest(
                symbol=sym,
                market_df=symbol_data[sym],
                start_date=start_date,
                end_date=end_date,
            )
            symbol_reports[sym] = rep
            for ev in (rep.get("trade_log") or []):
                if isinstance(ev, dict):
                    e2 = dict(ev)
                    e2["symbol"] = str(e2.get("symbol") or sym)
                    combined_trade_log.append(e2)

            eq = rep.get("equity_curve") or []
            if isinstance(eq, list) and len(eq) > 0:
                tmp = pd.DataFrame(eq)
                if "date" in tmp.columns and "equity" in tmp.columns:
                    tmp["date"] = pd.to_datetime(tmp["date"], errors="coerce").dt.date
                    tmp = tmp.dropna(subset=["date"])
                    tmp = tmp[["date", "equity"]].rename(columns={"equity": f"eq_{sym}"})
                    eq_parts.append(tmp)

        if len(eq_parts) == 0:
            return {
                "status": "FAILED",
                "error": "no_equity_curves",
                "metrics": {},
                "equity_curve": [],
                "trade_log": combined_trade_log,
                "symbol_reports": symbol_reports,
            }

        merged = eq_parts[0].copy()
        for part in eq_parts[1:]:
            merged = merged.merge(part, on="date", how="outer")
        merged = merged.sort_values("date")
        eq_cols = [c for c in merged.columns if c.startswith("eq_")]
        merged[eq_cols] = merged[eq_cols].ffill().bfill()
        merged["equity"] = merged[eq_cols].sum(axis=1) + float(cash_outside_csp)

        equity_curve: List[Dict[str, Any]] = []
        for i, r in enumerate(merged.itertuples(index=False), start=1):
            equity_curve.append({"i": i, "date": str(r.date), "equity": float(getattr(r, "equity"))})

        combined_trade_log = sorted(
            combined_trade_log,
            key=lambda e: (str(e.get("date") or ""), str(e.get("symbol") or ""), str(e.get("event") or "")),
        )

        eq_vals = np.array([_safe_float(e.get("equity"), np.nan) for e in equity_curve], dtype=float)
        eq_vals = eq_vals[np.isfinite(eq_vals)]
        if eq_vals.size > 0:
            initial_capital = float(eq_vals[0])
            final_capital = float(eq_vals[-1])
        else:
            initial_capital = float(self.cfg.initial_capital)
            final_capital = float(self.cfg.initial_capital)

        peaks = np.maximum.accumulate(eq_vals) if eq_vals.size > 0 else np.array([initial_capital], dtype=float)
        dd = np.where(peaks > 0.0, (eq_vals - peaks) / peaks, 0.0) if eq_vals.size > 0 else np.array([0.0], dtype=float)
        max_drawdown_pct = abs(float(np.min(dd))) * 100.0 if dd.size > 0 else 0.0

        sharpe_ratio = 0.0
        if eq_vals.size > 1:
            rets = pd.Series(eq_vals).pct_change().replace([np.inf, -np.inf], np.nan).dropna()
            if len(rets) > 1 and float(rets.std()) > 1e-12:
                sharpe_ratio = float(np.sqrt(252.0) * (rets.mean() / rets.std()))

        assigned_count = int(sum(_safe_float((symbol_reports[s].get("metrics") or {}).get("assigned_count"), 0.0) for s in symbol_reports))
        expired_otm_count = int(sum(_safe_float((symbol_reports[s].get("metrics") or {}).get("expired_otm_count"), 0.0) for s in symbol_reports))
        roll_count = int(sum(_safe_float((symbol_reports[s].get("metrics") or {}).get("roll_count"), 0.0) for s in symbol_reports))
        total_premium_collected = float(
            sum(_safe_float((symbol_reports[s].get("metrics") or {}).get("total_premium_collected"), 0.0) for s in symbol_reports)
        )
        resolved = int(assigned_count + expired_otm_count)
        win_rate_pct = (float(expired_otm_count) / float(resolved) * 100.0) if resolved > 0 else 0.0

        metrics = {
            "initial_capital": float(initial_capital),
            "final_capital": float(final_capital),
            "net_profit": float(final_capital - initial_capital),
            "total_return_pct": float(((final_capital / max(initial_capital, 1e-9)) - 1.0) * 100.0),
            "max_drawdown_pct": float(max_drawdown_pct),
            "sharpe_ratio": float(sharpe_ratio),
            "total_events": int(len(combined_trade_log)),
            "assigned_count": int(assigned_count),
            "expired_otm_count": int(expired_otm_count),
            "roll_count": int(roll_count),
            "resolved_positions": int(resolved),
            "win_rate_pct": float(win_rate_pct),
            "total_premium_collected": float(total_premium_collected),
            "selected_symbols": list(selected),
            "selected_symbol_count": int(len(selected)),
            "cash_outside_csp": float(cash_outside_csp),
            "per_symbol_capital": float(per_symbol_cap),
        }

        return {
            "status": "COMPLETED",
            "metrics": metrics,
            "equity_curve": equity_curve,
            "trade_log": combined_trade_log,
            "symbol_reports": symbol_reports,
        }
