"""Workbench coaching evaluator (deterministic + optional LLM providers)."""

from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from typing import Any, Dict, List

import httpx


def _safe_float(v: Any, default: float = 0.0) -> float:
    try:
        if v is None:
            return float(default)
        return float(v)
    except Exception:
        return float(default)


def _safe_int(v: Any, default: int = 0) -> int:
    try:
        if v is None:
            return int(default)
        return int(v)
    except Exception:
        return int(default)


def _mean(values: List[float]) -> float:
    if not values:
        return 0.0
    return float(sum(values) / max(1, len(values)))


def _grade(score: float) -> str:
    s = float(score)
    if s >= 90:
        return "A"
    if s >= 80:
        return "B"
    if s >= 70:
        return "C"
    if s >= 60:
        return "D"
    return "F"


def _extract_json_object(text: str) -> Dict[str, Any] | None:
    raw = str(text or "").strip()
    if not raw:
        return None

    # direct parse
    try:
        obj = json.loads(raw)
        if isinstance(obj, dict):
            return obj
    except Exception:
        pass

    # fenced block parse
    if "```" in raw:
        for part in raw.split("```"):
            s = part.strip()
            if s.lower().startswith("json"):
                s = s[4:].strip()
            try:
                obj = json.loads(s)
                if isinstance(obj, dict):
                    return obj
            except Exception:
                continue

    # brace extraction
    lo = raw.find("{")
    hi = raw.rfind("}")
    if lo >= 0 and hi > lo:
        try:
            obj = json.loads(raw[lo : hi + 1])
            if isinstance(obj, dict):
                return obj
        except Exception:
            return None
    return None


class WorkbenchCoach:
    """Evaluates manual trading behavior in Workbench sessions."""

    def __init__(self) -> None:
        self.default_provider = str(
            os.getenv("WORKBENCH_COACH_PROVIDER", "deterministic")
        ).strip().lower()
        self.gptoss_url = str(
            os.getenv("WORKBENCH_COACH_GPTOSS_URL", "http://127.0.0.1:8012")
        ).strip()
        self.openai_base = str(
            os.getenv("WORKBENCH_COACH_OPENAI_BASE_URL", "https://api.openai.com/v1")
        ).strip()
        self.claude_base = str(
            os.getenv("WORKBENCH_COACH_CLAUDE_BASE_URL", "https://api.anthropic.com")
        ).strip()
        self.anthropic_version = str(
            os.getenv("WORKBENCH_COACH_ANTHROPIC_VERSION", "2023-06-01")
        ).strip()
        self.timeout_sec = max(15, int(os.getenv("WORKBENCH_COACH_TIMEOUT_SEC", "90")))

    def _coach_knowledge_block(self, context: Dict[str, Any]) -> str:
        session = context.get("session") if isinstance(context.get("session"), dict) else {}
        tool_state = context.get("tool_state") if isinstance(context.get("tool_state"), dict) else {}
        fvg_cfg = tool_state.get("fvg_config") if isinstance(tool_state.get("fvg_config"), dict) else {}
        mean_rev_cfg = tool_state.get("mean_rev_config") if isinstance(tool_state.get("mean_rev_config"), dict) else {}
        tools = tool_state.get("tools") if isinstance(tool_state.get("tools"), dict) else {}
        fvg_tool = tools.get("fvg") if isinstance(tools.get("fvg"), dict) else {}
        mean_rev_tool = tools.get("mean_rev") if isinstance(tools.get("mean_rev"), dict) else {}
        zones_sample = fvg_tool.get("zones_sample") if isinstance(fvg_tool.get("zones_sample"), list) else []
        mean_rev_sample = mean_rev_tool.get("zones_sample") if isinstance(mean_rev_tool.get("zones_sample"), list) else []
        movement = tool_state.get("fvg_movement_strength") if isinstance(tool_state.get("fvg_movement_strength"), dict) else {}
        mean_rev_state = tool_state.get("mean_rev_current_state") if isinstance(tool_state.get("mean_rev_current_state"), dict) else {}

        trend_filter = bool(fvg_cfg.get("trend_filter_enabled", True))
        trend_mode = str(fvg_cfg.get("trend_alignment_mode") or "prefer").strip().lower()
        trend_mult = max(2, min(12, _safe_int(fvg_cfg.get("trend_multiplier"), 3)))
        strictness = max(1, min(5, _safe_int(fvg_cfg.get("strictness"), 3)))
        show_filled = bool(fvg_cfg.get("show_filled", False))
        mean_sma_period = max(5, _safe_int(mean_rev_cfg.get("sma_period"), 30))
        mean_dev = max(0.5, _safe_float(mean_rev_cfg.get("deviation"), 2.0))
        mean_strictness = max(1, min(5, _safe_int(mean_rev_cfg.get("strictness"), 3)))
        mean_show_exit = bool(mean_rev_cfg.get("show_exit_signals", True))
        mean_state_name = str(mean_rev_state.get("state") or "unknown")
        mean_z = _safe_float(mean_rev_state.get("z_score"), 0.0)
        aligned = int(sum(1 for z in zones_sample if isinstance(z, dict) and bool(z.get("trend_aligned", False))))
        counter = int(sum(1 for z in zones_sample if isinstance(z, dict) and ("trend_aligned" in z) and (not bool(z.get("trend_aligned", False)))))
        mitigated = int(sum(1 for z in zones_sample if isinstance(z, dict) and _safe_int(z.get("mitigations"), 0) > 0))
        filled = int(sum(1 for z in zones_sample if isinstance(z, dict) and bool(z.get("filled", False))))
        mean_buy = int(sum(1 for z in mean_rev_sample if isinstance(z, dict) and str(z.get("type") or "") == "buy_zone"))
        mean_sell = int(sum(1 for z in mean_rev_sample if isinstance(z, dict) and str(z.get("type") or "") == "sell_zone"))
        mean_cross = int(sum(1 for z in mean_rev_sample if isinstance(z, dict) and str(z.get("type") or "") == "mean_cross"))

        return (
            "Workbench FVG doctrine:\n"
            "1) FVG detection uses wick highs/lows only (not close).\n"
            "2) Bullish FVG: candle3.low > candle1.high. Bearish FVG: candle1.low > candle3.high.\n"
            "3) Mitigation rule: if a later wick enters gap without full cross, update breached boundary and shrink current gap.\n"
            "4) Cancellation rule: if wick fully crosses the far boundary, FVG is filled/cancelled.\n"
            "5) Always keep both original_gap_size and current_gap_size in analysis; current gap drives execution quality.\n"
            "6) Trend doctrine: prefer/chase FVG direction aligned with higher-timeframe trend bias.\n"
            f"7) Current setup: symbol={session.get('symbol')}, timeframe={session.get('timeframe')}, strictness={strictness}, "
            f"trend_filter_enabled={trend_filter}, trend_mode={trend_mode}, trend_multiplier={trend_mult}, show_filled={show_filled}.\n"
            f"8) Zone sample stats: sample_count={len(zones_sample)}, aligned={aligned}, countertrend={counter}, mitigated={mitigated}, filled={filled}.\n"
            f"9) Movement strength: score={_safe_float(movement.get('score'), -1.0):.2f}, state={str(movement.get('state') or 'unknown')}, gas_low={bool(movement.get('gas_low', False))}.\n"
            "10) If trend is unclear and trend mode is strict, recommend wait/review rather than forcing entries.\n"
            "11) Never advise entries that violate trend-alignment policy defined by current tool configuration.\n"
            "Workbench Mean-Reversion doctrine:\n"
            f"12) Mean-rev setup: sma_period={mean_sma_period}, deviation={mean_dev:.2f}, strictness={mean_strictness}, show_exit_signals={mean_show_exit}.\n"
            f"13) Current mean-rev state: state={mean_state_name}, z_score={mean_z:.3f}, sample_buy={mean_buy}, sample_sell={mean_sell}, sample_mean_cross={mean_cross}.\n"
            "14) If z>=+2, price is overextended up (avoid chasing new longs). If z<=-2, overextended down (avoid chasing new shorts).\n"
            "15) Mean-cross markers imply flatten/review context, not immediate continuation entries.\n"
        )

    def evaluate(
        self,
        context: Dict[str, Any],
        provider: str = "deterministic",
        model_label: str | None = None,
        llm_url: str | None = None,
        api_key: str | None = None,
        timeout_sec: int | None = None,
    ) -> Dict[str, Any]:
        provider_norm = str(provider or self.default_provider).strip().lower()
        if provider_norm in ("anthropic", "claude_api", "claude"):
            provider_norm = "claude"
        timeout = int(timeout_sec or self.timeout_sec)

        baseline = self._deterministic_report(context)
        baseline["provider"] = provider_norm
        baseline["llm_used"] = False
        baseline["model"] = model_label or "deterministic"
        baseline["warnings"] = []

        if provider_norm == "deterministic":
            return baseline

        if provider_norm == "local_gptoss_http":
            try:
                out = self._evaluate_local_gptoss(
                    context=context,
                    model_label=model_label or "gpt-oss-20b",
                    llm_url=llm_url or self.gptoss_url,
                    timeout_sec=timeout,
                )
                return out
            except Exception as exc:
                baseline["warnings"].append(
                    f"GPT-OSS unavailable, deterministic fallback used: {type(exc).__name__}: {str(exc)[:180]}"
                )
                baseline["model"] = f"FALLBACK_deterministic (attempted: {model_label or 'gpt-oss-20b'})"
                return baseline

        if provider_norm == "openai_compat":
            try:
                out = self._evaluate_openai_compat(
                    context=context,
                    model_label=model_label or "gpt-4.1-mini",
                    llm_url=llm_url or self.openai_base,
                    api_key=api_key,
                    timeout_sec=timeout,
                )
                return out
            except Exception as exc:
                baseline["warnings"].append(
                    f"openai_compat unavailable, deterministic fallback used: {type(exc).__name__}: {str(exc)[:180]}"
                )
                baseline["model"] = f"FALLBACK_deterministic (attempted: {model_label or 'gpt-4.1-mini'})"
                return baseline

        if provider_norm == "claude":
            try:
                out = self._evaluate_claude(
                    context=context,
                    model_label=model_label or "claude-3-5-sonnet-latest",
                    llm_url=llm_url or self.claude_base,
                    api_key=api_key,
                    timeout_sec=timeout,
                )
                return out
            except Exception as exc:
                baseline["warnings"].append(
                    f"claude unavailable, deterministic fallback used: {type(exc).__name__}: {str(exc)[:180]}"
                )
                baseline["model"] = f"FALLBACK_deterministic (attempted: {model_label or 'claude-3-5-sonnet-latest'})"
                return baseline

        baseline["warnings"].append(f"Unknown provider '{provider_norm}', deterministic fallback used.")
        baseline["model"] = "deterministic"
        return baseline

    def _deterministic_report(self, context: Dict[str, Any]) -> Dict[str, Any]:
        session = context.get("session") or {}
        metrics = context.get("metrics") or {}
        tool = context.get("tool_state") or {}

        total = int(metrics.get("total_trades") or 0)
        closed = int(metrics.get("closed_trades") or 0)
        wins = int(metrics.get("wins") or 0)
        losses = int(metrics.get("losses") or 0)
        win_rate = _safe_float(metrics.get("win_rate"), 0.0)
        avg_r = _safe_float(metrics.get("avg_r_multiple"), 0.0)
        rr_defined_ratio = _safe_float(metrics.get("rr_defined_ratio"), 0.0)
        tp_defined_ratio = _safe_float(metrics.get("tp_defined_ratio"), 0.0)
        bars_seen = int(session.get("current_bar") or 0)
        bars_total = int(session.get("total_bars") or 0)
        last_trade_direction = str(metrics.get("last_trade_direction") or "").strip().upper()

        fvg_scan_count = int(tool.get("fvg_scan_count") or 0)
        fvg_last_zone_count = int(tool.get("fvg_last_zone_count") or 0)
        mean_rev_scan_count = int(tool.get("mean_rev_scan_count") or 0)
        mean_rev_last_zone_count = int(tool.get("mean_rev_last_zone_count") or 0)
        active_tools = tool.get("active_tools") or []
        fvg_cfg = tool.get("fvg_config") if isinstance(tool.get("fvg_config"), dict) else {}
        mean_rev_cfg = tool.get("mean_rev_config") if isinstance(tool.get("mean_rev_config"), dict) else {}
        trend_filter_enabled = bool(fvg_cfg.get("trend_filter_enabled", True))
        trend_mode = str(fvg_cfg.get("trend_alignment_mode") or "prefer").strip().lower()
        trend_multiplier = max(2, min(12, _safe_int(fvg_cfg.get("trend_multiplier"), 3)))
        strictness = max(1, min(5, _safe_int(fvg_cfg.get("strictness"), 3)))
        mean_rev_strictness = max(1, min(5, _safe_int(mean_rev_cfg.get("strictness"), 3)))
        mean_rev_sma_period = max(5, _safe_int(mean_rev_cfg.get("sma_period"), 30))
        mean_rev_deviation = max(0.5, _safe_float(mean_rev_cfg.get("deviation"), 2.0))
        tools_full = tool.get("tools") if isinstance(tool.get("tools"), dict) else {}
        fvg_tool = tools_full.get("fvg") if isinstance(tools_full.get("fvg"), dict) else {}
        mean_rev_tool = tools_full.get("mean_rev") if isinstance(tools_full.get("mean_rev"), dict) else {}
        zones_sample = fvg_tool.get("zones_sample") if isinstance(fvg_tool.get("zones_sample"), list) else []
        mean_rev_sample = mean_rev_tool.get("zones_sample") if isinstance(mean_rev_tool.get("zones_sample"), list) else []
        movement = tool.get("fvg_movement_strength") if isinstance(tool.get("fvg_movement_strength"), dict) else {}
        mean_rev_state = tool.get("mean_rev_current_state") if isinstance(tool.get("mean_rev_current_state"), dict) else {}
        movement_score = max(0.0, min(100.0, _safe_float(movement.get("score"), 50.0)))
        movement_state = str(movement.get("state") or "").strip().lower()
        gas_low = bool(movement.get("gas_low", False))
        mean_rev_state_name = str(mean_rev_state.get("state") or "unknown")
        mean_rev_zscore = _safe_float(mean_rev_state.get("z_score"), 0.0)
        mean_rev_buy_count = int(sum(1 for z in mean_rev_sample if isinstance(z, dict) and str(z.get("type") or "") == "buy_zone"))
        mean_rev_sell_count = int(sum(1 for z in mean_rev_sample if isinstance(z, dict) and str(z.get("type") or "") == "sell_zone"))
        mean_rev_cross_count = int(sum(1 for z in mean_rev_sample if isinstance(z, dict) and str(z.get("type") or "") == "mean_cross"))
        aligned_count = int(sum(1 for z in zones_sample if isinstance(z, dict) and bool(z.get("trend_aligned", False))))
        countertrend_count = int(sum(1 for z in zones_sample if isinstance(z, dict) and ("trend_aligned" in z) and (not bool(z.get("trend_aligned", False)))))
        mitigation_count = int(sum(1 for z in zones_sample if isinstance(z, dict) and _safe_int(z.get("mitigations"), 0) > 0))
        gap_state_available = int(
            sum(
                1
                for z in zones_sample
                if isinstance(z, dict)
                and (z.get("current_gap_size") is not None or z.get("original_gap_size") is not None)
            )
        )

        discipline = 100.0
        risk = 100.0
        execution = 100.0
        tool_usage = 100.0
        strengths: List[str] = []
        issues: List[str] = []
        actions: List[str] = []

        if bars_seen > 0 and total == 0:
            discipline -= 20.0
            issues.append("No trades executed yet; decision process cannot be measured.")
            actions.append("Take one controlled paper trade with predefined SL/TP to establish baseline.")

        if total > max(10, int(max(1, bars_seen) / 35)):
            discipline -= 20.0
            issues.append("Trade frequency looks high relative to replay progress (possible overtrading).")
            actions.append("Reduce entries; require explicit setup checklist before each trade.")
        else:
            strengths.append("Trade frequency appears controlled for current replay progress.")

        if rr_defined_ratio < 0.95:
            risk -= 35.0
            issues.append("Some trades are missing risk boundaries (SL/TP coherence issue).")
            actions.append("Do not place entries until both stop-loss and take-profit are set.")
        else:
            strengths.append("Risk boundaries are consistently defined on entries.")

        if tp_defined_ratio < 0.60:
            risk -= 15.0
            issues.append("Take-profit is missing on many trades.")
            actions.append("Define a target plan (TP or explicit manual exit rule) before entry.")

        if closed >= 3:
            if avg_r >= 1.0:
                strengths.append(f"Average R-multiple is healthy ({avg_r:.2f}R).")
            else:
                execution -= 20.0
                issues.append(f"Average R-multiple is low ({avg_r:.2f}R).")
                actions.append("Improve entry quality or widen target distance to reach >=1R expectancy.")

            if win_rate >= 55:
                strengths.append(f"Win rate is stable at {win_rate:.1f}%.")
            elif win_rate < 40:
                execution -= 20.0
                issues.append(f"Win rate is weak ({win_rate:.1f}%).")
                actions.append("Tighten setup quality filters and avoid low-conviction entries.")
        else:
            execution -= 10.0
            issues.append("Too few closed trades for statistically reliable execution assessment.")
            actions.append("Collect at least 5 closed samples before trusting performance trends.")

        if fvg_scan_count <= 0:
            tool_usage -= 30.0
            issues.append("FVG tool was not used; tool-driven context missing.")
            actions.append("Run FVG scan before entries and mark whether setup interacts with zone.")
        else:
            strengths.append(f"FVG tool used {fvg_scan_count} time(s).")
            if fvg_last_zone_count > 0:
                strengths.append(f"Latest FVG scan found {fvg_last_zone_count} zone(s).")
            else:
                actions.append("Latest FVG scan had no zones; avoid forcing FVG-based trades.")

            if trend_filter_enabled:
                strengths.append(f"Trend alignment filter is enabled (mode={trend_mode}, multiplier={trend_multiplier}).")
            else:
                tool_usage -= 18.0
                issues.append("Trend-alignment filter is disabled; counter-trend FVG chasing risk is higher.")
                actions.append("Enable trend filter and use HTF multiplier (e.g., M5->M15) to keep FVG direction aligned.")

            if strictness in (1, 2):
                actions.append("Current FVG strictness is loose; verify low-quality gaps are not being over-traded.")
            elif strictness >= 4:
                strengths.append("FVG strictness is conservative, helping filter low-quality imbalances.")

            if zones_sample:
                if countertrend_count > 0 and trend_filter_enabled:
                    tool_usage -= 8.0
                    issues.append("Detected counter-trend zones in sample while trend filter is enabled; review filter behavior.")
                if aligned_count > 0:
                    strengths.append(f"Sample zones include {aligned_count} trend-aligned FVG(s).")
                if gap_state_available <= 0:
                    tool_usage -= 8.0
                    issues.append("Gap-state telemetry is incomplete (current/original gap missing).")
                    actions.append("Validate FVG scanner telemetry so coach can track mitigation shrink and fill events.")
                if mitigation_count > 0:
                    strengths.append(f"Mitigation-aware tracking active ({mitigation_count} mitigated zone sample(s)).")
                else:
                    actions.append("Review mitigation updates: boundary should move when wick enters but does not fully fill the gap.")

            if movement_state:
                if gas_low or movement_score < 35.0:
                    execution -= 12.0
                    issues.append(f"Impulse appears weak/exhausted (movement score {movement_score:.1f}/100, state={movement_state}).")
                    actions.append("When movement gas is low, reduce aggression and wait for refill/rebuild before new entries.")
                elif movement_score >= 70.0:
                    strengths.append(f"Impulse strength is healthy ({movement_score:.1f}/100, state={movement_state}).")

        if mean_rev_scan_count <= 0:
            tool_usage -= 12.0
            actions.append("Run Mean Reversion scan to quantify overextension before fade/flatten decisions.")
        else:
            strengths.append(f"Mean Reversion tool used {mean_rev_scan_count} time(s).")
            if mean_rev_last_zone_count > 0:
                strengths.append(f"Latest mean-reversion scan found {mean_rev_last_zone_count} signal zone(s).")
            if mean_rev_strictness in (1, 2):
                actions.append("Mean-reversion strictness is loose; verify noise around Bollinger edges is filtered.")
            elif mean_rev_strictness >= 4:
                strengths.append("Mean-reversion strictness is conservative and avoids weak overextension tags.")
            if mean_rev_cross_count > 0:
                strengths.append(f"Mean-cross flatten events detected ({mean_rev_cross_count}) for exit discipline.")

        if abs(mean_rev_zscore) >= 2.0 and last_trade_direction in {"BUY", "SELL"}:
            if mean_rev_zscore >= 2.0 and last_trade_direction == "BUY":
                execution -= 12.0
                issues.append("Recent trade direction was BUY while z-score was strongly overextended up (>= +2).")
                actions.append("When z-score is >= +2, avoid chasing longs; wait for mean-cross/normalization first.")
            elif mean_rev_zscore <= -2.0 and last_trade_direction == "SELL":
                execution -= 12.0
                issues.append("Recent trade direction was SELL while z-score was strongly overextended down (<= -2).")
                actions.append("When z-score is <= -2, avoid chasing shorts; wait for mean-cross/normalization first.")
            else:
                strengths.append(
                    f"Recent trade direction avoided overextension chase (z={mean_rev_zscore:.2f}, dir={last_trade_direction})."
                )

        if active_tools and len(active_tools) >= 1:
            strengths.append(f"Active tools: {', '.join([str(x) for x in active_tools])}.")

        discipline = max(0.0, min(100.0, discipline))
        risk = max(0.0, min(100.0, risk))
        execution = max(0.0, min(100.0, execution))
        tool_usage = max(0.0, min(100.0, tool_usage))
        overall = (discipline * 0.30) + (risk * 0.30) + (execution * 0.25) + (tool_usage * 0.15)

        if not strengths:
            strengths.append("Replay session is active and data feed is healthy.")
        if not issues:
            issues.append("No critical process violations detected.")
        if not actions:
            actions.append("Continue current process; re-evaluate after 3 additional closed trades.")

        return {
            "report_version": "workbench_coach_v1",
            "generated_at": datetime.now(timezone.utc).isoformat(),
            "scores": {
                "discipline": round(discipline, 1),
                "risk_management": round(risk, 1),
                "execution_quality": round(execution, 1),
                "tool_usage": round(tool_usage, 1),
                "overall": round(overall, 1),
                "grade": _grade(overall),
            },
            "summary": (
                f"{session.get('symbol', 'N/A')} {session.get('timeframe', '')} "
                f"| closed={closed}, win_rate={win_rate:.1f}%, avgR={avg_r:.2f}, "
                f"tools=fvg:{fvg_scan_count},mean_rev:{mean_rev_scan_count}, bars={bars_seen}/{bars_total}"
            ),
            "strengths": strengths[:8],
            "issues": issues[:8],
            "next_actions": actions[:8],
            "evidence": {
                "total_trades": total,
                "closed_trades": closed,
                "wins": wins,
                "losses": losses,
                "win_rate_pct": round(win_rate, 2),
                "avg_r_multiple": round(avg_r, 3),
                "rr_defined_ratio": round(rr_defined_ratio, 3),
                "tp_defined_ratio": round(tp_defined_ratio, 3),
                "fvg_scan_count": fvg_scan_count,
                "fvg_last_zone_count": fvg_last_zone_count,
                "fvg_trend_filter_enabled": trend_filter_enabled,
                "fvg_trend_alignment_mode": trend_mode,
                "fvg_trend_multiplier": trend_multiplier,
                "fvg_strictness": strictness,
                "fvg_sample_aligned_count": aligned_count,
                "fvg_sample_countertrend_count": countertrend_count,
                "fvg_sample_mitigated_count": mitigation_count,
                "fvg_sample_gap_state_available": gap_state_available,
                "fvg_movement_strength_score": movement_score,
                "fvg_movement_strength_state": movement_state,
                "fvg_movement_gas_low": gas_low,
                "mean_rev_scan_count": mean_rev_scan_count,
                "mean_rev_last_zone_count": mean_rev_last_zone_count,
                "mean_rev_sma_period": mean_rev_sma_period,
                "mean_rev_deviation": mean_rev_deviation,
                "mean_rev_strictness": mean_rev_strictness,
                "mean_rev_state": mean_rev_state_name,
                "mean_rev_z_score": mean_rev_zscore,
                "mean_rev_sample_buy_count": mean_rev_buy_count,
                "mean_rev_sample_sell_count": mean_rev_sell_count,
                "mean_rev_sample_cross_count": mean_rev_cross_count,
                "last_trade_direction": last_trade_direction,
            },
        }

    def _coach_schema_text(self) -> str:
        return (
            'Return ONLY valid JSON with keys: '
            '{"scores":{"discipline":0-100,"risk_management":0-100,"execution_quality":0-100,'
            '"tool_usage":0-100,"overall":0-100,"grade":"A|B|C|D|F"},'
            '"summary":"...",'
            '"strengths":["..."],'
            '"issues":["..."],'
            '"next_actions":["..."],'
            '"evidence":{"k":"v"}}'
        )

    def _evaluate_local_gptoss(
        self,
        context: Dict[str, Any],
        model_label: str,
        llm_url: str,
        timeout_sec: int,
    ) -> Dict[str, Any]:
        url = f"{str(llm_url).rstrip('/')}/chat"
        system = (
            "You are a strict trading process coach. "
            "Use only provided numeric evidence. No market prediction. "
            "Output JSON only.\n\n"
            + self._coach_knowledge_block(context)
        )
        message = (
            f"{self._coach_schema_text()}\n\n"
            f"Context:\n{json.dumps(context, ensure_ascii=True)}"
        )
        with httpx.Client(timeout=float(timeout_sec)) as client:
            resp = client.post(
                url,
                json={
                    "system": system,
                    "message": message,
                    "temperature": 0.1,
                    "max_tokens": 900,
                },
            )
        if resp.status_code != 200:
            raise ValueError(f"local_gptoss_http failed: HTTP {resp.status_code} - {resp.text[:240]}")
        body = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
        if not bool(body.get("ok")):
            raise ValueError(f"local_gptoss_http error: {body.get('error')}")
        reply = str(body.get("reply") or "").strip()
        parsed = _extract_json_object(reply)
        if not isinstance(parsed, dict):
            raise ValueError("local_gptoss_http returned non-JSON response")
        parsed["report_version"] = "workbench_coach_v1"
        parsed["generated_at"] = datetime.now(timezone.utc).isoformat()
        parsed["provider"] = "local_gptoss_http"
        parsed["llm_used"] = True
        parsed["model"] = model_label
        return parsed

    def _evaluate_openai_compat(
        self,
        context: Dict[str, Any],
        model_label: str,
        llm_url: str,
        api_key: str | None,
        timeout_sec: int,
    ) -> Dict[str, Any]:
        key = str(api_key or os.getenv("OPENAI_API_KEY") or "").strip()
        if not key:
            raise ValueError("openai_compat selected but API key is missing")
        base = str(llm_url).strip().rstrip("/")
        url = f"{base}/chat/completions"
        system = (
            "You are a strict trading process coach. "
            "Use only provided numeric evidence. No market prediction. Output JSON only.\n\n"
            + self._coach_knowledge_block(context)
        )
        user = f"{self._coach_schema_text()}\n\nContext:\n{json.dumps(context, ensure_ascii=True)}"
        with httpx.Client(timeout=float(timeout_sec)) as client:
            resp = client.post(
                url,
                headers={
                    "Authorization": f"Bearer {key}",
                    "Content-Type": "application/json",
                },
                json={
                    "model": model_label,
                    "temperature": 0.1,
                    "max_tokens": 900,
                    "messages": [
                        {"role": "system", "content": system},
                        {"role": "user", "content": user},
                    ],
                },
            )
        if resp.status_code != 200:
            raise ValueError(f"openai_compat failed: HTTP {resp.status_code} - {resp.text[:240]}")
        body = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
        content = str((((body.get("choices") or [{}])[0].get("message") or {}).get("content") or "")).strip()
        parsed = _extract_json_object(content)
        if not isinstance(parsed, dict):
            raise ValueError("openai_compat returned non-JSON content")
        parsed["report_version"] = "workbench_coach_v1"
        parsed["generated_at"] = datetime.now(timezone.utc).isoformat()
        parsed["provider"] = "openai_compat"
        parsed["llm_used"] = True
        parsed["model"] = model_label
        return parsed

    def _evaluate_claude(
        self,
        context: Dict[str, Any],
        model_label: str,
        llm_url: str,
        api_key: str | None,
        timeout_sec: int,
    ) -> Dict[str, Any]:
        key = str(
            api_key
            or os.getenv("ANTHROPIC_API_KEY")
            or os.getenv("CLAUDE_API_KEY")
            or ""
        ).strip()
        if not key:
            raise ValueError("claude selected but API key is missing")

        base = str(llm_url).strip().rstrip("/")
        if base.endswith("/v1/messages"):
            url = base
        else:
            url = f"{base}/v1/messages"

        system = (
            "You are a strict trading process coach. "
            "Use only provided numeric evidence. No market prediction. Output JSON only.\n\n"
            + self._coach_knowledge_block(context)
        )
        user = f"{self._coach_schema_text()}\n\nContext:\n{json.dumps(context, ensure_ascii=True)}"
        with httpx.Client(timeout=float(timeout_sec)) as client:
            resp = client.post(
                url,
                headers={
                    "x-api-key": key,
                    "anthropic-version": self.anthropic_version,
                    "Content-Type": "application/json",
                },
                json={
                    "model": model_label,
                    "max_tokens": 900,
                    "temperature": 0.1,
                    "system": system,
                    "messages": [
                        {"role": "user", "content": user},
                    ],
                },
            )
        if resp.status_code != 200:
            raise ValueError(f"claude failed: HTTP {resp.status_code} - {resp.text[:240]}")

        body = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
        content_items = body.get("content") if isinstance(body, dict) else []
        texts: List[str] = []
        if isinstance(content_items, list):
            for item in content_items:
                if not isinstance(item, dict):
                    continue
                if str(item.get("type") or "") == "text":
                    texts.append(str(item.get("text") or ""))
        content = "\n".join([t for t in texts if str(t).strip()]).strip()
        parsed = _extract_json_object(content)
        if not isinstance(parsed, dict):
            raise ValueError("claude returned non-JSON content")

        parsed["report_version"] = "workbench_coach_v1"
        parsed["generated_at"] = datetime.now(timezone.utc).isoformat()
        parsed["provider"] = "claude"
        parsed["llm_used"] = True
        parsed["model"] = model_label
        return parsed


def build_workbench_context(
    session: Dict[str, Any],
    trades: List[Dict[str, Any]],
    tool_state: Dict[str, Any] | None = None,
    notes: str | None = None,
) -> Dict[str, Any]:
    trade_rows = trades or []
    closed = [t for t in trade_rows if str(t.get("status") or "").lower() == "closed"]
    wins = [t for t in closed if _safe_float(t.get("pnl"), 0.0) > 0]
    losses = [t for t in closed if _safe_float(t.get("pnl"), 0.0) <= 0]
    rr_defined = [
        t for t in trade_rows
        if _safe_float(t.get("stop_loss"), 0.0) > 0 and _safe_float(t.get("entry_price"), 0.0) > 0
    ]
    tp_defined = [
        t for t in trade_rows
        if t.get("take_profit") is not None and _safe_float(t.get("take_profit"), 0.0) > 0
    ]
    avg_r = _mean([_safe_float(t.get("r_multiple"), 0.0) for t in closed])
    win_rate = (len(wins) / max(1, len(closed))) * 100.0 if closed else 0.0
    last_trade_direction = ""
    if trade_rows:
        last_trade_direction = str((trade_rows[-1] or {}).get("direction") or "").strip().upper()

    metrics = {
        "total_trades": len(trade_rows),
        "closed_trades": len(closed),
        "wins": len(wins),
        "losses": len(losses),
        "win_rate": round(win_rate, 4),
        "avg_r_multiple": round(avg_r, 6),
        "rr_defined_ratio": round(len(rr_defined) / max(1, len(trade_rows)), 6),
        "tp_defined_ratio": round(len(tp_defined) / max(1, len(trade_rows)), 6),
        "last_trade_direction": last_trade_direction,
    }

    out_session = {
        "session_id": session.get("id"),
        "strategy_id": session.get("strategy_id"),
        "symbol": session.get("symbol"),
        "timeframe": session.get("timeframe"),
        "current_bar": session.get("current_bar"),
        "total_bars": session.get("total_bars"),
        "current_balance": session.get("current_balance"),
        "initial_balance": session.get("initial_balance"),
        "total_pnl": session.get("total_pnl"),
    }

    tool = tool_state or {}
    fvg_cfg = tool.get("fvg_config") if isinstance(tool.get("fvg_config"), dict) else {}
    mean_rev_cfg = tool.get("mean_rev_config") if isinstance(tool.get("mean_rev_config"), dict) else {}
    tools = tool.get("tools") if isinstance(tool.get("tools"), dict) else {}
    fvg_tool = tools.get("fvg") if isinstance(tools.get("fvg"), dict) else {}
    mean_rev_tool = tools.get("mean_rev") if isinstance(tools.get("mean_rev"), dict) else {}
    zones_sample = fvg_tool.get("zones_sample") if isinstance(fvg_tool.get("zones_sample"), list) else []
    mean_rev_sample = mean_rev_tool.get("zones_sample") if isinstance(mean_rev_tool.get("zones_sample"), list) else []
    fvg_summary = {
        "enabled": bool(tool.get("fvg_enabled", False)),
        "scan_count": _safe_int(tool.get("fvg_scan_count"), 0),
        "last_zone_count": _safe_int(tool.get("fvg_last_zone_count"), 0),
        "strictness": max(1, min(5, _safe_int(fvg_cfg.get("strictness"), 3))),
        "trend_filter_enabled": bool(fvg_cfg.get("trend_filter_enabled", True)),
        "trend_alignment_mode": str(fvg_cfg.get("trend_alignment_mode") or "prefer").strip().lower(),
        "trend_multiplier": max(2, min(12, _safe_int(fvg_cfg.get("trend_multiplier"), 3))),
        "zones_sample_count": len(zones_sample),
        "aligned_sample_count": int(sum(1 for z in zones_sample if isinstance(z, dict) and bool(z.get("trend_aligned", False)))),
        "countertrend_sample_count": int(sum(1 for z in zones_sample if isinstance(z, dict) and ("trend_aligned" in z) and (not bool(z.get("trend_aligned", False))))),
        "mitigated_sample_count": int(sum(1 for z in zones_sample if isinstance(z, dict) and _safe_int(z.get("mitigations"), 0) > 0)),
        "movement_strength_score": _safe_float((tool.get("fvg_movement_strength") if isinstance(tool.get("fvg_movement_strength"), dict) else {}).get("score"), -1.0),
        "movement_strength_state": str((tool.get("fvg_movement_strength") if isinstance(tool.get("fvg_movement_strength"), dict) else {}).get("state") or ""),
        "movement_gas_low": bool((tool.get("fvg_movement_strength") if isinstance(tool.get("fvg_movement_strength"), dict) else {}).get("gas_low", False)),
    }
    mean_rev_state = tool.get("mean_rev_current_state") if isinstance(tool.get("mean_rev_current_state"), dict) else {}
    mean_rev_summary = {
        "enabled": bool(tool.get("mean_rev_enabled", False)),
        "scan_count": _safe_int(tool.get("mean_rev_scan_count"), 0),
        "last_zone_count": _safe_int(tool.get("mean_rev_last_zone_count"), 0),
        "strictness": max(1, min(5, _safe_int(mean_rev_cfg.get("strictness"), 3))),
        "sma_period": max(5, _safe_int(mean_rev_cfg.get("sma_period"), 30)),
        "deviation": max(0.5, _safe_float(mean_rev_cfg.get("deviation"), 2.0)),
        "show_exit_signals": bool(mean_rev_cfg.get("show_exit_signals", True)),
        "zones_sample_count": len(mean_rev_sample),
        "sample_buy_count": int(sum(1 for z in mean_rev_sample if isinstance(z, dict) and str(z.get("type") or "") == "buy_zone")),
        "sample_sell_count": int(sum(1 for z in mean_rev_sample if isinstance(z, dict) and str(z.get("type") or "") == "sell_zone")),
        "sample_cross_count": int(sum(1 for z in mean_rev_sample if isinstance(z, dict) and str(z.get("type") or "") == "mean_cross")),
        "current_state": mean_rev_state,
    }

    return {
        "session": out_session,
        "metrics": metrics,
        "tool_state": tool_state or {},
        "fvg_summary": fvg_summary,
        "mean_rev_summary": mean_rev_summary,
        "notes": str(notes or "").strip(),
    }
