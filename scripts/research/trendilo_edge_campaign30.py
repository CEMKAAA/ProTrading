#!/usr/bin/env python
"""30-candidate edge research campaign for Trendilo-family systems.

Purpose:
- Evaluate exactly 30 predefined candidates (the "30 chances")
- Compare against current fusion winner profile
- Favor robust, tradeable edges (not ultra-low-frequency artifacts)

Output:
- scripts/research/output/trendilo_edge_campaign30_*.json
"""

from __future__ import annotations

import json
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple
import runpy

import numpy as np
import pandas as pd

OUT_DIR = Path("scripts/research/output")


@dataclass
class CandidateSummary:
    id: str
    family: str
    params: Dict[str, Any]
    aggregate_score: float
    mean_score: float
    worst_score: float
    pass_symbols: int
    mean_trades_per_day: float
    symbols: Dict[str, Dict[str, float]]


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


def _h1_trend_filter(df: pd.DataFrame, ema_fn, ema_len: int = 200) -> pd.Series:
    h1 = (
        df[["close"]]
        .resample("1h")
        .last()
        .dropna()
    )
    h1_ema = ema_fn(h1["close"], ema_len)
    h1_slope = h1_ema.diff()
    f = pd.DataFrame(index=h1.index)
    f["bull"] = (h1["close"] > h1_ema) & (h1_slope > 0)
    f["bear"] = (h1["close"] < h1_ema) & (h1_slope < 0)
    f = f.reindex(df.index, method="ffill").fillna(False)
    trend = np.where(f["bull"], 1, np.where(f["bear"], -1, 0))
    return pd.Series(trend, index=df.index).astype(int)


def _trendilo_pulse_signals(
    df: pd.DataFrame,
    alma_fn,
    atr_fn,
    params: Dict[str, Any],
) -> pd.DataFrame:
    close = df["close"].astype(float)
    lookback = int(params["lookback"])
    pct_lb = int(params["pct_lookback"])
    offset = float(params["alma_offset"])
    sigma = float(params["alma_sigma"])
    bmult = float(params["band_mult"])
    adx_min = float(params["adx_min"])
    adx_len = int(params["adx_len"])
    hold_neutral = int(params["neutral_hold"])
    atr_mult = float(params["atr_mult"])

    pch = ((close - close.shift(pct_lb)) / close.replace(0.0, np.nan)) * 100.0
    avpch = alma_fn(pch, lookback, offset, sigma)
    rms = np.sqrt((avpch.pow(2)).rolling(window=lookback, min_periods=lookback).mean()) * bmult
    tdir = np.where(avpch > rms, 1, np.where(avpch < -rms, -1, 0))
    tdir_s = pd.Series(tdir, index=df.index).fillna(0).astype(int)
    prev = tdir_s.shift(1).fillna(0).astype(int)

    adx = _adx(df, adx_len)
    adx_gate = adx >= adx_min

    # allow brief neutral pullbacks before force-exit
    neutral_run = (tdir_s == 0).astype(int)
    neutral_age = neutral_run.groupby((neutral_run != neutral_run.shift()).cumsum()).cumsum()

    long_entry = (tdir_s == 1) & (prev <= 0) & adx_gate
    short_entry = (tdir_s == -1) & (prev >= 0) & adx_gate
    long_exit = (tdir_s == -1) | ((tdir_s == 0) & (neutral_age >= hold_neutral))
    short_exit = (tdir_s == 1) | ((tdir_s == 0) & (neutral_age >= hold_neutral))

    out = pd.DataFrame(index=df.index)
    out["long_entry_raw"] = long_entry.astype(bool)
    out["short_entry_raw"] = short_entry.astype(bool)
    out["long_exit_raw"] = long_exit.astype(bool)
    out["short_exit_raw"] = short_exit.astype(bool)
    out["stop_dist"] = (atr_fn(df, 14) * atr_mult).bfill().ffill().fillna(0.0)
    return out


def _lsma_hma_hybrid_signals(
    df: pd.DataFrame,
    ema_fn,
    hma_fn,
    atr_fn,
    params: Dict[str, Any],
) -> pd.DataFrame:
    # Fast approximation of Trendilo-LSMA style momentum color states:
    # smooth hl2 -> hma/ema blend -> slope sign; then apply ADX + H1 trend filter gates.
    high = df["high"].astype(float)
    low = df["low"].astype(float)
    close = df["close"].astype(float)
    hl2 = (high + low) / 2.0

    smooth = int(params["smooth"])
    lsma_len = int(params["lsma_len"])
    hma_len = int(params["hma_len"])
    adx_len = int(params["adx_len"])
    adx_min = float(params["adx_min"])
    atr_mult = float(params["atr_mult"])

    src = ema_fn(hl2, smooth)
    # LSMA proxy via EMA(hl2) smoothed with short regression-like filter
    lsma_proxy = ema_fn(src, max(2, lsma_len // 3))
    hma_val = hma_fn(src, hma_len)
    combine = (lsma_proxy + hma_val) / 2.0
    sig = combine.diff()

    color = np.where(sig > 0, 1, np.where(sig < 0, -1, 0))
    color_s = pd.Series(color, index=df.index).fillna(0).astype(int)
    prev = color_s.shift(1).fillna(0).astype(int)

    adx = _adx(df, adx_len)
    adx_gate = adx >= adx_min
    h1_trend = _h1_trend_filter(df, ema_fn, ema_len=int(params["h1_ema_len"]))

    long_entry = (color_s == 1) & (prev <= 0) & adx_gate & (h1_trend >= 0)
    short_entry = (color_s == -1) & (prev >= 0) & adx_gate & (h1_trend <= 0)
    long_exit = (color_s <= 0)
    short_exit = (color_s >= 0)

    out = pd.DataFrame(index=df.index)
    out["long_entry_raw"] = long_entry.astype(bool)
    out["short_entry_raw"] = short_entry.astype(bool)
    out["long_exit_raw"] = long_exit.astype(bool)
    out["short_exit_raw"] = short_exit.astype(bool)
    out["stop_dist"] = (atr_fn(df, 14) * atr_mult).bfill().ffill().fillna(0.0)
    return out


def _sym_score(test_metrics, trades_per_day: float) -> float:
    # Optimizes for edge + tradability:
    # return, PF, drawdown and enough frequency without forcing overtrading.
    ret = float(test_metrics.net_return_pct)
    dd = float(test_metrics.max_drawdown_pct)
    pf = float(test_metrics.profit_factor)
    base = ret - 1.6 * dd + min(18.0, pf * 4.0)
    freq_bonus = min(4.0, trades_per_day * 2.0)  # cap bonus near 2 trades/day
    freq_penalty = max(0.0, 0.4 - trades_per_day) * 6.0  # penalize ultra-rare
    return base + freq_bonus - freq_penalty


def _evaluate_candidate(
    cid: str,
    family: str,
    params: Dict[str, Any],
    data_by_symbol: Dict[str, pd.DataFrame],
    fns: Dict[str, Any],
) -> CandidateSummary:
    alpha = fns["alpha"]
    classic = fns["classic"]
    simulate = fns["simulate"]
    alma = fns["alma"]
    ema = fns["ema"]
    hma = fns["hma"]
    atr = fns["atr"]

    per_sym: Dict[str, Dict[str, float]] = {}
    scores: List[float] = []
    pass_symbols = 0
    tpd_vals: List[float] = []

    for sym, df in data_by_symbol.items():
        split = int(len(df) * 0.7)
        df_test = df.iloc[split:].copy()
        days = max(1.0, len(df_test) * 15.0 / (60.0 * 24.0))

        if family == "alpha":
            sig_full = alpha(df, params)
        elif family == "trendilo_pulse":
            sig_full = _trendilo_pulse_signals(df, alma, atr, params)
        elif family == "lsma_hybrid":
            sig_full = _lsma_hma_hybrid_signals(df, ema, hma, atr, params)
        elif family == "classic":
            sig_full = classic(df)
        else:
            raise ValueError(f"Unsupported family: {family}")

        sig_test = sig_full.iloc[split:].copy()
        m_test = simulate(df_test, sig_test, entry_filter=int(params.get("entry_filter", 1)), exit_filter=int(params.get("exit_filter", 1)))
        tpd = _safe_div(m_test.trades, days)
        sc = _sym_score(m_test, tpd)

        if m_test.net_return_pct > 0 and m_test.profit_factor > 1.0:
            pass_symbols += 1

        tpd_vals.append(float(tpd))
        scores.append(float(sc))
        per_sym[sym] = {
            "score": float(sc),
            "ret_pct": float(m_test.net_return_pct),
            "dd_pct": float(m_test.max_drawdown_pct),
            "pf": float(m_test.profit_factor),
            "trades": int(m_test.trades),
            "trades_per_day": float(tpd),
            "win_rate": float(m_test.win_rate),
        }

    mean_score = float(np.mean(scores)) if scores else -999.0
    worst_score = float(np.min(scores)) if scores else -999.0
    mean_tpd = float(np.mean(tpd_vals)) if tpd_vals else 0.0

    # Robust aggregate: favor strong mean + avoid single-symbol blowups + require breadth.
    aggregate = mean_score + 0.45 * worst_score + pass_symbols * 1.2
    return CandidateSummary(
        id=cid,
        family=family,
        params=params,
        aggregate_score=float(aggregate),
        mean_score=mean_score,
        worst_score=worst_score,
        pass_symbols=int(pass_symbols),
        mean_trades_per_day=mean_tpd,
        symbols=per_sym,
    )


def _build_candidates() -> List[Tuple[str, str, Dict[str, Any]]]:
    cands: List[Tuple[str, str, Dict[str, Any]]] = []

    # 1) Classic baseline anchor
    cands.append(("C01", "classic", {"entry_filter": 1, "exit_filter": 1}))

    # 2) Alpha family (12 total including current winner profile)
    alpha_base = {
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
        "stop_atr_length": 22,
        "entry_filter": 1,
        "exit_filter": 1,
    }
    alpha_variants = [
        # current winner (keep)
        {"vol_threshold": 90, "min_persistence": 1, "min_edge_ratio": 0.10, "stop_atr_mult": 3.0},
        {"vol_threshold": 90, "min_persistence": 2, "min_edge_ratio": 0.00, "stop_atr_mult": 3.0},
        {"vol_threshold": 90, "min_persistence": 1, "min_edge_ratio": 0.05, "stop_atr_mult": 2.8},
        {"vol_threshold": 86, "min_persistence": 1, "min_edge_ratio": 0.05, "stop_atr_mult": 2.8},
        {"vol_threshold": 86, "min_persistence": 2, "min_edge_ratio": 0.00, "stop_atr_mult": 3.0},
        {"vol_threshold": 84, "min_persistence": 1, "min_edge_ratio": 0.00, "stop_atr_mult": 2.4},
        {"vol_threshold": 84, "min_persistence": 2, "min_edge_ratio": 0.10, "stop_atr_mult": 2.4},
        {"vol_threshold": 90, "min_persistence": 2, "min_edge_ratio": 0.10, "stop_atr_mult": 2.8},
        {"vol_threshold": 86, "min_persistence": 2, "min_edge_ratio": 0.10, "stop_atr_mult": 2.6},
        {"vol_threshold": 82, "min_persistence": 1, "min_edge_ratio": 0.00, "stop_atr_mult": 2.2},
        {"vol_threshold": 82, "min_persistence": 2, "min_edge_ratio": 0.05, "stop_atr_mult": 2.6},
        {"vol_threshold": 88, "min_persistence": 1, "min_edge_ratio": 0.08, "stop_atr_mult": 3.0},
    ]
    for i, v in enumerate(alpha_variants, start=2):
        p = dict(alpha_base)
        p.update(v)
        cands.append((f"C{i:02d}", "alpha", p))

    # 3) Trendilo pulse family (10)
    pulse_variants = [
        {"lookback": 50, "pct_lookback": 1, "alma_offset": 0.85, "alma_sigma": 6, "band_mult": 1.0, "adx_min": 16, "adx_len": 14, "neutral_hold": 2, "atr_mult": 1.8},
        {"lookback": 50, "pct_lookback": 1, "alma_offset": 0.85, "alma_sigma": 6, "band_mult": 1.1, "adx_min": 18, "adx_len": 14, "neutral_hold": 2, "atr_mult": 1.9},
        {"lookback": 42, "pct_lookback": 1, "alma_offset": 0.88, "alma_sigma": 5, "band_mult": 1.0, "adx_min": 20, "adx_len": 14, "neutral_hold": 2, "atr_mult": 1.8},
        {"lookback": 42, "pct_lookback": 2, "alma_offset": 0.90, "alma_sigma": 5, "band_mult": 0.95, "adx_min": 18, "adx_len": 12, "neutral_hold": 3, "atr_mult": 1.7},
        {"lookback": 60, "pct_lookback": 1, "alma_offset": 0.85, "alma_sigma": 6, "band_mult": 1.0, "adx_min": 16, "adx_len": 14, "neutral_hold": 3, "atr_mult": 2.0},
        {"lookback": 60, "pct_lookback": 2, "alma_offset": 0.90, "alma_sigma": 6, "band_mult": 1.05, "adx_min": 20, "adx_len": 14, "neutral_hold": 2, "atr_mult": 2.0},
        {"lookback": 34, "pct_lookback": 1, "alma_offset": 0.82, "alma_sigma": 6, "band_mult": 0.95, "adx_min": 14, "adx_len": 10, "neutral_hold": 2, "atr_mult": 1.7},
        {"lookback": 34, "pct_lookback": 2, "alma_offset": 0.82, "alma_sigma": 7, "band_mult": 1.0, "adx_min": 16, "adx_len": 12, "neutral_hold": 2, "atr_mult": 1.8},
        {"lookback": 72, "pct_lookback": 1, "alma_offset": 0.88, "alma_sigma": 6, "band_mult": 1.1, "adx_min": 22, "adx_len": 14, "neutral_hold": 2, "atr_mult": 2.2},
        {"lookback": 72, "pct_lookback": 2, "alma_offset": 0.88, "alma_sigma": 7, "band_mult": 1.15, "adx_min": 24, "adx_len": 16, "neutral_hold": 2, "atr_mult": 2.2},
    ]
    for v in pulse_variants:
        idx = len(cands) + 1
        cands.append((f"C{idx:02d}", "trendilo_pulse", dict(v)))

    # 4) LSMA/HMA hybrid family (7)
    lsma_variants = [
        {"smooth": 5, "lsma_len": 25, "hma_len": 50, "adx_len": 14, "adx_min": 16, "h1_ema_len": 200, "atr_mult": 2.0},
        {"smooth": 4, "lsma_len": 20, "hma_len": 42, "adx_len": 12, "adx_min": 14, "h1_ema_len": 180, "atr_mult": 1.8},
        {"smooth": 6, "lsma_len": 30, "hma_len": 55, "adx_len": 14, "adx_min": 18, "h1_ema_len": 200, "atr_mult": 2.2},
        {"smooth": 5, "lsma_len": 18, "hma_len": 34, "adx_len": 10, "adx_min": 12, "h1_ema_len": 160, "atr_mult": 1.6},
        {"smooth": 7, "lsma_len": 35, "hma_len": 70, "adx_len": 16, "adx_min": 20, "h1_ema_len": 220, "atr_mult": 2.4},
        {"smooth": 3, "lsma_len": 15, "hma_len": 30, "adx_len": 10, "adx_min": 10, "h1_ema_len": 150, "atr_mult": 1.5},
        {"smooth": 5, "lsma_len": 25, "hma_len": 50, "adx_len": 14, "adx_min": 20, "h1_ema_len": 200, "atr_mult": 2.6},
    ]
    for v in lsma_variants:
        idx = len(cands) + 1
        cands.append((f"C{idx:02d}", "lsma_hybrid", dict(v)))

    assert len(cands) == 30, f"Expected exactly 30 candidates, got {len(cands)}"
    return cands


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    ns = runpy.run_path("scripts/research/trendilo_edge_lab.py", run_name="trendilo_edge_lab")
    fns = {
        "load": ns["_load_symbol_data"],
        "simulate": ns["_simulate"],
        "alpha": ns["_alpha_wave_signals"],
        "classic": ns["_classic_trendilo_signals"],
        "alma": ns["_alma"],
        "ema": ns["_ema"],
        "hma": ns["_hma"],
        "atr": ns["_atr"],
    }

    symbols = ["XAUUSD", "NAS100", "US500"]
    data_by_symbol: Dict[str, pd.DataFrame] = {}
    for sym in symbols:
        print(f"[campaign] loading {sym}...")
        df = fns["load"](sym)
        data_by_symbol[sym] = df
        print(f"[campaign] {sym} bars={len(df)} range={df.index.min()} -> {df.index.max()}")

    candidates = _build_candidates()
    print(f"[campaign] running {len(candidates)} candidates...")

    results: List[CandidateSummary] = []
    for i, (cid, fam, params) in enumerate(candidates, start=1):
        out = _evaluate_candidate(cid, fam, params, data_by_symbol, fns)
        results.append(out)
        print(
            f"[{i:02d}/30] {cid} {fam} agg={out.aggregate_score:.2f} "
            f"mean={out.mean_score:.2f} worst={out.worst_score:.2f} "
            f"pass={out.pass_symbols}/3 tpd={out.mean_trades_per_day:.2f}"
        )

    results.sort(
        key=lambda r: (r.aggregate_score, r.pass_symbols, r.mean_trades_per_day),
        reverse=True,
    )

    top10 = results[:10]
    print("\n[campaign] top 10:")
    for r in top10:
        print(
            f"{r.id} {r.family} agg={r.aggregate_score:.2f} "
            f"pass={r.pass_symbols}/3 tpd={r.mean_trades_per_day:.2f}"
        )

    payload = {
        "generated_at": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
        "symbols": symbols,
        "candidates_total": len(candidates),
        "top10": [asdict(r) for r in top10],
        "all": [asdict(r) for r in results],
    }
    out_file = OUT_DIR / f"trendilo_edge_campaign30_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}.json"
    out_file.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(f"[campaign] report saved: {out_file}")


if __name__ == "__main__":
    main()

