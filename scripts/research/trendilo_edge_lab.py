#!/usr/bin/env python
"""Research lab for finding robust Trendilo-family edge.

This script does NOT modify production strategy code.
It evaluates AlphaWave-style signal stack (from provided Pine logic)
vs. a classic Trendilo color-flip baseline across local historical CSV datasets.

Outputs:
- Console summary
- JSON report under scripts/research/output/
"""

from __future__ import annotations

import json
import math
from dataclasses import dataclass, asdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, List, Tuple, Any

import numpy as np
import pandas as pd

DATA_DIRS = [Path("dashboard/data/historical"), Path("data/historical")]
OUT_DIR = Path("scripts/research/output")
MAX_M15_BARS_PER_SYMBOL = 24_000  # ~250 trading days on M15; keeps research sweeps fast


@dataclass
class StrategyMetrics:
    trades: int
    win_rate: float
    net_return_pct: float
    max_drawdown_pct: float
    profit_factor: float
    expectancy_pct: float
    avg_r: float


@dataclass
class EvalResult:
    symbol: str
    strategy: str
    params: Dict[str, Any]
    train: StrategyMetrics
    test: StrategyMetrics
    score: float


def _safe_div(a: float, b: float) -> float:
    return float(a / b) if b and math.isfinite(b) and abs(b) > 1e-12 else 0.0


def _alma(series: pd.Series, length: int, offset: float, sigma: float) -> pd.Series:
    ln = max(2, int(length))
    off = float(max(0.0, min(1.0, offset)))
    sig = float(max(0.1, sigma))
    m = off * float(ln - 1)
    s = float(ln) / sig
    idx = np.arange(ln, dtype=float)
    w = np.exp(-((idx - m) ** 2) / (2.0 * s * s))
    w_sum = float(np.sum(w))
    if not np.isfinite(w_sum) or w_sum <= 1e-12:
        return series.rolling(window=ln, min_periods=1).mean()
    w = w / w_sum
    return series.rolling(window=ln, min_periods=ln).apply(lambda x: float(np.dot(x, w)), raw=True)


def _ema(series: pd.Series, length: int) -> pd.Series:
    return series.ewm(span=max(1, int(length)), adjust=False).mean()


def _hma(series: pd.Series, length: int) -> pd.Series:
    l = max(2, int(length))
    half = max(1, l // 2)
    sqrt_l = max(1, int(round(math.sqrt(l))))
    wma_half = series.rolling(half).apply(lambda x: np.average(x, weights=np.arange(1, len(x)+1)), raw=True)
    wma_full = series.rolling(l).apply(lambda x: np.average(x, weights=np.arange(1, len(x)+1)), raw=True)
    raw = 2.0 * wma_half - wma_full
    hma = raw.rolling(sqrt_l).apply(lambda x: np.average(x, weights=np.arange(1, len(x)+1)), raw=True)
    return hma


def _atr(df: pd.DataFrame, period: int = 14) -> pd.Series:
    p = max(2, int(period))
    high = df["high"].astype(float)
    low = df["low"].astype(float)
    close = df["close"].astype(float)
    prev_close = close.shift(1).fillna(close.iloc[0])
    tr = pd.concat(
        [
            (high - low).abs(),
            (high - prev_close).abs(),
            (low - prev_close).abs(),
        ],
        axis=1,
    ).max(axis=1)
    return tr.rolling(window=p, min_periods=1).mean()


def _load_symbol_data(symbol: str) -> pd.DataFrame:
    files: List[Path] = []
    for base in DATA_DIRS:
        if not base.exists():
            continue
        files.extend(sorted(base.glob(f"{symbol}_M1_*_dukascopy.csv")))
        files.extend(sorted(base.glob(f"{symbol}_M1_*_ibkr.csv")))
    # Deduplicate by absolute path
    uniq = []
    seen = set()
    for f in files:
        rp = str(f.resolve())
        if rp in seen:
            continue
        seen.add(rp)
        uniq.append(f)
    if not uniq:
        raise FileNotFoundError(f"No M1 CSV files found for {symbol}")

    chunks: List[pd.DataFrame] = []
    for f in uniq:
        df = pd.read_csv(f, sep=None, engine="python")
        cols = {c.strip().lower(): c for c in df.columns}
        if "date" in cols and "time" in cols:
            dt = pd.to_datetime(
                df[cols["date"]].astype(str).str.strip() + " " + df[cols["time"]].astype(str).str.strip(),
                errors="coerce",
                format="%Y.%m.%d %H:%M",
            )
        elif "datetime" in cols:
            dt = pd.to_datetime(df[cols["datetime"]], errors="coerce")
        else:
            continue
        volume_col = cols.get("volume") or cols.get("tickvolume")
        spread_col = cols.get("spread")
        open_col = cols.get("open")
        high_col = cols.get("high")
        low_col = cols.get("low")
        close_col = cols.get("close")
        if not open_col or not high_col or not low_col or not close_col:
            continue
        out = pd.DataFrame(
            {
                "datetime": dt,
                "open": pd.to_numeric(df[open_col], errors="coerce"),
                "high": pd.to_numeric(df[high_col], errors="coerce"),
                "low": pd.to_numeric(df[low_col], errors="coerce"),
                "close": pd.to_numeric(df[close_col], errors="coerce"),
                "volume": pd.to_numeric(df[volume_col], errors="coerce").fillna(0.0) if volume_col else 0.0,
                "spread": pd.to_numeric(df[spread_col], errors="coerce").fillna(0.0) if spread_col else 0.0,
            }
        )
        out = out.dropna(subset=["datetime", "open", "high", "low", "close"]) 
        chunks.append(out)

    if not chunks:
        raise RuntimeError(f"Unable to parse CSV files for {symbol}")

    full = pd.concat(chunks, ignore_index=True)
    full = full.sort_values("datetime").drop_duplicates(subset=["datetime"], keep="last")
    full = full.set_index("datetime")

    # Resample to M15 for robust signal extraction
    ohlc = full.resample("15min").agg(
        {
            "open": "first",
            "high": "max",
            "low": "min",
            "close": "last",
            "volume": "sum",
            "spread": "mean",
        }
    ).dropna(subset=["open", "high", "low", "close"])
    if len(ohlc) > MAX_M15_BARS_PER_SYMBOL:
        ohlc = ohlc.iloc[-MAX_M15_BARS_PER_SYMBOL:].copy()
    return ohlc


def _classic_trendilo_signals(df: pd.DataFrame) -> pd.DataFrame:
    close = df["close"].astype(float)
    pch = ((close - close.shift(1)) / close.replace(0.0, np.nan)) * 100.0
    avpch = _alma(pch, 50, 0.85, 6.0)
    rms = np.sqrt((avpch.pow(2)).rolling(window=50, min_periods=50).mean())
    color = np.where(avpch > rms, 1, np.where(avpch < -rms, -1, 0))
    color_s = pd.Series(color, index=df.index).fillna(0).astype(int)
    prev = color_s.shift(1).fillna(0).astype(int)

    long_entry = (color_s == 1) & (prev <= 0)
    short_entry = (color_s == -1) & (prev >= 0)
    long_exit = (color_s <= 0)
    short_exit = (color_s >= 0)

    out = pd.DataFrame(index=df.index)
    out["long_entry_raw"] = long_entry.astype(bool)
    out["short_entry_raw"] = short_entry.astype(bool)
    out["long_exit_raw"] = long_exit.astype(bool)
    out["short_exit_raw"] = short_exit.astype(bool)
    out["stop_dist"] = (_atr(df, 14) * 1.8).bfill().ffill().fillna(0.0)
    return out


def _quantum_adaptive_ma(df: pd.DataFrame, adx_len: int, weight: float, ma_len: int) -> pd.Series:
    high = df["high"].astype(float).to_numpy()
    low = df["low"].astype(float).to_numpy()
    close = df["close"].astype(float).to_numpy()
    n = len(df)

    power_bulls = np.zeros(n)
    power_bears = np.zeros(n)
    str_range = np.zeros(n)
    diag_x = np.zeros(n)
    var_ma = np.zeros(n)

    if n == 0:
        return pd.Series(dtype=float, index=df.index)

    str_range[0] = max(high[0] - low[0], 1e-12)
    var_ma[0] = close[0]

    for i in range(1, n):
        hi = high[i]
        hi1 = high[i - 1]
        lo = low[i]
        lo1 = low[i - 1]
        close1 = close[i - 1]

        bulls1 = 0.5 * (abs(hi - hi1) + (hi - hi1))
        bears1 = 0.5 * (abs(lo1 - lo) + (lo1 - lo))

        bears = 0.0 if bulls1 >= bears1 else bears1
        bulls = 0.0 if bulls1 <= bears1 else bulls1

        power_bulls[i] = (weight * power_bulls[i - 1] + bulls) / (weight + 1.0)
        power_bears[i] = (weight * power_bears[i - 1] + bears) / (weight + 1.0)

        true_range = max(hi - lo, hi - close1)
        str_range[i] = (weight * str_range[i - 1] + true_range) / (weight + 1.0)

        pos_di = power_bulls[i] / str_range[i] if str_range[i] > 0 else 0.0
        neg_di = power_bears[i] / str_range[i] if str_range[i] > 0 else 0.0
        di_sum = pos_di + neg_di
        di_diff = abs(pos_di - neg_di) / di_sum if di_sum > 0 else 0.0
        diag_x[i] = (weight * diag_x[i - 1] + di_diff) / (weight + 1.0)

        lo_idx = max(0, i - adx_len + 1)
        adx_min = float(np.min(diag_x[lo_idx : i + 1]))
        adx_max = float(np.max(diag_x[lo_idx : i + 1]))
        adx_diff = adx_max - adx_min
        adx_const = (diag_x[i] - adx_min) / adx_diff if adx_diff > 1e-12 else 0.0
        var_ma[i] = ((2.0 - adx_const) * var_ma[i - 1] + adx_const * close[i]) / 2.0

    var_series = pd.Series(var_ma, index=df.index)
    return var_series.rolling(window=max(1, int(ma_len)), min_periods=1).mean()


def _wave_pulse(close: pd.Series, smooth: int, constant: float) -> pd.Series:
    di_val = (smooth - 1.0) / 2.0 + 1.0
    c1 = 2.0 / (di_val + 1.0)
    c2 = 1.0 - c1
    c3 = 3.0 * (constant * constant + constant * constant * constant)
    c4 = -3.0 * (2.0 * constant * constant + constant + constant * constant * constant)
    c5 = 3.0 * constant + 1.0 + constant * constant * constant + 3.0 * constant * constant

    n = len(close)
    i1 = np.zeros(n)
    i2 = np.zeros(n)
    i3 = np.zeros(n)
    i4 = np.zeros(n)
    i5 = np.zeros(n)
    i6 = np.zeros(n)
    c = close.to_numpy(dtype=float)

    if n > 0:
        i1[0] = c[0]
        i2[0] = c[0]
        i3[0] = c[0]
        i4[0] = c[0]
        i5[0] = c[0]
        i6[0] = c[0]

    for t in range(1, n):
        i1[t] = c1 * c[t] + c2 * i1[t - 1]
        i2[t] = c1 * i1[t] + c2 * i2[t - 1]
        i3[t] = c1 * i2[t] + c2 * i3[t - 1]
        i4[t] = c1 * i3[t] + c2 * i4[t - 1]
        i5[t] = c1 * i4[t] + c2 * i5[t - 1]
        i6[t] = c1 * i5[t] + c2 * i6[t - 1]

    wave = -(constant**3) * i6 + c3 * i5 + c4 * i4 + c5 * i3
    return pd.Series(wave, index=close.index)


def _quantum_filter(src: np.ndarray, a: float, poles: int) -> np.ndarray:
    # Coefficients from provided Pine block
    coeff_map = {
        2: (1, 0, 0, 0, 0, 0, 0, 0),
        3: (3, 1, 0, 0, 0, 0, 0, 0),
        4: (6, 4, 1, 0, 0, 0, 0, 0),
        5: (10, 10, 5, 1, 0, 0, 0, 0),
        6: (15, 20, 15, 6, 1, 0, 0, 0),
        7: (21, 35, 35, 21, 7, 1, 0, 0),
        8: (28, 56, 70, 56, 28, 8, 1, 0),
        9: (36, 84, 126, 126, 84, 36, 9, 1),
    }
    p = max(1, min(9, int(poles)))
    c = coeff_map.get(p, (0, 0, 0, 0, 0, 0, 0, 0))
    x = 1.0 - float(a)
    n = len(src)
    f = np.zeros(n, dtype=float)
    if n == 0:
        return f
    f[0] = src[0]
    ap = float(a) ** p
    for t in range(1, n):
        term = ap * src[t] + p * x * f[t - 1]
        if p >= 2 and t >= 2:
            term -= c[0] * (x**2) * f[t - 2]
        if p >= 3 and t >= 3:
            term += c[1] * (x**3) * f[t - 3]
        if p >= 4 and t >= 4:
            term -= c[2] * (x**4) * f[t - 4]
        if p >= 5 and t >= 5:
            term += c[3] * (x**5) * f[t - 5]
        if p >= 6 and t >= 6:
            term -= c[4] * (x**6) * f[t - 6]
        if p >= 7 and t >= 7:
            term += c[5] * (x**7) * f[t - 7]
        if p >= 8 and t >= 8:
            term -= c[6] * (x**8) * f[t - 8]
        if p >= 9 and t >= 9:
            term += c[7] * (x**9) * f[t - 9]
        f[t] = term
    return f


def _alpha_wave_signals(df: pd.DataFrame, p: Dict[str, Any]) -> pd.DataFrame:
    close = df["close"].astype(float)
    high = df["high"].astype(float)
    low = df["low"].astype(float)
    open_ = df["open"].astype(float)
    hl2 = (high + low) / 2.0
    hlc3 = (high + low + close) / 3.0

    baseline = _quantum_adaptive_ma(df, p["baseline_adx_length"], p["baseline_weight"], p["baseline_ma_length"])
    baseline_trend = np.where(close > baseline, 1, np.where(close < baseline, -1, 0))

    wave = _wave_pulse(close, p["conf1_smooth"], p["conf1_constant"])
    wave_signal = np.where(wave > wave.shift(1), 1, -1)
    wave_long_basic = (wave_signal > 0) & (close > wave)
    wave_short_basic = (wave_signal < 0) & (close < wave)

    wave_long = wave_long_basic
    wave_short = wave_short_basic
    wave_long_cross = (~wave_long.shift(1).fillna(False)) & wave_long if p["conf1_cross"] else wave_long
    wave_short_cross = (~wave_short.shift(1).fillna(False)) & wave_short if p["conf1_cross"] else wave_short

    wave_long_final = wave_short_cross if p["conf1_inverse"] else wave_long_cross
    wave_short_final = wave_long_cross if p["conf1_inverse"] else wave_short_cross

    beta = (1 - math.cos(4 * math.asin(1) / p["conf2_period"])) / ((1.414 ** (2 / p["conf2_poles"])) - 1)
    alpha = -beta + math.sqrt(beta * beta + 2 * beta)

    tr = pd.concat(
        [
            (high - low).abs(),
            (high - close.shift(1).fillna(close)).abs(),
            (low - close.shift(1).fillna(close)).abs(),
        ],
        axis=1,
    ).max(axis=1)

    qf = _quantum_filter(hlc3.to_numpy(dtype=float), alpha, int(p["conf2_poles"]))
    qtr = _quantum_filter(tr.to_numpy(dtype=float), alpha, int(p["conf2_poles"]))
    qf_s = pd.Series(qf, index=df.index)
    qtr_s = pd.Series(qtr, index=df.index)

    q_signal = np.where(qf_s > qf_s.shift(1), 1, -1)
    q_long_basic = (q_signal > 0) & (close > qf_s)
    q_short_basic = (q_signal < 0) & (close < qf_s)

    q_long = q_long_basic
    q_short = q_short_basic
    q_long_cross = (~q_long.shift(1).fillna(False)) & q_long if p["conf2_cross"] else q_long
    q_short_cross = (~q_short.shift(1).fillna(False)) & q_short if p["conf2_cross"] else q_short

    q_long_final = q_short_cross if p["conf2_inverse"] else q_long_cross
    q_short_final = q_long_cross if p["conf2_inverse"] else q_short_cross

    bound = close.rolling(p["vol_ma_length"], min_periods=1).mean() - 0.2 * close.rolling(p["vol_ma_length"], min_periods=2).std().fillna(0.0)
    sum_above = (close > bound).astype(int).rolling(p["vol_length"], min_periods=1).sum()
    momentum_density = _ema((sum_above * 100.0) / float(p["vol_length"]), p["vol_smooth"])
    momentum_signal = momentum_density > p["vol_threshold"]

    # ATR trailing stop block
    stop_atr = _atr(df, p["stop_atr_length"]) * float(p["stop_atr_mult"])
    stop_src = hl2
    stop_high = high
    stop_low = low
    doji = (open_ == close) & (open_ == low) & (open_ == high)

    n = len(df)
    stop_long_level = np.zeros(n, dtype=float)
    stop_short_level = np.zeros(n, dtype=float)
    stop_dir = np.ones(n, dtype=int)

    for i in range(n):
        raw_long = float(stop_src.iloc[i] - stop_atr.iloc[i])
        raw_short = float(stop_src.iloc[i] + stop_atr.iloc[i])
        if i == 0:
            stop_long_level[i] = raw_long
            stop_short_level[i] = raw_short
            stop_dir[i] = 1
            continue

        prev_long = stop_long_level[i - 1]
        prev_short = stop_short_level[i - 1]
        prev_dir = stop_dir[i - 1]

        if bool(doji.iloc[i]):
            stop_long_level[i] = prev_long
            stop_short_level[i] = prev_short
        else:
            stop_long_level[i] = max(raw_long, prev_long) if float(stop_low.iloc[i - 1]) > prev_long else raw_long
            stop_short_level[i] = min(raw_short, prev_short) if float(stop_high.iloc[i - 1]) < prev_short else raw_short

        if prev_dir == -1 and float(stop_high.iloc[i]) > prev_short:
            stop_dir[i] = 1
        elif prev_dir == 1 and float(stop_low.iloc[i]) < prev_long:
            stop_dir[i] = -1
        else:
            stop_dir[i] = prev_dir

    stop_dir_s = pd.Series(stop_dir, index=df.index)
    stop_buy_signal = (stop_dir_s == 1) & (stop_dir_s.shift(1) == -1)
    stop_sell_signal = (stop_dir_s == -1) & (stop_dir_s.shift(1) == 1)

    # Inversed channel exit mode
    channel_long_exit = high > pd.Series(stop_short_level, index=df.index)
    channel_short_exit = low < pd.Series(stop_long_level, index=df.index)

    # "Balanced" style from provided script
    raw_long = (
        (baseline_trend == 1)
        & (close > baseline)
        & (
            (wave_long_final & q_long_final)
            | (wave_long_final & momentum_signal)
            | (q_long_final & momentum_signal)
        )
    )
    raw_short = (
        (baseline_trend == -1)
        & (close < baseline)
        & (
            (wave_short_final & q_short_final)
            | (wave_short_final & momentum_signal)
            | (q_short_final & momentum_signal)
        )
    )

    # Extra anti-drawdown guard (research mode): trendilo edge + persistence
    pch = ((close - close.shift(1)) / close.replace(0.0, np.nan)) * 100.0
    avpch = _alma(pch, 50, 0.85, 6.0)
    rms = np.sqrt((avpch.pow(2)).rolling(50, min_periods=50).mean())
    tdir = np.where(avpch > rms, 1, np.where(avpch < -rms, -1, 0))
    tdir_s = pd.Series(tdir, index=df.index)

    persist = np.zeros(n, dtype=int)
    for i in range(1, n):
        persist[i] = persist[i - 1] + 1 if tdir[i] != 0 and tdir[i] == tdir[i - 1] else (1 if tdir[i] != 0 else 0)
    edge = (avpch.abs() - rms) / rms.replace(0.0, np.nan)
    edge = edge.replace([np.inf, -np.inf], np.nan).fillna(0.0)

    anti_noise = (persist >= int(p["min_persistence"])) & (edge >= float(p["min_edge_ratio"]))
    raw_long = raw_long & anti_noise
    raw_short = raw_short & anti_noise

    out = pd.DataFrame(index=df.index)
    out["long_entry_raw"] = raw_long.astype(bool)
    out["short_entry_raw"] = raw_short.astype(bool)
    out["long_exit_raw"] = channel_long_exit.astype(bool) | stop_sell_signal.astype(bool)
    out["short_exit_raw"] = channel_short_exit.astype(bool) | stop_buy_signal.astype(bool)
    out["stop_dist"] = stop_atr.astype(float)
    return out


def _simulate(df: pd.DataFrame, sig: pd.DataFrame, entry_filter: int, exit_filter: int) -> StrategyMetrics:
    n = len(df)
    close = df["close"].to_numpy(dtype=float)
    high = df["high"].to_numpy(dtype=float)
    low = df["low"].to_numpy(dtype=float)

    # infer point from decimals to convert spread to price
    point = 0.001
    spread_price = (pd.to_numeric(df["spread"], errors="coerce").fillna(0.0) * point).to_numpy(dtype=float)

    pos = 0  # -1 short, +1 long
    entry_price = 0.0
    entry_stop = 0.0
    bars_since_entry = 10_000
    bars_since_exit = 10_000

    equity = 1.0
    peak = 1.0
    max_dd = 0.0

    returns: List[float] = []
    r_vals: List[float] = []

    for i in range(2, n):
        bars_since_entry += 1
        bars_since_exit += 1

        le = bool(sig["long_entry_raw"].iat[i]) and bars_since_entry >= entry_filter and pos <= 0
        se = bool(sig["short_entry_raw"].iat[i]) and bars_since_entry >= entry_filter and pos >= 0
        lx = bool(sig["long_exit_raw"].iat[i]) and bars_since_exit >= exit_filter and pos > 0
        sx = bool(sig["short_exit_raw"].iat[i]) and bars_since_exit >= exit_filter and pos < 0

        def close_trade(px: float):
            nonlocal pos, entry_price, entry_stop, equity, peak, max_dd, bars_since_exit
            if pos == 0:
                return
            gross = (px - entry_price) / entry_price if pos > 0 else (entry_price - px) / entry_price
            # Half spread on entry + half on exit
            cost = _safe_div((spread_price[i] * 0.5 + spread_price[max(0, i - 1)] * 0.5), max(1e-9, entry_price))
            ret = gross - cost
            risk = abs(entry_price - entry_stop)
            r = _safe_div((px - entry_price) if pos > 0 else (entry_price - px), max(1e-9, risk))
            returns.append(float(ret))
            r_vals.append(float(r))
            equity *= (1.0 + ret)
            peak = max(peak, equity)
            max_dd = max(max_dd, _safe_div((peak - equity), peak))
            pos = 0
            bars_since_exit = 0

        # exits first
        if lx:
            close_trade(float(close[i]))
        elif sx:
            close_trade(float(close[i]))

        # then entries/reversals
        if le:
            if pos < 0:
                close_trade(float(close[i]))
            if pos == 0:
                pos = 1
                entry_price = float(close[i])
                entry_stop = float(close[i] - max(1e-6, float(sig["stop_dist"].iat[i])))
                bars_since_entry = 0
        elif se:
            if pos > 0:
                close_trade(float(close[i]))
            if pos == 0:
                pos = -1
                entry_price = float(close[i])
                entry_stop = float(close[i] + max(1e-6, float(sig["stop_dist"].iat[i])))
                bars_since_entry = 0

    if pos != 0:
        # Force close last bar
        px = float(close[-1])
        gross = (px - entry_price) / entry_price if pos > 0 else (entry_price - px) / entry_price
        cost = _safe_div(spread_price[-1], max(1e-9, entry_price))
        ret = gross - cost
        risk = abs(entry_price - entry_stop)
        r = _safe_div((px - entry_price) if pos > 0 else (entry_price - px), max(1e-9, risk))
        returns.append(float(ret))
        r_vals.append(float(r))
        equity *= (1.0 + ret)
        peak = max(peak, equity)
        max_dd = max(max_dd, _safe_div((peak - equity), peak))

    trades = len(returns)
    wins = [r for r in returns if r > 0]
    losses = [r for r in returns if r < 0]
    net = (equity - 1.0) * 100.0
    pf = _safe_div(sum(wins), abs(sum(losses))) if losses else (999.0 if wins else 0.0)
    avg_r = float(np.mean(r_vals)) if r_vals else 0.0
    return StrategyMetrics(
        trades=trades,
        win_rate=(len(wins) / trades * 100.0) if trades else 0.0,
        net_return_pct=float(net),
        max_drawdown_pct=float(max_dd * 100.0),
        profit_factor=float(pf),
        expectancy_pct=float(np.mean(returns) * 100.0 if returns else 0.0),
        avg_r=float(avg_r),
    )


def _evaluate_symbol(symbol: str, df: pd.DataFrame) -> List[EvalResult]:
    split_idx = int(len(df) * 0.7)
    train_df = df.iloc[:split_idx].copy()
    test_df = df.iloc[split_idx:].copy()

    results: List[EvalResult] = []

    # Baseline Trendilo config
    base_sig_train = _classic_trendilo_signals(train_df)
    base_sig_test = _classic_trendilo_signals(test_df)
    base_train = _simulate(train_df, base_sig_train, entry_filter=1, exit_filter=1)
    base_test = _simulate(test_df, base_sig_test, entry_filter=1, exit_filter=1)
    base_score = base_test.net_return_pct - 1.5 * base_test.max_drawdown_pct + min(30.0, base_test.profit_factor * 5.0)
    results.append(
        EvalResult(
            symbol=symbol,
            strategy="trendilo_classic_baseline",
            params={"entry_filter": 1, "exit_filter": 1},
            train=base_train,
            test=base_test,
            score=float(base_score),
        )
    )

    grid = []
    for vol_threshold in [84, 90]:
        for min_persist in [1, 2]:
            for min_edge in [0.00, 0.05, 0.10]:
                for stop_mult in [2.4, 3.0]:
                    for entry_filter in [1, 2]:
                        grid.append(
                            {
                                "baseline_adx_length": 2,
                                "baseline_weight": 10.0,
                                "baseline_ma_length": 6,
                                "conf1_smooth": 21,
                                "conf1_constant": 0.4,
                                "conf1_cross": True,
                                "conf1_inverse": False,
                                "conf2_poles": 4,
                                "conf2_period": 144,
                                "conf2_multiplier": 1.414,
                                "conf2_cross": True,
                                "conf2_inverse": False,
                                "vol_ma_length": 100,
                                "vol_length": 60,
                                "vol_smooth": 3,
                                "vol_threshold": vol_threshold,
                                "stop_atr_length": 22,
                                "stop_atr_mult": stop_mult,
                                "min_persistence": min_persist,
                                "min_edge_ratio": min_edge,
                                "entry_filter": entry_filter,
                                "exit_filter": 1,
                            }
                        )

    best_train: List[Tuple[float, Dict[str, Any], StrategyMetrics]] = []

    for p in grid:
        sig_train = _alpha_wave_signals(train_df, p)
        m_train = _simulate(train_df, sig_train, entry_filter=int(p["entry_filter"]), exit_filter=int(p["exit_filter"]))
        # skeptical score: reward return + PF, punish drawdown + too few trades
        trade_penalty = 20.0 if m_train.trades < 20 else 0.0
        score = m_train.net_return_pct - 1.8 * m_train.max_drawdown_pct + min(35.0, m_train.profit_factor * 6.0) - trade_penalty
        best_train.append((float(score), p, m_train))

    best_train.sort(key=lambda x: x[0], reverse=True)
    top = best_train[:6]

    for train_score, p, m_train in top:
        sig_test = _alpha_wave_signals(test_df, p)
        m_test = _simulate(test_df, sig_test, entry_filter=int(p["entry_filter"]), exit_filter=int(p["exit_filter"]))
        oos_score = m_test.net_return_pct - 1.8 * m_test.max_drawdown_pct + min(35.0, m_test.profit_factor * 6.0)
        results.append(
            EvalResult(
                symbol=symbol,
                strategy="trendilo_fusion_alpha_wave_research",
                params=p,
                train=m_train,
                test=m_test,
                score=float(oos_score),
            )
        )

    results.sort(key=lambda r: r.score, reverse=True)
    return results


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    symbols = ["XAUUSD", "NAS100", "US500"]
    all_results: Dict[str, Any] = {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "symbols": {},
    }

    for sym in symbols:
        print(f"[research] loading {sym}...")
        df = _load_symbol_data(sym)
        if len(df) < 2000:
            print(f"[warn] {sym} bars too low after resample: {len(df)}")
        print(f"[research] {sym} M15 bars={len(df)} range={df.index.min()} -> {df.index.max()}")

        res = _evaluate_symbol(sym, df)
        baseline_rows = [r for r in res if r.strategy == "trendilo_classic_baseline"]
        fusion_rows = [r for r in res if r.strategy != "trendilo_classic_baseline"][:5]
        export_rows = baseline_rows + fusion_rows
        all_results["symbols"][sym] = [
            {
                "symbol": r.symbol,
                "strategy": r.strategy,
                "params": r.params,
                "train": asdict(r.train),
                "test": asdict(r.test),
                "score": r.score,
            }
            for r in export_rows
        ]

        best = res[0]
        print(
            f"[best:{sym}] {best.strategy} score={best.score:.2f} "
            f"test_ret={best.test.net_return_pct:.2f}% dd={best.test.max_drawdown_pct:.2f}% "
            f"pf={best.test.profit_factor:.2f} trades={best.test.trades}"
        )

    out_file = OUT_DIR / f"trendilo_edge_research_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.json"
    out_file.write_text(json.dumps(all_results, indent=2), encoding="utf-8")
    print(f"[research] report saved: {out_file}")


if __name__ == "__main__":
    main()
