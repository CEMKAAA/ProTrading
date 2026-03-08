"""
Deterministic portfolio backtest + walk-forward engine for options-edge scans.

Phase 3 scope:
- consume persisted options-edge scan/trade-candidate snapshots
- simulate portfolio PnL with deterministic proxy exits/costs
- emit walk-forward and stress-scenario reports
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import hashlib
import math
from typing import Any, Dict, List, Optional, Sequence, Tuple

import numpy as np
from sqlalchemy.orm import Session

from ...models.database import OptionsEdgeScanRunModel, OptionsEdgeTradeCandidateModel


def _safe_float(value: Any, default: float = 0.0) -> float:
    try:
        if value is None:
            return float(default)
        v = float(value)
        if math.isnan(v) or math.isinf(v):
            return float(default)
        return v
    except Exception:
        return float(default)


def _clamp(v: float, lo: float, hi: float) -> float:
    return float(max(lo, min(hi, v)))


def _hash_uniform(seed: int, key: str) -> float:
    blob = hashlib.sha256(f"{seed}|{key}".encode("utf-8")).digest()
    n = int.from_bytes(blob[:8], byteorder="big", signed=False)
    return n / float(2**64 - 1)


@dataclass(frozen=True)
class _Scenario:
    name: str
    slippage_mult: float = 1.0
    spread_mult: float = 1.0
    fill_probability: float = 1.0
    pop_penalty: float = 0.0


class OptionsEdgeBacktestEngine:
    """Runs deterministic proxy backtests from persisted trade candidates."""

    def __init__(self, db: Session):
        self.db = db

    def run(self, request: Dict[str, Any]) -> Dict[str, Any]:
        scans, trades = self._load_inputs(request)
        if len(trades) == 0:
            raise ValueError("No trade candidates available for requested scan window.")

        base_scenario = _Scenario(name="base")
        base_report = self._simulate(request, trades, base_scenario)
        folds = self._walk_forward(request, scans, trades, base_scenario)
        stress = self._stress_reports(request, trades)

        return {
            "mode": "deterministic_proxy",
            "scans_used": len(scans),
            "scan_ids": [s["scan_id"] for s in scans],
            "trades_input_count": len(trades),
            "metrics": base_report["metrics"],
            "equity_curve": base_report["equity_curve"],
            "trade_log": base_report["trade_log"],
            "walk_forward": folds,
            "stress": stress,
            "notes": [
                "Proxy model: outcomes are deterministic hash-sampled from pop_est and cost model.",
                "Use this for selection/risk validation; not a replacement for broker-grade option repricing.",
            ],
        }

    def _load_inputs(self, request: Dict[str, Any]) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
        scan_ids_req: List[str] = [str(s) for s in (request.get("scan_ids") or []) if str(s).strip()]
        max_trades_per_scan = max(1, int(request.get("max_trades_per_scan", 8)))
        min_selected_symbols = max(0, int(request.get("min_selected_symbols", 1)))
        min_pop = _clamp(_safe_float(request.get("min_pop", 0.0), 0.0), 0.0, 1.0)

        q = self.db.query(OptionsEdgeScanRunModel).filter(OptionsEdgeScanRunModel.status == "COMPLETED")
        if scan_ids_req:
            q = q.filter(OptionsEdgeScanRunModel.scan_id.in_(scan_ids_req))

        start_ts = request.get("start_ts")
        end_ts = request.get("end_ts")
        if isinstance(start_ts, datetime):
            q = q.filter(OptionsEdgeScanRunModel.scan_ts >= start_ts)
        if isinstance(end_ts, datetime):
            q = q.filter(OptionsEdgeScanRunModel.scan_ts <= end_ts)

        scan_rows = q.order_by(OptionsEdgeScanRunModel.scan_ts.asc()).all()
        scans: List[Dict[str, Any]] = []
        trades: List[Dict[str, Any]] = []

        for scan in scan_rows:
            if int(scan.selected_count or 0) < min_selected_symbols:
                continue

            trows = (
                self.db.query(OptionsEdgeTradeCandidateModel)
                .filter(OptionsEdgeTradeCandidateModel.scan_id == scan.scan_id)
                .order_by(
                    OptionsEdgeTradeCandidateModel.pop_est.desc(),
                    OptionsEdgeTradeCandidateModel.net_credit.desc(),
                )
                .all()
            )
            if len(trows) == 0:
                continue

            scans.append({
                "scan_id": scan.scan_id,
                "scan_ts": scan.scan_ts,
                "selected_count": int(scan.selected_count or 0),
            })

            added = 0
            for tr in trows:
                if added >= max_trades_per_scan:
                    break
                pop_est = _clamp(_safe_float(tr.pop_est, 0.55), 0.01, 0.99)
                if pop_est < min_pop:
                    continue

                legs = tr.legs_json if isinstance(tr.legs_json, list) else []
                legs_count = max(1, len(legs))
                max_profit = _safe_float(tr.max_profit, 0.0)
                max_loss = _safe_float(tr.max_loss, 0.0)
                if max_profit <= 0:
                    net_credit = _safe_float(tr.net_credit, 0.0)
                    max_profit = max(0.0, net_credit * 100.0)
                if max_loss <= 0:
                    max_loss = max(max_profit * 2.0, 1.0)

                trades.append({
                    "scan_id": scan.scan_id,
                    "scan_ts": scan.scan_ts,
                    "symbol": tr.symbol,
                    "structure_type": tr.structure_type,
                    "dte": int(tr.dte) if tr.dte is not None else None,
                    "legs_count": legs_count,
                    "pop_est": pop_est,
                    "max_profit": max_profit,
                    "max_loss": max_loss,
                })
                added += 1

        return scans, trades

    def _simulate(
        self,
        request: Dict[str, Any],
        trades: Sequence[Dict[str, Any]],
        scenario: _Scenario,
    ) -> Dict[str, Any]:
        initial_balance = _safe_float(request.get("initial_balance", 10_000.0), 10_000.0)
        allocation_per_trade_usd = max(10.0, _safe_float(request.get("allocation_per_trade_usd", 1_000.0), 1_000.0))
        max_contracts_per_trade = max(1, int(request.get("max_contracts_per_trade", 3)))
        take_profit_frac = _clamp(_safe_float(request.get("take_profit_frac", 0.50), 0.50), 0.05, 1.0)
        stop_loss_credit_mult = _clamp(_safe_float(request.get("stop_loss_credit_mult", 1.75), 1.75), 0.5, 5.0)

        commission_per_leg = max(0.0, _safe_float(request.get("commission_per_leg", 0.65), 0.65))
        slippage_pct = max(0.0, _safe_float(request.get("slippage_pct", 0.01), 0.01))
        spread_pct = max(0.0, _safe_float(request.get("spread_pct", 0.005), 0.005))
        min_fill_ratio = _clamp(_safe_float(request.get("min_fill_ratio", 0.70), 0.70), 0.1, 1.0)
        max_fill_ratio = _clamp(_safe_float(request.get("max_fill_ratio", 1.00), 1.00), min_fill_ratio, 1.0)
        seed = int(request.get("random_seed", 42))

        equity = initial_balance
        peak = initial_balance
        max_dd = 0.0
        equity_curve: List[Dict[str, Any]] = [
            {"i": 0, "equity": round(float(equity), 4), "scan_id": None, "symbol": None}
        ]
        trade_log: List[Dict[str, Any]] = []

        for idx, tr in enumerate(trades, start=1):
            trade_key = f"{tr['scan_id']}|{tr['symbol']}|{tr['structure_type']}|{idx}"
            fill_u = _hash_uniform(seed, f"fill|{trade_key}")
            if fill_u > scenario.fill_probability:
                continue

            fill_u2 = _hash_uniform(seed, f"fill_ratio|{trade_key}")
            fill_ratio = min_fill_ratio + (max_fill_ratio - min_fill_ratio) * fill_u2

            max_profit = max(1.0, _safe_float(tr["max_profit"], 1.0))
            max_loss = max(1.0, _safe_float(tr["max_loss"], max_profit * 2.0))
            take_profit_usd = max_profit * take_profit_frac
            stop_loss_usd = min(max_loss, max_profit * stop_loss_credit_mult)
            risk_per_contract = max(1.0, stop_loss_usd)
            qty = int(max(1, min(max_contracts_per_trade, math.floor(allocation_per_trade_usd / risk_per_contract))))

            pop = _clamp(_safe_float(tr.get("pop_est"), 0.55) - scenario.pop_penalty, 0.01, 0.99)
            win_u = _hash_uniform(seed, f"outcome|{trade_key}")
            is_win = win_u <= pop

            gross = take_profit_usd if is_win else -stop_loss_usd
            gross_total = gross * qty * fill_ratio

            commission = qty * int(tr.get("legs_count", 1)) * commission_per_leg
            slippage = abs(gross_total) * slippage_pct * scenario.slippage_mult
            spread = abs(gross_total) * spread_pct * scenario.spread_mult
            cost_total = commission + slippage + spread
            net = gross_total - cost_total

            equity += net
            peak = max(peak, equity)
            dd = 0.0 if peak <= 0 else ((peak - equity) / peak) * 100.0
            max_dd = max(max_dd, dd)

            trade_log.append({
                "i": idx,
                "scan_id": tr["scan_id"],
                "scan_ts": tr["scan_ts"].isoformat() if isinstance(tr.get("scan_ts"), datetime) else None,
                "symbol": tr["symbol"],
                "structure_type": tr["structure_type"],
                "qty": qty,
                "pop_est": round(float(pop), 6),
                "win": bool(is_win),
                "gross_pnl": round(float(gross_total), 4),
                "costs": round(float(cost_total), 4),
                "net_pnl": round(float(net), 4),
                "equity_after": round(float(equity), 4),
            })
            equity_curve.append({
                "i": idx,
                "equity": round(float(equity), 4),
                "scan_id": tr["scan_id"],
                "symbol": tr["symbol"],
            })

        metrics = self._metrics_from_trades(
            trade_log=trade_log,
            initial_balance=initial_balance,
            final_balance=equity,
            max_drawdown_pct=max_dd,
        )
        return {"metrics": metrics, "equity_curve": equity_curve, "trade_log": trade_log}

    def _metrics_from_trades(
        self,
        trade_log: Sequence[Dict[str, Any]],
        initial_balance: float,
        final_balance: float,
        max_drawdown_pct: float,
    ) -> Dict[str, Any]:
        n = len(trade_log)
        pnls = np.array([_safe_float(t.get("net_pnl"), 0.0) for t in trade_log], dtype=float)
        wins = pnls[pnls > 0]
        losses = pnls[pnls < 0]

        net_profit = float(final_balance - initial_balance)
        gross_profit = float(np.sum(wins)) if len(wins) else 0.0
        gross_loss_abs = float(abs(np.sum(losses))) if len(losses) else 0.0
        profit_factor = float(gross_profit / gross_loss_abs) if gross_loss_abs > 0 else (999.0 if gross_profit > 0 else 0.0)
        win_rate = float((len(wins) / n) * 100.0) if n > 0 else 0.0
        expectancy = float(net_profit / n) if n > 0 else 0.0

        rets = pnls / max(initial_balance, 1.0)
        ret_mean = float(np.mean(rets)) if n > 0 else 0.0
        ret_std = float(np.std(rets, ddof=1)) if n > 1 else 0.0
        sharpe = float((ret_mean / ret_std) * math.sqrt(n)) if ret_std > 1e-12 else 0.0

        downside = rets[rets < 0]
        downside_std = float(np.std(downside, ddof=1)) if len(downside) > 1 else 0.0
        sortino = float((ret_mean / downside_std) * math.sqrt(n)) if downside_std > 1e-12 else 0.0
        calmar = float((net_profit / max(initial_balance, 1.0)) / max(max_drawdown_pct / 100.0, 1e-9))

        return {
            "initial_balance": round(float(initial_balance), 4),
            "final_balance": round(float(final_balance), 4),
            "net_profit": round(float(net_profit), 4),
            "total_trades": int(n),
            "wins": int(len(wins)),
            "losses": int(len(losses)),
            "win_rate": round(float(win_rate), 4),
            "profit_factor": round(float(profit_factor), 6),
            "expectancy": round(float(expectancy), 4),
            "avg_win": round(float(np.mean(wins)) if len(wins) else 0.0, 4),
            "avg_loss": round(float(np.mean(losses)) if len(losses) else 0.0, 4),
            "largest_win": round(float(np.max(wins)) if len(wins) else 0.0, 4),
            "largest_loss": round(float(np.min(losses)) if len(losses) else 0.0, 4),
            "max_drawdown_pct": round(float(max_drawdown_pct), 6),
            "sharpe_ratio": round(float(sharpe), 6),
            "sortino_ratio": round(float(sortino), 6),
            "calmar_ratio": round(float(calmar), 6),
        }

    def _walk_forward(
        self,
        request: Dict[str, Any],
        scans: Sequence[Dict[str, Any]],
        trades: Sequence[Dict[str, Any]],
        scenario: _Scenario,
    ) -> Dict[str, Any]:
        n_scans = len(scans)
        req_folds = max(2, int(request.get("walk_forward_folds", 4)))
        folds = min(req_folds, n_scans)
        if folds < 2:
            return {"enabled": False, "reason": "insufficient_scans", "folds": []}

        scan_ids = [s["scan_id"] for s in scans]
        parts = np.array_split(np.array(scan_ids, dtype=object), folds)
        fold_results: List[Dict[str, Any]] = []
        for i, part in enumerate(parts, start=1):
            test_ids = {str(x) for x in part.tolist()}
            fold_trades = [t for t in trades if t["scan_id"] in test_ids]
            if len(fold_trades) == 0:
                fold_results.append({
                    "fold": i,
                    "scan_count": len(test_ids),
                    "metrics": {"total_trades": 0, "net_profit": 0.0, "win_rate": 0.0, "profit_factor": 0.0},
                })
                continue
            rep = self._simulate(request, fold_trades, scenario)
            fold_results.append({
                "fold": i,
                "scan_count": len(test_ids),
                "metrics": rep["metrics"],
            })

        net_profits = [float(f["metrics"].get("net_profit", 0.0)) for f in fold_results]
        pfs = [float(f["metrics"].get("profit_factor", 0.0)) for f in fold_results]
        return {
            "enabled": True,
            "fold_count": folds,
            "folds": fold_results,
            "aggregate": {
                "net_profit_mean": round(float(np.mean(net_profits)) if net_profits else 0.0, 6),
                "net_profit_min": round(float(np.min(net_profits)) if net_profits else 0.0, 6),
                "profit_factor_mean": round(float(np.mean(pfs)) if pfs else 0.0, 6),
                "profit_factor_std": round(float(np.std(pfs)) if len(pfs) > 1 else 0.0, 6),
            },
        }

    def _stress_reports(self, request: Dict[str, Any], trades: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
        slippage_mult = _clamp(_safe_float(request.get("stress_slippage_mult", 1.25), 1.25), 1.0, 5.0)
        spread_mult = _clamp(_safe_float(request.get("stress_spread_mult", 1.50), 1.50), 1.0, 5.0)
        pop_penalty = _clamp(_safe_float(request.get("stress_pop_penalty", 0.05), 0.05), 0.0, 0.5)
        fill_probability = _clamp(_safe_float(request.get("stress_fill_probability", 0.90), 0.90), 0.1, 1.0)

        scenarios = [
            _Scenario(name="base"),
            _Scenario(name="slippage_plus_25_spread_plus_50", slippage_mult=slippage_mult, spread_mult=spread_mult),
            _Scenario(name="delayed_fill_penalized_pop", fill_probability=fill_probability, pop_penalty=pop_penalty),
        ]

        out = {}
        for s in scenarios:
            rep = self._simulate(request, trades, s)
            out[s.name] = rep["metrics"]
        return out

