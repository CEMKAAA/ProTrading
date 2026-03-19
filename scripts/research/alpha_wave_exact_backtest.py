#!/usr/bin/env python
"""Exact-as-possible backtest of provided Alpha Wave Pine logic defaults.

No extra filters are injected.
No custom edge gates are injected.
Signals are generated from the same decision flow in the provided script.
"""

from __future__ import annotations

import json
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Tuple, Any
import runpy

import numpy as np
import pandas as pd

OUT_DIR = Path("scripts/research/output")


@dataclass
class Metrics:
    trades: int
    win_rate: float
    net_return_pct: float
    max_drawdown_pct: float
    profit_factor: float
    expectancy_pct: float
    trades_per_day: float


def _safe_div(a: float, b: float) -> float:
    return float(a / b) if b and np.isfinite(b) and abs(b) > 1e-12 else 0.0


def _adx(df: pd.DataFrame, period: int = 14) -> pd.Series:
    p = max(2, int(period))
    high = df["high"].astype(float)
    low = df["low"].astype(float)
    close = df["close"].astype(float)
    up_move = high.diff()
    down_move = -low.diff()
    plus_dm = np.where((up_move > down_move) & (up_move > 0), up_move, 0.0)
    minus_dm = np.where((down_move > up_move) & (down_move > 0), down_move, 0.0)
    prev_close = close.shift(1).fillna(close.iloc[0])
    tr = pd.concat(
        [
            (high - low).abs(),
            (high - prev_close).abs(),
            (low - prev_close).abs(),
        ],
        axis=1,
    ).max(axis=1)
    atr = tr.rolling(p, min_periods=p).mean()
    plus_di = 100.0 * pd.Series(plus_dm, index=df.index).rolling(p, min_periods=p).mean() / atr.replace(0.0, np.nan)
    minus_di = 100.0 * pd.Series(minus_dm, index=df.index).rolling(p, min_periods=p).mean() / atr.replace(0.0, np.nan)
    dx = 100.0 * (plus_di - minus_di).abs() / (plus_di + minus_di).replace(0.0, np.nan)
    return dx.rolling(p, min_periods=p).mean().fillna(0.0)


def _alpha_wave_exact_signals(
    df: pd.DataFrame,
    helpers: Dict[str, Any],
    p: Dict[str, Any],
) -> pd.DataFrame:
    close = df["close"].astype(float)
    high = df["high"].astype(float)
    low = df["low"].astype(float)
    open_ = df["open"].astype(float)
    hl2 = (high + low) / 2.0
    hlc3 = (high + low + close) / 3.0

    qama = helpers["qama"]
    wave_pulse = helpers["wave"]
    qfilter = helpers["qfilter"]
    atr_fn = helpers["atr"]
    ema_fn = helpers["ema"]

    # 1) Baseline
    baseline = qama(df, p["baseline_adx_length"], p["baseline_weight"], p["baseline_ma_length"])
    baseline_trend = np.where(close > baseline, 1, np.where(close < baseline, -1, 0))

    # 2) WavePulse
    wave_val = wave_pulse(close, p["conf1_smooth"], p["conf1_constant"])
    wave_signal = np.where(wave_val > wave_val.shift(1), 1, -1)
    wave_long_basic = (wave_signal > 0) & (close > wave_val)
    wave_short_basic = (wave_signal < 0) & (close < wave_val)
    wave_long = wave_long_basic if p["conf1_highlight"] else (close > wave_val)
    wave_short = wave_short_basic if p["conf1_highlight"] else (close < wave_val)
    if not p["use_conf1"]:
        wave_long = pd.Series(True, index=df.index)
        wave_short = pd.Series(True, index=df.index)
    wave_long_cross = ((~wave_long.shift(1).fillna(False)) & wave_long) if p["conf1_cross"] else wave_long
    wave_short_cross = ((~wave_short.shift(1).fillna(False)) & wave_short) if p["conf1_cross"] else wave_short
    wave_long_final = wave_short_cross if p["conf1_inverse"] else wave_long_cross
    wave_short_final = wave_long_cross if p["conf1_inverse"] else wave_short_cross

    # 3) Quantum channel
    beta = (1 - np.cos(4 * np.arcsin(1) / p["conf2_period"])) / ((1.414 ** (2 / p["conf2_poles"])) - 1)
    alpha = -beta + np.sqrt(beta * beta + 2 * beta)
    prev_close = close.shift(1).fillna(close)
    tr = pd.concat([(high - low).abs(), (high - prev_close).abs(), (low - prev_close).abs()], axis=1).max(axis=1)
    qf = qfilter(hlc3.to_numpy(dtype=float), alpha, int(p["conf2_poles"]))
    qtr = qfilter(tr.to_numpy(dtype=float), alpha, int(p["conf2_poles"]))
    qf_s = pd.Series(qf, index=df.index)
    qtr_s = pd.Series(qtr, index=df.index)
    q_upper = qf_s + qtr_s * float(p["conf2_multiplier"])
    q_lower = qf_s - qtr_s * float(p["conf2_multiplier"])
    q_signal = np.where(qf_s > qf_s.shift(1), 1, -1)
    q_long_basic = (q_signal > 0) & (close > qf_s)
    q_short_basic = (q_signal < 0) & (close < qf_s)
    q_long = q_long_basic if p["conf2_highlight"] else (close > qf_s)
    q_short = q_short_basic if p["conf2_highlight"] else (close < qf_s)
    if not p["use_conf2"]:
        q_long = pd.Series(True, index=df.index)
        q_short = pd.Series(True, index=df.index)
    q_long_cross = ((~q_long.shift(1).fillna(False)) & q_long) if p["conf2_cross"] else q_long
    q_short_cross = ((~q_short.shift(1).fillna(False)) & q_short) if p["conf2_cross"] else q_short
    q_long_final = q_short_cross if p["conf2_inverse"] else q_long_cross
    q_short_final = q_long_cross if p["conf2_inverse"] else q_short_cross

    # 4) Momentum density
    bound = close.rolling(p["vol_ma_length"], min_periods=1).mean() - 0.2 * close.rolling(
        p["vol_ma_length"], min_periods=2
    ).std().fillna(0.0)
    sum_above = (close > bound).astype(int).rolling(p["vol_length"], min_periods=1).sum()
    density = ema_fn((sum_above * 100.0) / float(p["vol_length"]), p["vol_smooth"])
    momentum_signal = density > p["vol_threshold"] if p["use_vol"] else pd.Series(True, index=df.index)

    # 5) Stop/trailing block
    stop_atr = atr_fn(df, p["stop_atr_length"]) * float(p["stop_atr_mult"])
    stop_src = hl2
    stop_high = high if p["stop_use_wicks"] else close
    stop_low = low if p["stop_use_wicks"] else close
    doji = (open_ == close) & (open_ == low) & (open_ == high)
    n = len(df)
    stop_long = np.zeros(n, dtype=float)
    stop_short = np.zeros(n, dtype=float)
    stop_dir = np.ones(n, dtype=int)
    for i in range(n):
        raw_l = float(stop_src.iloc[i] - stop_atr.iloc[i])
        raw_s = float(stop_src.iloc[i] + stop_atr.iloc[i])
        if i == 0:
            stop_long[i] = raw_l
            stop_short[i] = raw_s
            stop_dir[i] = 1
            continue
        prev_l = stop_long[i - 1]
        prev_s = stop_short[i - 1]
        prev_d = stop_dir[i - 1]
        if bool(doji.iloc[i]):
            stop_long[i] = prev_l
            stop_short[i] = prev_s
        else:
            stop_long[i] = max(raw_l, prev_l) if float(stop_low.iloc[i - 1]) > prev_l else raw_l
            stop_short[i] = min(raw_s, prev_s) if float(stop_high.iloc[i - 1]) < prev_s else raw_s
        if prev_d == -1 and float(stop_high.iloc[i]) > prev_s:
            stop_dir[i] = 1
        elif prev_d == 1 and float(stop_low.iloc[i]) < prev_l:
            stop_dir[i] = -1
        else:
            stop_dir[i] = prev_d
    stop_dir_s = pd.Series(stop_dir, index=df.index)
    stop_buy_signal = (stop_dir_s == 1) & (stop_dir_s.shift(1) == -1)
    stop_sell_signal = (stop_dir_s == -1) & (stop_dir_s.shift(1) == 1)
    channel_long_exit = high > pd.Series(stop_short, index=df.index)
    channel_short_exit = low < pd.Series(stop_long, index=df.index)

    # Trading style switch
    if p["trade_style"] == "Strict":
        raw_long = (baseline_trend == 1) & (close > baseline) & wave_long_final & q_long_final & momentum_signal
        raw_short = (baseline_trend == -1) & (close < baseline) & wave_short_final & q_short_final & momentum_signal
    elif p["trade_style"] == "Balanced":
        raw_long = (baseline_trend == 1) & (close > baseline) & (
            (wave_long_final & q_long_final) | (wave_long_final & momentum_signal) | (q_long_final & momentum_signal)
        )
        raw_short = (baseline_trend == -1) & (close < baseline) & (
            (wave_short_final & q_short_final) | (wave_short_final & momentum_signal) | (q_short_final & momentum_signal)
        )
    elif p["trade_style"] == "Scalper":
        raw_long = (baseline_trend == 1) & (close > baseline) & (wave_long_final | q_long_final) & momentum_signal
        raw_short = (baseline_trend == -1) & (close < baseline) & (wave_short_final | q_short_final) & momentum_signal
    else:  # Exits Only
        raw_long = pd.Series(False, index=df.index)
        raw_short = pd.Series(False, index=df.index)

    all_long = (baseline_trend == 1) & (wave_signal == 1) & (q_signal == 1) & momentum_signal
    all_short = (baseline_trend == -1) & (wave_signal == -1) & (q_signal == -1) & momentum_signal
    if p["require_all_aligned"]:
        raw_long = raw_long & all_long
        raw_short = raw_short & all_short

    stop_long_exit = stop_sell_signal
    stop_short_exit = stop_buy_signal
    if p["exit_type"] == "Stop Only":
        raw_long_exit = stop_long_exit
        raw_short_exit = stop_short_exit
    elif p["exit_type"] == "Inversed Channel":
        raw_long_exit = channel_long_exit
        raw_short_exit = channel_short_exit
    else:  # Combined
        raw_long_exit = stop_long_exit | channel_long_exit
        raw_short_exit = stop_short_exit | channel_short_exit

    out = pd.DataFrame(index=df.index)
    out["raw_long_signal"] = raw_long.astype(bool)
    out["raw_short_signal"] = raw_short.astype(bool)
    out["raw_long_exit"] = raw_long_exit.astype(bool)
    out["raw_short_exit"] = raw_short_exit.astype(bool)
    return out


def _simulate_exact(df: pd.DataFrame, sig: pd.DataFrame, p: Dict[str, Any]) -> Metrics:
    close = df["close"].astype(float).to_numpy()
    n = len(df)
    in_long = False
    in_short = False
    bars_since_entry = 1000
    bars_since_exit = 1000
    long_entry_price = np.nan
    short_entry_price = np.nan
    equity = 1.0
    peak = 1.0
    max_dd = 0.0
    rets: List[float] = []

    for i in range(1, n):
        bars_since_entry += 1
        bars_since_exit += 1

        # Apply entry/exit filters with current state (exact Pine intent)
        filtered_long_entry = bool(sig["raw_long_signal"].iat[i]) and (bars_since_entry >= p["entry_filter"]) and (not in_long)
        filtered_short_entry = bool(sig["raw_short_signal"].iat[i]) and (bars_since_entry >= p["entry_filter"]) and (not in_short)
        filtered_long_exit = bool(sig["raw_long_exit"].iat[i]) and (bars_since_exit >= p["exit_filter"]) and in_long
        filtered_short_exit = bool(sig["raw_short_exit"].iat[i]) and (bars_since_exit >= p["exit_filter"]) and in_short
        dtech_long_entry = (p["trade_style"] != "Exits Only") and filtered_long_entry
        dtech_short_entry = (p["trade_style"] != "Exits Only") and filtered_short_entry
        dtech_long_exit = filtered_long_exit
        dtech_short_exit = filtered_short_exit

        # Entry updates first (as in script order)
        if dtech_long_entry:
            in_long = True
            in_short = False
            bars_since_entry = 0
            long_entry_price = float(close[i])
        if dtech_short_entry:
            in_short = True
            in_long = False
            bars_since_entry = 0
            short_entry_price = float(close[i])

        # Exit updates
        if dtech_long_exit and in_long and np.isfinite(long_entry_price):
            ret = _safe_div((float(close[i]) - float(long_entry_price)), float(long_entry_price))
            rets.append(ret)
            equity *= (1.0 + ret)
            peak = max(peak, equity)
            max_dd = max(max_dd, _safe_div((peak - equity), peak))
            in_long = False
            bars_since_exit = 0
            long_entry_price = np.nan

        if dtech_short_exit and in_short and np.isfinite(short_entry_price):
            ret = _safe_div((float(short_entry_price) - float(close[i])), float(short_entry_price))
            rets.append(ret)
            equity *= (1.0 + ret)
            peak = max(peak, equity)
            max_dd = max(max_dd, _safe_div((peak - equity), peak))
            in_short = False
            bars_since_exit = 0
            short_entry_price = np.nan

    # close any open trade at last bar for accounting
    if in_long and np.isfinite(long_entry_price):
        ret = _safe_div((float(close[-1]) - float(long_entry_price)), float(long_entry_price))
        rets.append(ret)
        equity *= (1.0 + ret)
        peak = max(peak, equity)
        max_dd = max(max_dd, _safe_div((peak - equity), peak))
    if in_short and np.isfinite(short_entry_price):
        ret = _safe_div((float(short_entry_price) - float(close[-1])), float(short_entry_price))
        rets.append(ret)
        equity *= (1.0 + ret)
        peak = max(peak, equity)
        max_dd = max(max_dd, _safe_div((peak - equity), peak))

    wins = [r for r in rets if r > 0]
    losses = [r for r in rets if r < 0]
    trades = len(rets)
    days = max(1.0, len(df) * 15.0 / (60.0 * 24.0))
    pf = _safe_div(sum(wins), abs(sum(losses))) if losses else (999.0 if wins else 0.0)
    return Metrics(
        trades=trades,
        win_rate=(len(wins) / trades * 100.0) if trades else 0.0,
        net_return_pct=(equity - 1.0) * 100.0,
        max_drawdown_pct=max_dd * 100.0,
        profit_factor=float(pf),
        expectancy_pct=float(np.mean(rets) * 100.0 if rets else 0.0),
        trades_per_day=_safe_div(trades, days),
    )


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ns = runpy.run_path("scripts/research/trendilo_edge_lab.py", run_name="trendilo_edge_lab")
    load = ns["_load_symbol_data"]
    helpers = {
        "qama": ns["_quantum_adaptive_ma"],
        "wave": ns["_wave_pulse"],
        "qfilter": ns["_quantum_filter"],
        "atr": ns["_atr"],
        "ema": ns["_ema"],
    }

    params = {
        # exact defaults from provided Pine
        "baseline_adx_length": 2,
        "baseline_weight": 10.0,
        "baseline_ma_length": 6,
        "use_conf1": True,
        "conf1_smooth": 21,
        "conf1_constant": 0.4,
        "conf1_cross": True,
        "conf1_inverse": False,
        "conf1_highlight": True,
        "use_conf2": True,
        "conf2_poles": 4,
        "conf2_period": 144,
        "conf2_multiplier": 1.414,
        "conf2_cross": True,
        "conf2_inverse": False,
        "conf2_highlight": True,
        "use_vol": True,
        "vol_ma_length": 100,
        "vol_length": 60,
        "vol_smooth": 3,
        "vol_threshold": 90,
        "use_stop": True,
        "stop_atr_length": 22,
        "stop_atr_mult": 3.0,
        "stop_use_wicks": True,
        "exit_type": "Inversed Channel",
        "trade_style": "Balanced",
        "entry_filter": 3,
        "exit_filter": 2,
        "require_all_aligned": False,
    }

    symbols = ["XAUUSD", "NAS100", "US500"]
    report: Dict[str, Any] = {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "params": params,
        "symbols": {},
    }

    for sym in symbols:
        df = load(sym)
        split = int(len(df) * 0.7)
        train_df = df.iloc[:split].copy()
        test_df = df.iloc[split:].copy()

        train_sig = _alpha_wave_exact_signals(train_df, helpers, params)
        test_sig = _alpha_wave_exact_signals(test_df, helpers, params)
        m_train = _simulate_exact(train_df, train_sig, params)
        m_test = _simulate_exact(test_df, test_sig, params)

        report["symbols"][sym] = {
            "range_all": [str(df.index.min()), str(df.index.max())],
            "range_train": [str(train_df.index.min()), str(train_df.index.max())],
            "range_test": [str(test_df.index.min()), str(test_df.index.max())],
            "bars_all": int(len(df)),
            "bars_train": int(len(train_df)),
            "bars_test": int(len(test_df)),
            "train": asdict(m_train),
            "test": asdict(m_test),
        }
        print(
            f"[{sym}] TEST ret={m_test.net_return_pct:.2f}% dd={m_test.max_drawdown_pct:.2f}% "
            f"pf={m_test.profit_factor:.2f} trades={m_test.trades} tpd={m_test.trades_per_day:.2f}"
        )

    out_file = OUT_DIR / f"alpha_wave_exact_backtest_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.json"
    out_file.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"[exact] report saved: {out_file}")


if __name__ == "__main__":
    main()

