"""HTF FVG + Liquidity Sweep Reclaim backtest strategy."""

from __future__ import annotations

import math
from datetime import datetime, timedelta
from typing import Any, Dict, List, Optional, Tuple

import pandas as pd

from .base import BacktestStrategy, DayContext, TradeSetup
from ..timezone_config import ASIAN_SESSION, LONDON_SESSION, NY_TZ, ORB_SESSION, TRADING_SESSION, UTC_TZ
from ..workbench.analysis_utils import (
    atr_last,
    detect_fvg_zones,
    detect_liquidity_zones,
    filter_sweep_candidates,
    resample_ohlcv,
    timeframe_to_minutes,
)
from ..workbench.symbol_utils import normalize_strategy_symbol


class HTFFVGLiquidityReclaimStrategy(BacktestStrategy):
    """Trades LTF reclaim into HTF FVGs after liquidity-sweep confirmation."""

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        self._used_sweep_keys: set[str] = set()
        self._last_session_date: Optional[datetime.date] = None
        self._last_session_cycle: Optional[str] = None
        self._last_h1_df = pd.DataFrame()
        self._last_h4_df = pd.DataFrame()

    def initialize_day(
        self,
        date: datetime,
        daily_df: Optional[pd.DataFrame],
        intraday_df: pd.DataFrame,
    ) -> DayContext:
        if hasattr(date, "date") and self._last_session_date != date.date():
            self._last_session_date = date.date()
        atr = atr_last(intraday_df, 14) or 0.0
        self._last_h1_df = resample_ohlcv(intraday_df, "1h")
        self._last_h4_df = resample_ohlcv(intraday_df, "4h")
        bias, bias_strength = self._compute_bias(intraday_df)
        ctx = DayContext(
            date=date,
            bias=bias,
            bias_strength=bias_strength,
            atr=float(atr or 0.0),
        )
        if daily_df is not None and not daily_df.empty:
            try:
                day_only = date.date() if hasattr(date, "date") else date
                prior_daily = daily_df[daily_df.index.date < day_only]
                if not prior_daily.empty:
                    prev = prior_daily.iloc[-1]
                    ctx.levels["daily_close"] = float(prev.get("close"))
                    ctx.levels["daily_high"] = float(prev.get("high"))
                    ctx.levels["daily_low"] = float(prev.get("low"))
                    # G2: Daily structure — detect if prior two closes
                    # form a higher-close (bullish) or lower-close (bearish)
                    # sequence for cross-referencing in confidence scoring.
                    if len(prior_daily) >= 2:
                        d1 = float(prior_daily.iloc[-1]["close"])
                        d2 = float(prior_daily.iloc[-2]["close"])
                        ctx.levels["daily_trend"] = "bullish" if d1 > d2 else "bearish"
            except Exception:
                pass
        session_name = self._session_name_for_timestamp(date)
        session_cycle = self._session_cycle_key(date)
        if session_name:
            ctx.levels["session_name"] = session_name
        if session_cycle:
            ctx.levels["session_cycle"] = session_cycle
        return ctx

    def find_setup(
        self,
        bar: pd.Series,
        df: pd.DataFrame,
        day_context: DayContext,
        current_bar_index: int,
    ) -> Optional[TradeSetup]:
        if df is None or len(df) < self.get_required_lookback_bars() // 3:
            return None
        if not {"open", "high", "low", "close"}.issubset(df.columns):
            return None
        self._refresh_sweep_cycle(bar.name)

        current_price = float(bar["close"])
        atr = atr_last(df, 14) or float(day_context.atr or 0.0) or 1.0
        # E2: Use cached bias from initialize_day — resampling + EMA on
        # every bar is wasteful since H4 bias barely changes intraday.
        bias = str(day_context.bias or "neutral")
        bias_strength = int(day_context.bias_strength or 0)
        if bool(self.config.get("guardrail_news_filter_enabled", False)) and bool((day_context.levels or {}).get("news_high_impact", False)):
            return None
        active_fvgs = self._scan_htf_fvgs(df, atr)
        if not active_fvgs:
            return None

        fvg = self._select_active_fvg(active_fvgs, current_price, atr, bias, bias_strength)
        if not isinstance(fvg, dict):
            return None

        liq_df = df.tail(max(60, int(self.config.get("ltf_pool_lookback_bars", 420))))
        liquidity_zones = self._scan_liquidity_map(liq_df)
        if not liquidity_zones:
            return None

        bullish = str(fvg.get("type") or "") == "bullish_fvg"
        direction = "BUY" if bullish else "SELL"
        expected_sweep_dir = "bullish" if bullish else "bearish"
        # Keep fallback behavior symmetric across directions.
        sweep_ref_price = float((fvg.get("bottom") if bullish else fvg.get("top")) or current_price)

        # Use HTF ATR for sweep distance filtering — sweeps must be near HTF
        # structures, so distance tolerance should scale with HTF volatility.
        fvg_tf = str(fvg.get("timeframe") or self.config.get("htf_timeframe", "H4"))
        htf_df_for_atr = resample_ohlcv(df, self._timeframe_rule(fvg_tf))
        htf_atr_for_sweep = atr_last(htf_df_for_atr, 14) or atr

        freshness_bars = self._sweep_freshness_bars()
        sweep_candidates = filter_sweep_candidates(
            [z for z in liquidity_zones if str(z.get("type") or "").startswith("liquidity_sweep_")],
            entry_price=sweep_ref_price,
            direction=expected_sweep_dir,
            atr=htf_atr_for_sweep,
            max_age_bars=freshness_bars,
            max_distance_atr=float(self.config.get("sweep_distance_atr", self._default_sweep_distance_atr())),
            min_rejection_ratio=float(self.config.get("min_rejection_ratio", 0.30)),
            current_bar_index=len(liq_df) - 1,
        )
        if not sweep_candidates:
            return None

        sweep = sweep_candidates[0]

        # B4: Structural check — the swept pool must sit near the FVG's
        # entry edge, confirming the sweep targeted the same structural
        # liquidity.  Without this, distant coincidental sweeps can match.
        pool_boundary = float(sweep.get("pool_boundary") or sweep.get("swept_price") or 0.0)
        fvg_near_edge = float(fvg.get("bottom") if bullish else fvg.get("top") or 0.0)
        structural_tol = htf_atr_for_sweep * float(self.config.get("sweep_fvg_structural_atr", 0.75))
        if abs(pool_boundary - fvg_near_edge) > structural_tol:
            return None

        # A1: Bias alignment — strong sweeps (rejection > 0.60) override
        # the bias block because counter-trend sweeps with strong rejection
        # are the highest-edge ICT setups (institutional reversal traps).
        sweep_quality = str(sweep.get("rejection_quality") or "")
        if bool(self.config.get("require_bias_alignment", True)) and sweep_quality != "strong":
            if bullish and bias == "bearish" and bias_strength >= int(self.config.get("bias_min_strength", 30)):
                return None
            if (not bullish) and bias == "bullish" and bias_strength >= int(self.config.get("bias_min_strength", 30)):
                return None

        sweep_key = self._make_sweep_key(fvg, sweep)
        if sweep_key in self._used_sweep_keys:
            return None

        rejection_ratio = float(sweep.get("rejection_ratio") or 0.0)

        if not self._bar_retraces_into_fvg(bar, fvg, bullish):
            return None

        entry_estimate = float((day_context.levels or {}).get("execution_open", bar["close"]))
        stop_loss = self._compute_stop_loss(fvg, sweep, atr, bullish)
        risk = abs(entry_estimate - stop_loss)
        if risk <= 0.0 or not math.isfinite(risk):
            return None

        take_profit, target_source = self._compute_take_profit(
            entry_estimate=entry_estimate,
            fvg=fvg,
            liquidity_zones=liquidity_zones,
            risk=risk,
            bullish=bullish,
        )
        if take_profit is None:
            return None

        rr_ratio = abs(float(take_profit) - entry_estimate) / risk if risk > 0.0 else 0.0
        if rr_ratio < float(self.config.get("min_rr_ratio", 2.5)):
            return None

        self._used_sweep_keys.add(sweep_key)
        confidence = self._compute_confidence(
            fvg=fvg,
            sweep=sweep,
            bias=bias,
            bias_strength=bias_strength,
            atr=atr,
            day_context=day_context,
        )
        metadata = {
            "strategy": "htf_fvg_liquidity_reclaim_strategy",
            "fvg": {
                "type": str(fvg.get("type") or ""),
                "timeframe": str(fvg.get("timeframe") or ""),
                "top": float(fvg.get("top") or 0.0),
                "bottom": float(fvg.get("bottom") or 0.0),
                "size": float(fvg.get("current_gap_size") or fvg.get("gap_size") or abs(float(fvg.get("top") or 0.0) - float(fvg.get("bottom") or 0.0))),
                "quality_score": float(fvg.get("quality_score") or 0.0),
                "quality_label": str(fvg.get("quality_label") or ""),
            },
            "sweep_type": str(sweep.get("type") or ""),
            "sweep_rejection_ratio": float(rejection_ratio),
            "sweep_quality": str(sweep.get("rejection_quality") or ""),
            "sweep_extreme": float(sweep.get("swept_price") or 0.0),
            "sweep_pool_boundary": float(sweep.get("pool_boundary") or 0.0),
            "fvg_top": float(fvg.get("top") or 0.0),
            "fvg_bottom": float(fvg.get("bottom") or 0.0),
            "target_source": target_source,
            "expected_rr": float(round(rr_ratio, 4)),
            "skip_out_of_bounds_sl": True,
            "execution_entry_reference": float(entry_estimate),
            "session_name": str(self._session_name_for_timestamp(bar.name) or ""),
            "session_cycle": str(self._session_cycle_key(bar.name) or ""),
        }
        setup_type = f"HTF FVG Liquidity Reclaim ({'Long' if bullish else 'Short'})"
        return TradeSetup(
            direction=direction,
            entry_price=entry_estimate,
            stop_loss=float(stop_loss),
            take_profit=float(take_profit),
            setup_type=setup_type,
            confidence=float(confidence),
            metadata=metadata,
        )

    def should_close_early(
        self,
        bar: pd.Series,
        df: pd.DataFrame,
        position: Any,
        day_context: DayContext,
    ) -> Optional[str]:
        current_close = float(bar.get("close") or 0.0)
        is_long = str(position.direction or "").upper() == "BUY"
        fvg_top = float(position.fvg_top) if getattr(position, "fvg_top", None) is not None else None
        fvg_bottom = float(position.fvg_bottom) if getattr(position, "fvg_bottom", None) is not None else None
        meta = position.strategy_metadata or {}
        sweep_extreme = float(meta.get("sweep_extreme")) if meta.get("sweep_extreme") is not None else None

        # Buffer prevents premature exits from intrabar noise — a close
        # slightly beyond the FVG edge is normal on M15 Gold ($2-3 wicks).
        # The structural SL (below sweep extreme) is the real invalidation.
        atr = float(day_context.atr or 0.0)
        fvg_inval_buffer = atr * float(self.config.get("fvg_invalidation_buffer_atr", 0.15))
        if is_long and fvg_bottom is not None and current_close < fvg_bottom - fvg_inval_buffer:
            return "FVG Invalidation"
        if (not is_long) and fvg_top is not None and current_close > fvg_top + fvg_inval_buffer:
            return "FVG Invalidation"

        # C2: Sweep invalidation also gets a buffer — the SL below the
        # sweep extreme is the real guard; this exit is belt-and-suspenders.
        sweep_inval_buffer = atr * float(self.config.get("sweep_invalidation_buffer_atr", 0.10))
        if is_long and sweep_extreme is not None and current_close < sweep_extreme - sweep_inval_buffer:
            return "Sweep Invalidation"
        if (not is_long) and sweep_extreme is not None and current_close > sweep_extreme + sweep_inval_buffer:
            return "Sweep Invalidation"

        bars_held = len(df[df.index >= position.entry_time]) if getattr(position, "entry_time", None) is not None else 0

        # C4: Hard max-hold exit — if a trade hasn't resolved after
        # max_hold_bars (default 60 = 15h on M15), close regardless.
        max_hold = int(self.config.get("max_hold_bars", 60))
        if max_hold > 0 and bars_held > max_hold:
            return "Max Hold Time"

        if bars_held > int(self.config.get("momentum_fade_bars", 30)):
            initial_risk = abs(float(position.entry_price) - float(position.stop_loss))
            if initial_risk > 0.0:
                pnl_r = (
                    (current_close - float(position.entry_price)) / initial_risk
                    if is_long
                    else (float(position.entry_price) - current_close) / initial_risk
                )
                if pnl_r < float(self.config.get("momentum_fade_min_r", 0.5)):
                    return "Momentum Fade"

        return None

    def get_required_lookback_bars(self) -> int:
        return int(self.config.get("required_lookback_bars", 500))

    def get_required_daily_lookback_days(self) -> int:
        return 60

    def _default_sweep_distance_atr(self) -> float:
        symbol = normalize_strategy_symbol(self.config.get("symbol") or "")
        if symbol == "XAUUSD":
            return 0.50
        if symbol in {"NAS100", "US500"}:
            return 0.30
        if symbol.endswith("USD"):
            return 0.25
        return 0.30

    def _sweep_freshness_bars(self) -> int:
        hours = float(self.config.get("sweep_freshness_hours", 4.0))
        min_bars = int(self.config.get("sweep_freshness_min_bars", 4))
        tf_min = max(1, timeframe_to_minutes(self.config.get("timeframe"), 15))
        return max(min_bars, int(math.ceil((hours * 60.0) / float(tf_min))))

    def _compute_bias(self, df: pd.DataFrame) -> Tuple[str, int]:
        htf = resample_ohlcv(df, self._timeframe_rule(str(self.config.get("htf_timeframe", "H4"))))
        if len(htf) < 50:
            return "neutral", 0
        close = htf["close"].astype(float)
        # A2: Configurable EMA spans — default 20/50 is very slow for
        # mean-reversion setups; presets can use faster spans (e.g. 9/21).
        fast_span = int(self.config.get("bias_ema_fast", 20))
        slow_span = int(self.config.get("bias_ema_slow", 50))
        ema_fast = close.ewm(span=fast_span, adjust=False).mean()
        ema_slow = close.ewm(span=slow_span, adjust=False).mean()
        fast_now = float(ema_fast.iloc[-1])
        slow_now = float(ema_slow.iloc[-1])
        fast_prev = float(ema_fast.iloc[-5]) if len(ema_fast) >= 5 else fast_now
        slope = fast_now - fast_prev
        spread = abs(fast_now - slow_now)
        px = max(abs(float(close.iloc[-1])), 1e-9)
        strength = int(max(0.0, min(100.0, ((spread / px) * 10000.0) + abs(slope / px) * 5000.0)))
        if fast_now > slow_now and slope >= 0.0:
            return "bullish", strength
        if fast_now < slow_now and slope <= 0.0:
            return "bearish", strength
        return "neutral", min(strength, 25)

    def _timeframe_rule(self, timeframe: str) -> str:
        tf = str(timeframe or "").strip().upper()
        try:
            if tf.startswith("M") and len(tf) > 1:
                return f"{max(1, int(tf[1:]))}min"
            if tf.startswith("H") and len(tf) > 1:
                return f"{max(1, int(tf[1:]))}h"
        except (ValueError, TypeError):
            pass
        if tf in {"D", "D1"}:
            return "1D"
        # Invalid or unparseable timeframe falls back to execution TF.
        base_min = timeframe_to_minutes(self.config.get("timeframe"), 15)
        return f"{max(1, int(base_min))}min"

    def _scan_htf_fvgs_detailed(self, df: pd.DataFrame, atr: float) -> Dict[str, Any]:
        out: List[Dict[str, Any]] = []
        timeframes = [str(self.config.get("htf_timeframe", "H4")).upper()]
        secondary = str(self.config.get("secondary_htf_timeframe", "H1")).upper()
        if secondary and secondary not in timeframes:
            timeframes.append(secondary)

        current_price = float(df["close"].astype(float).iloc[-1])
        max_age = int(self.config.get("fvg_max_age_bars", 200))
        max_fill = float(self.config.get("fvg_max_fill_ratio", 0.70))
        proximity_atr = float(self.config.get("fvg_proximity_atr", 2.0))
        min_gap_atr = float(self.config.get("htf_fvg_min_gap_atr", 0.15))
        scan_detail: List[Dict[str, Any]] = []
        total_raw_zones = 0

        for tf in timeframes:
            htf_df = resample_ohlcv(df, self._timeframe_rule(tf))
            if htf_df.empty:
                scan_detail.append(
                    {
                        "timeframe": tf,
                        "bars_scanned": 0,
                        "raw_zones_count": 0,
                        "candidate_count": 0,
                        "rejected_age_count": 0,
                        "rejected_fill_count": 0,
                        "rejected_distance_count": 0,
                    }
                )
                continue
            lookback = max(30, int(self.config.get("htf_fvg_lookback_bars", 100)))
            htf_df = htf_df.tail(lookback)
            if len(htf_df) < 3:
                scan_detail.append(
                    {
                        "timeframe": tf,
                        "bars_scanned": int(len(htf_df)),
                        "raw_zones_count": 0,
                        "candidate_count": 0,
                        "rejected_age_count": 0,
                        "rejected_fill_count": 0,
                        "rejected_distance_count": 0,
                    }
                )
                continue
            htf_atr = atr_last(htf_df, 14) or atr or 1.0
            zones = detect_fvg_zones(
                htf_df,
                {
                    "symbol": self.config.get("symbol"),
                    "strictness": 3,
                    "show_filled": False,
                    "trend_filter_enabled": False,
                    "min_gap": float(htf_atr) * min_gap_atr,
                },
            )
            total_raw_zones += len(zones)
            latest_idx = len(htf_df) - 1
            tf_detail = {
                "timeframe": tf,
                "bars_scanned": int(len(htf_df)),
                "raw_zones_count": int(len(zones)),
                "candidate_count": 0,
                "rejected_age_count": 0,
                "rejected_fill_count": 0,
                "rejected_distance_count": 0,
                "htf_atr": float(round(float(htf_atr), 6)),
                "proximity_limit": float(round(float(htf_atr) * proximity_atr, 6)),
                "max_fill_ratio": float(round(max_fill, 6)),
                "max_age_bars": int(max_age),
            }
            for zone in zones:
                original_gap = float(zone.get("original_gap_size") or zone.get("gap_size") or 0.0)
                current_gap = float(zone.get("current_gap_size") or zone.get("gap_size") or 0.0)
                fill_ratio = 1.0 - (current_gap / original_gap) if original_gap > 0.0 else 1.0
                age_bars = max(0, latest_idx - int(zone.get("bar_index") or 0))
                distance_from_price = min(
                    abs(current_price - float(zone.get("top") or 0.0)),
                    abs(current_price - float(zone.get("bottom") or 0.0)),
                )
                if age_bars > max_age:
                    tf_detail["rejected_age_count"] = int(tf_detail["rejected_age_count"]) + 1
                    continue
                if fill_ratio > max_fill:
                    tf_detail["rejected_fill_count"] = int(tf_detail["rejected_fill_count"]) + 1
                    continue
                # HTF proximity must be scaled by HTF volatility, not LTF ATR.
                if distance_from_price > float(htf_atr) * proximity_atr:
                    tf_detail["rejected_distance_count"] = int(tf_detail["rejected_distance_count"]) + 1
                    continue
                item = dict(zone)
                item["timeframe"] = tf
                item["age_bars"] = age_bars
                item["distance_from_price"] = float(distance_from_price)
                item["fill_ratio"] = float(max(0.0, min(1.0, fill_ratio)))
                item["quality_score"], item["quality_label"] = self._score_fvg(item, htf_atr)
                out.append(item)
                tf_detail["candidate_count"] = int(tf_detail["candidate_count"]) + 1
            scan_detail.append(tf_detail)

        out.sort(
            key=lambda z: (
                -float(z.get("quality_score") or 0.0),
                float(z.get("distance_from_price") or 10**9),
                int(z.get("age_bars") or 10**9),
            )
        )
        return {
            "candidates": out,
            "scan_detail": scan_detail,
            "raw_zones_count": int(total_raw_zones),
            "candidate_count": int(len(out)),
        }

    def _scan_htf_fvgs(self, df: pd.DataFrame, atr: float) -> List[Dict[str, Any]]:
        detail = self._scan_htf_fvgs_detailed(df, atr)
        return detail.get("candidates") if isinstance(detail.get("candidates"), list) else []

    def _scan_liquidity_map(self, df: pd.DataFrame) -> List[Dict[str, Any]]:
        return detect_liquidity_zones(
            df,
            {
                "symbol": self.config.get("symbol"),
                "strictness": int(self.config.get("liquidity_strictness", 3)),
                "pivot_span": int(self.config.get("ltf_pool_pivot_span", 3)),
                "min_touches": int(self.config.get("min_pool_touches", 2)),
                "lookback_bars": int(self.config.get("ltf_pool_lookback_bars", 420)),
                "sweep_lookahead": int(self.config.get("sweep_lookahead_bars", 120)),
                "tolerance_atr_mult": float(self.config.get("pool_tolerance_atr_mult", 0.12)),
            },
        )

    def _score_fvg(self, zone: Dict[str, Any], atr: float) -> Tuple[float, str]:
        remain_ratio = 1.0 - float(zone.get("fill_ratio") or 0.0)
        gap_size = float(zone.get("current_gap_size") or zone.get("gap_size") or 0.0)
        gap_atr_ratio = gap_size / max(float(atr), 1e-9)
        distance_ratio = float(zone.get("distance_from_price") or 0.0) / max(float(atr), 1e-9)
        mitigations = int(zone.get("mitigations") or 0)
        age_bars = int(zone.get("age_bars") or 0)

        score = 0.0
        score += remain_ratio * 40.0
        score += min(1.0, gap_atr_ratio / max(float(self.config.get("htf_fvg_min_gap_atr", 0.15)), 1e-9)) * 25.0
        score += max(0.0, 1.0 - min(1.0, distance_ratio / max(float(self.config.get("fvg_proximity_atr", 2.0)), 1e-9))) * 20.0
        score += max(0.0, 1.0 - min(1.0, mitigations / 3.0)) * 10.0
        score += max(0.0, 1.0 - min(1.0, age_bars / max(int(self.config.get("fvg_max_age_bars", 200)), 1))) * 5.0

        if score >= 70.0:
            label = "strong"
        elif score >= 50.0:
            label = "moderate"
        else:
            label = "weak"
        return round(score, 2), label

    def _select_active_fvg(
        self,
        fvgs: List[Dict[str, Any]],
        current_price: float,
        atr: float,
        bias: str,
        bias_strength: int,
    ) -> Optional[Dict[str, Any]]:
        # Do not pre-filter by bias here.
        # A1 bias alignment is intentionally enforced after sweep selection so
        # strong sweep rejection can override counter-trend blocks.
        if not fvgs:
            return None
        return fvgs[0]

    def _bar_retraces_into_fvg(self, bar: pd.Series, fvg: Dict[str, Any], bullish: bool) -> bool:
        top = float(fvg.get("top") or 0.0)
        bottom = float(fvg.get("bottom") or 0.0)
        high = float(bar.get("high") or 0.0)
        low = float(bar.get("low") or 0.0)
        close = float(bar.get("close") or 0.0)
        # Configurable reclaim depth — 0.30 means close must be in the inner
        # 70% of the FVG.  The old 0.50 midpoint requirement was too strict
        # for many HTF zones and rejected valid reclaim entries.
        depth = float(self.config.get("fvg_reclaim_depth", 0.30))
        gap = top - bottom
        overlaps = low <= top and high >= bottom
        if not overlaps:
            return False
        if bullish:
            return close >= bottom + gap * depth
        return close <= top - gap * depth

    def _compute_stop_loss(self, fvg: Dict[str, Any], sweep: Dict[str, Any], atr: float, bullish: bool) -> float:
        buffer = float(atr) * float(self.config.get("sl_buffer_atr", 0.25))
        if bullish:
            stop_anchor = min(float(fvg.get("bottom") or 0.0), float(sweep.get("swept_price") or 0.0))
            return float(stop_anchor - buffer)
        stop_anchor = max(float(fvg.get("top") or 0.0), float(sweep.get("swept_price") or 0.0))
        return float(stop_anchor + buffer)

    def _compute_take_profit(
        self,
        *,
        entry_estimate: float,
        fvg: Dict[str, Any],
        liquidity_zones: List[Dict[str, Any]],
        risk: float,
        bullish: bool,
    ) -> Tuple[Optional[float], str]:
        min_rr = float(self.config.get("min_rr_ratio", 2.5))
        max_rr_cap = float(self.config.get("max_rr_cap", 8.0))
        base_target = float(fvg.get("top") if bullish else (fvg.get("bottom") or 0.0))
        liq_target = self._next_liquidity_target(liquidity_zones, entry_estimate, bullish)

        rr_floor_long = entry_estimate + (risk * min_rr)
        rr_floor_short = entry_estimate - (risk * min_rr)

        if bullish:
            # Prefer nearest structural target (FVG boundary or liquidity pool)
            # that sits above entry. Fall back to rr_floor if none exist.
            structural = [x for x in [base_target, liq_target] if x and x > entry_estimate]
            if structural:
                target = min(structural)  # nearest structural target above
                source = "liquidity" if liq_target is not None and abs(target - liq_target) < 1e-9 else "fvg"
            else:
                target = rr_floor_long
                source = "rr_floor"
            # Ensure minimum R:R floor is met
            if target < rr_floor_long:
                target = rr_floor_long
                source = "rr_floor"
            cap = entry_estimate + (risk * max_rr_cap)
            if target > cap:
                target = cap
            return float(target), source

        # Bearish: nearest structural target below entry
        structural = [x for x in [base_target, liq_target] if x and x < entry_estimate]
        if structural:
            target = max(structural)  # nearest structural target below
            source = "liquidity" if liq_target is not None and abs(target - liq_target) < 1e-9 else "fvg"
        else:
            target = rr_floor_short
            source = "rr_floor"
        # Ensure minimum R:R floor is met
        if target > rr_floor_short:
            target = rr_floor_short
            source = "rr_floor"
        cap = entry_estimate - (risk * max_rr_cap)
        if target < cap:
            target = cap
        return float(target), source

    def _next_liquidity_target(
        self,
        liquidity_zones: List[Dict[str, Any]],
        entry_price: float,
        bullish: bool,
    ) -> Optional[float]:
        # Only target unswept pools — swept levels already rejected price
        # once and act as resistance, not realistic TP targets.
        target_types = {"liquidity_pool_high"} if bullish else {"liquidity_pool_low"}
        candidates: List[float] = []
        for zone in liquidity_zones:
            ztype = str(zone.get("type") or "")
            if ztype not in target_types:
                continue
            level = float(zone.get("liquidity_level") or zone.get("pool_boundary") or zone.get("swept_price") or 0.0)
            if bullish and level > entry_price:
                candidates.append(level)
            if (not bullish) and level < entry_price:
                candidates.append(level)
        if not candidates:
            return None
        return min(candidates) if bullish else max(candidates)

    def _compute_confidence(
        self,
        *,
        fvg: Dict[str, Any],
        sweep: Dict[str, Any],
        bias: str,
        bias_strength: int,
        atr: float,
        day_context: Optional[DayContext] = None,
    ) -> float:
        score = 0.0
        score += min(100.0, float(fvg.get("quality_score") or 0.0)) * 0.45
        score += min(1.0, float(sweep.get("rejection_ratio") or 0.0)) * 35.0
        score += min(4.0, float(sweep.get("swept_pool_touches") or 0.0)) * 5.0
        if str(fvg.get("type") or "") == "bullish_fvg" and bias == "bullish":
            score += min(20.0, bias_strength * 0.2)
        elif str(fvg.get("type") or "") == "bearish_fvg" and bias == "bearish":
            score += min(20.0, bias_strength * 0.2)
        else:
            score += 5.0
        distance_ratio = float(fvg.get("distance_from_price") or 0.0) / max(float(atr), 1e-9)
        score -= min(15.0, distance_ratio * 5.0)

        # A3: Session quality — use canonical NY session windows so DST
        # and session boundaries stay consistent.
        sweep_time_unix = int(sweep.get("end_time_unix") or 0)
        if sweep_time_unix > 0:
            try:
                session_name = self._session_name_for_timestamp(datetime.fromtimestamp(sweep_time_unix, tz=UTC_TZ))
                if session_name in {"london", "new_york"}:
                    score += 5.0
                elif session_name == "asian":
                    score -= 5.0
            except Exception:
                pass

        if bool((day_context.levels or {}).get("news_high_impact", False)):
            score -= 12.0

        # G2: Daily structure cross-reference — if the FVG direction
        # contradicts the daily trend, reduce confidence.
        if day_context is not None:
            daily_trend = str((day_context.levels or {}).get("daily_trend") or "")
            fvg_type = str(fvg.get("type") or "")
            if daily_trend and daily_trend != "":
                if (fvg_type == "bullish_fvg" and daily_trend == "bearish") or \
                   (fvg_type == "bearish_fvg" and daily_trend == "bullish"):
                    score -= 8.0

        return round(max(1.0, min(100.0, score)), 2)

    def _to_ny_datetime(self, value: Any) -> Optional[datetime]:
        try:
            ts = pd.Timestamp(value)
            if ts.tzinfo is None:
                ts = ts.tz_localize(UTC_TZ)
            else:
                ts = ts.tz_convert(UTC_TZ)
            return ts.tz_convert(NY_TZ).to_pydatetime()
        except Exception:
            return None

    def _time_in_window(self, dt_obj: datetime, start, end) -> bool:
        now_t = dt_obj.timetz().replace(tzinfo=None)
        if end >= start:
            return bool(start <= now_t <= end)
        return bool(now_t >= start or now_t <= end)

    def _session_name_for_timestamp(self, value: Any) -> str:
        dt_ny = self._to_ny_datetime(value)
        if dt_ny is None:
            return ""
        if self._time_in_window(dt_ny, ASIAN_SESSION.start, ASIAN_SESSION.end):
            return "asian"
        if self._time_in_window(dt_ny, LONDON_SESSION.start, LONDON_SESSION.end):
            return "london"
        if self._time_in_window(dt_ny, ORB_SESSION.start, ORB_SESSION.end) or self._time_in_window(dt_ny, TRADING_SESSION.start, TRADING_SESSION.end):
            return "new_york"
        return "offhours"

    def _session_cycle_key(self, value: Any) -> str:
        dt_ny = self._to_ny_datetime(value)
        if dt_ny is None:
            return ""
        session_name = self._session_name_for_timestamp(dt_ny)
        cycle_date = dt_ny.date()
        if session_name == "asian" and dt_ny.timetz().replace(tzinfo=None) <= ASIAN_SESSION.end:
            cycle_date = (dt_ny - timedelta(days=1)).date()
        return f"{cycle_date.isoformat()}:{session_name}"

    def _refresh_sweep_cycle(self, value: Any) -> None:
        cycle_key = self._session_cycle_key(value)
        if not cycle_key:
            return
        if self._last_session_cycle != cycle_key:
            self._last_session_cycle = cycle_key
            self._used_sweep_keys.clear()

    def _make_sweep_key(self, fvg: Dict[str, Any], sweep: Dict[str, Any]) -> str:
        return "|".join(
            [
                str(fvg.get("timeframe") or ""),
                str(fvg.get("type") or ""),
                str(int(fvg.get("end_time_unix") or 0)),
                str(sweep.get("type") or ""),
                str(int(sweep.get("end_time_unix") or 0)),
                f"{float(sweep.get('swept_price') or 0.0):.6f}",
            ]
        )
