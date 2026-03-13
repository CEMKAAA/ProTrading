"""Unified Workbench Agent orchestration (Phase 2).

This module provides a single agent entrypoint that can:
- chat with the user,
- call Workbench tools through a provided executor callback,
- produce proposed actions for trade/analysis workflows.

It is additive and can coexist with existing coach/consultant/copilot modules.
"""

from __future__ import annotations

import json
import os
import re
import math
import time
import logging
from pathlib import Path
from datetime import datetime, timezone
from typing import Any, Callable, Dict, List, Optional, Tuple

import httpx
from .history_compressor import compress_history
from .intent_classifier import get_tools_for_intent


ToolExecutor = Callable[[str, Dict[str, Any]], Dict[str, Any]]
logger = logging.getLogger(__name__)

_ALLOWED_TOOL_NAMES = {
    "scan_tool",
    "scan_draw_fvg_range",
    "run_mtf_analysis",
    "run_htf_fvg_liquidity_reclaim_analysis",
    "get_market_snapshot",
    "get_positions_detail",
    "get_indicator_values",
    "get_scheduled_triggers",
    "get_market_news",
    "place_trade",
    "close_trade",
    "schedule_trade_entry",
    "cancel_scheduled_entry",
    "run_research_optimize",
    "run_ml_diagnostic",
    "set_indicator_visibility",
    "set_market_context",
    "set_agent_personality",
    "search_memory",
    "save_memory_note",
}

_SUBMIT_PROPOSED_ACTIONS_TOOL = "submit_proposed_actions"

_ACTION_TYPE_ENUM = [
    "SCAN_TOOL",
    "SET_INDICATOR_VISIBILITY",
    "RUN_RESEARCH_OPTIMIZER",
    "RUN_ML_DIAGNOSTIC",
    "PROPOSE_TRADE_ENTRY",
    "PROPOSE_TRADE_EXIT",
    "EXECUTE_TRADE_ENTRY",
    "EXECUTE_TRADE_EXIT",
    "REVIEW_NOTE",
]
_ALLOWED_ACTION_TYPES = set(_ACTION_TYPE_ENUM)

_ACTION_TYPE_ALIASES = {
    "MONITOR": "REVIEW_NOTE",
    "WATCH": "REVIEW_NOTE",
    "OBSERVE": "REVIEW_NOTE",
    "TRADE_SETUP": "PROPOSE_TRADE_ENTRY",
    "ENTRY_SETUP": "PROPOSE_TRADE_ENTRY",
    "EXIT_SETUP": "PROPOSE_TRADE_EXIT",
    "RESEARCH": "RUN_RESEARCH_OPTIMIZER",
    "OPTIMIZE": "RUN_RESEARCH_OPTIMIZER",
    "TOOL_SCAN": "SCAN_TOOL",
    "SCAN": "SCAN_TOOL",
    "INDICATORS": "SET_INDICATOR_VISIBILITY",
    "ML": "RUN_ML_DIAGNOSTIC",
}

_CLAUDE_HAIKU_45_INPUT_USD_PER_MTOK = 1.0
_CLAUDE_HAIKU_45_OUTPUT_USD_PER_MTOK = 5.0
_CLAUDE_SONNET_INPUT_USD_PER_MTOK = 3.0
_CLAUDE_SONNET_OUTPUT_USD_PER_MTOK = 15.0
_OPENAI_41_MINI_INPUT_USD_PER_MTOK = 0.4
_OPENAI_41_MINI_OUTPUT_USD_PER_MTOK = 1.6
_OPENAI_41_INPUT_USD_PER_MTOK = 2.0
_OPENAI_41_OUTPUT_USD_PER_MTOK = 8.0


def _sleep_backoff(attempt: int, *, base_sec: float = 0.35, cap_sec: float = 2.5) -> None:
    try:
        n = max(1, int(attempt))
    except Exception:
        n = 1
    delay = min(float(cap_sec), float(base_sec) * (2 ** (n - 1)))
    time.sleep(max(0.0, float(delay)))


def _is_transient_http_status(code: int) -> bool:
    try:
        c = int(code)
    except Exception:
        return False
    return c in {408, 409, 425, 429, 500, 502, 503, 504, 529}


def _read_env_file_value(var_name: str) -> Optional[str]:
    """Lightweight .env lookup without requiring python-dotenv."""
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
    return None


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


def _looks_like_agent_payload(obj: Any) -> bool:
    if not isinstance(obj, dict):
        return False
    return any(k in obj for k in ("reply", "tool_calls", "proposed_actions", "memory_notes"))


def _extract_reply_from_payload_like(text: str) -> str:
    """Best-effort extraction of reply from malformed/partial structured payload text."""
    raw = str(text or "").strip()
    if not raw:
        return ""

    # Fast path: valid JSON object extraction.
    obj = _extract_json_object(raw)
    if isinstance(obj, dict):
        rep = str(obj.get("reply") or "").strip()
        if rep:
            return rep

    low = raw.lower()
    if '"reply"' not in low:
        return ""
    if not any(k in low for k in ('"proposed_actions"', '"tool_calls"', '"memory_notes"')):
        return ""

    # Fallback for truncated / malformed payloads: pull "reply":"...".
    m = re.search(r'"reply"\s*:\s*"((?:\\.|[^"\\])*)"', raw, flags=re.DOTALL)
    if not m:
        return ""
    body = str(m.group(1) or "")
    try:
        return str(json.loads(f"\"{body}\"")).strip()
    except Exception:
        return (
            body.replace("\\n", "\n")
            .replace('\\"', '"')
            .replace("\\\\", "\\")
            .strip()
        )


def _strip_embedded_agent_payload(text: str) -> str:
    raw = str(text or "").strip()
    if not raw:
        return ""
    out = raw

    # Drop fenced JSON payload blocks if they are structured agent payloads.
    def _fence_repl(m: re.Match[str]) -> str:
        body = str(m.group(1) or "").strip()
        try:
            obj = json.loads(body)
            if _looks_like_agent_payload(obj):
                return ""
        except Exception:
            low = body.lower()
            if '"reply"' in low and any(k in low for k in ('"proposed_actions"', '"tool_calls"', '"memory_notes"')):
                return ""
        return m.group(0)

    out = re.sub(r"```json\s*([\s\S]*?)```", _fence_repl, out, flags=re.IGNORECASE).strip()

    # Handle unclosed fenced payload blocks (common when model output is cut/truncated).
    if out.lower().startswith("```json"):
        extracted = _extract_reply_from_payload_like(out)
        if extracted:
            return extracted

    # Drop trailing raw JSON payload appended after prose.
    tail = re.search(r"(\{[\s\S]*\})\s*$", out)
    if tail and tail.start(1) > 0:
        body = str(tail.group(1) or "").strip()
        try:
            obj = json.loads(body)
            if _looks_like_agent_payload(obj):
                out = out[: tail.start(1)].strip()
        except Exception:
            low = body.lower()
            if '"reply"' in low and any(k in low for k in ('"proposed_actions"', '"tool_calls"', '"memory_notes"')):
                out = out[: tail.start(1)].strip()

    out = re.sub(r"\n{3,}", "\n\n", out).strip()
    return out


def _safe_float(v: Any, default: float = 0.0) -> float:
    try:
        if v is None:
            return float(default)
        return float(v)
    except Exception:
        return float(default)


def _contains_any(text: str, needles: List[str]) -> bool:
    t = str(text or "").lower()
    for n in needles:
        if str(n or "").lower() in t:
            return True
    return False


def _contains_word(text: str, word: str) -> bool:
    t = str(text or "").lower()
    w = str(word or "").strip().lower()
    if not w:
        return False
    return re.search(rf"\b{re.escape(w)}\b", t) is not None


def _extract_first_number(text: str, patterns: List[str]) -> Optional[float]:
    t = str(text or "")
    for pat in patterns:
        m = re.search(pat, t, flags=re.IGNORECASE)
        if not m:
            continue
        raw = m.group(1) if m.lastindex else None
        if raw is None:
            continue
        try:
            return float(raw)
        except Exception:
            continue
    return None


def _redact_error_text(text: str) -> str:
    raw = str(text or "")
    if not raw:
        return ""
    s = raw
    # Mask common key/token patterns.
    s = re.sub(r"\b(sk-[A-Za-z0-9_\-]{8,})\b", "sk-***", s)
    s = re.sub(r"([?&](?:api_key|key|token|access_token)=)[^&\s]+", r"\1***", s, flags=re.IGNORECASE)
    # Strip overlong payloads.
    return s[:320]


def _extract_first_int(text: str, patterns: List[str]) -> Optional[int]:
    v = _extract_first_number(text, patterns)
    if v is None:
        return None
    try:
        return int(v)
    except Exception:
        return None


def _safe_int(v: Any, default: int = 0) -> int:
    try:
        if v is None:
            return int(default)
        return int(v)
    except Exception:
        return int(default)


def _round_or_none(v: Any, digits: int = 5) -> Optional[float]:
    try:
        fv = float(v)
    except Exception:
        return None
    if not math.isfinite(fv):
        return None
    return float(round(fv, int(digits)))


def _ema_last(series: List[float], span: int) -> Optional[float]:
    if not series:
        return None
    p = max(2, int(span))
    alpha = 2.0 / (float(p) + 1.0)
    ema = float(series[0])
    for x in series[1:]:
        ema = (alpha * float(x)) + ((1.0 - alpha) * ema)
    return _round_or_none(ema)


def _sma_last(series: List[float], period: int) -> Optional[float]:
    if not series:
        return None
    p = max(1, int(period))
    win = series[-p:]
    if not win:
        return None
    return _round_or_none(sum(float(x) for x in win) / float(len(win)))


def _rsi_last(series: List[float], period: int = 14) -> Optional[float]:
    if not isinstance(series, list) or len(series) < 2:
        return None
    p = max(2, int(period))
    gains: List[float] = []
    losses: List[float] = []
    for i in range(1, len(series)):
        d = float(series[i]) - float(series[i - 1])
        gains.append(max(0.0, d))
        losses.append(max(0.0, -d))
    if not gains:
        return None
    gains = gains[-p:]
    losses = losses[-p:]
    avg_gain = sum(gains) / float(len(gains))
    avg_loss = sum(losses) / float(len(losses))
    if avg_loss <= 1e-12:
        return 100.0
    rs = avg_gain / avg_loss
    rsi = 100.0 - (100.0 / (1.0 + rs))
    return _round_or_none(rsi, 2)


def _usage_empty(provider: str, model: str = "") -> Dict[str, Any]:
    return {
        "provider": str(provider or "deterministic"),
        "model": str(model or ""),
        "api_calls": 0,
        "input_tokens": 0,
        "output_tokens": 0,
        "total_tokens": 0,
        "estimated_cost_usd": 0.0,
        "cost_estimate_source": "none",
    }


def _usage_extract_openai(body: Any) -> Dict[str, int]:
    if not isinstance(body, dict):
        return {"input_tokens": 0, "output_tokens": 0}
    usage = body.get("usage") if isinstance(body.get("usage"), dict) else {}
    inp = _safe_int(
        usage.get("input_tokens")
        if usage.get("input_tokens") is not None
        else usage.get("prompt_tokens"),
        0,
    )
    out = _safe_int(
        usage.get("output_tokens")
        if usage.get("output_tokens") is not None
        else usage.get("completion_tokens"),
        0,
    )
    return {
        "input_tokens": max(0, int(inp)),
        "output_tokens": max(0, int(out)),
    }


def _usage_extract_claude(body: Any) -> Dict[str, int]:
    if not isinstance(body, dict):
        return {"input_tokens": 0, "output_tokens": 0}
    usage = body.get("usage") if isinstance(body.get("usage"), dict) else {}
    inp = _safe_int(usage.get("input_tokens"), 0)
    inp += _safe_int(usage.get("cache_creation_input_tokens"), 0)
    inp += _safe_int(usage.get("cache_read_input_tokens"), 0)
    out = _safe_int(usage.get("output_tokens"), 0)
    return {
        "input_tokens": max(0, int(inp)),
        "output_tokens": max(0, int(out)),
    }


def _usage_add(total: Dict[str, Any], delta: Dict[str, int]) -> None:
    if not isinstance(total, dict):
        return
    if not isinstance(delta, dict):
        return
    total["input_tokens"] = max(0, int(_safe_int(total.get("input_tokens"), 0) + _safe_int(delta.get("input_tokens"), 0)))
    total["output_tokens"] = max(0, int(_safe_int(total.get("output_tokens"), 0) + _safe_int(delta.get("output_tokens"), 0)))
    total["total_tokens"] = max(0, int(total["input_tokens"] + total["output_tokens"]))
    if "api_calls" in delta:
        total["api_calls"] = max(0, int(_safe_int(total.get("api_calls"), 0) + _safe_int(delta.get("api_calls"), 0)))


def _estimate_usage_tokens_from_text(*parts: Any) -> int:
    total_chars = 0
    for p in parts:
        total_chars += len(str(p or ""))
    # Lightweight token estimate when provider does not return usage.
    return max(0, int(round(total_chars / 4.0)))


def _usage_finalize(total: Dict[str, Any]) -> Dict[str, Any]:
    out = dict(total) if isinstance(total, dict) else {}
    provider = str(out.get("provider") or "").strip().lower()
    model = str(out.get("model") or "").strip().lower()
    inp = max(0, _safe_int(out.get("input_tokens"), 0))
    out_tok = max(0, _safe_int(out.get("output_tokens"), 0))
    out["input_tokens"] = int(inp)
    out["output_tokens"] = int(out_tok)
    out["total_tokens"] = int(max(0, inp + out_tok))
    out["api_calls"] = int(max(0, _safe_int(out.get("api_calls"), 0)))

    est = 0.0
    src = "none"
    if provider == "claude" and ("haiku-4-5" in model or "claude-haiku-4-5" in model):
        est = (inp / 1_000_000.0) * _CLAUDE_HAIKU_45_INPUT_USD_PER_MTOK + (
            out_tok / 1_000_000.0
        ) * _CLAUDE_HAIKU_45_OUTPUT_USD_PER_MTOK
        src = "anthropic_public_pricing_haiku_4_5"
    elif provider == "claude" and "sonnet" in model:
        est = (inp / 1_000_000.0) * _CLAUDE_SONNET_INPUT_USD_PER_MTOK + (
            out_tok / 1_000_000.0
        ) * _CLAUDE_SONNET_OUTPUT_USD_PER_MTOK
        src = "anthropic_public_pricing_sonnet"
    elif provider == "openai_compat" and ("gpt-4.1-mini" in model or "gpt-4o-mini" in model):
        est = (inp / 1_000_000.0) * _OPENAI_41_MINI_INPUT_USD_PER_MTOK + (
            out_tok / 1_000_000.0
        ) * _OPENAI_41_MINI_OUTPUT_USD_PER_MTOK
        src = "openai_public_pricing_mini"
    elif provider == "openai_compat" and ("gpt-4.1" in model or "gpt-4o" in model):
        est = (inp / 1_000_000.0) * _OPENAI_41_INPUT_USD_PER_MTOK + (
            out_tok / 1_000_000.0
        ) * _OPENAI_41_OUTPUT_USD_PER_MTOK
        src = "openai_public_pricing_standard"
    out["estimated_cost_usd"] = float(max(0.0, est))
    out["cost_estimate_source"] = src
    return out


def _to_provider_name(provider: str) -> str:
    p = str(provider or "deterministic").strip().lower()
    if p in {"anthropic", "claude_api"}:
        return "claude"
    if p not in {"deterministic", "local_gptoss_http", "openai_compat", "claude"}:
        return "deterministic"
    return p


class WorkbenchAgent:
    """Unified agent that supports tool-calling across providers."""

    def __init__(self, anthropic_version: str = "2023-06-01") -> None:
        self.anthropic_version = str(anthropic_version or "2023-06-01")

    @staticmethod
    def _default_model(provider: str) -> str:
        p = _to_provider_name(provider)
        if p == "local_gptoss_http":
            return "gpt-oss-20b"
        if p == "openai_compat":
            return "gpt-4.1-mini"
        if p == "claude":
            return "claude-sonnet-4-5-20250929"
        return "deterministic"

    @staticmethod
    def _default_url(provider: str) -> str:
        p = _to_provider_name(provider)
        if p == "local_gptoss_http":
            return "http://127.0.0.1:8012"
        if p == "openai_compat":
            return "https://api.openai.com/v1"
        if p == "claude":
            return "https://api.anthropic.com"
        return ""

    @staticmethod
    def _claude_model_candidates(model_label: str) -> List[str]:
        preferred = str(model_label or "").strip() or "claude-sonnet-4-5-20250929"
        # Respect explicit user-selected model strictly (no silent fallback drift).
        if str(model_label or "").strip():
            return [preferred]
        candidates = [
            preferred,
            "claude-sonnet-4-5-20250929",
            "claude-3-5-sonnet-latest",
            "claude-3-5-haiku-latest",
            "claude-haiku-4-5-20251001",
        ]
        out: List[str] = []
        for m in candidates:
            s = str(m or "").strip()
            if s and s not in out:
                out.append(s)
        return out

    @staticmethod
    def _trim_history(history: Any, max_messages: int = 12, max_chars: int = 800) -> List[Dict[str, str]]:
        out: List[Dict[str, str]] = []
        if not isinstance(history, list):
            return out
        for row in history:
            if not isinstance(row, dict):
                continue
            role = str(row.get("role") or "").strip().lower()
            if role not in {"user", "assistant"}:
                continue
            content = str(row.get("content") or "").strip()
            if not content:
                continue
            if len(content) > int(max_chars):
                content = content[: int(max_chars)]
            out.append({"role": role, "content": content})
        coalesced: List[Dict[str, str]] = []
        for row in out:
            role = str(row.get("role") or "")
            content = str(row.get("content") or "")
            if not role or not content:
                continue
            if coalesced and str(coalesced[-1].get("role") or "") == role:
                merged = (str(coalesced[-1].get("content") or "") + "\n" + content).strip()
                if len(merged) > int(max_chars):
                    merged = merged[: int(max_chars)]
                coalesced[-1]["content"] = merged
            else:
                coalesced.append({"role": role, "content": content})
        if len(coalesced) > int(max_messages):
            return coalesced[-int(max_messages) :]
        return coalesced

    @staticmethod
    def _normalize_memory_notes(raw: Any) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        if not isinstance(raw, list):
            return out
        for row in raw[:12]:
            if not isinstance(row, dict):
                continue
            content = re.sub(r"\s+", " ", str(row.get("content") or "").strip())
            if len(content) < 8:
                continue
            mtype = str(row.get("memory_type") or row.get("type") or "note").strip().lower()[:40] or "note"
            scope = str(row.get("scope") or "SESSION").strip().upper()
            if scope not in {"GLOBAL", "SESSION", "SYMBOL"}:
                scope = "SESSION"
            try:
                importance = float(row.get("importance") if row.get("importance") is not None else 0.7)
            except Exception:
                importance = 0.7
            importance = max(0.0, min(1.0, importance))
            out.append(
                {
                    "content": content[:1800],
                    "memory_type": mtype,
                    "scope": scope,
                    "importance": importance,
                    "symbol": (str(row.get("symbol") or "").strip().upper() or None),
                    "timeframe": (str(row.get("timeframe") or "").strip().upper() or None),
                }
            )
        return out

    @staticmethod
    def _tool_specs() -> List[Dict[str, Any]]:
        return [
            {
                "name": "scan_tool",
                "description": "Child/granular scanner for fvg/liquidity/mean_rev. Use mainly for manual deep-dive/debug. For HTF->LTF FVG strategy execution, prefer run_mtf_analysis (parent) for better reliability and token efficiency.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "tool_id": {"type": "string", "description": "fvg, liquidity, or mean_rev"},
                        "timeframe": {"type": "string", "description": "Optional: M1, M5, M15, M30, H1, H4, D1"},
                        "lookback_days": {"type": "number", "description": "Optional: limit scan window by recent days."},
                        "config": {"type": "object"},
                        "bars": {"type": "array", "items": {"type": "object"}},
                    },
                    "required": ["tool_id"],
                    "additionalProperties": False,
                },
            },
            {
                "name": "scan_draw_fvg_range",
                "description": "Child chart-range FVG scan between selected bar indexes. Use for manual chart forensics, not as primary strategy planner.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "start_index": {"type": "integer"},
                        "end_index": {"type": "integer"},
                        "config": {"type": "object"},
                    },
                    "required": ["start_index", "end_index"],
                    "additionalProperties": False,
                },
            },
            {
                "name": "run_mtf_analysis",
                "description": "Parent strategy tool (preferred): deterministic HTF->LTF FVG analysis in one call (anchors, confirmation, sizing, blockers, trigger candidate). Use this first for multi-timeframe FVG workflows instead of chaining child tools.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "symbol": {"type": "string", "description": "Optional symbol override (defaults to session symbol)."},
                        "source": {"type": "string", "description": "Optional data source override: mt5 or databento."},
                        "htf_timeframes": {
                            "type": "array",
                            "items": {"type": "string"},
                            "description": "Higher-timeframe anchors list (e.g., [\"D1\",\"H4\"]).",
                        },
                        "execution_timeframe": {"type": "string", "description": "Lower timeframe for execution logic (default M15)."},
                        "htf_history_days": {"type": "number", "description": "Optional HTF history window in days."},
                        "ltf_history_days": {"type": "number", "description": "Optional LTF history window in days."},
                        "risk_percent": {"type": "number", "description": "Risk percent for lot sizing (default 0.5)."},
                        "rr_target": {"type": "number", "description": "Target risk-reward multiple (default 2.0)."},
                        "include_news": {"type": "boolean", "description": "Include market news headlines in output when true."},
                        "news_limit": {"type": "integer", "description": "News headline limit (1-10)."},
                        "news_lookback_min": {"type": "integer", "description": "News lookback window in minutes."},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "run_htf_fvg_liquidity_reclaim_analysis",
                "description": "Separate parent strategy tool: backtest-aligned HTF FVG + liquidity reclaim analysis. Uses sweep confirmation near HTF FVGs, then builds a schedule-ready reclaim setup with deterministic server-side logic.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "symbol": {"type": "string", "description": "Optional symbol override (defaults to session symbol)."},
                        "source": {"type": "string", "description": "Optional data source override: mt5 or databento."},
                        "preset": {"type": "string", "description": "Optional preset override: default, conservative, aggressive, xauusd_m15, nas100_m15."},
                        "execution_timeframe": {"type": "string", "description": "Optional execution timeframe override (default from preset/session, usually M15)."},
                        "history_days": {"type": "number", "description": "Optional live-history window in days."},
                        "risk_percent": {"type": "number", "description": "Optional risk percent override for lot sizing."},
                        "min_rr_ratio": {"type": "number", "description": "Optional minimum risk-reward override."},
                        "expires_sec": {"type": "integer", "description": "Optional trigger expiry override in seconds."},
                        "include_news": {"type": "boolean", "description": "Include market news headlines in output when true."},
                        "news_limit": {"type": "integer", "description": "News headline limit (1-10)."},
                        "news_lookback_min": {"type": "integer", "description": "News lookback window in minutes."},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "get_market_snapshot",
                "description": "General market context snapshot (price, indicators, optional bars). Safe for quick status checks; not a replacement for run_mtf_analysis when building HTF->LTF FVG execution plans.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "bars_limit": {"type": "integer", "description": "How many recent bars to include (default 40)."},
                        "include_bars": {"type": "boolean", "description": "Include recent bars array in response."},
                        "include_indicators": {"type": "boolean", "description": "Include computed indicator snapshot."},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "get_positions_detail",
                "description": "Get detailed open positions and recent closed trades.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "open_limit": {"type": "integer"},
                        "recent_limit": {"type": "integer"},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "get_indicator_values",
                "description": "Child indicator diagnostic tool (EMA/SMA/RSI/ATR/BB/Stoch). Use for targeted confirmation/debug after parent analysis or for non-FVG workflows.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "bars_limit": {"type": "integer", "description": "Max bars to use for indicator computation."},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "get_scheduled_triggers",
                "description": "Get scheduled trade triggers and current trigger counts.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "include_non_pending": {"type": "boolean"},
                        "limit": {"type": "integer"},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "get_market_news",
                "description": "Fetch recent instrument-relevant news headlines for context-aware risk assessment.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "symbol": {"type": "string", "description": "Optional symbol override; defaults to current session symbol."},
                        "limit": {"type": "integer", "description": "Max headline count (1-10)."},
                        "lookback_min": {"type": "integer", "description": "Headline recency window in minutes."},
                        "provider": {"type": "string", "description": "Optional provider override: polygon or ibkr."},
                        "include_summary": {"type": "boolean", "description": "When true, include cached one-shot LLM summary."},
                        "summary_model": {"type": "string", "description": "Optional Anthropic summary model override."},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "place_trade",
                "description": "Place a paper trade when permissions allow.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "direction": {"type": "string", "description": "BUY or SELL"},
                        "stop_loss": {"type": "number"},
                        "take_profit": {"type": "number"},
                        "lot_size": {"type": "number"},
                        "entry_price": {"type": "number"},
                        "bar_time_unix": {"type": "integer"},
                    },
                    "required": ["direction", "stop_loss"],
                    "additionalProperties": False,
                },
            },
            {
                "name": "close_trade",
                "description": "Close an open paper trade by trade id.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "trade_id": {"type": "integer"},
                        "exit_price": {"type": "number"},
                        "bar_time_unix": {"type": "integer"},
                    },
                    "required": ["trade_id"],
                    "additionalProperties": False,
                },
            },
            {
                "name": "schedule_trade_entry",
                "description": "Schedule a conditional entry trigger to auto-place trade when condition is met. Supports optional multi-step arming via precondition (e.g. reclaim then reject) and optional cancel_rule (invalidation before entry).",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "condition": {"type": "string", "description": "close_below, close_above, price_below, price_above, sweep_below, or sweep_above"},
                        "trigger_price": {"type": "number"},
                        "precondition": {
                            "type": "object",
                            "description": "Optional first step. Trigger is armed only after this condition is hit.",
                            "properties": {
                                "condition": {"type": "string", "description": "close_below, close_above, price_below, price_above, sweep_below, or sweep_above"},
                                "trigger_price": {"type": "number"},
                            },
                            "required": ["condition", "trigger_price"],
                            "additionalProperties": False,
                        },
                        "cancel_rule": {
                            "type": "object",
                            "description": "Optional invalidation guard. Trigger is cancelled if this condition is hit before entry.",
                            "properties": {
                                "condition": {"type": "string", "description": "close_below, close_above, price_below, price_above, sweep_below, or sweep_above"},
                                "trigger_price": {"type": "number"},
                            },
                            "required": ["condition", "trigger_price"],
                            "additionalProperties": False,
                        },
                        "cancel_condition": {"type": "string", "description": "Alias for cancel_rule.condition"},
                        "cancel_trigger_price": {"type": "number", "description": "Alias for cancel_rule.trigger_price"},
                        "direction": {"type": "string", "description": "BUY or SELL"},
                        "stop_loss": {"type": "number"},
                        "take_profit": {"type": "number"},
                        "lot_size": {"type": "number"},
                        "entry_ref": {"type": "number", "description": "Optional reference entry price used for server-side risk math validation"},
                        "expected_rr": {"type": "number", "description": "Optional expected R:R used for server-side mismatch checks"},
                        "min_rr": {"type": "number", "description": "Optional minimum acceptable R:R"},
                        "risk_percent": {"type": "number", "description": "Optional risk percent (e.g. 0.5 means 0.5%) for lot-size validation"},
                        "risk_amount": {"type": "number", "description": "Optional fixed risk amount for lot-size validation"},
                        "account_balance": {"type": "number", "description": "Optional balance reference for risk_percent conversion"},
                        "point_value_per_1lot": {"type": "number", "description": "Optional per-lot price-unit value override for risk math"},
                        "timeframe": {"type": "string", "description": "M1, M5, M15, M30, H1, H4, D1"},
                        "expires_sec": {"type": "integer", "description": "Optional trigger expiry in seconds"},
                    },
                    "required": ["condition", "trigger_price", "direction", "stop_loss"],
                    "additionalProperties": False,
                },
            },
            {
                "name": "cancel_scheduled_entry",
                "description": "Cancel one scheduled entry trigger by trigger_id, or set cancel_all=true to cancel all pending triggers.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "trigger_id": {"type": "string"},
                        "cancel_all": {"type": "boolean"},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "run_research_optimize",
                "description": "Run research optimizer (SMA crossover or mean reversion).",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "strategy_type": {"type": "string"},
                        "params": {"type": "object"},
                        "top_n": {"type": "integer"},
                        "max_combinations": {"type": "integer"},
                        "tc_rate": {"type": "number"},
                        "bars": {"type": "array", "items": {"type": "object"}},
                    },
                    "required": ["strategy_type"],
                    "additionalProperties": False,
                },
            },
            {
                "name": "run_ml_diagnostic",
                "description": "Run research ML feature diagnostic on session bars.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "lags": {"type": "integer"},
                        "split_ratio": {"type": "number"},
                        "drift_warn_pct": {"type": "number"},
                        "params": {"type": "object"},
                        "bars": {"type": "array", "items": {"type": "object"}},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "set_indicator_visibility",
                "description": "Set desired indicator visibility profile.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "visibility": {"type": "object"},
                    },
                    "required": ["visibility"],
                    "additionalProperties": False,
                },
            },
            {
                "name": "set_market_context",
                "description": "Switch symbol/timeframe/source/history context. Use this whenever market context must change before scanning or planning.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "symbol": {"type": "string", "description": "XAUUSD, NAS100, US500, GBPUSD, EURUSD"},
                        "timeframe": {"type": "string", "description": "M1, M5, M15, M30, H1, H4, D1"},
                        "source": {"type": "string", "description": "mt5 or databento"},
                        "history_days": {"type": "number"},
                    },
                    "additionalProperties": False,
                },
            },
            {
                "name": "set_agent_personality",
                "description": "Switch locked agent identity profile to master_quant or apprentice for this session.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "profile": {"type": "string", "description": "master_quant or apprentice"},
                        "lock_personality": {"type": "boolean", "description": "Optional lock override"},
                    },
                    "required": ["profile"],
                    "additionalProperties": False,
                },
            },
            {
                "name": "search_memory",
                "description": "Search long-term trader memory notes relevant to current question.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {"type": "string"},
                        "limit": {"type": "integer"},
                        "memory_type": {"type": "string"},
                    },
                    "required": ["query"],
                    "additionalProperties": False,
                },
            },
            {
                "name": "save_memory_note",
                "description": "Save a durable trader memory note for future sessions.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "content": {"type": "string"},
                        "memory_type": {"type": "string"},
                        "scope": {
                            "type": "string",
                            "enum": ["GLOBAL", "SESSION", "SYMBOL"],
                            "description": "GLOBAL, SESSION, or SYMBOL",
                        },
                        "importance": {"type": "number"},
                        "symbol": {"type": "string"},
                        "timeframe": {"type": "string"},
                    },
                    "required": ["content"],
                    "additionalProperties": False,
                },
            },
            {
                "name": _SUBMIT_PROPOSED_ACTIONS_TOOL,
                "description": "Submit structured proposed actions using only allowed action types.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "proposed_actions": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "action_type": {"type": "string", "enum": _ACTION_TYPE_ENUM},
                                    "summary": {"type": "string"},
                                    "payload": {"type": "object"},
                                    "confidence": {"type": "number"},
                                },
                                "required": ["action_type"],
                                "additionalProperties": False,
                            },
                        }
                    },
                    "required": ["proposed_actions"],
                    "additionalProperties": False,
                },
            },
        ]

    @staticmethod
    def _claude_tool_specs() -> List[Dict[str, Any]]:
        """Anthropic uses input_schema instead of parameters."""
        out: List[Dict[str, Any]] = []
        for spec in WorkbenchAgent._tool_specs():
            if not isinstance(spec, dict):
                continue
            row = dict(spec)
            params = row.pop("parameters", None)
            if isinstance(params, dict):
                row["input_schema"] = params
            out.append(row)
        return out

    @staticmethod
    def _tool_specs_filtered(allowed_tool_names: Optional[List[str]]) -> List[Dict[str, Any]]:
        specs = WorkbenchAgent._tool_specs()
        if not allowed_tool_names:
            return specs
        allow = {str(x or "").strip() for x in allowed_tool_names if str(x or "").strip()}
        if not allow:
            return []
        return [s for s in specs if str(s.get("name") or "").strip() in allow]

    @staticmethod
    def _claude_tool_specs_filtered(allowed_tool_names: Optional[List[str]]) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        for spec in WorkbenchAgent._tool_specs_filtered(allowed_tool_names):
            if not isinstance(spec, dict):
                continue
            row = dict(spec)
            params = row.pop("parameters", None)
            if isinstance(params, dict):
                row["input_schema"] = params
            out.append(row)
        return out

    @staticmethod
    def _build_market_summary(context: Dict[str, Any]) -> Dict[str, Any]:
        ctx = context if isinstance(context, dict) else {}
        session = ctx.get("session") if isinstance(ctx.get("session"), dict) else {}
        stats = ctx.get("session_stats") if isinstance(ctx.get("session_stats"), dict) else {}
        bars = ctx.get("bars") if isinstance(ctx.get("bars"), list) else []
        closes: List[float] = []
        highs: List[float] = []
        lows: List[float] = []
        for b in bars[-500:]:
            if not isinstance(b, dict):
                continue
            c = _round_or_none(b.get("close"))
            h = _round_or_none(b.get("high"))
            l = _round_or_none(b.get("low"))
            if c is None or h is None or l is None:
                continue
            closes.append(float(c))
            highs.append(float(h))
            lows.append(float(l))
        current_price = closes[-1] if closes else None
        lookback = min(20, max(0, len(closes) - 1))
        pct_change_20 = None
        if current_price is not None and lookback > 0:
            base = float(closes[-1 - lookback])
            if abs(base) > 1e-12:
                pct_change_20 = _round_or_none(((float(current_price) - base) / base) * 100.0, 3)
        ema20 = _ema_last(closes, 20)
        ema50 = _ema_last(closes, 50)
        ema200 = _ema_last(closes, 200)
        rsi14 = _rsi_last(closes, 14)
        trend_bias = "unknown"
        if ema20 is not None and ema50 is not None and ema200 is not None:
            if ema20 > ema50 > ema200:
                trend_bias = "bullish"
            elif ema20 < ema50 < ema200:
                trend_bias = "bearish"
            else:
                trend_bias = "mixed"
        open_positions = ctx.get("open_positions") if isinstance(ctx.get("open_positions"), list) else []
        buy_count = 0
        sell_count = 0
        for p in open_positions:
            if not isinstance(p, dict):
                continue
            d = str(p.get("direction") or "").strip().upper()
            if d == "BUY":
                buy_count += 1
            elif d == "SELL":
                sell_count += 1
        triggers = ctx.get("scheduled_triggers") if isinstance(ctx.get("scheduled_triggers"), list) else []
        pending_triggers = 0
        for tr in triggers:
            if isinstance(tr, dict) and str(tr.get("status") or "").strip().lower() == "pending":
                pending_triggers += 1
        rolling_range_20 = None
        if len(highs) >= 20 and len(lows) >= 20:
            rolling_range_20 = _round_or_none(max(highs[-20:]) - min(lows[-20:]), 3)
        return {
            "symbol": str(session.get("symbol") or ""),
            "timeframe": str(session.get("timeframe") or ""),
            "current_price": _round_or_none(current_price, 5),
            "pct_change_20": pct_change_20,
            "trend_bias": trend_bias,
            "ema20": ema20,
            "ema50": ema50,
            "ema200": ema200,
            "rsi14": rsi14,
            "range20": rolling_range_20,
            "open_positions_count": int(len(open_positions)),
            "open_positions_buy": int(buy_count),
            "open_positions_sell": int(sell_count),
            "pending_triggers_count": int(pending_triggers),
            "current_balance": _round_or_none(stats.get("current_balance"), 2),
            "total_pnl": _round_or_none(stats.get("total_pnl"), 2),
            "bars_count": int(len(bars)),
        }

    @staticmethod
    def _compact_memory_hits(mem_hits: List[Dict[str, Any]], limit: int = 6) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        for row in mem_hits[: max(1, int(limit))]:
            if not isinstance(row, dict):
                continue
            out.append(
                {
                    "id": row.get("id"),
                    "memory_type": str(row.get("memory_type") or ""),
                    "scope": str(row.get("scope") or ""),
                    "importance": _round_or_none(row.get("importance"), 3),
                    "symbol": str(row.get("symbol") or "") or None,
                    "timeframe": str(row.get("timeframe") or "") or None,
                    "pinned": bool(row.get("pinned", False)),
                    "content": str(row.get("content") or "")[:180],
                }
            )
        return out

    def _build_prompt_context(self, context: Dict[str, Any]) -> Dict[str, Any]:
        ctx = context if isinstance(context, dict) else {}
        compact_ctx = dict(ctx)
        compact_ctx["market_summary"] = self._build_market_summary(compact_ctx)

        bars = compact_ctx.get("bars") if isinstance(compact_ctx.get("bars"), list) else []
        compact_ctx["bars_available"] = int(len(bars))
        compact_ctx.pop("bars", None)

        open_positions = compact_ctx.get("open_positions") if isinstance(compact_ctx.get("open_positions"), list) else []
        compact_ctx["open_positions_brief"] = [
            {
                "id": p.get("id"),
                "direction": str(p.get("direction") or "").upper(),
                "entry_price": _round_or_none(p.get("entry_price"), 5),
                "stop_loss": _round_or_none(p.get("stop_loss"), 5),
                "take_profit": _round_or_none(p.get("take_profit"), 5),
                "lot_size": _round_or_none(p.get("lot_size"), 3),
            }
            for p in open_positions[:5]
            if isinstance(p, dict)
        ]
        compact_ctx["open_positions_count"] = int(len(open_positions))
        compact_ctx.pop("open_positions", None)

        recent_trades = compact_ctx.get("recent_trades") if isinstance(compact_ctx.get("recent_trades"), list) else []
        compact_ctx["recent_trades_brief"] = [
            {
                "id": t.get("id"),
                "direction": str(t.get("direction") or "").upper(),
                "status": str(t.get("status") or "").lower(),
                "pnl": _round_or_none(t.get("pnl"), 2),
                "r_multiple": _round_or_none(t.get("r_multiple"), 2),
                "exit_reason": str(t.get("exit_reason") or "")[:80] or None,
            }
            for t in recent_trades[:8]
            if isinstance(t, dict)
        ]
        compact_ctx.pop("recent_trades", None)

        triggers = compact_ctx.get("scheduled_triggers") if isinstance(compact_ctx.get("scheduled_triggers"), list) else []
        compact_ctx["scheduled_triggers_brief"] = [
            {
                "id": str(tr.get("id") or ""),
                "status": str(tr.get("status") or "").lower(),
                "state": str(tr.get("state") or "").lower(),
                "condition": str(tr.get("condition") or "").lower(),
                "trigger_price": _round_or_none(tr.get("trigger_price"), 5),
                "timeframe": str(tr.get("timeframe") or "").upper() or None,
                "direction": str((tr.get("trade_args") or {}).get("direction") or "").upper() if isinstance(tr.get("trade_args"), dict) else None,
            }
            for tr in triggers[:8]
            if isinstance(tr, dict)
        ]
        compact_ctx["scheduled_triggers_count"] = int(len(triggers))
        compact_ctx["scheduled_triggers_pending_count"] = int(
            sum(1 for tr in triggers if isinstance(tr, dict) and str(tr.get("status") or "").lower() == "pending")
        )
        compact_ctx.pop("scheduled_triggers", None)

        tool_state = compact_ctx.get("tool_state") if isinstance(compact_ctx.get("tool_state"), dict) else {}
        if isinstance(tool_state, dict):
            ts_compact: Dict[str, Any] = {}
            for k, v in tool_state.items():
                if isinstance(v, list):
                    ts_compact[k] = v[-8:]
                elif isinstance(v, dict):
                    inner: Dict[str, Any] = {}
                    for ik, iv in list(v.items())[:20]:
                        if isinstance(iv, list):
                            inner[ik] = iv[-6:]
                        elif isinstance(iv, dict):
                            inner[ik] = {kk: vv for kk, vv in list(iv.items())[:12]}
                        else:
                            inner[ik] = iv
                    ts_compact[k] = inner
                else:
                    ts_compact[k] = v
            compact_ctx["tool_state"] = ts_compact

        mem = compact_ctx.get("memory") if isinstance(compact_ctx.get("memory"), dict) else {}
        mem_hits = mem.get("hits") if isinstance(mem.get("hits"), list) else []
        mem["hits"] = self._compact_memory_hits(mem_hits, limit=6)
        compact_ctx["memory"] = mem

        # Identity is injected separately; keep context payload lean.
        compact_ctx.pop("identity", None)
        return compact_ctx

    def _build_prompt_context_on_demand(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """Ultra-compact context for local tool-on-demand providers."""
        ctx = context if isinstance(context, dict) else {}
        out: Dict[str, Any] = {}
        out["market_summary"] = self._build_market_summary(ctx)

        sess = ctx.get("session") if isinstance(ctx.get("session"), dict) else {}
        out["session"] = {
            "id": sess.get("id"),
            "symbol": str(sess.get("symbol") or ""),
            "timeframe": str(sess.get("timeframe") or ""),
            "live_feed_active": bool(sess.get("live_feed_active", False)),
            "transport_mode": str(sess.get("transport_mode") or ""),
        }

        stats = ctx.get("session_stats") if isinstance(ctx.get("session_stats"), dict) else {}
        out["session_stats"] = {
            "current_balance": _round_or_none(stats.get("current_balance"), 2),
            "total_pnl": _round_or_none(stats.get("total_pnl"), 2),
            "trades_count": int(_safe_int(stats.get("trades_count"), 0)),
        }

        open_positions = ctx.get("open_positions") if isinstance(ctx.get("open_positions"), list) else []
        out["open_positions_count"] = int(len(open_positions))

        triggers = ctx.get("scheduled_triggers") if isinstance(ctx.get("scheduled_triggers"), list) else []
        out["scheduled_triggers_count"] = int(len(triggers))
        out["scheduled_triggers_pending_count"] = int(
            sum(1 for tr in triggers if isinstance(tr, dict) and str(tr.get("status") or "").lower() == "pending")
        )

        tool_state = ctx.get("tool_state") if isinstance(ctx.get("tool_state"), dict) else {}
        active_tools = tool_state.get("active_tools")
        if isinstance(active_tools, list):
            out["active_tools"] = [str(x) for x in active_tools[:8]]

        mem = ctx.get("memory") if isinstance(ctx.get("memory"), dict) else {}
        mem_hits = mem.get("hits") if isinstance(mem.get("hits"), list) else []
        if mem_hits:
            out["memory"] = {"hits": self._compact_memory_hits(mem_hits, limit=4)}
        return out

    def _system_prompt_parts(
        self,
        context: Dict[str, Any],
        permissions: Dict[str, Any],
        objective: str = "",
        allowed_tool_names: Optional[List[str]] = None,
        include_tool_summaries: bool = True,
        on_demand_mode: bool = False,
        delta_context: Optional[Dict[str, Any]] = None,
    ) -> Tuple[str, str]:
        ctx = context if isinstance(context, dict) else {}
        identity = ctx.get("identity") if isinstance(ctx.get("identity"), dict) else {}
        compact_ctx = self._build_prompt_context_on_demand(ctx) if on_demand_mode else self._build_prompt_context(ctx)
        tools_block = ""
        if include_tool_summaries:
            tool_lines = []
            for spec in self._tool_specs_filtered(allowed_tool_names):
                if not isinstance(spec, dict):
                    continue
                name = str(spec.get("name") or "").strip()
                params = spec.get("parameters") if isinstance(spec.get("parameters"), dict) else {}
                props = params.get("properties") if isinstance(params.get("properties"), dict) else {}
                keys = ", ".join(sorted(list(props.keys()))[: (4 if on_demand_mode else 8)])
                if on_demand_mode:
                    tool_lines.append(f"- {name} args: {{{keys}}}")
                else:
                    desc = str(spec.get("description") or "").strip()
                    tool_lines.append(f"- {name}: {desc}. args: {{{keys}}}")
            tools_block = "\n".join(tool_lines)
        tools_section = ""
        if include_tool_summaries and tools_block:
            tools_section = "Available tools:\n" + tools_block + "\n\n"
        effective_ctx = delta_context if (isinstance(delta_context, dict) and bool(delta_context)) else compact_ctx
        ctx_json = json.dumps(effective_ctx, ensure_ascii=True)
        perm_json = json.dumps(permissions or {}, ensure_ascii=True)
        identity_json = json.dumps(identity, ensure_ascii=True)
        static_part = (
            "You are a professional trading co-pilot for paper simulation.\n"
            "Never fabricate prices, fills, or tool outputs. Respect permissions strictly.\n\n"
            "STRATEGY WORKFLOW:\n"
            "- For classic multi-timeframe FVG analysis, call run_mtf_analysis first (HTF anchors + LTF confirmation + risk math in one call).\n"
            "- For the separate HTF FVG + Liquidity Reclaim strategy, call run_htf_fvg_liquidity_reclaim_analysis first.\n"
            "- If a parent strategy returns NO_TRIGGER, zero HTF candidates, or sparse negative output, verify before concluding: run raw scan_tool checks on HTF FVG structure and execution-timeframe liquidity, then explain whether the structure truly does not exist or was filtered out by strategy rules.\n"
            "- For conditional entries, use schedule_trade_entry with precondition, condition, and cancel_rule.\n"
            "- Always include stop_loss and take_profit with every trade action.\n\n"
            "PROFESSIONALITY:\n"
            "- Act on data, not guesses. Run tools first, then form conclusions.\n"
            "- When asked to analyse or plan, deliver a concrete professional plan — do not ask for inputs you can infer from tools.\n"
            "- Always explain your reasoning: which HTF anchor, why this direction, what confirms, what invalidates.\n"
            "- When a parent strategy returns NO_TRIGGER, still report the technical read: HTF anchors, selected anchor, LTF confirmation, blockers, and unlock condition.\n"
            "- When a parent strategy returns a valid setup, include the exact schedule_trade_entry args block, but do not execute unless the operator explicitly asks.\n\n"
            "OUTPUT FORMAT: Return JSON with keys: reply, tool_calls (optional), proposed_actions (optional), memory_notes (optional).\n"
            "Keep reply concise, evidence-backed, and execution-focused.\n\n"
            f"Identity: {identity_json}\n\n"
            f"{tools_section}"
        )
        if on_demand_mode:
            static_part = (
                "You are Workbench Agent running in compact local mode.\n"
                "Assume context is intentionally minimal. Fetch details on demand using tools before decisive analysis or trade actions.\n"
                "For market data detail, call get_market_snapshot and/or get_indicator_values.\n"
                "For position state, call get_positions_detail. For trigger state, call get_scheduled_triggers.\n"
                "Call get_market_news only when user explicitly asks for news/headlines/macro context.\n"
                "Respect permissions strictly and never fabricate executions or prices.\n"
                "Return JSON with keys reply, optional tool_calls, optional proposed_actions, optional memory_notes.\n"
                f"Locked Identity JSON: {identity_json}\n\n"
                f"{tools_section}"
            )
        dynamic_part = (
            f"Objective: {objective}\n"
            f"Permissions JSON: {perm_json}\n"
            f"Context JSON: {ctx_json}\n"
        )
        return static_part, dynamic_part

    def _system_prompt(
        self,
        context: Dict[str, Any],
        permissions: Dict[str, Any],
        objective: str = "",
        allowed_tool_names: Optional[List[str]] = None,
        include_tool_summaries: bool = True,
        on_demand_mode: bool = False,
        delta_context: Optional[Dict[str, Any]] = None,
    ) -> str:
        static_part, dynamic_part = self._system_prompt_parts(
            context=context,
            permissions=permissions,
            objective=objective,
            allowed_tool_names=allowed_tool_names,
            include_tool_summaries=include_tool_summaries,
            on_demand_mode=on_demand_mode,
            delta_context=delta_context,
        )
        return f"{static_part}\n{dynamic_part}"

    @staticmethod
    def _normalize_proposed_actions(raw: Any) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        if not isinstance(raw, list):
            return out
        for row in raw[:20]:
            if not isinstance(row, dict):
                continue
            raw_action_type = str(row.get("action_type") or "").strip().upper()
            action_type = _ACTION_TYPE_ALIASES.get(raw_action_type, raw_action_type)
            if not action_type:
                continue
            if action_type not in _ALLOWED_ACTION_TYPES:
                action_type = "REVIEW_NOTE"
            payload = row.get("payload") if isinstance(row.get("payload"), dict) else {}
            if raw_action_type and raw_action_type != action_type:
                payload = dict(payload)
                payload["_raw_action_type"] = raw_action_type
            out.append(
                {
                    "action_type": action_type,
                    "summary": str(row.get("summary") or "").strip()[:1000],
                    "payload": payload,
                    "confidence": max(0.0, min(1.0, _safe_float(row.get("confidence"), 0.0))),
                }
            )
        return out

    @staticmethod
    def _normalize_tool_calls(raw: Any) -> List[Dict[str, Any]]:
        out: List[Dict[str, Any]] = []
        if not isinstance(raw, list):
            return out
        for row in raw[:20]:
            if not isinstance(row, dict):
                continue
            name = str(row.get("name") or row.get("tool_id") or "").strip()
            if not name or (name not in _ALLOWED_TOOL_NAMES and name != _SUBMIT_PROPOSED_ACTIONS_TOOL):
                continue
            args = row.get("args")
            if not isinstance(args, dict):
                args = row.get("arguments") if isinstance(row.get("arguments"), dict) else {}
            out.append({"name": name, "args": args})
        return out

    @staticmethod
    def _extract_submitted_actions(args: Dict[str, Any]) -> List[Dict[str, Any]]:
        if not isinstance(args, dict):
            return []
        return WorkbenchAgent._normalize_proposed_actions(args.get("proposed_actions"))

    @staticmethod
    def _parse_final_payload(text: str) -> Tuple[str, List[Dict[str, Any]], List[Dict[str, Any]]]:
        obj = _extract_json_object(text)
        if isinstance(obj, dict):
            reply = str(obj.get("reply") or "").strip()
            actions = WorkbenchAgent._normalize_proposed_actions(obj.get("proposed_actions"))
            memory_notes = WorkbenchAgent._normalize_memory_notes(obj.get("memory_notes"))
            if reply:
                return reply, actions, memory_notes
            if actions or memory_notes:
                return "", actions, memory_notes
        reply_loose = _extract_reply_from_payload_like(text)
        if reply_loose:
            return reply_loose, [], []
        cleaned = _strip_embedded_agent_payload(text)
        return (cleaned or str(text or "").strip()), [], []

    @staticmethod
    def _fallback_text_from_tool_calls(tool_calls_log: List[Dict[str, Any]]) -> str:
        rows = tool_calls_log if isinstance(tool_calls_log, list) else []
        if not rows:
            return "I could not generate a final response in this turn."
        parts: List[str] = []
        for row in rows[-4:]:
            if not isinstance(row, dict):
                continue
            name = str(row.get("tool_id") or "").strip() or "tool"
            res = row.get("result") if isinstance(row.get("result"), dict) else {}
            ok = bool(res.get("ok")) if isinstance(res, dict) else False
            if ok:
                parts.append(f"{name}:ok")
            else:
                err = str(res.get("error") or "failed")[:80] if isinstance(res, dict) else "failed"
                parts.append(f"{name}:{err}")
        if not parts:
            return "I completed tool execution but did not generate a final response."
        return "Tool execution finished (" + ", ".join(parts) + "). Ask me to continue and I will summarize."

    @staticmethod
    def _parent_result_needs_auto_verification(tool_name: str, result: Dict[str, Any]) -> bool:
        name = str(tool_name or "").strip().lower()
        if name not in {"run_mtf_analysis", "run_htf_fvg_liquidity_reclaim_analysis"}:
            return False
        if not isinstance(result, dict) or bool(result.get("ok")) is False:
            return False
        data = result.get("data") if isinstance(result.get("data"), dict) else {}
        if not isinstance(data, dict) or not data:
            return False
        best_setup = data.get("best_setup") if isinstance(data.get("best_setup"), dict) else {}
        if best_setup:
            return False
        trace = data.get("analysis_trace") if isinstance(data.get("analysis_trace"), dict) else {}
        stage = str(trace.get("stage") or "").strip().lower()
        if stage in {
            "trigger_ready",
            "manual_confirmation_required",
            "open_position_exists",
            "duplicate_pending_trigger",
            "current_price_unavailable",
        }:
            return False
        if stage:
            return True
        return bool(data.get("trigger_ready") is False)

    @staticmethod
    def _run_auto_parent_verification(
        *,
        tool_calls_log: List[Dict[str, Any]],
        context: Dict[str, Any],
        tool_executor: ToolExecutor,
        allowed_tool_names: Optional[List[str]] = None,
    ) -> List[Dict[str, Any]]:
        if not isinstance(tool_calls_log, list) or not tool_calls_log:
            return []
        allow: Optional[set[str]] = None
        if isinstance(allowed_tool_names, list):
            allow = {
                str(name or "").strip().lower()
                for name in allowed_tool_names
                if str(name or "").strip()
            }

        def _tool_allowed(name: str) -> bool:
            if allow is None:
                return True
            return str(name or "").strip().lower() in allow

        if not _tool_allowed("scan_tool"):
            return []

        latest = tool_calls_log[-1] if isinstance(tool_calls_log[-1], dict) else {}
        tool_name = str(latest.get("tool_id") or "").strip()
        result = latest.get("result") if isinstance(latest.get("result"), dict) else {}
        if not WorkbenchAgent._parent_result_needs_auto_verification(tool_name, result):
            return []

        existing_keys = {
            f"{str((row if isinstance(row, dict) else {}).get('tool_id') or '').strip()}:{json.dumps(((row if isinstance(row, dict) else {}).get('args') if isinstance((row if isinstance(row, dict) else {}).get('args'), dict) else {}), sort_keys=True, ensure_ascii=True)}"
            for row in tool_calls_log
            if isinstance(row, dict)
        }

        data = result.get("data") if isinstance(result.get("data"), dict) else {}
        symbol = str(data.get("symbol") or context.get("symbol") or "XAUUSD").strip().upper() or "XAUUSD"
        execution_tf = str(data.get("execution_timeframe") or context.get("timeframe") or "M15").strip().upper() or "M15"
        scan_summary = data.get("scan_summary") if isinstance(data.get("scan_summary"), dict) else {}
        htf_tfs: List[str] = [tf for tf in ["D1", "H4"] if tf in scan_summary]
        if not htf_tfs:
            htf_tfs = ["D1", "H4"]

        candidates: List[Dict[str, Any]] = []
        for tf in htf_tfs:
            candidates.append(
                {
                    "name": "scan_tool",
                    "args": {
                        "tool_id": "fvg",
                        "timeframe": str(tf),
                        "lookback_days": 30,
                        "config": {
                            "timeframe": str(tf),
                            "show_filled": True,
                            "trend_filter_enabled": False,
                            "symbol": symbol,
                        },
                    },
                }
            )
        candidates.append(
            {
                "name": "scan_tool",
                "args": {
                    "tool_id": "liquidity",
                    "timeframe": execution_tf,
                    "lookback_days": 30,
                    "config": {
                        "timeframe": execution_tf,
                        "symbol": symbol,
                    },
                },
            }
        )
        if _tool_allowed("get_indicator_values"):
            candidates.append(
                {
                    "name": "get_indicator_values",
                    "args": {
                        "bars_limit": 300,
                        "timeframe": execution_tf,
                        "symbol": symbol,
                    },
                }
            )

        out: List[Dict[str, Any]] = []
        for row in candidates:
            name = str(row.get("name") or "").strip()
            args = row.get("args") if isinstance(row.get("args"), dict) else {}
            key = f"{name}:{json.dumps(args, sort_keys=True, ensure_ascii=True)}"
            if key in existing_keys:
                continue
            try:
                res = tool_executor(name, args)
            except Exception as exc:
                logger.warning("auto parent verification failed tool=%s err=%s", name, str(exc)[:180])
                res = {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}
            existing_keys.add(key)
            out.append({"tool_id": name, "args": args, "result": res})
        return out

    @staticmethod
    def _heuristic_tool_plan(
        message: str,
        context: Dict[str, Any],
        permissions: Dict[str, Any],
        allowed_tool_names: Optional[List[str]] = None,
    ) -> List[Dict[str, Any]]:
        plan: List[Dict[str, Any]] = []
        msg = str(message or "").lower()
        strategy_profile = str(context.get("agent_strategy_profile") or "").strip().lower()
        can_scan = bool(permissions.get("can_scan_tools", True))
        can_research = bool(permissions.get("can_use_research", False))
        can_manage_ind = bool(permissions.get("can_manage_indicators", True))
        can_place = bool(permissions.get("can_place_trades", False))
        can_close = bool(permissions.get("can_close_trades", False))
        requires_confirm = bool(permissions.get("requires_user_confirm_for_trade", True))
        allow: Optional[set[str]] = None
        if isinstance(allowed_tool_names, list):
            allow = {
                str(name or "").strip().lower()
                for name in allowed_tool_names
                if str(name or "").strip()
            }

        def _tool_allowed(name: str) -> bool:
            if allow is None:
                return True
            return str(name or "").strip().lower() in allow

        bars = context.get("bars") if isinstance(context.get("bars"), list) else []
        tool_state = context.get("tool_state") if isinstance(context.get("tool_state"), dict) else {}

        if _contains_any(msg, ["market snapshot", "market state", "current market", "price snapshot"]):
            plan.append(
                {
                    "name": "get_market_snapshot",
                    "args": {"bars_limit": 40, "include_bars": True, "include_indicators": True},
                }
            )

        if _contains_any(msg, ["open positions", "open trades", "position details", "recent trades", "portfolio status"]):
            plan.append(
                {
                    "name": "get_positions_detail",
                    "args": {"open_limit": 20, "recent_limit": 20},
                }
            )

        if _contains_any(msg, ["trigger", "scheduled entry", "pending trigger", "armed trigger"]):
            plan.append(
                {
                    "name": "get_scheduled_triggers",
                    "args": {"include_non_pending": False, "limit": 20},
                }
            )

        if _contains_any(msg, ["news", "headline", "calendar", "macro", "event risk", "economic release", "fomc", "cpi", "nfp"]):
            plan.append(
                {
                    "name": "get_market_news",
                    "args": {"limit": 5, "lookback_min": 240, "include_summary": True},
                }
            )

        if _contains_any(msg, ["how many trades", "trade count", "trades today", "win rate", "win ratio", "performance", "stats"]):
            plan.append(
                {
                    "name": "get_positions_detail",
                    "args": {"include_closed": True, "open_limit": 20, "recent_limit": 40},
                }
            )

        if _contains_any(msg, ["show triggers", "trigger status", "scheduled entries", "conditional entries", "any triggers"]):
            plan.append(
                {
                    "name": "get_scheduled_triggers",
                    "args": {"include_non_pending": True, "limit": 40},
                }
            )

        if _contains_any(msg, ["risk", "exposure", "how much am i risking", "risk level", "current risk"]):
            plan.append(
                {
                    "name": "get_positions_detail",
                    "args": {"open_limit": 20, "recent_limit": 20},
                }
            )
            plan.append(
                {
                    "name": "get_market_snapshot",
                    "args": {"bars_limit": 20, "include_bars": True, "include_indicators": True},
                }
            )

        if _contains_any(msg, ["summary", "status", "overview", "dashboard", "what's going on", "whats going on"]):
            plan.append(
                {
                    "name": "get_market_snapshot",
                    "args": {"bars_limit": 20, "include_bars": True, "include_indicators": True},
                }
            )
            plan.append(
                {
                    "name": "get_positions_detail",
                    "args": {"open_limit": 20, "recent_limit": 20},
                }
            )
            plan.append(
                {
                    "name": "get_scheduled_triggers",
                    "args": {"include_non_pending": True, "limit": 20},
                }
            )

        if _contains_any(msg, ["indicator", "rsi", "ema", "sma", "atr", "bollinger", "stoch", "adx"]):
            plan.append(
                {
                    "name": "get_indicator_values",
                    "args": {"bars_limit": 300},
                }
            )

        # FVG scan on draw-selection range.
        if can_scan and (
            _contains_any(msg, ["draw fvg", "selected bars", "between bars", "manual fvg", "scan selection"])
        ):
            picks = []
            draw_state = tool_state.get("draw_fvg") if isinstance(tool_state.get("draw_fvg"), dict) else {}
            if isinstance(draw_state.get("picks"), list):
                picks = [p for p in draw_state.get("picks") if isinstance(p, int)]
            i0 = picks[0] if len(picks) >= 1 else _extract_first_int(msg, [r"bar\s*#?\s*(\d+)"])
            i1 = picks[1] if len(picks) >= 2 else _extract_first_int(msg, [r"(?:to|and)\s*bar\s*#?\s*(\d+)"])
            if i0 is not None and i1 is not None and i0 != i1:
                plan.append(
                    {
                        "name": "scan_draw_fvg_range",
                        "args": {
                            "start_index": int(min(i0, i1)),
                            "end_index": int(max(i0, i1)),
                            "config": {},
                        },
                    }
                )

        mtf_fvg_request = (
            can_scan
            and _contains_any(msg, ["fvg", "fair value gap", "mitigation", "breaker", "reclaim"])
            and _contains_any(msg, ["multi-timeframe", "multi timeframe", "mtf", "d1", "h4", "m15", "m5", "higher timeframe"])
        )
        if can_scan and strategy_profile == "classic_htf_fvg" and _contains_any(msg, ["strategy", "setup", "analysis", "scan", "plan", "trade plan", "run active strategy", "active strategy"]):
            mtf_fvg_request = True
        liquidity_reclaim_request = (
            can_scan
            and _contains_any(msg, ["fvg", "fair value gap", "reclaim"])
            and _contains_any(msg, ["liquidity", "sweep", "liquidity reclaim", "sweep reclaim", "liq reclaim"])
        )
        if can_scan and strategy_profile == "htf_fvg_liquidity_reclaim_v2" and _contains_any(msg, ["strategy", "setup", "analysis", "scan", "plan", "trade plan", "run active strategy", "active strategy"]):
            liquidity_reclaim_request = True
        classic_parent_allowed = can_scan and _tool_allowed("run_mtf_analysis")
        liquidity_parent_allowed = can_scan and _tool_allowed("run_htf_fvg_liquidity_reclaim_analysis")
        raw_verify_request = can_scan and _contains_any(
            msg,
            [
                "verify",
                "audit",
                "raw scan",
                "why blocked",
                "why no trigger",
                "block or not",
                "technical detail",
                "technical analysis",
            ],
        )
        if mtf_fvg_request:
            if liquidity_reclaim_request and liquidity_parent_allowed:
                plan.append(
                    {
                        "name": "run_htf_fvg_liquidity_reclaim_analysis",
                        "args": {
                            "execution_timeframe": "M15",
                            "preset": str(context.get("agent_strategy_preset") or "default"),
                            "include_news": False,
                        },
                    }
                )
            elif classic_parent_allowed:
                plan.append(
                    {
                        "name": "run_mtf_analysis",
                        "args": {
                            "execution_timeframe": "M15",
                            "htf_timeframes": ["D1", "H4"],
                            "risk_percent": 0.5,
                            "rr_target": 2.0,
                            "include_news": False,
                        },
                    }
                )
            elif liquidity_parent_allowed:
                plan.append(
                    {
                        "name": "run_htf_fvg_liquidity_reclaim_analysis",
                        "args": {
                            "execution_timeframe": "M15",
                            "preset": str(context.get("agent_strategy_preset") or "default"),
                            "include_news": False,
                        },
                    }
                )
        elif liquidity_reclaim_request and liquidity_parent_allowed:
            plan.append(
                {
                    "name": "run_htf_fvg_liquidity_reclaim_analysis",
                    "args": {
                        "execution_timeframe": "M15",
                        "preset": str(context.get("agent_strategy_preset") or "default"),
                        "include_news": False,
                    },
                }
            )
        if raw_verify_request and can_scan and _tool_allowed("scan_tool"):
            for tf in ["D1", "H4"]:
                plan.append(
                    {
                        "name": "scan_tool",
                        "args": {
                            "tool_id": "fvg",
                            "timeframe": tf,
                            "config": {"timeframe": tf, "show_filled": True, "trend_filter_enabled": False},
                        },
                    }
                )
            plan.append(
                {
                    "name": "scan_tool",
                    "args": {
                        "tool_id": "liquidity",
                        "timeframe": str(context.get("timeframe") or "M15"),
                        "config": {"timeframe": str(context.get("timeframe") or "M15")},
                    },
                }
            )
        if can_scan and (not mtf_fvg_request) and (not liquidity_reclaim_request) and ("fvg" in msg or ("scan" in msg and "gap" in msg)):
            plan.append(
                {
                    "name": "scan_tool",
                    "args": {
                        "tool_id": "fvg",
                        "config": {},
                        "bars": bars[:12000],
                    },
                }
            )
        if can_scan and ("mean reversion" in msg or "mean-rev" in msg or "mean rev" in msg):
            plan.append(
                {
                    "name": "scan_tool",
                    "args": {
                        "tool_id": "mean_rev",
                        "config": {},
                        "bars": bars[:12000],
                    },
                }
            )
        if can_scan and _contains_any(msg, ["liquidity", "liquidity sweep", "equal highs", "equal lows", "stop hunt", "sweep"]):
            plan.append(
                {
                    "name": "scan_tool",
                    "args": {
                        "tool_id": "liquidity",
                        "config": {},
                        "bars": bars[:12000],
                    },
                }
            )

        if can_research and _contains_any(msg, ["optimize", "optimizer", "best parameters", "grid search"]):
            strategy_type = "mean_reversion" if _contains_any(msg, ["mean reversion", "mean-rev", "mean rev"]) else "sma_crossover"
            plan.append(
                {
                    "name": "run_research_optimize",
                    "args": {
                        "strategy_type": strategy_type,
                        "params": {},
                        "top_n": 10,
                        "max_combinations": 2500,
                        "bars": bars[:12000],
                    },
                }
            )

        if can_research and _contains_any(msg, ["ml diagnostic", "feature drift", "drift check", "ml drift", "feature hygiene"]):
            plan.append(
                {
                    "name": "run_ml_diagnostic",
                    "args": {
                        "lags": 5,
                        "split_ratio": 0.7,
                        "drift_warn_pct": 50.0,
                        "params": {},
                        "bars": bars[:12000],
                    },
                }
            )

        if can_manage_ind and _contains_any(msg, ["indicator", "show", "hide", "enable", "disable", "turn on", "turn off"]):
            current = context.get("indicators") if isinstance(context.get("indicators"), dict) else {}
            enabled = current.get("enabled") if isinstance(current.get("enabled"), dict) else {}
            vis = {
                "smaEma": bool(enabled.get("smaEma", True)),
                "adx": bool(enabled.get("adx", True)),
                "rsi": bool(enabled.get("rsi", True)),
                "stoch": bool(enabled.get("stoch", True)),
                "bollinger": bool(enabled.get("bollinger", True)),
                "goldenCross": bool(enabled.get("goldenCross", True)),
            }
            if _contains_any(msg, ["hide all indicators", "disable all indicators"]):
                for k in list(vis.keys()):
                    vis[k] = False
            if _contains_any(msg, ["show all indicators", "enable all indicators"]):
                for k in list(vis.keys()):
                    vis[k] = True

            indicator_terms = {
                "smaEma": ["sma", "ema", "moving average"],
                "adx": ["adx"],
                "rsi": ["rsi"],
                "stoch": ["stoch", "stochastic"],
                "bollinger": ["bollinger", "bb "],
                "goldenCross": ["golden cross", "death cross", "cross marker"],
            }
            has_indicator_context = _contains_any(msg, ["indicator"]) or any(
                any(w in msg for w in words) for words in indicator_terms.values()
            )
            changed = False
            if has_indicator_context:
                for key, words in indicator_terms.items():
                    has_term = any(w in msg for w in words)
                    if not has_term:
                        continue
                    term_pat = "(" + "|".join([re.escape(w) for w in words]) + ")"
                    hide_re = re.search(rf"(hide|disable|turn off)\s+{term_pat}", msg, flags=re.IGNORECASE)
                    hide_re = hide_re or re.search(rf"{term_pat}\s+(?:is\s+)?(hidden|off|disabled)", msg, flags=re.IGNORECASE)
                    show_re = re.search(rf"(show|enable|turn on)\s+{term_pat}", msg, flags=re.IGNORECASE)
                    show_re = show_re or re.search(rf"{term_pat}\s+(?:is\s+)?(shown|on|enabled)", msg, flags=re.IGNORECASE)
                    if hide_re and not show_re:
                        vis[key] = False
                        changed = True
                    elif show_re and not hide_re:
                        vis[key] = True
                        changed = True
                if changed or _contains_any(msg, ["hide all indicators", "disable all indicators", "show all indicators", "enable all indicators"]):
                    plan.append({"name": "set_indicator_visibility", "args": {"visibility": vis}})

        # Market/timeframe/source switch intents.
        if _contains_any(msg, ["timeframe", "tf", "symbol", "market"]) and _contains_any(msg, ["switch", "change", "set", "move", "use"]):
            tf_match = re.search(r"\b(m1|m5|m15|m30|h1|h4|d1)\b", msg, flags=re.IGNORECASE)
            sym_match = re.search(r"\b(xauusd|nas100|us500|gbpusd|eurusd)\b", msg, flags=re.IGNORECASE)
            days = _extract_first_number(
                msg,
                [
                    r"(?:lookback|window|last)\s*(\d+(?:\.\d+)?)\s*day",
                    r"(\d+(?:\.\d+)?)\s*d(?:ay|ays)?\b",
                ],
            )
            source = None
            if _contains_any(msg, ["databento"]):
                source = "databento"
            elif _contains_any(msg, ["mt5", "metatrader", "meta trader"]):
                source = "mt5"
            switch_args: Dict[str, Any] = {}
            if sym_match:
                switch_args["symbol"] = str(sym_match.group(1) or "").upper()
            if tf_match:
                switch_args["timeframe"] = str(tf_match.group(1) or "").upper()
            if source:
                switch_args["source"] = source
            if days is not None:
                switch_args["history_days"] = float(days)
            if switch_args:
                plan.append({"name": "set_market_context", "args": switch_args})

        # Identity/personality profile switching.
        if _contains_any(msg, ["personality", "persona", "identity", "profile", "master", "apprentice"]) and _contains_any(msg, ["switch", "change", "set", "use"]):
            profile = None
            if _contains_any(msg, ["master", "master_quant", "quant", "pro"]):
                profile = "master_quant"
            elif _contains_any(msg, ["apprentice", "basic", "default"]):
                profile = "apprentice"
            if profile:
                plan.append({"name": "set_agent_personality", "args": {"profile": profile}})

        scheduled_trade_added = False
        condition = None
        trigger_price = None
        precondition: Optional[Dict[str, Any]] = None
        cancel_condition = None
        cancel_trigger_price = None
        if can_place:
            level_pat = r"([\d,]+(?:\.\d+)?)"

            def _parse_level(raw: Any) -> Optional[float]:
                txt = str(raw or "").replace(",", "").strip()
                if not txt:
                    return None
                try:
                    val = float(txt)
                except Exception:
                    return None
                if not math.isfinite(val) or val <= 0.0:
                    return None
                return float(val)

            two_step_clause = rf"(?:(price)|(?:candle\s+close|close(?!\s+trade(?:\s|$))))\s+(?:to\s+)?(below|above)\s+{level_pat}"
            two_step_re = rf"{two_step_clause}.{{0,120}}?(?:then|and\s+then|->)\s*{two_step_clause}"
            m2 = re.search(two_step_re, msg, flags=re.IGNORECASE)
            if m2:
                is_price_1 = bool(m2.group(1))
                dir_1 = str(m2.group(2) or "").lower()
                px_1 = _parse_level(m2.group(3))
                is_price_2 = bool(m2.group(4))
                dir_2 = str(m2.group(5) or "").lower()
                px_2 = _parse_level(m2.group(6))
                if px_1 is not None and px_2 is not None and dir_1 in {"below", "above"} and dir_2 in {"below", "above"}:
                    precondition = {
                        "condition": f"{'price' if is_price_1 else 'close'}_{dir_1}",
                        "trigger_price": float(px_1),
                    }
                    condition = f"{'price' if is_price_2 else 'close'}_{dir_2}"
                    trigger_price = float(px_2)
            trigger_patterns = [
                (rf"(?:candle\s+close|close(?!\s+trade(?:\s|$)))\s+below\s+{level_pat}", "close_below"),
                (rf"(?:candle\s+close|close(?!\s+trade(?:\s|$)))\s+above\s+{level_pat}", "close_above"),
                (rf"(?:if|when)\s+price\s+(?:is\s+)?below\s+{level_pat}", "price_below"),
                (rf"(?:if|when)\s+price\s+(?:is\s+)?above\s+{level_pat}", "price_above"),
                (rf"(?:wait|waiting)\s+for\s+price\s+(?:to\s+be\s+|to\s+go\s+|to\s+)?below\s+{level_pat}", "price_below"),
                (rf"(?:wait|waiting)\s+for\s+price\s+(?:to\s+be\s+|to\s+go\s+|to\s+)?above\s+{level_pat}", "price_above"),
                (rf"(?:wait|waiting)\s+for\s+(?:a\s+)?close\s+below\s+{level_pat}", "close_below"),
                (rf"(?:wait|waiting)\s+for\s+(?:a\s+)?close\s+above\s+{level_pat}", "close_above"),
            ]
            if condition is None:
                for pat, cond in trigger_patterns:
                    m = re.search(pat, msg, flags=re.IGNORECASE)
                    if not m:
                        continue
                    trigger_price = _parse_level(m.group(1))
                    condition = cond
                    break
            cancel_patterns = [
                (rf"(?:cancel|invalidate)\s+(?:the\s+trigger\s+)?(?:if|when)\s+(?:a\s+)?(?:candle\s+close|close(?!\s+trade(?:\s|$)))\s+below\s+{level_pat}", "close_below"),
                (rf"(?:cancel|invalidate)\s+(?:the\s+trigger\s+)?(?:if|when)\s+(?:a\s+)?(?:candle\s+close|close(?!\s+trade(?:\s|$)))\s+above\s+{level_pat}", "close_above"),
                (rf"(?:cancel|invalidate)\s+(?:the\s+trigger\s+)?(?:if|when)\s+price\s+(?:is\s+)?below\s+{level_pat}", "price_below"),
                (rf"(?:cancel|invalidate)\s+(?:the\s+trigger\s+)?(?:if|when)\s+price\s+(?:is\s+)?above\s+{level_pat}", "price_above"),
            ]
            for pat, cond in cancel_patterns:
                m = re.search(pat, msg, flags=re.IGNORECASE)
                if not m:
                    continue
                cancel_trigger_price = _parse_level(m.group(1))
                cancel_condition = cond
                break
            if condition and trigger_price is not None and trigger_price > 0:
                direction = "BUY" if any(_contains_word(msg, w) for w in ["buy", "long"]) else ("SELL" if any(_contains_word(msg, w) for w in ["sell", "short"]) else "")
                sl = _extract_first_number(
                    msg,
                    [r"(?:\bsl\b|stop(?:\s*loss)?)\s*[:=]?\s*(\d+(?:\.\d+)?)"],
                )
                tp = _extract_first_number(msg, [r"(?:\btp\b|take(?:\s*profit)?)\s*[:=]?\s*(\d+(?:\.\d+)?)"])
                lot = _extract_first_number(msg, [r"(?:\blot(?:_size)?\b|size)\s*[:=]?\s*(\d+(?:\.\d+)?)"])
                tf_match = re.search(r"\b(m1|m5|m15|m30|h1|h4|d1)\b", msg, flags=re.IGNORECASE)
                if direction and sl is not None and float(sl) > 0.0:
                    lot_value = float(lot if lot is not None else 0.01)
                    if lot_value <= 0.0:
                        lot_value = 0.01
                    s_args: Dict[str, Any] = {
                        "condition": condition,
                        "trigger_price": float(trigger_price),
                        "direction": direction,
                        "stop_loss": float(sl),
                        "lot_size": lot_value,
                    }
                    if tp is not None:
                        s_args["take_profit"] = float(tp)
                    if tf_match:
                        s_args["timeframe"] = str(tf_match.group(1) or "").upper()
                    if isinstance(precondition, dict):
                        s_args["precondition"] = {
                            "condition": str(precondition.get("condition") or ""),
                            "trigger_price": float(precondition.get("trigger_price")),
                        }
                    if cancel_condition and cancel_trigger_price is not None:
                        s_args["cancel_rule"] = {
                            "condition": str(cancel_condition),
                            "trigger_price": float(cancel_trigger_price),
                        }
                    plan.append({"name": "schedule_trade_entry", "args": s_args})
                    scheduled_trade_added = True

        if can_place and _contains_any(msg, ["cancel trigger", "cancel scheduled", "cancel pending trigger", "cancel all triggers"]):
            trigger_id = _extract_first_int(
                msg,
                [
                    r"(?:trigger)\s*#?\s*(\d+)",
                    r"\bid\s*[:=]?\s*(\d+)",
                ],
            )
            c_args: Dict[str, Any] = {}
            if trigger_id is not None:
                c_args["trigger_id"] = str(trigger_id)
            else:
                c_args["cancel_all"] = True
            plan.append({"name": "cancel_scheduled_entry", "args": c_args})

        trade_intent = _contains_any(
            msg,
            ["open trade", "enter trade", "place trade", "execute trade", "open position", "enter position"],
        )
        if not trade_intent:
            has_dir_word = any(_contains_word(msg, w) for w in ["buy", "sell", "long", "short"])
            trade_intent = (
                has_dir_word
                and (_contains_word(msg, "sl") or _contains_any(msg, ["stop loss", "stop_loss"]))
                and not _contains_any(msg, ["should i", "can i", "do i", "would", "if i", "?"])
            )
        if can_place and (not scheduled_trade_added) and trade_intent and _contains_any(msg, ["buy", "sell", "long", "short"]):
            direction = "BUY" if any(_contains_word(msg, w) for w in ["buy", "long"]) else ("SELL" if any(_contains_word(msg, w) for w in ["sell", "short"]) else "")
            if direction:
                sl = _extract_first_number(
                    msg,
                    [
                        r"(?:\bsl\b|stop(?:\s*loss)?)\s*[:=]?\s*(\d+(?:\.\d+)?)",
                    ],
                )
                tp = _extract_first_number(msg, [r"(?:\btp\b|take(?:\s*profit)?)\s*[:=]?\s*(\d+(?:\.\d+)?)"])
                lot = _extract_first_number(msg, [r"(?:\blot(?:_size)?\b|size)\s*[:=]?\s*(\d+(?:\.\d+)?)"])
                entry = _extract_first_number(msg, [r"(?:entry|price)\s*[:=]?\s*(\d+(?:\.\d+)?)"])
                if sl is not None and float(sl) > 0.0:
                    lot_value = float(lot if lot is not None else 0.01)
                    if lot_value <= 0.0:
                        lot_value = 0.01
                    args: Dict[str, Any] = {
                        "direction": direction,
                        "stop_loss": float(sl),
                        "lot_size": lot_value,
                    }
                    if tp is not None:
                        args["take_profit"] = float(tp)
                    if entry is not None:
                        args["entry_price"] = float(entry)
                    plan.append({"name": "place_trade", "args": args})

        if can_close and _contains_any(msg, ["close trade", "exit trade", "flatten position", "close position"]):
            trade_id = _extract_first_int(
                msg,
                [
                    r"(?:trade|position)\s*#?\s*(\d+)",
                ],
            )
            if trade_id is None:
                open_positions = context.get("open_positions") if isinstance(context.get("open_positions"), list) else []
                if open_positions and isinstance(open_positions[0], dict) and open_positions[0].get("id") is not None:
                    try:
                        trade_id = int(open_positions[0].get("id"))
                    except Exception:
                        trade_id = None
            if trade_id is not None:
                exit_price = _extract_first_number(msg, [r"(?:exit|price)\s*[:=]?\s*(-?\d+(?:\.\d+)?)"])
                args = {"trade_id": int(trade_id)}
                if exit_price is not None:
                    args["exit_price"] = float(exit_price)
                plan.append({"name": "close_trade", "args": args})

        deduped: List[Dict[str, Any]] = []
        seen: set[str] = set()
        for row in plan:
            if not isinstance(row, dict):
                continue
            name = str(row.get("name") or "").strip()
            args = row.get("args") if isinstance(row.get("args"), dict) else {}
            if not name or (not _tool_allowed(name)):
                continue
            key = f"{name}:{json.dumps(args, sort_keys=True, ensure_ascii=True)}"
            if key in seen:
                continue
            seen.add(key)
            deduped.append({"name": name, "args": args})
        return deduped

    def _chat_deterministic(
        self,
        message: str,
        context: Dict[str, Any],
        permissions: Dict[str, Any],
        tool_executor: ToolExecutor,
        allow_tools: bool,
        max_tool_steps: int,
        allowed_tool_names: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        tool_calls_log: List[Dict[str, Any]] = []
        if allow_tools and int(max_tool_steps) > 0:
            plan = self._heuristic_tool_plan(
                message=message,
                context=context,
                permissions=permissions,
                allowed_tool_names=allowed_tool_names,
            )
            for row in plan[: int(max_tool_steps)]:
                name = str(row.get("name") or "")
                args = row.get("args") if isinstance(row.get("args"), dict) else {}
                try:
                    result = tool_executor(name, args)
                except Exception as exc:
                    logger.warning("deterministic tool execution failed tool=%s err=%s", name, str(exc)[:180])
                    result = {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}
                tool_calls_log.append({"tool_id": name, "args": args, "result": result})
                extra_rows = self._run_auto_parent_verification(
                    tool_calls_log=tool_calls_log,
                    context=context,
                    tool_executor=tool_executor,
                    allowed_tool_names=allowed_tool_names,
                )
                if extra_rows:
                    tool_calls_log.extend(extra_rows)

        latest = tool_calls_log[-1]["result"] if tool_calls_log else {}
        zones_count = None
        if isinstance(latest, dict):
            zones_count = latest.get("count")
            if zones_count is None and isinstance(latest.get("data"), dict):
                zones_count = latest["data"].get("count")
        reply = "I reviewed your request."
        if zones_count is not None:
            reply = f"I scanned the chart and found {int(zones_count)} zones."
        reply += " I prepared an execution-focused plan from current context and tool outputs."
        return {
            "ok": True,
            "reply": reply,
            "tool_calls": tool_calls_log,
            "proposed_actions": [],
            "memory_notes": [],
            "raw_text": reply,
            "usage": _usage_finalize(_usage_empty("deterministic", "deterministic")),
        }

    def _chat_local_gptoss(
        self,
        message: str,
        system_prompt: str,
        model_label: str,
        llm_url: str,
        timeout_sec: int,
        max_tokens: int = 1200,
    ) -> Tuple[str, Dict[str, Any]]:
        url = f"{str(llm_url).rstrip('/')}/chat"
        mtok = max(120, min(1200, int(max_tokens or 1200)))
        payload = {
            "system": system_prompt,
            "message": f"MODEL={model_label}\nUSER:\n{message}",
            "temperature": 0.2,
            "max_tokens": mtok,
        }
        effective_read_timeout = max(90, int(timeout_sec or 0))
        timeout_obj = httpx.Timeout(
            connect=10.0,
            read=float(effective_read_timeout),
            write=30.0,
            pool=10.0,
        )
        resp: Optional[httpx.Response] = None
        last_exc: Optional[Exception] = None
        for attempt in range(1, 3):
            try:
                with httpx.Client(
                    timeout=timeout_obj,
                    limits=httpx.Limits(max_keepalive_connections=0, max_connections=10),
                    http2=False,
                ) as client:
                    resp = client.post(url, json=payload)
                break
            except (httpx.ReadTimeout, httpx.TimeoutException, httpx.TransportError) as exc:
                last_exc = exc
                if attempt < 2:
                    logger.warning(
                        "local_gptoss transport timeout attempt %s/2: %s",
                        attempt,
                        _redact_error_text(str(exc)),
                    )
                    _sleep_backoff(attempt, base_sec=0.5, cap_sec=1.5)
                    continue
        if resp is None:
            if last_exc is not None:
                raise RuntimeError(f"local_gptoss_http timeout/transport error: {_redact_error_text(str(last_exc))}")
            raise RuntimeError("local_gptoss_http failed: no response")
        if resp.status_code != 200:
            detail = _redact_error_text((resp.text or "")[:300]) if getattr(resp, "text", None) else ""
            logger.warning("local_gptoss_http HTTP %s: %s", resp.status_code, detail)
            raise RuntimeError(f"local_gptoss_http failed: HTTP {resp.status_code}: {detail}")
        body = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
        if isinstance(body, dict) and str(body.get("reply") or "").strip():
            reply = str(body.get("reply")).strip()
            usage = _usage_empty("local_gptoss_http", str(model_label or ""))
            usage["api_calls"] = 1
            usage["input_tokens"] = _estimate_usage_tokens_from_text(payload.get("system"), payload.get("message"))
            usage["output_tokens"] = _estimate_usage_tokens_from_text(reply)
            return reply, _usage_finalize(usage)
        raw_text = str(resp.text or "").strip()
        usage = _usage_empty("local_gptoss_http", str(model_label or ""))
        usage["api_calls"] = 1
        usage["input_tokens"] = _estimate_usage_tokens_from_text(payload.get("system"), payload.get("message"))
        usage["output_tokens"] = _estimate_usage_tokens_from_text(raw_text)
        return raw_text, _usage_finalize(usage)

    def _chat_local_gptoss_with_tools(
        self,
        *,
        message: str,
        context: Dict[str, Any],
        history: List[Dict[str, str]],
        system_prompt: str,
        model_label: str,
        llm_url: str,
        timeout_sec: int,
        tool_executor: ToolExecutor,
        allow_tools: bool,
        max_tool_steps: int,
        allowed_tool_names: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        def _coerce_local_chat_result(raw: Any, prompt_text: str) -> Tuple[str, Dict[str, Any]]:
            if isinstance(raw, tuple) and len(raw) == 2:
                text = str(raw[0] or "")
                usage = raw[1] if isinstance(raw[1], dict) else {}
                return text, _usage_finalize(usage)
            text = str(raw or "")
            usage = _usage_empty("local_gptoss_http", str(model_label or ""))
            usage["api_calls"] = 1
            usage["input_tokens"] = _estimate_usage_tokens_from_text(system_prompt, prompt_text)
            usage["output_tokens"] = _estimate_usage_tokens_from_text(text)
            return text, _usage_finalize(usage)

        def _invoke_local(prompt_text: str, max_tokens: int) -> Any:
            call_kwargs: Dict[str, Any] = {
                "message": prompt_text,
                "system_prompt": system_prompt,
                "model_label": model_label,
                "llm_url": llm_url,
                "timeout_sec": timeout_sec,
                "max_tokens": int(max_tokens),
            }
            try:
                return self._chat_local_gptoss(**call_kwargs)
            except TypeError as exc:
                # Backward-compatible fallback for tests/mocks or older adapters that
                # do not accept max_tokens.
                msg = str(exc or "")
                if "max_tokens" in msg and "unexpected keyword argument" in msg:
                    call_kwargs.pop("max_tokens", None)
                    return self._chat_local_gptoss(**call_kwargs)
                raise

        history_block = ""
        if isinstance(history, list) and history:
            hist_rows = []
            for h in history[-6:]:
                if not isinstance(h, dict):
                    continue
                role = str(h.get("role") or "").strip().lower()
                if role not in {"user", "assistant"}:
                    continue
                txt = str(h.get("content") or "").strip()[:300]
                if not txt:
                    continue
                hist_rows.append(f"{role.upper()}: {txt}")
            if hist_rows:
                history_block = "Conversation history:\n" + "\n".join(hist_rows) + "\n\n"
        first_user_prompt = f"{history_block}USER:\n{message}"

        # Pass 1: let the model propose tool calls (if needed) and/or direct response.
        usage_total = _usage_empty("local_gptoss_http", str(model_label or ""))
        first_raw = _invoke_local(first_user_prompt, 420)
        first_text, usage_first = _coerce_local_chat_result(first_raw, first_user_prompt)
        _usage_add(usage_total, usage_first)
        usage_total["api_calls"] = int(_safe_int(usage_total.get("api_calls"), 0) + _safe_int(usage_first.get("api_calls"), 0))
        tool_calls_log: List[Dict[str, Any]] = []
        first_obj = _extract_json_object(first_text)
        requested_calls = self._normalize_tool_calls(
            first_obj.get("tool_calls") if isinstance(first_obj, dict) else None
        )
        if allowed_tool_names:
            allow = {str(x or "").strip() for x in allowed_tool_names if str(x or "").strip()}
            requested_calls = [x for x in requested_calls if str(x.get("name") or "").strip() in allow]
        submitted_actions: List[Dict[str, Any]] = []
        used_external_tools = False

        if allow_tools and requested_calls:
            for row in requested_calls[: max(0, int(max_tool_steps))]:
                name = str(row.get("name") or "").strip()
                args = row.get("args") if isinstance(row.get("args"), dict) else {}
                if name == _SUBMIT_PROPOSED_ACTIONS_TOOL:
                    submitted = self._extract_submitted_actions(args)
                    submitted_actions.extend(submitted)
                    result = {
                        "ok": True,
                        "accepted": int(len(submitted)),
                        "action_types": [str(a.get("action_type") or "") for a in submitted],
                    }
                else:
                    try:
                        result = tool_executor(name, args)
                        used_external_tools = True
                    except Exception as exc:
                        logger.warning("local_gptoss tool execution failed tool=%s err=%s", name, str(exc)[:180])
                        result = {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}
                tool_calls_log.append({"tool_id": name, "args": args, "result": result})

            extra_rows = self._run_auto_parent_verification(
                tool_calls_log=tool_calls_log,
                context=context,
                tool_executor=tool_executor,
                allowed_tool_names=allowed_tool_names,
            )
            if extra_rows:
                tool_calls_log.extend(extra_rows)
                used_external_tools = True

            if used_external_tools:
                # Pass 2: provide tool results and ask for final response/proposals.
                tool_result_json = json.dumps(tool_calls_log, ensure_ascii=True)
                second_prompt = (
                    f"Original user request:\n{message}\n\n"
                    f"Executed tool results JSON:\n{tool_result_json}\n\n"
                    "Now provide final reply, proposed_actions, and optional memory_notes as JSON."
                )
                second_raw = _invoke_local(second_prompt, 800)
                second_text, usage_second = _coerce_local_chat_result(second_raw, second_prompt)
                _usage_add(usage_total, usage_second)
                usage_total["api_calls"] = int(_safe_int(usage_total.get("api_calls"), 0) + _safe_int(usage_second.get("api_calls"), 0))
                reply, actions, memory_notes = self._parse_final_payload(second_text)
                final_actions = submitted_actions if submitted_actions else actions
                return {
                    "ok": True,
                    "reply": reply or second_text,
                    "tool_calls": tool_calls_log,
                    "proposed_actions": final_actions,
                    "memory_notes": memory_notes,
                    "raw_text": second_text,
                    "usage": _usage_finalize(usage_total),
                }

        reply, actions, memory_notes = self._parse_final_payload(first_text)
        final_actions = submitted_actions if submitted_actions else actions
        return {
            "ok": True,
            "reply": reply or first_text,
            "tool_calls": tool_calls_log,
            "proposed_actions": final_actions,
            "memory_notes": memory_notes,
            "raw_text": first_text,
            "usage": _usage_finalize(usage_total),
        }

    def _chat_openai_with_tools(
        self,
        *,
        message: str,
        context: Dict[str, Any],
        system_prompt: str,
        history: List[Dict[str, str]],
        model_label: str,
        llm_url: str,
        api_key: str,
        timeout_sec: int,
        tool_executor: ToolExecutor,
        allow_tools: bool,
        max_tool_steps: int,
        allowed_tool_names: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        base = str(llm_url).strip().rstrip("/")
        url = f"{base}/chat/completions"
        tools = [{"type": "function", "function": t} for t in self._tool_specs_filtered(allowed_tool_names)] if allow_tools else []
        messages: List[Dict[str, Any]] = [{"role": "system", "content": system_prompt}]
        messages.extend(history)
        messages.append({"role": "user", "content": message})
        tool_calls_log: List[Dict[str, Any]] = []
        final_text = ""
        submitted_actions: List[Dict[str, Any]] = []
        usage_total = _usage_empty("openai_compat", str(model_label or ""))

        with httpx.Client(timeout=float(timeout_sec)) as client:
            for _ in range(max(0, int(max_tool_steps)) + 1):
                payload = {
                    "model": model_label,
                    "temperature": 0.2,
                    "max_tokens": 1200,
                    "messages": messages,
                }
                if tools:
                    payload["tools"] = tools
                resp = client.post(
                    url,
                    headers={
                        "Authorization": f"Bearer {api_key}",
                        "Content-Type": "application/json",
                    },
                    json=payload,
                )
                if resp.status_code != 200:
                    detail = _redact_error_text((resp.text or "")[:300]) if getattr(resp, "text", None) else ""
                    logger.warning("openai_compat HTTP %s: %s", resp.status_code, detail)
                    raise RuntimeError(f"openai_compat failed: HTTP {resp.status_code}: {detail}")
                body = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
                usage_total["api_calls"] = int(_safe_int(usage_total.get("api_calls"), 0) + 1)
                _usage_add(usage_total, _usage_extract_openai(body))
                choice = ((body.get("choices") or [{}])[0]) if isinstance(body, dict) else {}
                msg_obj = choice.get("message") if isinstance(choice, dict) else {}
                if not isinstance(msg_obj, dict):
                    break
                tcalls = msg_obj.get("tool_calls") if isinstance(msg_obj.get("tool_calls"), list) else []
                if not tcalls:
                    final_text = str(msg_obj.get("content") or "").strip()
                    break
                messages.append(msg_obj)
                for tc in tcalls:
                    tc_id = str(tc.get("id") or "")
                    fn = tc.get("function") if isinstance(tc.get("function"), dict) else {}
                    name = str(fn.get("name") or "").strip()
                    raw_args = str(fn.get("arguments") or "{}")
                    try:
                        args = json.loads(raw_args) if raw_args else {}
                    except Exception:
                        args = {}
                    try:
                        if name == _SUBMIT_PROPOSED_ACTIONS_TOOL:
                            submitted = self._extract_submitted_actions(args)
                            submitted_actions.extend(submitted)
                            result = {
                                "ok": True,
                                "accepted": int(len(submitted)),
                                "action_types": [str(a.get("action_type") or "") for a in submitted],
                            }
                        elif name not in _ALLOWED_TOOL_NAMES:
                            result = {"ok": False, "error": f"disallowed_tool:{name}"}
                        else:
                            result = tool_executor(name, args)
                    except Exception as exc:
                        logger.warning("openai tool execution failed tool=%s err=%s", name, str(exc)[:180])
                        result = {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}
                    tool_calls_log.append({"tool_id": name, "args": args, "result": result})
                    messages.append(
                        {
                            "role": "tool",
                            "tool_call_id": tc_id,
                            "content": json.dumps(result, ensure_ascii=True),
                        }
                    )
                extra_rows = self._run_auto_parent_verification(
                    tool_calls_log=tool_calls_log,
                    context=context,
                    tool_executor=tool_executor,
                    allowed_tool_names=allowed_tool_names,
                )
                if extra_rows:
                    tool_calls_log.extend(extra_rows)
                    messages.append(
                        {
                            "role": "user",
                            "content": (
                                "Automatic verification scans were executed because the parent strategy returned a negative "
                                "or sparse result. Treat these tool outputs as authoritative evidence for the final analysis.\n\n"
                                + json.dumps(extra_rows, ensure_ascii=True)
                            ),
                        }
                    )
            if not final_text and tool_calls_log:
                messages.append(
                    {
                        "role": "user",
                        "content": "Now provide the final JSON reply/proposed_actions for the trader. Do not call tools in this step.",
                    }
                )
                payload = {
                    "model": model_label,
                    "temperature": 0.2,
                    "max_tokens": 1200,
                    "messages": messages,
                }
                resp = client.post(
                    url,
                    headers={
                        "Authorization": f"Bearer {api_key}",
                        "Content-Type": "application/json",
                    },
                    json=payload,
                )
                if resp.status_code == 200:
                    body = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
                    usage_total["api_calls"] = int(_safe_int(usage_total.get("api_calls"), 0) + 1)
                    _usage_add(usage_total, _usage_extract_openai(body))
                    choice = ((body.get("choices") or [{}])[0]) if isinstance(body, dict) else {}
                    msg_obj = choice.get("message") if isinstance(choice, dict) else {}
                    if isinstance(msg_obj, dict):
                        final_text = str(msg_obj.get("content") or "").strip()
            if not final_text:
                final_text = self._fallback_text_from_tool_calls(tool_calls_log)

        reply, actions, memory_notes = self._parse_final_payload(final_text)
        final_actions = submitted_actions if submitted_actions else actions
        return {
            "ok": True,
            "reply": reply or final_text,
            "tool_calls": tool_calls_log,
            "proposed_actions": final_actions,
            "memory_notes": memory_notes,
            "raw_text": final_text,
            "usage": _usage_finalize(usage_total),
        }

    def _chat_claude_with_tools(
        self,
        *,
        message: str,
        context: Dict[str, Any],
        system_prompt_static: str,
        system_prompt_dynamic: str,
        history: List[Dict[str, str]],
        model_label: str,
        llm_url: str,
        api_key: str,
        timeout_sec: int,
        tool_executor: ToolExecutor,
        allow_tools: bool,
        max_tool_steps: int,
        allowed_tool_names: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        base = str(llm_url).strip().rstrip("/")
        url = base if base.endswith("/v1/messages") else f"{base}/v1/messages"
        tools = self._claude_tool_specs_filtered(allowed_tool_names) if allow_tools else []
        messages: List[Dict[str, Any]] = []
        for h in history:
            messages.append(
                {
                    "role": str(h.get("role") or "user"),
                    "content": [{"type": "text", "text": str(h.get("content") or "")}],
                }
            )
        messages.append({"role": "user", "content": [{"type": "text", "text": message}]})
        tool_calls_log: List[Dict[str, Any]] = []
        final_text = ""
        used_model = str(model_label or "").strip()
        submitted_actions: List[Dict[str, Any]] = []
        usage_total = _usage_empty("claude", used_model or str(model_label or ""))
        headers = {
            "x-api-key": api_key,
            "anthropic-version": self.anthropic_version,
            "anthropic-beta": "prompt-caching-2024-07-31",
            "Content-Type": "application/json",
        }

        def _claude_post(req_payload: Dict[str, Any], *, attempts: int = 3) -> httpx.Response:
            last_resp: Optional[httpx.Response] = None
            last_exc: Optional[Exception] = None
            max_attempts = max(1, int(attempts))
            for at in range(1, max_attempts + 1):
                try:
                    with httpx.Client(
                        timeout=float(timeout_sec),
                        limits=httpx.Limits(max_keepalive_connections=0, max_connections=20),
                        http2=False,
                    ) as _client:
                        resp = _client.post(url, headers=headers, json=req_payload)
                    last_resp = resp
                    if _is_transient_http_status(resp.status_code) and at < max_attempts:
                        detail = _redact_error_text((resp.text or "")[:180]) if getattr(resp, "text", None) else ""
                        logger.warning(
                            "claude transient HTTP %s (attempt %s/%s): %s",
                            resp.status_code,
                            at,
                            max_attempts,
                            detail,
                        )
                        _sleep_backoff(at)
                        continue
                    return resp
                except (httpx.ReadError, httpx.TimeoutException, httpx.TransportError) as exc:
                    last_exc = exc
                    if at < max_attempts:
                        logger.warning(
                            "claude transport error attempt %s/%s: %s",
                            at,
                            max_attempts,
                            _redact_error_text(str(exc)),
                        )
                        _sleep_backoff(at)
                        continue
                    raise
            if last_resp is not None:
                return last_resp
            if last_exc is not None:
                raise last_exc
            raise RuntimeError("claude request failed without response")

        _accumulated_text_parts: List[str] = []
        for _ in range(max(0, int(max_tool_steps)) + 1):
            if str(system_prompt_static or "").strip():
                system_payload: Any = [
                    {
                        "type": "text",
                        "text": str(system_prompt_static),
                        "cache_control": {"type": "ephemeral"},
                    },
                    {"type": "text", "text": str(system_prompt_dynamic or "")},
                ]
            else:
                system_payload = str(system_prompt_dynamic or "")
            payload: Dict[str, Any] = {
                "max_tokens": 4096,
                "temperature": 0.2,
                "system": system_payload,
                "messages": messages,
            }
            if tools:
                payload["tools"] = tools
            resp = None
            last_detail = ""
            for m in self._claude_model_candidates(model_label):
                payload["model"] = m
                _resp = _claude_post(payload)
                if _resp.status_code == 200:
                    resp = _resp
                    used_model = m
                    break
                detail = _redact_error_text((_resp.text or "")[:300]) if getattr(_resp, "text", None) else ""
                last_detail = f"model={m} HTTP {_resp.status_code}: {detail}"
                # Try fallback model only for not-found/invalid-model style failures.
                if _resp.status_code not in {400, 404}:
                    resp = _resp
                    break
            if resp is None:
                raise RuntimeError(f"claude failed: {last_detail or 'no_response'}")
            if resp.status_code != 200:
                detail = _redact_error_text((resp.text or "")[:300]) if getattr(resp, "text", None) else ""
                logger.warning("claude HTTP %s: %s", resp.status_code, detail)
                raise RuntimeError(f"claude failed: HTTP {resp.status_code}: {detail}")
            body = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
            usage_total["api_calls"] = int(_safe_int(usage_total.get("api_calls"), 0) + 1)
            _usage_add(usage_total, _usage_extract_claude(body))
            usage_total["model"] = str(used_model or usage_total.get("model") or "")
            content = body.get("content") if isinstance(body, dict) and isinstance(body.get("content"), list) else []
            if not content:
                break
            messages.append({"role": "assistant", "content": content})
            tool_uses = [c for c in content if isinstance(c, dict) and str(c.get("type") or "") == "tool_use"]
            stop_reason = str(body.get("stop_reason") or "") if isinstance(body, dict) else ""
            if not tool_uses:
                texts = [str(c.get("text") or "") for c in content if isinstance(c, dict) and str(c.get("type") or "") == "text"]
                partial = "\n".join([t for t in texts if t.strip()]).strip()
                # Auto-continue if truncated by max_tokens (report cut mid-sentence).
                if stop_reason == "max_tokens" and partial:
                    _accumulated_text_parts.append(partial)
                    logger.info("claude response truncated by max_tokens, requesting continuation (parts=%d)", len(_accumulated_text_parts))
                    messages.append({"role": "user", "content": [{"type": "text", "text": "Continue from where you left off."}]})
                    continue
                if _accumulated_text_parts:
                    _accumulated_text_parts.append(partial)
                    final_text = "\n".join(_accumulated_text_parts).strip()
                else:
                    final_text = partial
                break

            tool_results: List[Dict[str, Any]] = []
            for tu in tool_uses:
                tool_name = str(tu.get("name") or "").strip()
                tool_id = str(tu.get("id") or "").strip()
                args = tu.get("input") if isinstance(tu.get("input"), dict) else {}
                try:
                    if tool_name == _SUBMIT_PROPOSED_ACTIONS_TOOL:
                        submitted = self._extract_submitted_actions(args)
                        submitted_actions.extend(submitted)
                        result = {
                            "ok": True,
                            "accepted": int(len(submitted)),
                            "action_types": [str(a.get("action_type") or "") for a in submitted],
                        }
                    elif tool_name not in _ALLOWED_TOOL_NAMES:
                        result = {"ok": False, "error": f"disallowed_tool:{tool_name}"}
                    else:
                        result = tool_executor(tool_name, args)
                except Exception as exc:
                    logger.warning("claude tool execution failed tool=%s err=%s", tool_name, str(exc)[:180])
                    result = {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}
                tool_calls_log.append({"tool_id": tool_name, "args": args, "result": result})
                tool_results.append(
                    {
                        "type": "tool_result",
                        "tool_use_id": tool_id,
                        "content": json.dumps(result, ensure_ascii=True),
                    }
                )
            messages.append({"role": "user", "content": tool_results})
            extra_rows = self._run_auto_parent_verification(
                tool_calls_log=tool_calls_log,
                context=context,
                tool_executor=tool_executor,
                allowed_tool_names=allowed_tool_names,
            )
            if extra_rows:
                messages.append(
                    {
                        "role": "user",
                        "content": [
                            {
                                "type": "text",
                                "text": (
                                    "Automatic verification scans were executed because the parent strategy returned a "
                                    "negative or sparse result. Treat these tool outputs as authoritative evidence for the "
                                    "final analysis.\n\n"
                                    + json.dumps(extra_rows, ensure_ascii=True)
                                ),
                            }
                        ],
                    }
                )
                tool_calls_log.extend(extra_rows)
        if not final_text and tool_calls_log:
            messages.append(
                {
                    "role": "user",
                    "content": [
                        {
                            "type": "text",
                            "text": "Now provide the final JSON reply/proposed_actions for the trader. Do not call tools in this step.",
                        }
                    ],
                }
            )
            if str(system_prompt_static or "").strip():
                system_payload = [
                    {
                        "type": "text",
                        "text": str(system_prompt_static),
                        "cache_control": {"type": "ephemeral"},
                    },
                    {"type": "text", "text": str(system_prompt_dynamic or "")},
                ]
            else:
                system_payload = str(system_prompt_dynamic or "")
            payload = {
                "model": str(used_model or model_label),
                "max_tokens": 4096,
                "temperature": 0.2,
                "system": system_payload,
                "messages": messages,
            }
            _final_parts: List[str] = []
            for _cont in range(3):  # max 2 continuations for final pass
                resp = _claude_post(payload)
                if resp.status_code != 200:
                    break
                body = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
                usage_total["api_calls"] = int(_safe_int(usage_total.get("api_calls"), 0) + 1)
                _usage_add(usage_total, _usage_extract_claude(body))
                content = body.get("content") if isinstance(body, dict) and isinstance(body.get("content"), list) else []
                texts = [str(c.get("text") or "") for c in content if isinstance(c, dict) and str(c.get("type") or "") == "text"]
                chunk = "\n".join([t for t in texts if t.strip()]).strip()
                if chunk:
                    _final_parts.append(chunk)
                sr = str(body.get("stop_reason") or "") if isinstance(body, dict) else ""
                if sr != "max_tokens" or not chunk:
                    break
                logger.info("claude final-pass truncated by max_tokens, continuing (part=%d)", _cont + 1)
                messages.append({"role": "assistant", "content": content})
                messages.append({"role": "user", "content": [{"type": "text", "text": "Continue from where you left off."}]})
                payload["messages"] = messages
            if _final_parts:
                final_text = "\n".join(_final_parts).strip()
        if not final_text:
            final_text = self._fallback_text_from_tool_calls(tool_calls_log)

        reply, actions, memory_notes = self._parse_final_payload(final_text)
        final_actions = submitted_actions if submitted_actions else actions
        return {
            "ok": True,
            "reply": reply or final_text,
            "tool_calls": tool_calls_log,
            "proposed_actions": final_actions,
            "memory_notes": memory_notes,
            "raw_text": final_text,
            "model_used": used_model or str(model_label or ""),
            "usage": _usage_finalize(usage_total),
        }

    def chat(
        self,
        *,
        message: str,
        context: Optional[Dict[str, Any]],
        conversation_history: Optional[List[Dict[str, str]]],
        provider: str,
        model_label: Optional[str],
        llm_url: Optional[str],
        api_key: Optional[str],
        timeout_sec: Optional[int],
        permissions: Optional[Dict[str, Any]],
        tool_executor: ToolExecutor,
        allow_tools: bool = True,
        max_tool_steps: int = 4,
        allowed_tool_names: Optional[List[str]] = None,
        objective: str = "",
    ) -> Dict[str, Any]:
        msg = str(message or "").strip()
        if not msg:
            return {"ok": False, "error": "Message is empty"}

        p = _to_provider_name(provider)
        model = str(model_label or "").strip() or self._default_model(p)
        base_url = str(llm_url or "").strip() or self._default_url(p)
        timeout = int(timeout_sec or 60)
        timeout = max(10, min(600, timeout))
        history = self._trim_history(conversation_history)
        if len(history) >= 8:
            history = compress_history(history, keep_recent=2)
        safe_context = dict(context) if isinstance(context, dict) else {}
        delta_context = safe_context.pop("_delta_context", None)
        perms = permissions if isinstance(permissions, dict) else {}
        if allowed_tool_names is None and bool(allow_tools):
            allowed_tool_names = get_tools_for_intent(msg, conversation_history=conversation_history)
        local_on_demand_mode = p == "local_gptoss_http"
        include_tool_summaries = not (bool(allow_tools) and p in {"claude", "openai_compat"})
        system_prompt_static, system_prompt_dynamic = self._system_prompt_parts(
            safe_context,
            perms,
            objective=objective,
            allowed_tool_names=allowed_tool_names,
            include_tool_summaries=include_tool_summaries,
            on_demand_mode=local_on_demand_mode,
            delta_context=delta_context,
        )
        system_prompt = f"{system_prompt_static}\n{system_prompt_dynamic}"

        try:
            if p == "deterministic":
                out = self._chat_deterministic(
                    message=msg,
                    context=safe_context,
                    permissions=perms,
                    tool_executor=tool_executor,
                    allow_tools=allow_tools,
                    max_tool_steps=max_tool_steps,
                    allowed_tool_names=allowed_tool_names,
                )
            elif p == "local_gptoss_http":
                # Local GPT-OSS now supports tool planning via two-pass JSON protocol.
                out = self._chat_local_gptoss_with_tools(
                    message=msg,
                    context=safe_context,
                    history=history,
                    system_prompt=system_prompt,
                    model_label=model,
                    llm_url=base_url,
                    timeout_sec=timeout,
                    tool_executor=tool_executor,
                    allow_tools=allow_tools,
                    max_tool_steps=max_tool_steps,
                    allowed_tool_names=allowed_tool_names,
                )
            elif p == "openai_compat":
                key = str(api_key or _get_env_value("OPENAI_API_KEY") or "").strip()
                if not key:
                    return {"ok": False, "error": "openai_compat selected but API key is missing"}
                out = self._chat_openai_with_tools(
                    message=msg,
                    context=safe_context,
                    system_prompt=system_prompt,
                    history=history,
                    model_label=model,
                    llm_url=base_url,
                    api_key=key,
                    timeout_sec=timeout,
                    tool_executor=tool_executor,
                    allow_tools=allow_tools,
                    max_tool_steps=max_tool_steps,
                    allowed_tool_names=allowed_tool_names,
                )
            elif p == "claude":
                key = str(
                    api_key
                    or _get_env_value("ANTHROPIC_API_KEY", "CLAUDE_API_KEY")
                    or ""
                ).strip()
                if not key:
                    return {"ok": False, "error": "claude selected but API key is missing"}
                out = self._chat_claude_with_tools(
                    message=msg,
                    context=safe_context,
                    system_prompt_static=system_prompt_static,
                    system_prompt_dynamic=system_prompt_dynamic,
                    history=history,
                    model_label=model,
                    llm_url=base_url,
                    api_key=key,
                    timeout_sec=timeout,
                    tool_executor=tool_executor,
                    allow_tools=allow_tools,
                    max_tool_steps=max_tool_steps,
                    allowed_tool_names=allowed_tool_names,
                )
            else:
                return {"ok": False, "error": f"Unknown provider: {p}"}
        except Exception as exc:
            logger.exception("agent.chat failed provider=%s model=%s", p, model)
            return {
                "ok": False,
                "error": f"{type(exc).__name__}: {_redact_error_text(str(exc))}",
                "provider": p,
                "model": model,
                "usage": _usage_finalize(_usage_empty(p, model)),
            }

        if not isinstance(out.get("usage"), dict):
            out["usage"] = _usage_finalize(_usage_empty(p, model))
        else:
            usage_obj = dict(out.get("usage") or {})
            usage_obj["provider"] = str(usage_obj.get("provider") or p)
            usage_obj["model"] = str(usage_obj.get("model") or out.get("model_used") or model)
            out["usage"] = _usage_finalize(usage_obj)
        out["provider"] = p
        out["model"] = str(out.get("model_used") or model)
        out["generated_at"] = datetime.now(timezone.utc).isoformat()
        return out

    def run_once(
        self,
        *,
        context: Optional[Dict[str, Any]],
        objective: str,
        provider: str,
        model_label: Optional[str],
        llm_url: Optional[str],
        api_key: Optional[str],
        timeout_sec: Optional[int],
        permissions: Optional[Dict[str, Any]],
        tool_executor: ToolExecutor,
        allow_tools: bool = True,
        max_tool_steps: int = 4,
        allowed_tool_names: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        prompt = (
            f"Run one agent cycle.\nObjective: {str(objective or 'Review setup and propose next actions')}.\n"
            "Use tools if needed, then return concise reply and proposed_actions JSON."
        )
        return self.chat(
            message=prompt,
            context=context,
            conversation_history=[],
            provider=provider,
            model_label=model_label,
            llm_url=llm_url,
            api_key=api_key,
            timeout_sec=timeout_sec,
            permissions=permissions,
            tool_executor=tool_executor,
            allow_tools=allow_tools,
            max_tool_steps=max_tool_steps,
            allowed_tool_names=allowed_tool_names,
            objective=str(objective or "").strip(),
        )
