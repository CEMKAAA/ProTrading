from __future__ import annotations

import argparse
import csv
import json
import math
from collections import defaultdict
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple

import MetaTrader5 as mt5


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUT_DIR = PROJECT_ROOT / "logs" / "mt5_runtime_audit"


def asdict(obj: Any) -> Dict[str, Any]:
    if obj is None:
        return {}
    if hasattr(obj, "_asdict"):
        return dict(obj._asdict())
    return {name: getattr(obj, name) for name in dir(obj) if not name.startswith("_")}


def dt_from_ts(ts: Any) -> str:
    try:
        return datetime.fromtimestamp(int(ts)).strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        return ""


def build_const_map(prefix: str) -> Dict[int, str]:
    out: Dict[int, str] = {}
    for name in dir(mt5):
        if not name.startswith(prefix):
            continue
        value = getattr(mt5, name)
        if isinstance(value, int):
            out[value] = name.replace(prefix, "")
    return out


DEAL_TYPE = build_const_map("DEAL_TYPE_")
DEAL_ENTRY = build_const_map("DEAL_ENTRY_")
DEAL_REASON = build_const_map("DEAL_REASON_")
ORDER_TYPE = build_const_map("ORDER_TYPE_")
ORDER_REASON = build_const_map("ORDER_REASON_")


def f(value: Any, default: float = 0.0) -> float:
    try:
        if value is None:
            return default
        x = float(value)
        if math.isnan(x) or math.isinf(x):
            return default
        return x
    except Exception:
        return default


def ivalue(value: Any, default: int = 0) -> int:
    try:
        if value is None:
            return default
        return int(value)
    except Exception:
        return default


def classify_ea(magic: int, comment: str) -> str:
    c = (comment or "").lower()
    if "nas_v3" in c or "nas" in c:
        return "NAS"
    if "orb" in c:
        return "ORB15"
    if "erl" in c or "irl" in c:
        return "ERL_IRL"
    if "gann" in c:
        return "GannMadeEasy"
    if "prz" in c:
        return "PRZPattern"
    if "gold" in c or "bo atr" in c or "atr" in c:
        return "Gold_BO_ATR_or_ATR"
    if "sats" in c or "supertrend" in c:
        return "SuperTrend_SATS"
    if magic == 0:
        return "Manual_or_Unknown"
    return f"Magic_{magic}"


def weighted_avg(items: Iterable[Tuple[float, float]]) -> float:
    total_vol = 0.0
    total = 0.0
    for price, vol in items:
        total += price * vol
        total_vol += vol
    return total / total_vol if total_vol > 0 else 0.0


def symbol_rates(symbol: str, start: datetime, end: datetime):
    for tf in (mt5.TIMEFRAME_M1, mt5.TIMEFRAME_M5, mt5.TIMEFRAME_M15):
        rates = mt5.copy_rates_range(symbol, tf, start, end)
        if rates is not None and len(rates) > 0:
            return rates, {mt5.TIMEFRAME_M1: "M1", mt5.TIMEFRAME_M5: "M5", mt5.TIMEFRAME_M15: "M15"}[tf]
    return None, ""


def excursions(symbol: str, direction: str, entry_time: datetime, end_time: datetime, entry_price: float) -> Dict[str, Any]:
    rates, tf = symbol_rates(symbol, entry_time - timedelta(minutes=2), end_time + timedelta(minutes=2))
    if rates is None or len(rates) == 0:
        return {"mfe_price": None, "mae_price": None, "mfe_abs": None, "mae_abs": None, "rates_tf": ""}
    highs = [float(r["high"]) for r in rates]
    lows = [float(r["low"]) for r in rates]
    if direction == "BUY":
        mfe_abs = max(highs) - entry_price
        mae_abs = entry_price - min(lows)
        mfe_price = max(highs)
        mae_price = min(lows)
    else:
        mfe_abs = entry_price - min(lows)
        mae_abs = max(highs) - entry_price
        mfe_price = min(lows)
        mae_price = max(highs)
    return {
        "mfe_price": round(mfe_price, 6),
        "mae_price": round(mae_price, 6),
        "mfe_abs": round(max(0.0, mfe_abs), 6),
        "mae_abs": round(max(0.0, mae_abs), 6),
        "rates_tf": tf,
    }


def order_sl_tp(position_id: int, orders: List[Dict[str, Any]]) -> Tuple[float, float]:
    relevant = [o for o in orders if ivalue(o.get("position_id"), 0) == position_id]
    sl = 0.0
    tp = 0.0
    for o in relevant:
        osl = f(o.get("sl"))
        otp = f(o.get("tp"))
        if osl > 0:
            sl = osl
        if otp > 0:
            tp = otp
    return sl, tp


def trade_rows_from_history(deals: List[Dict[str, Any]], orders: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    by_pos: Dict[int, List[Dict[str, Any]]] = defaultdict(list)
    for d in deals:
        pos = ivalue(d.get("position_id"), 0)
        if pos:
            by_pos[pos].append(d)

    rows: List[Dict[str, Any]] = []
    now = datetime.now()
    for pos, ds in by_pos.items():
        ds.sort(key=lambda x: (ivalue(x.get("time"), 0), ivalue(x.get("ticket"), 0)))
        in_deals = [d for d in ds if DEAL_ENTRY.get(ivalue(d.get("entry"), -1), str(d.get("entry"))) in ("IN", "INOUT")]
        out_deals = [d for d in ds if DEAL_ENTRY.get(ivalue(d.get("entry"), -1), str(d.get("entry"))) in ("OUT", "OUT_BY", "INOUT")]
        if not in_deals:
            continue

        first = in_deals[0]
        direction = "BUY" if DEAL_TYPE.get(ivalue(first.get("type"), -1), "") == "BUY" else "SELL"
        symbol = str(first.get("symbol") or "")
        magic = ivalue(first.get("magic"), 0)
        comments = [str(d.get("comment") or "") for d in ds if str(d.get("comment") or "")]
        comment = comments[0] if comments else ""
        ea = classify_ea(magic, " ".join(comments))
        entry_price = weighted_avg((f(d.get("price")), f(d.get("volume"))) for d in in_deals)
        entry_vol = sum(f(d.get("volume")) for d in in_deals)
        exit_price = weighted_avg((f(d.get("price")), f(d.get("volume"))) for d in out_deals) if out_deals else 0.0
        exit_vol = sum(f(d.get("volume")) for d in out_deals)
        profit = sum(f(d.get("profit")) + f(d.get("swap")) + f(d.get("commission")) + f(d.get("fee")) for d in ds)
        entry_time = datetime.fromtimestamp(ivalue(first.get("time"), 0))
        if out_deals:
            last_out = out_deals[-1]
            exit_time = datetime.fromtimestamp(ivalue(last_out.get("time"), 0))
            exit_reason = DEAL_REASON.get(ivalue(last_out.get("reason"), -1), str(last_out.get("reason")))
            status = "closed"
        else:
            exit_time = now
            exit_reason = "OPEN"
            status = "open_or_partial"

        sl, tp = order_sl_tp(pos, orders)
        ex = excursions(symbol, direction, entry_time, exit_time, entry_price) if symbol and entry_price > 0 else {}
        mfe_abs = ex.get("mfe_abs")
        mae_abs = ex.get("mae_abs")
        tp_dist = abs(tp - entry_price) if tp > 0 else 0.0
        sl_dist = abs(entry_price - sl) if sl > 0 else 0.0
        tp_progress = (float(mfe_abs) / tp_dist * 100.0) if tp_dist > 0 and mfe_abs is not None else None
        sl_pressure = (float(mae_abs) / sl_dist * 100.0) if sl_dist > 0 and mae_abs is not None else None
        risk_r = None
        if sl_dist > 0 and exit_price > 0:
            move = (exit_price - entry_price) if direction == "BUY" else (entry_price - exit_price)
            risk_r = move / sl_dist

        rows.append({
            "position_id": pos,
            "status": status,
            "ea": ea,
            "magic": magic,
            "symbol": symbol,
            "direction": direction,
            "entry_time": entry_time.strftime("%Y-%m-%d %H:%M:%S"),
            "exit_time": exit_time.strftime("%Y-%m-%d %H:%M:%S") if out_deals else "",
            "duration_min": round((exit_time - entry_time).total_seconds() / 60.0, 2),
            "entry_volume": round(entry_vol, 6),
            "exit_volume": round(exit_vol, 6),
            "entry_price": round(entry_price, 6),
            "exit_price": round(exit_price, 6) if exit_price else "",
            "sl": round(sl, 6) if sl else "",
            "tp": round(tp, 6) if tp else "",
            "profit": round(profit, 2),
            "exit_reason": exit_reason,
            "comment": comment,
            "mfe_abs": ex.get("mfe_abs"),
            "mae_abs": ex.get("mae_abs"),
            "mfe_price": ex.get("mfe_price"),
            "mae_price": ex.get("mae_price"),
            "rates_tf": ex.get("rates_tf"),
            "tp_progress_pct": round(tp_progress, 2) if tp_progress is not None else "",
            "sl_pressure_pct": round(sl_pressure, 2) if sl_pressure is not None else "",
            "close_r_by_sl": round(risk_r, 3) if risk_r is not None else "",
            "deal_count": len(ds),
            "in_deals": len(in_deals),
            "out_deals": len(out_deals),
        })
    rows.sort(key=lambda r: (r["entry_time"], r["position_id"]))
    return rows


def open_position_rows(positions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    rows = []
    now = datetime.now()
    for p in positions:
        direction = "BUY" if ivalue(p.get("type"), 0) == mt5.POSITION_TYPE_BUY else "SELL"
        symbol = str(p.get("symbol") or "")
        entry = f(p.get("price_open"))
        open_time = datetime.fromtimestamp(ivalue(p.get("time"), 0))
        ex = excursions(symbol, direction, open_time, now, entry) if symbol and entry > 0 else {}
        tp = f(p.get("tp"))
        sl = f(p.get("sl"))
        tp_dist = abs(tp - entry) if tp > 0 else 0.0
        sl_dist = abs(entry - sl) if sl > 0 else 0.0
        mfe_abs = ex.get("mfe_abs")
        mae_abs = ex.get("mae_abs")
        tp_progress = (float(mfe_abs) / tp_dist * 100.0) if tp_dist > 0 and mfe_abs is not None else None
        sl_pressure = (float(mae_abs) / sl_dist * 100.0) if sl_dist > 0 and mae_abs is not None else None
        rows.append({
            "ticket": ivalue(p.get("ticket"), 0),
            "identifier": ivalue(p.get("identifier"), 0),
            "ea": classify_ea(ivalue(p.get("magic"), 0), str(p.get("comment") or "")),
            "magic": ivalue(p.get("magic"), 0),
            "symbol": symbol,
            "direction": direction,
            "volume": f(p.get("volume")),
            "entry_time": open_time.strftime("%Y-%m-%d %H:%M:%S"),
            "duration_min": round((now - open_time).total_seconds() / 60.0, 2),
            "entry_price": entry,
            "current_price": f(p.get("price_current")),
            "sl": sl if sl else "",
            "tp": tp if tp else "",
            "profit": round(f(p.get("profit")) + f(p.get("swap")), 2),
            "comment": str(p.get("comment") or ""),
            "mfe_abs": ex.get("mfe_abs"),
            "mae_abs": ex.get("mae_abs"),
            "mfe_price": ex.get("mfe_price"),
            "mae_price": ex.get("mae_price"),
            "rates_tf": ex.get("rates_tf"),
            "tp_progress_pct": round(tp_progress, 2) if tp_progress is not None else "",
            "sl_pressure_pct": round(sl_pressure, 2) if sl_pressure is not None else "",
        })
    rows.sort(key=lambda r: (r["entry_time"], r["ticket"]))
    return rows


def summarize(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    by_ea: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for r in rows:
        by_ea[str(r.get("ea") or "Unknown")].append(r)
    out = []
    for ea, group in sorted(by_ea.items()):
        closed = [r for r in group if r.get("status") == "closed"]
        wins = [r for r in closed if f(r.get("profit")) > 0]
        losses = [r for r in closed if f(r.get("profit")) < 0]
        pnl = sum(f(r.get("profit")) for r in closed)
        gross_win = sum(f(r.get("profit")) for r in wins)
        gross_loss = abs(sum(f(r.get("profit")) for r in losses))
        out.append({
            "ea": ea,
            "closed_trades": len(closed),
            "wins": len(wins),
            "losses": len(losses),
            "win_rate_pct": round(len(wins) / len(closed) * 100.0, 2) if closed else 0.0,
            "net_pnl": round(pnl, 2),
            "gross_win": round(gross_win, 2),
            "gross_loss": round(gross_loss, 2),
            "profit_factor": round(gross_win / gross_loss, 3) if gross_loss > 0 else (99.0 if gross_win > 0 else 0.0),
            "avg_win": round(gross_win / len(wins), 2) if wins else 0.0,
            "avg_loss": round(-gross_loss / len(losses), 2) if losses else 0.0,
            "avg_loser_tp_progress_pct": round(sum(f(r.get("tp_progress_pct")) for r in losses if r.get("tp_progress_pct") != "") / max(1, len([r for r in losses if r.get("tp_progress_pct") != ""])), 2) if losses else "",
            "avg_loser_sl_pressure_pct": round(sum(f(r.get("sl_pressure_pct")) for r in losses if r.get("sl_pressure_pct") != "") / max(1, len([r for r in losses if r.get("sl_pressure_pct") != ""])), 2) if losses else "",
        })
    return out


def write_csv(path: Path, rows: List[Dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = sorted({k for r in rows for k in r.keys()}) if rows else ["empty"]
    with path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--hours", type=int, default=24)
    ap.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    args = ap.parse_args()

    if not mt5.initialize():
        raise RuntimeError(f"mt5 initialize failed: {mt5.last_error()}")
    try:
        now = datetime.now()
        start = now - timedelta(hours=args.hours)
        account = asdict(mt5.account_info())
        terminal = asdict(mt5.terminal_info())
        deals = [asdict(x) for x in (mt5.history_deals_get(start, now) or [])]
        orders = [asdict(x) for x in (mt5.history_orders_get(start, now) or [])]
        positions = [asdict(x) for x in (mt5.positions_get() or [])]

        trades = trade_rows_from_history(deals, orders)
        open_rows = open_position_rows(positions)
        summary = summarize(trades)

        stamp = now.strftime("%Y%m%d_%H%M%S")
        out = args.out_dir / stamp
        out.mkdir(parents=True, exist_ok=True)
        write_csv(out / "closed_trades.csv", trades)
        write_csv(out / "open_positions.csv", open_rows)
        write_csv(out / "summary_by_ea.csv", summary)
        payload = {
            "generated_at": now.strftime("%Y-%m-%d %H:%M:%S"),
            "window_hours": args.hours,
            "window_from": start.strftime("%Y-%m-%d %H:%M:%S"),
            "window_to": now.strftime("%Y-%m-%d %H:%M:%S"),
            "account": account,
            "terminal": terminal,
            "counts": {"deals": len(deals), "orders": len(orders), "positions": len(positions), "closed_trade_groups": len(trades)},
            "summary_by_ea": summary,
            "open_positions": open_rows,
            "worst_closed": sorted([r for r in trades if r.get("status") == "closed"], key=lambda r: f(r.get("profit")))[:10],
            "best_closed": sorted([r for r in trades if r.get("status") == "closed"], key=lambda r: f(r.get("profit")), reverse=True)[:10],
        }
        (out / "audit.json").write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
        print(json.dumps({"out_dir": str(out), **payload["counts"], "summary_by_ea": summary}, indent=2, ensure_ascii=False))
        return 0
    finally:
        mt5.shutdown()


if __name__ == "__main__":
    raise SystemExit(main())
