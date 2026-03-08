"""Orchestration helpers for Workbench copilot iterations."""

from __future__ import annotations

import hashlib
import json
from typing import Any, Dict, List, Tuple

from .context_collector import build_snapshot
from .event_engine import detect_events
from .advice_engine import generate_advices
from .llm_advisor import generate_advices_with_provider_chain
from .policy_engine import normalize_mode


DEFAULT_COPILOT_CONFIG: Dict[str, Any] = {
    "risk_alert_usd": 250.0,
    "review_interval_bars": 50,
    "emit_bar_events": False,
    "global_cooldown_bars": 3,
    "dedupe_window_bars": 8,
    "max_advices_per_iteration": 2,
    "min_confidence_actionable": 0.75,
    "min_confidence_watch": 0.55,
    "provider_chain": ["deterministic"],
    "llm_timeout_sec": 45,
    "snapshot_retention": 5000,
    "async_llm_jobs": True,
    "job_min_interval_bars": 3,
    "auto_paper_min_conf_entry": 0.90,
    "auto_paper_min_conf_exit": 0.80,
    "auto_paper_rr_target": 1.8,
    "auto_paper_require_tp": True,
    "auto_paper_action_cooldown_bars": 2,
    "auto_paper_max_actions_per_iteration": 1,
    "auto_paper_session_drawdown_stop_usd": 300.0,
    "auto_paper_max_consecutive_losses": 3,
    "auto_paper_max_open_positions": 1,
    "auto_paper_manual_pause": False,
    "auto_paper_entry_reject_suppress_n": 3,
    "enable_auto_tool_scan": True,
    "auto_tool_scan_min_conf": 0.70,
    "auto_tool_scan_cooldown_bars": 5,
    "fvg_entry_proximity_pct": 0.20,
    "fvg_entry_require_active_session": True,
    "fvg_entry_session_utc_start": 6,
    "fvg_entry_session_utc_end": 23,
    "fvg_entry_allowed_regimes": [],
    "fvg_entry_min_movement_strength": 35.0,
    "coach_profile": "beginner",
    "coach_style": "strict",
    "watchdog_mode": "deterministic",
    "watchdog_interval_sec": 30,
    "watchdog_llm_min_interval_sec": 180,
    "watchdog_model_label": "",
    "watchdog_llm_url": "",
    "watchdog_trigger_requires_approval": False,
    "guardrail_enabled": True,
    "guardrail_session_filter_enabled": False,
    "guardrail_news_filter_enabled": False,
    "guardrail_news_lookback_min": 120,
    "market_news_provider": "polygon",
    "market_news_llm_summary_enabled": False,
    "market_news_summary_model": "claude-haiku-4-5-20251001",
    "market_news_llm_timeout_sec": 8,
    "market_news_ibkr_host": "127.0.0.1",
    "market_news_ibkr_port": 7497,
    "event_cooldowns": {
        "RISK_BREACH": 1,
        "TRADE_OPENED": 3,
        "TRADE_CLOSED": 3,
        "REGIME_SHIFT": 10,
        "PERIODIC_REVIEW": 40,
        "REPLAY_COMPLETED": 999999,
    },
}


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


def normalize_copilot_mode(mode: str | None) -> str:
    return normalize_mode(mode)


def normalize_copilot_config(config: Dict[str, Any] | None) -> Dict[str, Any]:
    cfg = dict(DEFAULT_COPILOT_CONFIG)
    raw = config or {}
    cfg["risk_alert_usd"] = max(1.0, _safe_float(raw.get("risk_alert_usd"), cfg["risk_alert_usd"]))
    cfg["review_interval_bars"] = max(10, _safe_int(raw.get("review_interval_bars"), cfg["review_interval_bars"]))
    cfg["emit_bar_events"] = bool(raw.get("emit_bar_events", cfg["emit_bar_events"]))
    cfg["global_cooldown_bars"] = max(0, _safe_int(raw.get("global_cooldown_bars"), cfg["global_cooldown_bars"]))
    cfg["dedupe_window_bars"] = max(1, _safe_int(raw.get("dedupe_window_bars"), cfg["dedupe_window_bars"]))
    cfg["max_advices_per_iteration"] = max(1, _safe_int(raw.get("max_advices_per_iteration"), cfg["max_advices_per_iteration"]))
    cfg["min_confidence_actionable"] = max(0.0, min(1.0, _safe_float(raw.get("min_confidence_actionable"), cfg["min_confidence_actionable"])))
    cfg["min_confidence_watch"] = max(0.0, min(1.0, _safe_float(raw.get("min_confidence_watch"), cfg["min_confidence_watch"])))
    if cfg["min_confidence_watch"] > cfg["min_confidence_actionable"]:
        cfg["min_confidence_watch"] = cfg["min_confidence_actionable"]
    cfg["llm_timeout_sec"] = max(10, _safe_int(raw.get("llm_timeout_sec"), cfg["llm_timeout_sec"]))
    cfg["snapshot_retention"] = max(200, _safe_int(raw.get("snapshot_retention"), cfg["snapshot_retention"]))
    cfg["async_llm_jobs"] = bool(raw.get("async_llm_jobs", cfg["async_llm_jobs"]))
    cfg["job_min_interval_bars"] = max(0, _safe_int(raw.get("job_min_interval_bars"), cfg["job_min_interval_bars"]))
    cfg["auto_paper_min_conf_entry"] = max(
        0.0,
        min(1.0, _safe_float(raw.get("auto_paper_min_conf_entry"), cfg["auto_paper_min_conf_entry"])),
    )
    cfg["auto_paper_min_conf_exit"] = max(
        0.0,
        min(1.0, _safe_float(raw.get("auto_paper_min_conf_exit"), cfg["auto_paper_min_conf_exit"])),
    )
    cfg["auto_paper_rr_target"] = max(0.5, _safe_float(raw.get("auto_paper_rr_target"), cfg["auto_paper_rr_target"]))
    cfg["auto_paper_require_tp"] = bool(raw.get("auto_paper_require_tp", cfg["auto_paper_require_tp"]))
    cfg["auto_paper_action_cooldown_bars"] = max(
        0,
        _safe_int(raw.get("auto_paper_action_cooldown_bars"), cfg["auto_paper_action_cooldown_bars"]),
    )
    cfg["auto_paper_max_actions_per_iteration"] = max(
        1,
        _safe_int(raw.get("auto_paper_max_actions_per_iteration"), cfg["auto_paper_max_actions_per_iteration"]),
    )
    cfg["auto_paper_session_drawdown_stop_usd"] = max(
        10.0,
        _safe_float(raw.get("auto_paper_session_drawdown_stop_usd"), cfg["auto_paper_session_drawdown_stop_usd"]),
    )
    cfg["auto_paper_max_consecutive_losses"] = max(
        1,
        _safe_int(raw.get("auto_paper_max_consecutive_losses"), cfg["auto_paper_max_consecutive_losses"]),
    )
    cfg["auto_paper_max_open_positions"] = max(
        1,
        _safe_int(raw.get("auto_paper_max_open_positions"), cfg["auto_paper_max_open_positions"]),
    )
    cfg["auto_paper_manual_pause"] = bool(raw.get("auto_paper_manual_pause", cfg["auto_paper_manual_pause"]))
    cfg["auto_paper_entry_reject_suppress_n"] = max(
        2,
        _safe_int(raw.get("auto_paper_entry_reject_suppress_n"), cfg["auto_paper_entry_reject_suppress_n"]),
    )
    cfg["enable_auto_tool_scan"] = bool(raw.get("enable_auto_tool_scan", cfg["enable_auto_tool_scan"]))
    cfg["auto_tool_scan_min_conf"] = max(
        0.0,
        min(1.0, _safe_float(raw.get("auto_tool_scan_min_conf"), cfg["auto_tool_scan_min_conf"])),
    )
    cfg["auto_tool_scan_cooldown_bars"] = max(
        0,
        _safe_int(raw.get("auto_tool_scan_cooldown_bars"), cfg["auto_tool_scan_cooldown_bars"]),
    )
    cfg["fvg_entry_proximity_pct"] = max(
        0.01,
        min(5.0, _safe_float(raw.get("fvg_entry_proximity_pct"), cfg["fvg_entry_proximity_pct"])),
    )
    cfg["fvg_entry_require_active_session"] = bool(
        raw.get("fvg_entry_require_active_session", cfg["fvg_entry_require_active_session"])
    )
    cfg["fvg_entry_session_utc_start"] = max(
        0,
        min(23, _safe_int(raw.get("fvg_entry_session_utc_start"), cfg["fvg_entry_session_utc_start"])),
    )
    cfg["fvg_entry_session_utc_end"] = max(
        0,
        min(23, _safe_int(raw.get("fvg_entry_session_utc_end"), cfg["fvg_entry_session_utc_end"])),
    )
    regimes_raw = raw.get("fvg_entry_allowed_regimes") if isinstance(raw.get("fvg_entry_allowed_regimes"), list) else []
    regimes: List[str] = []
    for r in regimes_raw:
        rr = str(r or "").strip().lower()
        if rr and rr not in regimes:
            regimes.append(rr)
    cfg["fvg_entry_allowed_regimes"] = regimes[:8]
    cfg["fvg_entry_min_movement_strength"] = max(
        0.0,
        min(100.0, _safe_float(raw.get("fvg_entry_min_movement_strength"), cfg["fvg_entry_min_movement_strength"])),
    )
    cfg["coach_profile"] = str(raw.get("coach_profile") or cfg["coach_profile"]).strip().lower()
    cfg["coach_style"] = str(raw.get("coach_style") or cfg["coach_style"]).strip().lower()
    watchdog_mode = str(raw.get("watchdog_mode") or cfg["watchdog_mode"]).strip().lower()
    if watchdog_mode not in {"deterministic", "local_gptoss_http", "claude"}:
        watchdog_mode = str(cfg["watchdog_mode"]).strip().lower()
    cfg["watchdog_mode"] = watchdog_mode
    cfg["watchdog_interval_sec"] = max(5, min(300, _safe_int(raw.get("watchdog_interval_sec"), cfg["watchdog_interval_sec"])))
    cfg["watchdog_llm_min_interval_sec"] = max(
        10,
        min(3600, _safe_int(raw.get("watchdog_llm_min_interval_sec"), cfg["watchdog_llm_min_interval_sec"])),
    )
    cfg["watchdog_trigger_requires_approval"] = bool(
        raw.get("watchdog_trigger_requires_approval", cfg["watchdog_trigger_requires_approval"])
    )
    cfg["guardrail_enabled"] = bool(raw.get("guardrail_enabled", cfg["guardrail_enabled"]))
    cfg["guardrail_session_filter_enabled"] = bool(
        raw.get("guardrail_session_filter_enabled", cfg["guardrail_session_filter_enabled"])
    )
    cfg["guardrail_news_filter_enabled"] = bool(
        raw.get("guardrail_news_filter_enabled", cfg["guardrail_news_filter_enabled"])
    )
    cfg["guardrail_news_lookback_min"] = max(
        15,
        min(24 * 60, _safe_int(raw.get("guardrail_news_lookback_min"), cfg["guardrail_news_lookback_min"])),
    )
    news_provider = str(raw.get("market_news_provider") or cfg["market_news_provider"]).strip().lower()
    if news_provider not in {"polygon", "ibkr"}:
        news_provider = str(cfg["market_news_provider"]).strip().lower()
    cfg["market_news_provider"] = news_provider
    cfg["market_news_llm_summary_enabled"] = bool(
        raw.get("market_news_llm_summary_enabled", cfg["market_news_llm_summary_enabled"])
    )
    cfg["market_news_summary_model"] = str(
        raw.get("market_news_summary_model") or cfg["market_news_summary_model"]
    ).strip() or str(cfg["market_news_summary_model"])
    cfg["market_news_llm_timeout_sec"] = max(
        4,
        min(30, _safe_int(raw.get("market_news_llm_timeout_sec"), cfg["market_news_llm_timeout_sec"])),
    )
    cfg["market_news_ibkr_host"] = str(raw.get("market_news_ibkr_host") or cfg["market_news_ibkr_host"]).strip() or "127.0.0.1"
    cfg["market_news_ibkr_port"] = max(
        1,
        min(65535, _safe_int(raw.get("market_news_ibkr_port"), cfg["market_news_ibkr_port"])),
    )
    if raw.get("watchdog_model_label") is not None:
        cfg["watchdog_model_label"] = str(raw.get("watchdog_model_label") or "").strip()
    if raw.get("watchdog_llm_url") is not None:
        cfg["watchdog_llm_url"] = str(raw.get("watchdog_llm_url") or "").strip()
    provider_chain_raw = raw.get("provider_chain") if isinstance(raw.get("provider_chain"), list) else []
    provider_chain: List[str] = []
    for p in provider_chain_raw:
        ps = str(p or "").strip().lower()
        if not ps:
            continue
        if ps in {"anthropic", "claude_api"}:
            ps = "claude"
        if ps not in {"deterministic", "local_gptoss_http", "openai_compat", "claude"}:
            continue
        if ps not in provider_chain:
            provider_chain.append(ps)
    if "deterministic" not in provider_chain:
        provider_chain.append("deterministic")
    cfg["provider_chain"] = provider_chain
    # Optional provider settings (kept if provided)
    for key in [
        "local_gptoss_url",
        "openai_base_url",
        "claude_base_url",
        "anthropic_version",
    ]:
        if key in raw and raw.get(key) is not None:
            cfg[key] = raw.get(key)
    raw_event_cd = raw.get("event_cooldowns") if isinstance(raw.get("event_cooldowns"), dict) else {}
    event_cd = dict(DEFAULT_COPILOT_CONFIG["event_cooldowns"])
    for k, v in raw_event_cd.items():
        kk = str(k or "").strip().upper()
        if not kk:
            continue
        event_cd[kk] = max(0, _safe_int(v, event_cd.get(kk, 0)))
    cfg["event_cooldowns"] = event_cd
    return cfg


def _signature_for_event(ev: Dict[str, Any]) -> str:
    event_type = str(ev.get("event_type") or "").strip().upper()
    payload = ev.get("payload") if isinstance(ev.get("payload"), dict) else {}
    raw = json.dumps({"event_type": event_type, "payload": payload}, sort_keys=True, ensure_ascii=True)
    return hashlib.sha1(raw.encode("utf-8")).hexdigest()


def _apply_trigger_policy(
    events: List[Dict[str, Any]],
    snapshot: Dict[str, Any],
    prev_snapshot: Dict[str, Any] | None,
    config: Dict[str, Any],
) -> Tuple[List[Dict[str, Any]], Dict[str, Any]]:
    current_bar = _safe_int(snapshot.get("current_bar"), 0)
    meta_prev = (
        (prev_snapshot or {}).get("__copilot_meta")
        if isinstance((prev_snapshot or {}).get("__copilot_meta"), dict)
        else {}
    )
    last_event_bar = dict(meta_prev.get("last_event_bar") or {})
    last_sig_bar = dict(meta_prev.get("last_sig_bar") or {})
    global_last_bar = _safe_int(meta_prev.get("last_event_global_bar"), -10_000_000)
    global_cd = max(0, _safe_int(config.get("global_cooldown_bars"), 0))
    dedupe_window = max(1, _safe_int(config.get("dedupe_window_bars"), 8))
    event_cd = config.get("event_cooldowns") if isinstance(config.get("event_cooldowns"), dict) else {}

    kept: List[Dict[str, Any]] = []
    for ev in sorted(events, key=lambda x: int(x.get("priority") or 0), reverse=True):
        et = str(ev.get("event_type") or "").strip().upper()
        if not et:
            continue
        if (current_bar - global_last_bar) < global_cd:
            continue
        et_last = _safe_int(last_event_bar.get(et), -10_000_000)
        et_cd = max(0, _safe_int(event_cd.get(et), 0))
        if (current_bar - et_last) < et_cd:
            continue
        sig = _signature_for_event(ev)
        sig_last = _safe_int(last_sig_bar.get(sig), -10_000_000)
        if (current_bar - sig_last) < dedupe_window:
            continue

        kept.append(ev)
        last_event_bar[et] = current_bar
        last_sig_bar[sig] = current_bar
        global_last_bar = current_bar

    # Trim signature history
    min_keep_bar = current_bar - (dedupe_window * 4)
    pruned_sig_bar = {k: int(v) for k, v in last_sig_bar.items() if _safe_int(v, -10_000_000) >= min_keep_bar}
    meta_next = {
        "last_event_bar": {k: int(v) for k, v in last_event_bar.items()},
        "last_sig_bar": pruned_sig_bar,
        "last_event_global_bar": int(global_last_bar),
    }
    return kept, meta_next


def process_copilot_iteration(
    prev_snapshot: Dict[str, Any] | None,
    session: Any,
    advance_result: Dict[str, Any],
    mode: str | None,
    provider: str | None,
    model_label: str | None,
    config: Dict[str, Any] | None,
) -> Tuple[Dict[str, Any], List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Return next snapshot, detected events, and generated advices."""
    normalized_mode = normalize_copilot_mode(mode)
    normalized_config = normalize_copilot_config(config)
    snapshot = build_snapshot(session=session, advance_result=advance_result)
    # Carry forward external tool state emitted by tool-scan hooks.
    if prev_snapshot and isinstance(prev_snapshot.get("tool_state"), dict) and not isinstance(snapshot.get("tool_state"), dict):
        snapshot["tool_state"] = prev_snapshot.get("tool_state")
    if prev_snapshot and isinstance(prev_snapshot.get("tool_state_full"), dict) and not isinstance(snapshot.get("tool_state_full"), dict):
        snapshot["tool_state_full"] = prev_snapshot.get("tool_state_full")
    raw_events = detect_events(
        prev_snapshot=prev_snapshot,
        snapshot=snapshot,
        config=normalized_config,
    )
    events, meta = _apply_trigger_policy(
        events=raw_events,
        snapshot=snapshot,
        prev_snapshot=prev_snapshot,
        config=normalized_config,
    )
    deterministic_advices = generate_advices(
        snapshot=snapshot,
        events=events,
        mode=normalized_mode,
        config=normalized_config,
    )
    advices, provider_meta = generate_advices_with_provider_chain(
        snapshot=snapshot,
        events=events,
        mode=normalized_mode,
        provider=provider,
        model_label=model_label,
        config=normalized_config,
        deterministic_advices=deterministic_advices,
    )
    max_adv = max(1, _safe_int(normalized_config.get("max_advices_per_iteration"), 2))
    visible_advices = [a for a in advices if str(a.get("delivery") or "").upper() != "SUPPRESS"]
    suppressed_advices = [a for a in advices if str(a.get("delivery") or "").upper() == "SUPPRESS"]
    visible_advices = sorted(
        visible_advices,
        key=lambda a: (
            int(a.get("source_event_priority") or 0),
            float(a.get("confidence") or 0.0),
        ),
        reverse=True,
    )[:max_adv]
    advices = [*visible_advices, *suppressed_advices]
    meta["provider_used"] = str(provider_meta.get("provider_used") or "deterministic")
    meta["provider_attempts"] = provider_meta.get("provider_attempts") if isinstance(provider_meta.get("provider_attempts"), list) else []
    meta["provider_fallback_reason"] = str(provider_meta.get("provider_fallback_reason") or "").strip() or None
    snapshot["__copilot_meta"] = meta
    return snapshot, events, advices
