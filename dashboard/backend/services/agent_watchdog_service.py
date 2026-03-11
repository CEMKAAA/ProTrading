"""
Agent Watchdog Service

Deterministic open-trade watchdog for Workbench Agent sessions.
Tracks SL->TP progress in 0..10 segments and emits agent events when segment changes.
Optional SMS notifications via Twilio REST API (env-configured).
"""

from __future__ import annotations

import json
import logging
import math
import os
import re
import threading
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional, Tuple

import httpx
import pandas as pd

from ..core.workbench.agent import WorkbenchAgent
from ..core.workbench import get_tool
from ..models.database import (
    SessionLocal,
    SimulationSession,
    SimulationTrade,
    WorkbenchAgentEventModel,
    WorkbenchAgentMemoryModel,
    WorkbenchAgentSessionModel,
)


logger = logging.getLogger(__name__)


class AgentWatchdogService:
    def __init__(self) -> None:
        self._thread: Optional[threading.Thread] = None
        self._stop = threading.Event()
        self._agent_runtime = WorkbenchAgent()
        self._last_segment_by_trade: Dict[Tuple[int, int], int] = {}
        self._last_sms_segment_by_trade: Dict[Tuple[int, int], int] = {}
        self._last_scan_at_by_agent: Dict[int, datetime] = {}
        self._last_llm_at_by_agent: Dict[int, datetime] = {}
        self._pending_decisions: Dict[Tuple[int, int], Dict[str, Any]] = {}
        self._last_live_bar_by_agent: Dict[int, Dict[str, Any]] = {}

    @staticmethod
    def _utc_now() -> datetime:
        return datetime.now(timezone.utc)

    @staticmethod
    def _interval_sec() -> float:
        try:
            raw = float(os.getenv("AGENT_WATCHDOG_INTERVAL_SEC", "30"))
        except Exception:
            raw = 30.0
        return max(5.0, min(300.0, raw))

    @staticmethod
    def _enabled() -> bool:
        v = str(os.getenv("AGENT_WATCHDOG_ENABLED", "1")).strip().lower()
        return v not in {"0", "false", "no", "off"}

    @staticmethod
    def _sms_enabled() -> bool:
        v = str(os.getenv("AGENT_WATCHDOG_SMS_ENABLED", "0")).strip().lower()
        return v in {"1", "true", "yes", "on"}

    @staticmethod
    def _sms_segments_filter() -> Optional[set[int]]:
        raw = str(os.getenv("AGENT_WATCHDOG_SMS_SEGMENTS", "*")).strip()
        if not raw or raw == "*":
            return None
        out: set[int] = set()
        for part in raw.split(","):
            try:
                out.add(max(0, min(10, int(part.strip()))))
            except Exception:
                continue
        # Invalid config should disable segment-based SMS, not broadcast all segments.
        return out if out else set()

    @staticmethod
    def _watchdog_cfg(agent: WorkbenchAgentSessionModel) -> Dict[str, Any]:
        cfg = agent.config_json if isinstance(agent.config_json, dict) else {}
        mode_raw = str(cfg.get("watchdog_mode") or "deterministic").strip().lower()
        if mode_raw not in {"deterministic", "local_gptoss_http", "claude"}:
            mode_raw = "deterministic"
        try:
            interval = float(cfg.get("watchdog_interval_sec") or 30.0)
        except Exception:
            interval = 30.0
        interval = max(5.0, min(300.0, interval))
        try:
            llm_min = float(cfg.get("watchdog_llm_min_interval_sec") or 180.0)
        except Exception:
            llm_min = 180.0
        llm_min = max(10.0, min(3600.0, llm_min))
        model_label = str(cfg.get("watchdog_model_label") or "").strip() or None
        llm_url = str(cfg.get("watchdog_llm_url") or "").strip() or None
        allow_tools_raw = str(cfg.get("watchdog_allow_tools", "0")).strip().lower()
        allow_tools = allow_tools_raw not in {"0", "false", "no", "off"}
        try:
            tool_steps = int(cfg.get("watchdog_tool_max_steps") or 2)
        except Exception:
            tool_steps = 2
        tool_steps = max(0, min(3, tool_steps))
        try:
            decision_window_sec = int(cfg.get("watchdog_decision_window_sec") or 90)
        except Exception:
            decision_window_sec = 90
        decision_window_sec = max(30, min(300, decision_window_sec))
        return {
            "mode": mode_raw,
            "interval_sec": interval,
            "llm_min_interval_sec": llm_min,
            "model_label": model_label,
            "llm_url": llm_url,
            "allow_tools": bool(allow_tools),
            "tool_max_steps": int(tool_steps),
            "decision_window_sec": int(decision_window_sec),
        }

    @staticmethod
    def _segment_for_trade(trade: SimulationTrade, price: float) -> Optional[int]:
        try:
            direction = str(trade.direction or "").upper()
            sl = float(trade.stop_loss) if trade.stop_loss is not None else None
            tp = float(trade.take_profit) if trade.take_profit is not None else None
            px = float(price)
        except Exception:
            return None
        if sl is None or tp is None or not math.isfinite(px):
            return None
        if direction == "BUY":
            den = float(tp - sl)
            if den <= 0:
                return None
            progress = ((px - sl) / den) * 10.0
        elif direction == "SELL":
            den = float(sl - tp)
            if den <= 0:
                return None
            progress = ((sl - px) / den) * 10.0
        else:
            return None
        seg = int(math.floor(progress))
        return max(0, min(10, seg))

    @staticmethod
    def _price_from_agent_snapshot(agent: WorkbenchAgentSessionModel) -> Optional[float]:
        snap = agent.last_snapshot_json if isinstance(agent.last_snapshot_json, dict) else {}
        tool_state = snap.get("tool_state") if isinstance(snap.get("tool_state"), dict) else {}
        live_bar = tool_state.get("live_bar") if isinstance(tool_state.get("live_bar"), dict) else {}
        close = live_bar.get("close")
        try:
            px = float(close)
            if math.isfinite(px):
                return px
        except Exception:
            pass
        return None

    @staticmethod
    def _live_bar_from_agent_snapshot(agent: WorkbenchAgentSessionModel) -> Optional[Dict[str, Any]]:
        snap = agent.last_snapshot_json if isinstance(agent.last_snapshot_json, dict) else {}
        tool_state = snap.get("tool_state") if isinstance(snap.get("tool_state"), dict) else {}
        live_bar = tool_state.get("live_bar") if isinstance(tool_state.get("live_bar"), dict) else {}
        try:
            ts = int(live_bar.get("time") or 0)
            close = float(live_bar.get("close"))
            if ts <= 0 or not math.isfinite(close):
                return None
            out: Dict[str, Any] = {"time": int(ts), "close": float(close)}
            try:
                hi = float(live_bar.get("high"))
                if math.isfinite(hi):
                    out["high"] = float(hi)
            except Exception:
                pass
            try:
                lo = float(live_bar.get("low"))
                if math.isfinite(lo):
                    out["low"] = float(lo)
            except Exception:
                pass
            return out
        except Exception:
            return None

    @staticmethod
    def _bars_payload_to_df(
        bars: Any,
        *,
        max_rows: int = 20000,
        min_rows: int = 3,
    ) -> Optional[pd.DataFrame]:
        if not isinstance(bars, list):
            return None
        src = bars[-max(1, int(max_rows)) :]
        if len(src) < int(min_rows):
            return None
        rows: List[Dict[str, float]] = []
        for b in src:
            if not isinstance(b, dict):
                continue
            try:
                t = int(b.get("time") or 0)
                o = float(b.get("open"))
                h = float(b.get("high"))
                l = float(b.get("low"))
                c = float(b.get("close"))
                v = float(b.get("volume") or 0.0)
                if t <= 0:
                    continue
                if not all(math.isfinite(x) for x in (o, h, l, c, v)):
                    continue
                rows.append({"time": t, "open": o, "high": h, "low": l, "close": c, "volume": v})
            except Exception:
                continue
        if len(rows) < int(min_rows):
            return None
        df = pd.DataFrame(rows).sort_values("time").drop_duplicates(subset=["time"], keep="last")
        df["dt"] = pd.to_datetime(df["time"], unit="s", utc=True, errors="coerce")
        df = df.dropna(subset=["dt"]).set_index("dt")
        df = df[["open", "high", "low", "close", "volume"]]
        if df.empty or len(df) < int(min_rows):
            return None
        return df

    @staticmethod
    def _memory_row_to_dict(row: WorkbenchAgentMemoryModel) -> Dict[str, Any]:
        return {
            "id": int(row.id) if row.id is not None else 0,
            "content": str(row.content or ""),
            "memory_type": str(row.memory_type or "note"),
            "scope": str(row.scope or "SESSION"),
            "importance": float(row.importance or 0.0),
            "symbol": (str(row.symbol or "").upper() or None),
            "timeframe": (str(row.timeframe or "").upper() or None),
            "updated_at": row.updated_at.isoformat() if row.updated_at else None,
            "created_at": row.created_at.isoformat() if row.created_at else None,
        }

    @staticmethod
    def _watchdog_memory_search(
        *,
        db,
        session: SimulationSession,
        query: str,
        limit: int = 6,
        memory_type: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        q = str(query or "").strip().lower()
        if not q:
            return []
        symbol = str(session.symbol or "").strip().upper()
        mt = str(memory_type or "").strip().lower() or None
        rows = (
            db.query(WorkbenchAgentMemoryModel)
            .filter(
                (WorkbenchAgentMemoryModel.scope == "GLOBAL")
                | (WorkbenchAgentMemoryModel.simulation_session_id == int(session.id))
                | (WorkbenchAgentMemoryModel.symbol == symbol)
            )
            .order_by(WorkbenchAgentMemoryModel.updated_at.desc(), WorkbenchAgentMemoryModel.id.desc())
            .limit(300)
            .all()
        )
        scored: List[Tuple[float, WorkbenchAgentMemoryModel]] = []
        q_terms = [x for x in re.split(r"\W+", q) if len(x) >= 2][:12]
        for r in rows:
            if mt and str(r.memory_type or "").strip().lower() != mt:
                continue
            text = str(r.content or "").lower()
            if not text:
                continue
            hit_terms = sum(1 for t in q_terms if t in text)
            if hit_terms <= 0 and q not in text:
                continue
            imp = float(r.importance or 0.0)
            score = (hit_terms * 0.4) + (1.0 if q in text else 0.0) + (imp * 0.5)
            scored.append((score, r))
        scored.sort(key=lambda x: x[0], reverse=True)
        return [AgentWatchdogService._memory_row_to_dict(r) for _, r in scored[: max(1, min(12, int(limit)))]]

    @staticmethod
    def _watchdog_scan_tool(
        *,
        session: SimulationSession,
        tool_id: str,
        config: Dict[str, Any],
        bars: Any,
    ) -> Dict[str, Any]:
        tool = get_tool(tool_id)
        if tool is None:
            return {"ok": False, "error": f"unknown_tool:{tool_id}"}
        bars_df = AgentWatchdogService._bars_payload_to_df(bars, max_rows=20000, min_rows=3)
        if bars_df is None:
            return {"ok": False, "error": "insufficient_bars"}
        merged_config = {
            **tool.get_default_config(),
            **(config if isinstance(config, dict) else {}),
            "symbol": str(session.symbol or ""),
            "timeframe": str(session.timeframe or "M15"),
        }
        trend_meta: Dict[str, Any] = {}
        movement_strength: Dict[str, Any] = {}
        current_state: Dict[str, Any] = {}
        trend_fn = getattr(tool, "compute_trend_context", None)
        strength_fn = getattr(tool, "compute_movement_strength", None)
        state_fn = getattr(tool, "compute_current_state", None)
        if callable(trend_fn):
            try:
                trend_meta = trend_fn(bars_df, merged_config) or {}
            except Exception:
                trend_meta = {}
        if callable(strength_fn):
            try:
                movement_strength = strength_fn(bars_df, merged_config, trend_ctx=trend_meta) or {}
            except Exception:
                movement_strength = {}
        if callable(state_fn):
            try:
                current_state = state_fn(bars_df, merged_config) or {}
            except Exception:
                current_state = {}
        scan_config = dict(merged_config)
        if trend_meta:
            scan_config["_trend_context"] = trend_meta
        zones = tool.scan(bars_df, scan_config)
        return {
            "ok": True,
            "data": {
                "tool_id": str(tool_id),
                "zones": zones if isinstance(zones, list) else [],
                "count": int(len(zones)) if isinstance(zones, list) else 0,
                "scan_source": "watchdog_context",
                "scan_timeframe": str(merged_config.get("timeframe") or ""),
                "trend": trend_meta,
                "movement_strength": movement_strength,
                "current_state": current_state,
            },
        }

    @staticmethod
    def _twilio_send_sms(message: str) -> bool:
        sid = str(os.getenv("TWILIO_ACCOUNT_SID") or "").strip()
        token = str(os.getenv("TWILIO_AUTH_TOKEN") or "").strip()
        from_no = str(os.getenv("TWILIO_FROM_NUMBER") or "").strip()
        to_raw = str(os.getenv("AGENT_WATCHDOG_SMS_TO") or "").strip()
        if not (sid and token and from_no and to_raw):
            logger.debug("Watchdog SMS skipped: missing Twilio env vars")
            return False
        recipients = [x.strip() for x in to_raw.split(",") if x.strip()]
        if not recipients:
            return False
        url = f"https://api.twilio.com/2010-04-01/Accounts/{sid}/Messages.json"
        sent = 0
        with httpx.Client(timeout=12.0, auth=(sid, token)) as client:
            for to_no in recipients[:5]:
                try:
                    resp = client.post(
                        url,
                        data={
                            "To": to_no,
                            "From": from_no,
                            "Body": message[:1000],
                        },
                    )
                    if int(resp.status_code) in {200, 201}:
                        sent += 1
                    else:
                        logger.warning("Watchdog SMS failed status=%s body=%s", resp.status_code, (resp.text or "")[:160])
                except Exception as exc:
                    logger.warning("Watchdog SMS exception: %s", exc)
        return sent > 0

    def _notify_sms_if_needed(
        self,
        *,
        key: Tuple[int, int],
        segment: int,
        message: str,
    ) -> None:
        if not self._sms_enabled():
            return
        seg_filter = self._sms_segments_filter()
        if seg_filter is not None and int(segment) not in seg_filter:
            return
        if self._last_sms_segment_by_trade.get(key) == int(segment):
            return
        ok = self._twilio_send_sms(message)
        if ok:
            self._last_sms_segment_by_trade[key] = int(segment)

    @staticmethod
    def _trade_payload(trade: SimulationTrade) -> Dict[str, Any]:
        return {
            "id": int(trade.id),
            "direction": str(trade.direction or "").upper(),
            "entry_price": float(trade.entry_price) if trade.entry_price is not None else None,
            "stop_loss": float(trade.stop_loss) if trade.stop_loss is not None else None,
            "take_profit": float(trade.take_profit) if trade.take_profit is not None else None,
            "lot_size": float(trade.lot_size) if trade.lot_size is not None else None,
            "pnl": float(trade.pnl) if trade.pnl is not None else None,
        }

    @staticmethod
    def _parse_watchdog_reply(text: str) -> Dict[str, Any]:
        raw = str(text or "").strip()
        if not raw:
            return {"recommendation": "HOLD", "severity": "info", "message": "No response", "should_exit": False}
        try:
            obj = json.loads(raw)
            if isinstance(obj, dict):
                recommendation = str(obj.get("recommendation") or obj.get("action") or "HOLD").strip().upper()
                severity = str(obj.get("severity") or "info").strip().lower()
                message = str(obj.get("message") or obj.get("summary") or raw)[:600]
                should_exit = bool(obj.get("should_exit", recommendation in {"EXIT", "FULL_EXIT", "CLOSE"}))
                confidence = obj.get("confidence")
                try:
                    conf = float(confidence) if confidence is not None else None
                except Exception:
                    conf = None
                return {
                    "recommendation": recommendation,
                    "severity": severity,
                    "message": message,
                    "should_exit": should_exit,
                    "confidence": conf,
                }
        except Exception:
            pass
        upper = raw.upper()
        should_exit = any(x in upper for x in ["EXIT", "CLOSE NOW", "FULL_EXIT"])
        return {
            "recommendation": "EXIT" if should_exit else "HOLD",
            "severity": "warning" if should_exit else "info",
            "message": raw[:600],
            "should_exit": should_exit,
            "confidence": None,
        }

    @staticmethod
    def _safe_iso(dt: Optional[datetime]) -> Optional[str]:
        if dt is None:
            return None
        try:
            return dt.astimezone(timezone.utc).isoformat()
        except Exception:
            return None

    def _execute_timeout_close(
        self,
        *,
        db,
        session: SimulationSession,
        trade_id: int,
        exit_price: Optional[float],
    ) -> Dict[str, Any]:
        try:
            from ..api.simulation_routes import CloseTradeRequest, close_trade
            req = CloseTradeRequest(
                exit_price=float(exit_price) if (exit_price is not None and math.isfinite(float(exit_price))) else None,
                bar_time_unix=None,
                cost_spread=None,
                cost_tc_rate=None,
                cost_spread_source=None,
            )
            prev_suppress = bool(getattr(db, "_suppress_commit", False))
            setattr(db, "_suppress_commit", True)
            try:
                data = close_trade(
                    session_id=int(session.id),
                    trade_id=int(trade_id),
                    req=req,
                    db=db,
                )
            finally:
                setattr(db, "_suppress_commit", prev_suppress)
            return {"ok": True, "data": data if isinstance(data, dict) else {}}
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:220]}"}

    def _process_entry_triggers(
        self,
        *,
        db,
        agent: WorkbenchAgentSessionModel,
        session: SimulationSession,
        now: datetime,
        current_price: float,
        closed_bar: Optional[Dict[str, Any]],
        current_live_bar: Optional[Dict[str, Any]] = None,
    ) -> List[WorkbenchAgentEventModel]:
        event_rows: List[WorkbenchAgentEventModel] = []
        snap = agent.last_snapshot_json if isinstance(agent.last_snapshot_json, dict) else {}
        raw_triggers = snap.get("agent_trade_triggers") if isinstance(snap.get("agent_trade_triggers"), list) else []
        if not raw_triggers:
            return event_rows
        cfg = agent.config_json if isinstance(agent.config_json, dict) else {}
        perms = cfg.get("agent_permissions") if isinstance(cfg.get("agent_permissions"), dict) else {}
        trigger_requires_approval_default = bool(cfg.get("watchdog_trigger_requires_approval", False))
        changed = False
        next_triggers: List[Dict[str, Any]] = []

        for raw in raw_triggers[:200]:
            t = dict(raw) if isinstance(raw, dict) else {}
            if not t:
                continue
            status = str(t.get("status") or "pending").strip().lower()
            if status != "pending":
                next_triggers.append(t)
                continue

            # Freeze per-trigger approval behavior at creation time when available.
            trigger_guardrails = t.get("guardrails") if isinstance(t.get("guardrails"), dict) else {}
            trigger_requires_approval = (
                bool(trigger_guardrails.get("trigger_requires_approval"))
                if "trigger_requires_approval" in trigger_guardrails
                else bool(trigger_requires_approval_default)
            )
            trigger_tool_config: Dict[str, Any] = {}
            if isinstance(trigger_guardrails, dict):
                if "guardrail_enabled" in trigger_guardrails:
                    trigger_tool_config["guardrail_enabled"] = bool(trigger_guardrails.get("guardrail_enabled"))
                if "session_filter_enabled" in trigger_guardrails:
                    trigger_tool_config["guardrail_session_filter_enabled"] = bool(trigger_guardrails.get("session_filter_enabled"))
                if "news_filter_enabled" in trigger_guardrails:
                    trigger_tool_config["guardrail_news_filter_enabled"] = bool(trigger_guardrails.get("news_filter_enabled"))
                if "news_lookback_min" in trigger_guardrails:
                    try:
                        trigger_tool_config["guardrail_news_lookback_min"] = int(trigger_guardrails.get("news_lookback_min"))
                    except Exception:
                        pass
                if "news_provider" in trigger_guardrails:
                    trigger_tool_config["market_news_provider"] = str(trigger_guardrails.get("news_provider") or "polygon").strip().lower() or "polygon"
                if "news_ibkr_host" in trigger_guardrails:
                    trigger_tool_config["market_news_ibkr_host"] = str(trigger_guardrails.get("news_ibkr_host") or "127.0.0.1").strip() or "127.0.0.1"
                if "news_ibkr_port" in trigger_guardrails:
                    try:
                        trigger_tool_config["market_news_ibkr_port"] = int(trigger_guardrails.get("news_ibkr_port"))
                    except Exception:
                        pass
            trigger_perms = dict(perms)
            if not trigger_requires_approval:
                # Trigger-driven entries should auto-execute by default once condition is met.
                trigger_perms["requires_user_confirm_for_trade"] = False

            expires_at = t.get("expires_at")
            exp_dt: Optional[datetime] = None
            if isinstance(expires_at, str) and expires_at.strip():
                try:
                    exp_dt = datetime.fromisoformat(expires_at.replace("Z", "+00:00"))
                    if exp_dt.tzinfo is None:
                        exp_dt = exp_dt.replace(tzinfo=timezone.utc)
                except Exception:
                    exp_dt = None
            if exp_dt is not None and now >= exp_dt:
                t["status"] = "expired"
                t["expired_at"] = self._safe_iso(now)
                changed = True
                event_rows.append(
                    WorkbenchAgentEventModel(
                        agent_session_id=int(agent.id),
                        event_type="WATCHDOG_ENTRY_EXPIRED",
                        severity="info",
                        payload_json={
                            "source": "agent_watchdog",
                            "trigger_id": str(t.get("id") or ""),
                            "condition": str(t.get("condition") or ""),
                            "trigger_price": t.get("trigger_price"),
                            "expired_at": self._safe_iso(now),
                        },
                        created_at=self._utc_now(),
                    )
                )
                next_triggers.append(t)
                continue

            def _evaluate_condition(cond_name: str, level_value: float) -> Tuple[str, Optional[float], Optional[int]]:
                eval_px: Optional[float] = None
                eval_tm: Optional[int] = None
                if cond_name in {"close_below", "close_above"}:
                    if isinstance(closed_bar, dict):
                        try:
                            cpx = float(closed_bar.get("close"))
                            ctm = int(closed_bar.get("time") or 0)
                            if math.isfinite(cpx) and ctm > 0:
                                eval_px = cpx
                                eval_tm = ctm
                        except Exception:
                            eval_px = None
                    if eval_px is None:
                        return ("no_eval", None, None)
                else:
                    # price_* conditions are touch-based: use live bar extremes when available
                    # so brief intrabar touches are not missed between watchdog polls.
                    if isinstance(current_live_bar, dict):
                        try:
                            ltm = int(current_live_bar.get("time") or 0)
                            if ltm > 0:
                                eval_tm = ltm
                        except Exception:
                            eval_tm = None
                        if cond_name == "price_below":
                            try:
                                lo = float(current_live_bar.get("low"))
                                if math.isfinite(lo):
                                    eval_px = float(lo)
                            except Exception:
                                eval_px = None
                        elif cond_name == "price_above":
                            try:
                                hi = float(current_live_bar.get("high"))
                                if math.isfinite(hi):
                                    eval_px = float(hi)
                            except Exception:
                                eval_px = None
                    if eval_px is None:
                        eval_px = float(current_price)
                if cond_name == "close_below":
                    return ("hit" if bool(eval_px < level_value) else "miss", eval_px, eval_tm)
                if cond_name == "close_above":
                    return ("hit" if bool(eval_px > level_value) else "miss", eval_px, eval_tm)
                if cond_name == "price_below":
                    return ("hit" if bool(eval_px <= level_value) else "miss", eval_px, eval_tm)
                if cond_name == "price_above":
                    return ("hit" if bool(eval_px >= level_value) else "miss", eval_px, eval_tm)
                return ("invalid_condition", eval_px, eval_tm)

            cond = str(t.get("condition") or "").strip().lower()
            try:
                level = float(t.get("trigger_price"))
            except Exception:
                level = float("nan")
            if not math.isfinite(level) or level <= 0:
                t["status"] = "failed"
                t["failed_at"] = self._safe_iso(now)
                t["error"] = "invalid_trigger_price"
                changed = True
                event_rows.append(
                    WorkbenchAgentEventModel(
                        agent_session_id=int(agent.id),
                        event_type="WATCHDOG_ENTRY_FAILED",
                        severity="warning",
                        payload_json={
                            "source": "agent_watchdog",
                            "trigger_id": str(t.get("id") or ""),
                            "condition": str(cond),
                            "trigger_price": t.get("trigger_price"),
                            "error": "invalid_trigger_price",
                        },
                        created_at=self._utc_now(),
                    )
                )
                next_triggers.append(t)
                continue

            cancel_rule = t.get("cancel_rule") if isinstance(t.get("cancel_rule"), dict) else None
            if isinstance(cancel_rule, dict):
                cancel_cond = str(cancel_rule.get("condition") or "").strip().lower()
                try:
                    cancel_level = float(cancel_rule.get("trigger_price"))
                except Exception:
                    cancel_level = float("nan")
                if not math.isfinite(cancel_level) or cancel_level <= 0:
                    t["status"] = "failed"
                    t["failed_at"] = self._safe_iso(now)
                    t["error"] = "invalid_cancel_trigger_price"
                    changed = True
                    event_rows.append(
                        WorkbenchAgentEventModel(
                            agent_session_id=int(agent.id),
                            event_type="WATCHDOG_ENTRY_FAILED",
                            severity="warning",
                            payload_json={
                                "source": "agent_watchdog",
                                "trigger_id": str(t.get("id") or ""),
                                "condition": str(cond),
                                "trigger_price": t.get("trigger_price"),
                                "cancel_rule": {"condition": cancel_cond, "trigger_price": cancel_rule.get("trigger_price")},
                                "error": "invalid_cancel_trigger_price",
                            },
                            created_at=self._utc_now(),
                        )
                    )
                    next_triggers.append(t)
                    continue
                cancel_state, cancel_eval_price, _cancel_eval_time = _evaluate_condition(cancel_cond, float(cancel_level))
                if cancel_state == "invalid_condition":
                    t["status"] = "failed"
                    t["failed_at"] = self._safe_iso(now)
                    t["error"] = "invalid_cancel_condition"
                    changed = True
                    next_triggers.append(t)
                    continue
                if cancel_state == "hit":
                    cancel2 = dict(cancel_rule)
                    cancel2["hit_at"] = self._safe_iso(now)
                    cancel2["hit_price"] = float(cancel_eval_price) if cancel_eval_price is not None else None
                    t["cancel_rule"] = cancel2
                    t["status"] = "canceled"
                    t["canceled_at"] = self._safe_iso(now)
                    t["cancel_reason"] = "cancel_rule_hit"
                    changed = True
                    event_rows.append(
                        WorkbenchAgentEventModel(
                            agent_session_id=int(agent.id),
                            event_type="WATCHDOG_ENTRY_CANCELED",
                            severity="info",
                            payload_json={
                                "source": "agent_watchdog",
                                "trigger_id": str(t.get("id") or ""),
                                "condition": cond,
                                "trigger_price": float(level),
                                "cancel_rule": cancel2,
                                "cancel_reason": "cancel_rule_hit",
                            },
                            created_at=self._utc_now(),
                        )
                    )
                    next_triggers.append(t)
                    continue

            pre = t.get("precondition") if isinstance(t.get("precondition"), dict) else None
            state = str(t.get("state") or ("waiting_precondition" if isinstance(pre, dict) else "waiting_entry")).strip().lower()
            if state not in {"waiting_precondition", "waiting_entry"}:
                state = "waiting_precondition" if isinstance(pre, dict) else "waiting_entry"
                t["state"] = state
                changed = True

            if state == "waiting_precondition":
                if not isinstance(pre, dict):
                    t["state"] = "waiting_entry"
                    changed = True
                else:
                    pcond = str(pre.get("condition") or "").strip().lower()
                    try:
                        plevel = float(pre.get("trigger_price"))
                    except Exception:
                        plevel = float("nan")
                    if not math.isfinite(plevel) or plevel <= 0:
                        t["status"] = "failed"
                        t["failed_at"] = self._safe_iso(now)
                        t["error"] = "invalid_precondition_trigger_price"
                        changed = True
                        event_rows.append(
                            WorkbenchAgentEventModel(
                                agent_session_id=int(agent.id),
                                event_type="WATCHDOG_ENTRY_FAILED",
                                severity="warning",
                                payload_json={
                                    "source": "agent_watchdog",
                                    "trigger_id": str(t.get("id") or ""),
                                    "condition": str(cond),
                                    "trigger_price": t.get("trigger_price"),
                                    "precondition": {"condition": pcond, "trigger_price": pre.get("trigger_price")},
                                    "error": "invalid_precondition_trigger_price",
                                },
                                created_at=self._utc_now(),
                            )
                        )
                        next_triggers.append(t)
                        continue
                    p_state, p_eval_px, _p_eval_tm = _evaluate_condition(pcond, float(plevel))
                    if p_state == "invalid_condition":
                        t["status"] = "failed"
                        t["failed_at"] = self._safe_iso(now)
                        t["error"] = "invalid_precondition_condition"
                        changed = True
                        next_triggers.append(t)
                        continue
                    if p_state in {"no_eval", "miss"}:
                        next_triggers.append(t)
                        continue
                    pre2 = dict(pre)
                    pre2["hit_at"] = self._safe_iso(now)
                    pre2["hit_price"] = float(p_eval_px) if p_eval_px is not None else None
                    t["precondition"] = pre2
                    t["state"] = "waiting_entry"
                    t["armed_at"] = self._safe_iso(now)
                    changed = True
                    event_rows.append(
                        WorkbenchAgentEventModel(
                            agent_session_id=int(agent.id),
                            event_type="WATCHDOG_ENTRY_STAGE_ADVANCED",
                            severity="info",
                            payload_json={
                                "source": "agent_watchdog",
                                "trigger_id": str(t.get("id") or ""),
                                "from_state": "waiting_precondition",
                                "to_state": "waiting_entry",
                                "precondition": pre2,
                                "condition": cond,
                                "trigger_price": float(level),
                            },
                            created_at=self._utc_now(),
                        )
                    )
                    next_triggers.append(t)
                    continue

            c_state, eval_price, eval_time = _evaluate_condition(cond, float(level))
            if c_state == "invalid_condition":
                t["status"] = "failed"
                t["failed_at"] = self._safe_iso(now)
                t["error"] = "invalid_condition"
                changed = True
                next_triggers.append(t)
                continue
            if c_state in {"no_eval", "miss"}:
                next_triggers.append(t)
                continue

            trade_args = t.get("trade_args") if isinstance(t.get("trade_args"), dict) else {}
            place_args = dict(trade_args)
            if place_args.get("bar_time_unix") is None and eval_time is not None:
                place_args["bar_time_unix"] = int(eval_time)

            try:
                from ..api.simulation_routes import _agent_execute_tool
                result = _agent_execute_tool(
                    session=session,
                    db=db,
                    permissions=trigger_perms,
                    context_snapshot=snap if isinstance(snap, dict) else {},
                    tool_name="place_trade",
                    args=place_args,
                    tool_config=(trigger_tool_config if trigger_tool_config else None),
                    atomic=True,
                )
            except Exception as exc:
                result = {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}

            if bool(result.get("ok", False)):
                t["status"] = "executed"
                t["executed_at"] = self._safe_iso(now)
                t["executed_price"] = float(eval_price)
                t["result"] = result.get("data") if isinstance(result.get("data"), dict) else {}
                changed = True
                event_rows.append(
                    WorkbenchAgentEventModel(
                        agent_session_id=int(agent.id),
                        event_type="WATCHDOG_ENTRY_EXECUTED",
                        severity="info",
                        payload_json={
                            "source": "agent_watchdog",
                            "trigger_id": str(t.get("id") or ""),
                            "condition": cond,
                            "trigger_price": float(level),
                            "hit_price": float(eval_price),
                            "trade": result.get("data") if isinstance(result.get("data"), dict) else {},
                        },
                        created_at=self._utc_now(),
                    )
                )
            elif bool(result.get("requires_confirmation")) and isinstance(result.get("pending_action"), dict):
                t["status"] = "pending_approval"
                t["pending_at"] = self._safe_iso(now)
                t["pending_action"] = result.get("pending_action")
                changed = True
                event_rows.append(
                    WorkbenchAgentEventModel(
                        agent_session_id=int(agent.id),
                        event_type="WATCHDOG_ENTRY_PENDING",
                        severity="warning",
                        payload_json={
                            "source": "agent_watchdog",
                            "trigger_id": str(t.get("id") or ""),
                            "condition": cond,
                            "trigger_price": float(level),
                            "hit_price": float(eval_price),
                            "pending_action": result.get("pending_action"),
                            "message": "Conditional entry trigger hit. Awaiting approval to execute.",
                        },
                        created_at=self._utc_now(),
                    )
                )
            else:
                t["status"] = "failed"
                t["failed_at"] = self._safe_iso(now)
                t["error"] = str(result.get("error") or "trigger_execution_failed")[:280]
                changed = True
                event_rows.append(
                    WorkbenchAgentEventModel(
                        agent_session_id=int(agent.id),
                        event_type="WATCHDOG_ENTRY_FAILED",
                        severity="warning",
                        payload_json={
                            "source": "agent_watchdog",
                            "trigger_id": str(t.get("id") or ""),
                            "condition": cond,
                            "trigger_price": float(level),
                            "hit_price": float(eval_price),
                            "error": str(result.get("error") or "trigger_execution_failed")[:280],
                        },
                        created_at=self._utc_now(),
                    )
                )
            next_triggers.append(t)

        if changed:
            # Re-read latest snapshot before write to reduce race-loss against
            # concurrent chat/run-once updates that may append new triggers.
            latest_agent = db.get(WorkbenchAgentSessionModel, int(agent.id))
            latest_snap = (
                latest_agent.last_snapshot_json
                if (latest_agent is not None and isinstance(latest_agent.last_snapshot_json, dict))
                else (snap if isinstance(snap, dict) else {})
            )
            latest_raw = (
                latest_snap.get("agent_trade_triggers")
                if isinstance(latest_snap.get("agent_trade_triggers"), list)
                else []
            )
            merged: List[Dict[str, Any]] = []
            next_by_id: Dict[str, Dict[str, Any]] = {}
            next_without_id: List[Dict[str, Any]] = []
            for t in next_triggers:
                if not isinstance(t, dict):
                    continue
                tid = str(t.get("id") or "").strip()
                if tid:
                    next_by_id[tid] = dict(t)
                else:
                    next_without_id.append(dict(t))

            used_ids: set[str] = set()
            for raw in latest_raw[:200]:
                if not isinstance(raw, dict):
                    continue
                rid = str(raw.get("id") or "").strip()
                if rid and rid in next_by_id:
                    merged.append(dict(next_by_id[rid]))
                    used_ids.add(rid)
                else:
                    merged.append(dict(raw))

            for tid, row in next_by_id.items():
                if tid in used_ids:
                    continue
                merged.append(dict(row))
            for row in next_without_id:
                merged.append(dict(row))

            new_snap = dict(latest_snap) if isinstance(latest_snap, dict) else {}
            new_snap["agent_trade_triggers"] = merged[:200]
            target = latest_agent if latest_agent is not None else agent
            target.last_snapshot_json = new_snap
            target.updated_at = self._utc_now()
            db.add(target)
        return event_rows

    def _process_pending_decisions(
        self,
        *,
        db,
        now: datetime,
        event_rows: List[WorkbenchAgentEventModel],
    ) -> None:
        if not self._pending_decisions:
            return
        to_delete: List[Tuple[int, int]] = []
        for key, dec in list(self._pending_decisions.items()):
            if not isinstance(dec, dict):
                to_delete.append(key)
                continue
            status = str(dec.get("status") or "pending").lower()
            if status != "pending":
                to_delete.append(key)
                continue
            deadline = dec.get("deadline_at")
            if not isinstance(deadline, datetime):
                to_delete.append(key)
                continue
            if now < deadline:
                continue
            sim_id, trade_id = int(key[0]), int(key[1])
            decision_id = str(dec.get("decision_id") or "")
            agent_session_id = int(dec.get("agent_session_id") or 0)
            auto_decision = str(dec.get("auto_decision") or "cancel").lower()
            session = db.get(SimulationSession, sim_id)
            if session is None or str(session.strategy_id or "") != "_workbench":
                to_delete.append(key)
                continue
            trade = (
                db.query(SimulationTrade)
                .filter(SimulationTrade.session_id == sim_id)
                .filter(SimulationTrade.id == trade_id)
                .filter(SimulationTrade.status == "open")
                .first()
            )
            if trade is None:
                if agent_session_id > 0:
                    event_rows.append(
                        WorkbenchAgentEventModel(
                            agent_session_id=agent_session_id,
                            event_type="WATCHDOG_DECISION_TIMEOUT",
                            severity="info",
                            payload_json={
                                "source": "agent_watchdog",
                                "decision_id": decision_id,
                                "session_id": sim_id,
                                "trade_id": trade_id,
                                "status": "skipped_trade_not_open",
                                "auto_decision": auto_decision,
                                "executed_at": self._safe_iso(now),
                            },
                            created_at=self._utc_now(),
                        )
                    )
                to_delete.append(key)
                continue
            if auto_decision != "approve":
                if agent_session_id > 0:
                    event_rows.append(
                        WorkbenchAgentEventModel(
                            agent_session_id=agent_session_id,
                            event_type="WATCHDOG_DECISION_TIMEOUT",
                            severity="warning",
                            payload_json={
                                "source": "agent_watchdog",
                                "decision_id": decision_id,
                                "session_id": sim_id,
                                "trade_id": trade_id,
                                "status": "kept_open",
                                "auto_decision": auto_decision,
                                "executed_at": self._safe_iso(now),
                            },
                            created_at=self._utc_now(),
                        )
                    )
                to_delete.append(key)
                continue

            exit_price = dec.get("price_at_review")
            try:
                px = float(exit_price) if exit_price is not None else None
            except Exception:
                px = None
            close_out = self._execute_timeout_close(
                db=db,
                session=session,
                trade_id=trade_id,
                exit_price=px,
            )
            ok = bool(close_out.get("ok", False))
            sev = "high" if ok else "warning"
            payload = {
                "source": "agent_watchdog",
                "decision_id": decision_id,
                "session_id": sim_id,
                "trade_id": trade_id,
                "status": "auto_closed" if ok else "auto_close_failed",
                "auto_decision": auto_decision,
                "executed_at": self._safe_iso(now),
                "result": close_out.get("data") if isinstance(close_out.get("data"), dict) else {},
                "error": str(close_out.get("error") or "")[:300] if not ok else None,
            }
            if agent_session_id > 0:
                event_rows.append(
                    WorkbenchAgentEventModel(
                        agent_session_id=agent_session_id,
                        event_type="WATCHDOG_DECISION_TIMEOUT",
                        severity=sev,
                        payload_json=payload,
                        created_at=self._utc_now(),
                    )
                )
            if ok and self._sms_enabled():
                self._twilio_send_sms(
                    f"Apprentice auto-decision executed: closed trade #{trade_id} on {session.symbol} {session.timeframe} after timeout."
                )
            to_delete.append(key)
        for k in to_delete:
            self._pending_decisions.pop(k, None)

    def _run_llm_watchdog_review(
        self,
        *,
        db,
        agent_row: WorkbenchAgentSessionModel,
        session: SimulationSession,
        mode: str,
        model_label: Optional[str],
        llm_url: Optional[str],
        allow_tools: bool,
        max_tool_steps: int,
        price: float,
        open_trades: List[SimulationTrade],
        segment_changes: List[Dict[str, Any]],
    ) -> Dict[str, Any]:
        agent = self._agent_runtime
        tool_state = {}
        snap = agent_row.last_snapshot_json if isinstance(agent_row.last_snapshot_json, dict) else {}
        if isinstance(snap.get("tool_state"), dict):
            tool_state = dict(snap.get("tool_state"))
        bars = snap.get("bars") if isinstance(snap.get("bars"), list) else []
        if len(bars) > 320:
            bars = bars[-320:]
        ctx = {
            "symbol": str(session.symbol or ""),
            "timeframe": str(session.timeframe or ""),
            "current_price": float(price),
            "open_trades": [self._trade_payload(t) for t in open_trades[:8]],
            "segment_changes": segment_changes[:8],
            "tool_state": tool_state,
            "bars": bars,
        }
        msg = (
            "You are a strict watchdog assistant. Review current open trades and market/tool context.\n"
            "Goal: decide if trader should HOLD, TIGHTEN_SL, PARTIAL_EXIT, or FULL_EXIT now.\n"
            "Return JSON only: "
            "{\"recommendation\":\"HOLD|TIGHTEN_SL|PARTIAL_EXIT|FULL_EXIT\","
            "\"severity\":\"info|warning|high\","
            "\"should_exit\":false,"
            "\"confidence\":0.0,"
            "\"message\":\"short rationale\"}"
        )
        def _watchdog_tool_executor(name: str, args: Dict[str, Any]) -> Dict[str, Any]:
            tname = str(name or "").strip()
            payload = args if isinstance(args, dict) else {}
            if tname == "scan_tool":
                tool_id = str(payload.get("tool_id") or "fvg").strip().lower()
                if tool_id not in {"fvg", "mean_rev"}:
                    return {"ok": False, "error": "watchdog_tool_not_allowed"}
                cfg = payload.get("config") if isinstance(payload.get("config"), dict) else {}
                bars_payload = payload.get("bars") if isinstance(payload.get("bars"), list) else bars
                if isinstance(bars_payload, list) and len(bars_payload) > 20000:
                    bars_payload = bars_payload[-20000:]
                return self._watchdog_scan_tool(
                    session=session,
                    tool_id=tool_id,
                    config=cfg,
                    bars=bars_payload,
                )
            if tname == "search_memory":
                query = str(payload.get("query") or "").strip()
                if not query:
                    return {"ok": False, "error": "missing_query"}
                try:
                    try:
                        limit = int(payload.get("limit") or 6)
                    except Exception:
                        limit = 6
                    memory_type = str(payload.get("memory_type") or "").strip() or None
                    hits = self._watchdog_memory_search(
                        db=db,
                        session=session,
                        query=query,
                        limit=max(1, min(8, limit)),
                        memory_type=memory_type,
                    )
                    return {"ok": True, "data": {"hits": hits, "count": int(len(hits))}}
                except Exception as exc:
                    return {"ok": False, "error": f"{type(exc).__name__}: {str(exc)[:180]}"}
            return {"ok": False, "error": "watchdog_tool_not_allowed"}

        out = agent.chat(
            message=msg,
            context=ctx,
            conversation_history=[],
            provider=str(mode),
            model_label=model_label,
            llm_url=llm_url,
            api_key=None,
            timeout_sec=45,
            permissions={"can_chat": True},
            tool_executor=_watchdog_tool_executor,
            allow_tools=bool(allow_tools),
            max_tool_steps=int(max(0, max_tool_steps)),
            allowed_tool_names=["scan_tool", "search_memory"],
            objective="watchdog_review",
        )
        if not bool(out.get("ok", False)):
            err = str(out.get("error") or "watchdog_model_error")[:280]
            return {
                "ok": False,
                "error": err,
                "severity": "warning",
                "message": err,
                "provider": str(out.get("provider") or mode),
                "model": str(out.get("model") or model_label or ""),
            }
        parsed = self._parse_watchdog_reply(str(out.get("reply") or ""))
        return {
            "ok": True,
            "provider": str(out.get("provider") or mode),
            "model": str(out.get("model") or model_label or ""),
            **parsed,
        }

    def _process_once(self) -> None:
        db = SessionLocal()
        try:
            if not self._enabled():
                return

            rows = (
                db.query(WorkbenchAgentSessionModel)
                .filter(WorkbenchAgentSessionModel.status == "ACTIVE")
                .order_by(WorkbenchAgentSessionModel.simulation_session_id.asc(), WorkbenchAgentSessionModel.id.desc())
                .all()
            )

            # Keep latest active agent session per simulation session.
            latest_by_sim: Dict[int, WorkbenchAgentSessionModel] = {}
            for row in rows:
                sid = int(row.simulation_session_id or 0)
                if sid <= 0:
                    continue
                if sid not in latest_by_sim:
                    latest_by_sim[sid] = row

            active_keys: set[Tuple[int, int]] = set()
            next_live_updates: Dict[int, Dict[str, Any]] = {}
            event_rows = []

            now = datetime.now(timezone.utc)
            self._process_pending_decisions(db=db, now=now, event_rows=event_rows)
            for agent in latest_by_sim.values():
                sim_id = int(agent.simulation_session_id or 0)
                if sim_id <= 0:
                    continue
                session = db.get(SimulationSession, sim_id)
                if session is None or str(session.strategy_id or "") != "_workbench":
                    continue
                agent_id = int(agent.id)
                cfg = self._watchdog_cfg(agent)
                interval_sec = float(cfg.get("interval_sec") or 30.0)
                last_scan = self._last_scan_at_by_agent.get(agent_id)
                if last_scan is not None:
                    elapsed = (now - last_scan).total_seconds()
                    if elapsed < interval_sec:
                        continue
                self._last_scan_at_by_agent[agent_id] = now

                live_bar = self._live_bar_from_agent_snapshot(agent)
                if live_bar is None:
                    continue
                price = float(live_bar["close"])
                prev_live = self._last_live_bar_by_agent.get(agent_id)
                closed_bar: Optional[Dict[str, Any]] = None
                if isinstance(prev_live, dict):
                    try:
                        prev_t = int(prev_live.get("time") or 0)
                        prev_c = float(prev_live.get("close"))
                        cur_t = int(live_bar.get("time") or 0)
                        if cur_t > prev_t and prev_t > 0 and math.isfinite(prev_c):
                            closed_bar = {"time": int(prev_t), "close": float(prev_c)}
                    except Exception:
                        closed_bar = None
                next_live_updates[int(agent_id)] = dict(live_bar)

                trigger_events = self._process_entry_triggers(
                    db=db,
                    agent=agent,
                    session=session,
                    now=now,
                    current_price=float(price),
                    closed_bar=closed_bar,
                    current_live_bar=live_bar,
                )
                if trigger_events:
                    event_rows.extend(trigger_events)

                open_trades = (
                    db.query(SimulationTrade)
                    .filter(SimulationTrade.session_id == sim_id)
                    .filter(SimulationTrade.status == "open")
                    .all()
                )
                segment_changes: List[Dict[str, Any]] = []
                for trade in open_trades:
                    key = (int(agent.id), int(trade.id))
                    active_keys.add(key)
                    seg = self._segment_for_trade(trade, float(price))
                    if seg is None:
                        continue
                    prev = self._last_segment_by_trade.get(key)
                    self._last_segment_by_trade[key] = int(seg)
                    if prev is None or int(prev) == int(seg):
                        continue

                    direction = str(trade.direction or "").upper()
                    sl = float(trade.stop_loss) if trade.stop_loss is not None else None
                    tp = float(trade.take_profit) if trade.take_profit is not None else None
                    if direction == "BUY" and sl is not None and tp is not None:
                        dist_to_tp = float(tp - float(price))
                    elif direction == "SELL" and sl is not None and tp is not None:
                        dist_to_tp = float(float(price) - tp)
                    else:
                        dist_to_tp = None

                    sev = "info"
                    if int(seg) <= 1:
                        sev = "warning"
                    if int(seg) >= 9:
                        sev = "high"
                    if int(seg) in {0, 10}:
                        sev = "high"

                    payload = {
                        "source": "agent_watchdog",
                        "trade_id": int(trade.id),
                        "session_id": sim_id,
                        "symbol": str(session.symbol or ""),
                        "timeframe": str(session.timeframe or ""),
                        "direction": direction,
                        "from_segment": int(prev),
                        "to_segment": int(seg),
                        "price": float(price),
                        "stop_loss": sl,
                        "take_profit": tp,
                        "distance_to_tp": float(dist_to_tp) if dist_to_tp is not None else None,
                        "updated_at": self._utc_now().isoformat(),
                    }
                    event_rows.append(
                        WorkbenchAgentEventModel(
                            agent_session_id=int(agent.id),
                            event_type="WATCHDOG_SEGMENT",
                            severity=sev,
                            payload_json=payload,
                            created_at=self._utc_now(),
                        )
                    )
                    segment_changes.append(
                        {
                            "trade_id": int(trade.id),
                            "direction": direction,
                            "from_segment": int(prev),
                            "to_segment": int(seg),
                            "price": float(price),
                        }
                    )

                    sms_msg = (
                        f"Watchdog {session.symbol} {session.timeframe}: "
                        f"Trade #{int(trade.id)} {direction} segment {int(prev)}->{int(seg)} "
                        f"price={float(price):.2f} SL={float(sl):.2f} TP={float(tp):.2f}"
                        if (sl is not None and tp is not None)
                        else (
                            f"Watchdog {session.symbol} {session.timeframe}: "
                            f"Trade #{int(trade.id)} {direction} segment {int(prev)}->{int(seg)} price={float(price):.2f}"
                        )
                    )
                    self._notify_sms_if_needed(key=key, segment=int(seg), message=sms_msg)

                mode = str(cfg.get("mode") or "deterministic")
                if mode != "deterministic" and len(open_trades) > 0:
                    llm_min = float(cfg.get("llm_min_interval_sec") or 180.0)
                    last_llm = self._last_llm_at_by_agent.get(agent_id)
                    llm_due = True
                    if last_llm is not None:
                        llm_due = (now - last_llm).total_seconds() >= llm_min
                    if segment_changes and llm_due:
                        review = self._run_llm_watchdog_review(
                            db=db,
                            agent_row=agent,
                            session=session,
                            mode=mode,
                            model_label=cfg.get("model_label"),
                            llm_url=cfg.get("llm_url"),
                            allow_tools=bool(cfg.get("allow_tools", False)),
                            max_tool_steps=int(cfg.get("tool_max_steps", 2) or 2),
                            price=float(price),
                            open_trades=open_trades,
                            segment_changes=segment_changes,
                        )
                        self._last_llm_at_by_agent[agent_id] = now
                        rev_payload = {
                            "source": "agent_watchdog",
                            "recipient": "apprentice_agent",
                            "mode": mode,
                            "session_id": sim_id,
                            "symbol": str(session.symbol or ""),
                            "timeframe": str(session.timeframe or ""),
                            "price": float(price),
                            "segment_changes": segment_changes[:8],
                            "provider": str(review.get("provider") or mode),
                            "model": str(review.get("model") or ""),
                            "ok": bool(review.get("ok", False)),
                            "recommendation": str(review.get("recommendation") or "HOLD"),
                            "should_exit": bool(review.get("should_exit", False)),
                            "confidence": review.get("confidence"),
                            "message": str(review.get("message") or review.get("error") or "")[:800],
                            "decision_window_sec": int(cfg.get("decision_window_sec") or 90),
                        }
                        target_trade_id: Optional[int] = None
                        if segment_changes:
                            try:
                                target_trade_id = int(segment_changes[-1].get("trade_id"))
                            except Exception:
                                target_trade_id = None
                        if target_trade_id is None and open_trades:
                            try:
                                target_trade_id = int(open_trades[0].id)
                            except Exception:
                                target_trade_id = None
                        if bool(review.get("should_exit", False)) and target_trade_id is not None and target_trade_id > 0:
                            decision_window_sec = int(cfg.get("decision_window_sec") or 90)
                            dkey = (int(sim_id), int(target_trade_id))
                            existing = self._pending_decisions.get(dkey)
                            decision_id = str(existing.get("decision_id")) if isinstance(existing, dict) and existing.get("decision_id") else f"wd_{int(now.timestamp())}_{sim_id}_{int(target_trade_id)}"
                            create_pending = True
                            if isinstance(existing, dict):
                                ex_status = str(existing.get("status") or "pending").lower()
                                ex_deadline = existing.get("deadline_at")
                                if ex_status == "pending" and isinstance(ex_deadline, datetime) and now < ex_deadline:
                                    create_pending = False
                            if create_pending:
                                self._pending_decisions[dkey] = {
                                    "decision_id": decision_id,
                                    "agent_session_id": int(agent.id),
                                    "simulation_session_id": int(sim_id),
                                    "trade_id": int(target_trade_id),
                                    "created_at": now,
                                    "deadline_at": now + timedelta(seconds=decision_window_sec),
                                    "auto_decision": "approve",
                                    "recommendation": str(review.get("recommendation") or "FULL_EXIT"),
                                    "message": str(review.get("message") or "")[:400],
                                    "price_at_review": float(price),
                                    "status": "pending",
                                }
                            rev_payload["pending_action"] = {
                                "tool": "close_trade",
                                "args": {
                                    "trade_id": int(target_trade_id),
                                },
                                "message": "Watchdog recommends closing this position unless trader overrides.",
                            }
                            rev_payload["auto_decision"] = "approve"
                            rev_payload["auto_decision_reason"] = "watchdog_timeout_exit"
                            rev_payload["decision_id"] = decision_id
                            rev_payload["deadline_at"] = self._safe_iso(now + timedelta(seconds=decision_window_sec))
                            if create_pending:
                                event_rows.append(
                                    WorkbenchAgentEventModel(
                                        agent_session_id=int(agent.id),
                                        event_type="WATCHDOG_DECISION_PENDING",
                                        severity="warning",
                                        payload_json={
                                            "source": "agent_watchdog",
                                            "recipient": "apprentice_agent",
                                            "decision_id": decision_id,
                                            "session_id": sim_id,
                                            "symbol": str(session.symbol or ""),
                                            "timeframe": str(session.timeframe or ""),
                                            "trade_id": int(target_trade_id),
                                            "recommendation": str(review.get("recommendation") or "FULL_EXIT"),
                                            "message": str(review.get("message") or "")[:500],
                                            "decision_window_sec": decision_window_sec,
                                            "deadline_at": self._safe_iso(now + timedelta(seconds=decision_window_sec)),
                                            "auto_decision": "approve",
                                        },
                                        created_at=self._utc_now(),
                                    )
                                )
                        sev = str(review.get("severity") or ("high" if bool(review.get("should_exit")) else "info")).lower()
                        if sev not in {"debug", "info", "warning", "high"}:
                            sev = "info"
                        event_rows.append(
                            WorkbenchAgentEventModel(
                                agent_session_id=int(agent.id),
                                event_type="WATCHDOG_MODEL_REVIEW",
                                severity=sev,
                                payload_json=rev_payload,
                                created_at=self._utc_now(),
                            )
                        )
                        if bool(review.get("should_exit")) and self._sms_enabled():
                            win = int(cfg.get("decision_window_sec") or 90)
                            trade_part = f" trade #{int(target_trade_id)}" if target_trade_id is not None else ""
                            self._twilio_send_sms(
                                (
                                    f"Apprentice alert {session.symbol} {session.timeframe}{trade_part}: "
                                    f"{str(review.get('recommendation') or 'EXIT')} | "
                                    f"{str(review.get('message') or '')[:220]} | "
                                    f"Decide in {win}s or auto-close."
                                )
                            )

            # Cleanup stale cache keys for closed/removed trades.
            stale = [k for k in self._last_segment_by_trade.keys() if k not in active_keys]
            for k in stale:
                self._last_segment_by_trade.pop(k, None)
                self._last_sms_segment_by_trade.pop(k, None)
            active_agent_ids = {int(a.id) for a in latest_by_sim.values()}
            for aid in list(self._last_scan_at_by_agent.keys()):
                if aid not in active_agent_ids:
                    self._last_scan_at_by_agent.pop(aid, None)
            for aid in list(self._last_llm_at_by_agent.keys()):
                if aid not in active_agent_ids:
                    self._last_llm_at_by_agent.pop(aid, None)
            for aid in list(self._last_live_bar_by_agent.keys()):
                if aid not in active_agent_ids:
                    self._last_live_bar_by_agent.pop(aid, None)

            needs_commit = bool(event_rows) or bool(db.new) or bool(db.dirty) or bool(db.deleted)
            if needs_commit:
                for ev in event_rows:
                    db.add(ev)
                db.commit()
            if next_live_updates:
                self._last_live_bar_by_agent.update(next_live_updates)
        except Exception as exc:
            try:
                db.rollback()
            except Exception:
                pass
            logger.error("Agent watchdog loop error: %s", exc, exc_info=True)
        finally:
            db.close()

    def _loop(self) -> None:
        while not self._stop.is_set():
            self._process_once()
            self._stop.wait(self._interval_sec())

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._loop, daemon=True, name="agent-watchdog")
        self._thread.start()
        logger.info("Agent watchdog service started")

    def stop(self) -> None:
        self._stop.set()
        if self._thread and self._thread.is_alive():
            self._thread.join(timeout=2.0)
        logger.info("Agent watchdog service stopped")
