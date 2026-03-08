"""LLM-backed advice generation with provider-chain fallback."""

from __future__ import annotations

import json
import os
from pathlib import Path
from datetime import datetime, timezone
from typing import Any, Dict, List, Tuple

import httpx

from .policy_engine import is_action_allowed, normalize_mode
from .routing import route_advices_by_confidence


_ALLOWED_PROVIDERS = {"deterministic", "local_gptoss_http", "openai_compat", "claude"}


def _read_env_file_value(var_name: str) -> str:
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
                line = str(raw or "").strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                if str(k).strip() != str(var_name):
                    continue
                val = str(v).strip().strip('"').strip("'")
                if val:
                    return val
        except Exception:
            continue
    return ""


def _get_env_value(*names: str) -> str:
    for n in names:
        key = str(n or "").strip()
        if not key:
            continue
        v = str(os.getenv(key) or "").strip()
        if v:
            return v
        fv = str(_read_env_file_value(key) or "").strip()
        if fv:
            return fv
    return ""


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


def _extract_utc_hour(snapshot: Dict[str, Any]) -> int | None:
    latest = snapshot.get("latest_bar") if isinstance(snapshot.get("latest_bar"), dict) else {}
    ts = _safe_int(latest.get("time"), 0)
    if ts <= 0:
        return None
    if ts > 10_000_000_000:
        ts = int(ts / 1000)
    try:
        return int(datetime.fromtimestamp(int(ts), timezone.utc).hour)
    except Exception:
        return None


def _extract_json_object(text: str) -> Dict[str, Any] | None:
    raw = str(text or "").strip()
    if not raw:
        return None
    try:
        obj = json.loads(raw)
        if isinstance(obj, dict):
            return obj
    except Exception:
        pass

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

    lo = raw.find("{")
    if lo >= 0:
        depth = 0
        for i in range(lo, len(raw)):
            ch = raw[i]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    try:
                        obj = json.loads(raw[lo : i + 1])
                        if isinstance(obj, dict):
                            return obj
                    except Exception:
                        pass
                    break
    return None


def _normalize_provider(provider: str | None) -> str:
    p = str(provider or "deterministic").strip().lower()
    if p in {"anthropic", "claude_api"}:
        p = "claude"
    if p not in _ALLOWED_PROVIDERS:
        return "deterministic"
    return p


def _resolve_provider_chain(provider: str | None, config: Dict[str, Any]) -> List[str]:
    primary = _normalize_provider(provider)
    raw_chain = config.get("provider_chain") if isinstance(config.get("provider_chain"), list) else []
    chain: List[str] = []
    for p in [primary, *raw_chain, "deterministic"]:
        pn = _normalize_provider(p)
        if pn not in chain:
            chain.append(pn)
    return chain


def _schema_text() -> str:
    return (
        'Return JSON only: {"advices":[{'
        '"advice_type":"SUGGEST_ENTRY|SUGGEST_EXIT|SUGGEST_RISK_ADJUSTMENT|REVIEW_NOTE|AUTO_PAPER_ENTRY|AUTO_PAPER_EXIT|AUTO_TOOL_SCAN",'
        '"summary":"short actionable sentence",'
        '"confidence":0.0,'
        '"source_event_type":"EVENT_TYPE",'
        '"evidence_json":{"k":"v"},'
        '"action_json":{"action_type":"...","tool_id":"fvg","config":{},"direction":"BUY|SELL","stop_loss":0.0,"take_profit":0.0,"lot_size":0.01}'
        "}]}."
    )


def _knowledge_block(snapshot: Dict[str, Any], config: Dict[str, Any]) -> str:
    profile = str(config.get("coach_profile") or "beginner").strip().lower()
    style = str(config.get("coach_style") or "strict").strip().lower()
    tool_state = snapshot.get("tool_state") if isinstance(snapshot.get("tool_state"), dict) else {}
    fvg_on = bool(tool_state.get("fvg_enabled"))
    fvg_zones = int(tool_state.get("fvg_last_zone_count") or 0)
    fvg_ctx = snapshot.get("fvg_context") if isinstance(snapshot.get("fvg_context"), dict) else {}
    near_bull = fvg_ctx.get("nearest_bullish") if isinstance(fvg_ctx.get("nearest_bullish"), dict) else {}
    near_bear = fvg_ctx.get("nearest_bearish") if isinstance(fvg_ctx.get("nearest_bearish"), dict) else {}
    bull_dist_pct = _safe_float(near_bull.get("distance_pct"), -1.0)
    bear_dist_pct = _safe_float(near_bear.get("distance_pct"), -1.0)
    bull_inside = bool(near_bull.get("inside")) if near_bull else False
    bear_inside = bool(near_bear.get("inside")) if near_bear else False
    auto_entry_conf = float(config.get("auto_paper_min_conf_entry") or 0.90)
    auto_exit_conf = float(config.get("auto_paper_min_conf_exit") or 0.80)
    auto_scan_conf = float(config.get("auto_tool_scan_min_conf") or 0.70)
    proximity_pct = float(config.get("fvg_entry_proximity_pct") or 0.20)
    session_gate = bool(config.get("fvg_entry_require_active_session", True))
    session_start = max(0, min(23, _safe_int(config.get("fvg_entry_session_utc_start"), 6)))
    session_end = max(0, min(23, _safe_int(config.get("fvg_entry_session_utc_end"), 23)))
    regime = str(snapshot.get("market_regime") or "").strip().lower()
    regimes = [str(x or "").strip().lower() for x in (config.get("fvg_entry_allowed_regimes") or []) if str(x or "").strip()]
    hour = _extract_utc_hour(snapshot)
    hour_txt = str(hour) if hour is not None else "unknown"
    fvg_cfg = tool_state.get("fvg_config") if isinstance(tool_state.get("fvg_config"), dict) else {}
    trend_filter_enabled = bool(fvg_cfg.get("trend_filter_enabled", True))
    trend_mode = str(fvg_cfg.get("trend_alignment_mode") or "prefer").strip().lower()
    trend_mult = _safe_int(fvg_cfg.get("trend_multiplier"), 3)
    trend_dir = str(fvg_ctx.get("trend_direction") or "").strip().lower()
    trend_tf = str(fvg_ctx.get("trend_timeframe") or "").strip()
    aligned_cnt = _safe_int(fvg_ctx.get("aligned_count"), 0)
    counter_cnt = _safe_int(fvg_ctx.get("countertrend_count"), 0)
    mitigated_cnt = _safe_int(fvg_ctx.get("mitigated_count"), 0)
    filled_cnt = _safe_int(fvg_ctx.get("filled_count"), 0)
    bull_gap_now = _safe_float(near_bull.get("current_gap_size"), -1.0)
    bear_gap_now = _safe_float(near_bear.get("current_gap_size"), -1.0)
    bull_gap_orig = _safe_float(near_bull.get("original_gap_size"), -1.0)
    bear_gap_orig = _safe_float(near_bear.get("original_gap_size"), -1.0)
    bull_mit = _safe_int(near_bull.get("mitigations"), 0)
    bear_mit = _safe_int(near_bear.get("mitigations"), 0)
    bull_align = bool(near_bull.get("trend_aligned")) if near_bull else False
    bear_align = bool(near_bear.get("trend_aligned")) if near_bear else False
    movement = fvg_ctx.get("movement_strength") if isinstance(fvg_ctx.get("movement_strength"), dict) else {}
    movement_score = _safe_float(movement.get("score"), -1.0)
    movement_state = str(movement.get("state") or "").strip().lower()
    gas_low = bool(movement.get("gas_low", False))
    min_movement_required = _safe_float(config.get("fvg_entry_min_movement_strength"), 35.0)
    return (
        "Trading doctrine:\n"
        "1) Never predict. Only assess process quality and risk alignment.\n"
        "2) Respect invalidation first (stop-loss logic is mandatory).\n"
        "3) No averaging down, no revenge entries, no risk expansion after entry.\n"
        "4) Prefer checklist language: setup -> risk -> execution -> review.\n"
        f"5) Coach profile={profile}, style={style}.\n"
        f"6) Tool context: fvg_enabled={fvg_on}, fvg_zones={fvg_zones}.\n"
        "7) FVG definition: 3-candle imbalance using wick highs/lows only (not close).\n"
        "8) Mitigation rule: if later wick enters the gap but does not fully cross it, update the breached boundary and shrink current_gap_size.\n"
        "9) Cancellation rule: if later wick fully crosses the gap boundary, FVG is filled/cancelled (current_gap_size -> 0).\n"
        f"10) FVG proximity: bullish_dist_pct={bull_dist_pct:.3f}, bearish_dist_pct={bear_dist_pct:.3f}, bullish_inside={bull_inside}, bearish_inside={bear_inside}.\n"
        f"11) FVG gap state: bull_current={bull_gap_now:.5f}, bull_original={bull_gap_orig:.5f}, bull_mitigations={bull_mit}, bull_aligned={bull_align}; "
        f"bear_current={bear_gap_now:.5f}, bear_original={bear_gap_orig:.5f}, bear_mitigations={bear_mit}, bear_aligned={bear_align}.\n"
        f"12) Trend doctrine: trade FVG direction with trend; higher timeframe bias controls lower timeframe entries. "
        f"trend_filter_enabled={trend_filter_enabled}, trend_mode={trend_mode}, trend_multiplier={trend_mult}, trend_direction={trend_dir or 'unknown'}, trend_tf={trend_tf or 'unknown'}.\n"
        f"13) Trend coverage: aligned_zones={aligned_cnt}, countertrend_zones={counter_cnt}, mitigated_zones={mitigated_cnt}, filled_zones={filled_cnt}.\n"
        "14) If trend filter is enabled and trend is clear, prefer aligned zones; avoid counter-trend entry suggestions.\n"
        "15) In strict trend mode with unknown trend, prefer WATCH/REVIEW_NOTE or AUTO_TOOL_SCAN over entry.\n"
        f"16) Consider entry only when zone distance <= {proximity_pct:.3f}% or price is inside zone.\n"
        f"17) Movement strength (impulse gas): score={movement_score:.2f}, state={movement_state or 'unknown'}, gas_low={gas_low}, min_entry_strength={min_movement_required:.1f}.\n"
        "18) If movement strength is weak/exhausted or gas_low=true, avoid new entry suggestions and favor REVIEW/EXIT planning.\n"
        "19) If tool evidence is weak, issue WATCH/REVIEW_NOTE instead of forcing entry.\n"
        f"20) AUTO_PAPER guardrails: entry_conf>={auto_entry_conf:.2f}, exit_conf>={auto_exit_conf:.2f}.\n"
        f"21) AUTO_TOOL_SCAN threshold: scan_conf>={auto_scan_conf:.2f}. Prefer tool_id='fvg'.\n"
        "22) If proposing AUTO_PAPER_ENTRY/AUTO_PAPER_EXIT, include action_json with direction, stop_loss, take_profit, lot_size.\n"
        f"23) Session gate: enabled={session_gate}, window_utc={session_start}-{session_end}, current_hour={hour_txt}.\n"
        f"24) Regime gate: current_regime={regime or 'unknown'}, allowed={regimes if regimes else ['any']}.\n"
        "25) Keep responses short, numeric, and directly actionable.\n"
    )


def _build_prompt(
    snapshot: Dict[str, Any],
    events: List[Dict[str, Any]],
    mode: str,
    config: Dict[str, Any] | None = None,
) -> Tuple[str, str]:
    cfg = config if isinstance(config, dict) else {}
    system = (
        "You are a strict trading copilot. Use only provided numbers and events. "
        "No market prediction, no fabricated data. Output JSON only.\n\n"
        + _knowledge_block(snapshot=snapshot, config=cfg)
    )
    user_payload = {
        "now": datetime.now(timezone.utc).isoformat(),
        "mode": mode,
        "snapshot": snapshot,
        "events": events,
    }
    user = f"{_schema_text()}\n\nContext:\n{json.dumps(user_payload, ensure_ascii=True)}"
    return system, user


def _parse_llm_advices(
    obj: Dict[str, Any],
    events: List[Dict[str, Any]],
    mode: str,
) -> List[Dict[str, Any]]:
    out: List[Dict[str, Any]] = []
    by_event_priority = {
        str(e.get("event_type") or "").strip().upper(): int(e.get("priority") or 0)
        for e in events
    }
    arr = obj.get("advices") if isinstance(obj.get("advices"), list) else []
    for item in arr:
        if not isinstance(item, dict):
            continue
        advice_type = str(item.get("advice_type") or "REVIEW_NOTE").strip().upper()
        if not advice_type:
            advice_type = "REVIEW_NOTE"
        if not is_action_allowed(mode, advice_type) and advice_type != "REVIEW_NOTE":
            advice_type = "REVIEW_NOTE"
        source_event_type = str(item.get("source_event_type") or "").strip().upper()
        if not source_event_type and events:
            source_event_type = str(events[0].get("event_type") or "").strip().upper()
        conf = max(0.0, min(1.0, _safe_float(item.get("confidence"), 0.65)))
        evidence = item.get("evidence_json") if isinstance(item.get("evidence_json"), dict) else {}
        action = item.get("action_json") if isinstance(item.get("action_json"), dict) else {}
        out.append(
            {
                "advice_type": advice_type,
                "summary": str(item.get("summary") or "Review current conditions before acting."),
                "confidence": conf,
                "source_event_type": source_event_type,
                "source_event_priority": int(by_event_priority.get(source_event_type, 0)),
                "evidence_json": evidence,
                "action_json": action,
                "status": "NEW",
                "delivery": "ACTIONABLE",
            }
        )
    return out


def _call_local_gptoss(
    snapshot: Dict[str, Any],
    events: List[Dict[str, Any]],
    mode: str,
    model_label: str | None,
    config: Dict[str, Any],
) -> Dict[str, Any]:
    system, user = _build_prompt(snapshot=snapshot, events=events, mode=mode, config=config)
    url = str(config.get("local_gptoss_url") or os.getenv("WORKBENCH_COPILOT_GPTOSS_URL") or "http://127.0.0.1:8012").strip().rstrip("/") + "/chat"
    timeout_sec = max(10, _safe_int(config.get("llm_timeout_sec"), 45))
    with httpx.Client(timeout=float(timeout_sec)) as client:
        res = client.post(
            url,
            json={
                "system": system,
                "message": user,
                "temperature": 0.1,
                "max_tokens": 700,
                "model": str(model_label or "gpt-oss-20b"),
            },
        )
    if res.status_code != 200:
        raise RuntimeError(f"local_gptoss_http status={res.status_code}")
    body = res.json() if res.headers.get("content-type", "").startswith("application/json") else {}
    reply = str(body.get("reply") or "")
    parsed = _extract_json_object(reply)
    if not isinstance(parsed, dict):
        raise RuntimeError("local_gptoss_http returned non-JSON response")
    return parsed


def _call_openai_compat(
    snapshot: Dict[str, Any],
    events: List[Dict[str, Any]],
    mode: str,
    model_label: str | None,
    config: Dict[str, Any],
) -> Dict[str, Any]:
    key = str(config.get("openai_api_key") or _get_env_value("OPENAI_API_KEY") or "").strip()
    if not key:
        raise RuntimeError("openai_compat missing OPENAI_API_KEY")
    base = str(config.get("openai_base_url") or os.getenv("WORKBENCH_COPILOT_OPENAI_BASE_URL") or "https://api.openai.com/v1").strip().rstrip("/")
    url = f"{base}/chat/completions"
    timeout_sec = max(10, _safe_int(config.get("llm_timeout_sec"), 45))
    system, user = _build_prompt(snapshot=snapshot, events=events, mode=mode, config=config)
    with httpx.Client(timeout=float(timeout_sec)) as client:
        res = client.post(
            url,
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
            json={
                "model": str(model_label or "gpt-4.1-mini"),
                "temperature": 0.1,
                "max_tokens": 700,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
            },
        )
    if res.status_code != 200:
        raise RuntimeError(f"openai_compat status={res.status_code}")
    body = res.json() if res.headers.get("content-type", "").startswith("application/json") else {}
    content = str((((body.get("choices") or [{}])[0].get("message") or {}).get("content") or "")).strip()
    parsed = _extract_json_object(content)
    if not isinstance(parsed, dict):
        raise RuntimeError("openai_compat returned non-JSON response")
    return parsed


def _call_claude(
    snapshot: Dict[str, Any],
    events: List[Dict[str, Any]],
    mode: str,
    model_label: str | None,
    config: Dict[str, Any],
) -> Dict[str, Any]:
    key = str(
        config.get("anthropic_api_key")
        or _get_env_value("ANTHROPIC_API_KEY", "CLAUDE_API_KEY")
        or ""
    ).strip()
    if not key:
        raise RuntimeError("claude missing ANTHROPIC_API_KEY/CLAUDE_API_KEY")
    base = str(config.get("claude_base_url") or os.getenv("WORKBENCH_COPILOT_CLAUDE_BASE_URL") or "https://api.anthropic.com").strip().rstrip("/")
    url = base if base.endswith("/v1/messages") else f"{base}/v1/messages"
    version = str(config.get("anthropic_version") or os.getenv("WORKBENCH_COPILOT_ANTHROPIC_VERSION") or "2023-06-01").strip()
    timeout_sec = max(10, _safe_int(config.get("llm_timeout_sec"), 45))
    system, user = _build_prompt(snapshot=snapshot, events=events, mode=mode, config=config)
    preferred = str(model_label or "claude-haiku-4-5-20251001").strip()
    model_candidates = []
    for m in [preferred, "claude-3-5-haiku-latest", "claude-3-5-sonnet-latest"]:
        mm = str(m or "").strip()
        if mm and mm not in model_candidates:
            model_candidates.append(mm)
    with httpx.Client(timeout=float(timeout_sec)) as client:
        res = None
        last_err = ""
        for m in model_candidates:
            _res = client.post(
                url,
                headers={
                    "x-api-key": key,
                    "anthropic-version": version,
                    "content-type": "application/json",
                },
                json={
                    "model": m,
                    "max_tokens": 700,
                    "temperature": 0.1,
                    "system": system,
                    "messages": [{"role": "user", "content": user}],
                },
            )
            if _res.status_code == 200:
                res = _res
                break
            snippet = str((_res.text or "")[:220]).replace("\n", " ").replace("\r", " ")
            last_err = f"model={m} status={_res.status_code} body={snippet}"
            if _res.status_code not in {400, 404}:
                res = _res
                break
    if res is None:
        raise RuntimeError(f"claude failed: {last_err or 'no_response'}")
    if res.status_code != 200:
        snippet = str((res.text or "")[:220]).replace("\n", " ").replace("\r", " ")
        raise RuntimeError(f"claude status={res.status_code} body={snippet}")
    body = res.json() if res.headers.get("content-type", "").startswith("application/json") else {}
    parts = body.get("content") if isinstance(body, dict) else []
    text_chunks: List[str] = []
    if isinstance(parts, list):
        for part in parts:
            if not isinstance(part, dict):
                continue
            if str(part.get("type") or "") == "text":
                text_chunks.append(str(part.get("text") or ""))
    parsed = _extract_json_object("\n".join(text_chunks))
    if not isinstance(parsed, dict):
        raise RuntimeError("claude returned non-JSON response")
    return parsed


def generate_advices_with_provider_chain(
    snapshot: Dict[str, Any],
    events: List[Dict[str, Any]],
    mode: str | None,
    provider: str | None,
    model_label: str | None,
    config: Dict[str, Any] | None,
    deterministic_advices: List[Dict[str, Any]],
) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    """Try providers in order and return first valid advice list, fallback deterministic."""
    cfg = config or {}
    norm_mode = normalize_mode(mode)
    if norm_mode == "OBSERVE":
        return deterministic_advices, {
            "provider_used": "deterministic",
            "provider_attempts": [],
            "provider_fallback_reason": "observe_mode",
        }
    if not events:
        return deterministic_advices, {
            "provider_used": "deterministic",
            "provider_attempts": [],
            "provider_fallback_reason": "no_events",
        }
    allow_default = [
        "RISK_BREACH",
        "TRADE_OPENED",
        "TRADE_CLOSED",
        "REGIME_SHIFT",
        "PERIODIC_REVIEW",
        "SESSION_SNAPSHOT",
        "REPLAY_COMPLETED",
        "TOOL_SIGNAL_CHANGED",
        "MANUAL_OVERRIDE",
    ]
    allow_raw = cfg.get("llm_event_allowlist") if isinstance(cfg.get("llm_event_allowlist"), list) else allow_default
    allow = {str(x or "").strip().upper() for x in allow_raw if str(x or "").strip()}
    if allow:
        has_allowed = any(str(e.get("event_type") or "").strip().upper() in allow for e in events)
        if not has_allowed:
            return deterministic_advices, {
                "provider_used": "deterministic",
                "provider_attempts": [],
                "provider_fallback_reason": "no_llm_event_in_allowlist",
            }
    chain = _resolve_provider_chain(provider=provider, config=cfg)
    if chain and chain[0] == "deterministic":
        return deterministic_advices, {
            "provider_used": "deterministic",
            "provider_attempts": [],
            "provider_fallback_reason": "provider_forced_deterministic",
        }
    attempts: List[Dict[str, Any]] = []

    for p in chain:
        if p == "deterministic":
            return deterministic_advices, {
                "provider_used": "deterministic",
                "provider_attempts": attempts,
            }
        try:
            if p == "local_gptoss_http":
                parsed = _call_local_gptoss(snapshot, events, norm_mode, model_label, cfg)
            elif p == "openai_compat":
                parsed = _call_openai_compat(snapshot, events, norm_mode, model_label, cfg)
            elif p == "claude":
                parsed = _call_claude(snapshot, events, norm_mode, model_label, cfg)
            else:
                raise RuntimeError(f"unsupported provider={p}")

            advices = _parse_llm_advices(parsed, events=events, mode=norm_mode)
            advices = route_advices_by_confidence(advices=advices, config=cfg)
            if not advices:
                raise RuntimeError("provider returned no actionable/watch advice")
            return advices, {
                "provider_used": p,
                "provider_attempts": attempts,
                "provider_fallback_reason": None,
            }
        except Exception as exc:
            attempts.append(
                {
                    "provider": p,
                    "error_type": type(exc).__name__,
                    "error": str(exc)[:240],
                }
            )
            continue

    return deterministic_advices, {
        "provider_used": "deterministic",
        "provider_attempts": attempts,
        "provider_fallback_reason": "provider_error_fallback",
    }
