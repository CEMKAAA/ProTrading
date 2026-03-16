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
        self._last_stale_live_warn_at_by_agent: Dict[int, datetime] = {}
        self._live_bar_cache_lock = threading.RLock()
        self._agent_eval_locks: Dict[int, threading.RLock] = {}
        self._agent_eval_locks_guard = threading.RLock()

    @staticmethod
    def _utc_now() -> datetime:
        return datetime.now(timezone.utc)

    def _get_agent_eval_lock(self, agent_id: int) -> threading.RLock:
        key = int(agent_id)
        with self._agent_eval_locks_guard:
            lock = self._agent_eval_locks.get(key)
            if lock is None:
                lock = threading.RLock()
                self._agent_eval_locks[key] = lock
            return lock

    @staticmethod
    def _backend_live_relay_enabled(session: SimulationSession) -> bool:
        cfg = getattr(session, "config_json", None)
        cfg_obj: Dict[str, Any] = {}
        if isinstance(cfg, dict):
            cfg_obj = dict(cfg)
        elif isinstance(cfg, str):
            raw = str(cfg).strip()
            if raw:
                try:
                    parsed = json.loads(raw)
                    if isinstance(parsed, dict):
                        cfg_obj = parsed
                except Exception:
                    cfg_obj = {}
        live = cfg_obj.get("live_control") if isinstance(cfg_obj.get("live_control"), dict) else {}
        source = str(live.get("source") or "").strip().lower()
        return (
            str(getattr(session, "mode", "") or "").strip().lower() == "live"
            and bool(live.get("enabled", False))
            and bool(live.get("backend_native", False))
            and source == "mt5"
        )

    @staticmethod
    def _interval_sec() -> float:
        try:
            raw = float(os.getenv("AGENT_WATCHDOG_INTERVAL_SEC", "5"))
        except Exception:
            raw = 5.0
        return max(1.0, min(300.0, raw))

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
            interval = float(cfg.get("watchdog_interval_sec") or 5.0)
        except Exception:
            interval = 5.0
        interval = max(1.0, min(300.0, interval))
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
        try:
            live_bar_max_age_sec = float(cfg.get("watchdog_live_bar_max_age_sec") or max(interval * 3.0, 120.0))
        except Exception:
            live_bar_max_age_sec = max(interval * 3.0, 120.0)
        live_bar_max_age_sec = max(15.0, min(3600.0, float(live_bar_max_age_sec)))
        return {
            "mode": mode_raw,
            "interval_sec": interval,
            "llm_min_interval_sec": llm_min,
            "model_label": model_label,
            "llm_url": llm_url,
            "allow_tools": bool(allow_tools),
            "tool_max_steps": int(tool_steps),
            "decision_window_sec": int(decision_window_sec),
            "live_bar_max_age_sec": float(live_bar_max_age_sec),
        }

    @staticmethod
    def _timeframe_minutes(timeframe: Any) -> int:
        tf = str(timeframe or "").strip().upper()
        if not tf:
            return 15
        if tf.startswith("M"):
            try:
                return max(1, int(tf[1:]))
            except Exception:
                return 15
        if tf.startswith("H"):
            try:
                return max(1, int(tf[1:])) * 60
            except Exception:
                return 15
        if tf in {"D", "D1"}:
            return 1440
        return 15

    @staticmethod
    def _is_live_bar_fresh(
        *,
        now: datetime,
        live_bar: Optional[Dict[str, Any]],
        max_age_sec: float,
        max_future_skew_sec: float = 5.0,
    ) -> bool:
        if not isinstance(live_bar, dict):
            return False
        try:
            bar_time = int(live_bar.get("time") or 0)
        except Exception:
            return False
        if bar_time <= 0:
            return False
        # Prefer feed update timestamp when present (keepalive/tick push time).
        # Bar open time can be minutes old on M15+ while feed is still healthy.
        freshness_ref = bar_time
        try:
            asof_time = int(live_bar.get("asof_time") or 0)
            if asof_time > 0:
                freshness_ref = asof_time
        except Exception:
            pass
        try:
            age_sec = float(now.timestamp()) - float(freshness_ref)
        except Exception:
            return False
        if age_sec < -float(max_future_skew_sec):
            return False
        return bool(age_sec <= float(max_age_sec))

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
    def _trigger_trade_id(row: Dict[str, Any]) -> int:
        if not isinstance(row, dict):
            return 0
        res = row.get("result") if isinstance(row.get("result"), dict) else {}
        for k in ("id", "trade_id"):
            try:
                v = int(res.get(k) or 0)
                if v > 0:
                    return int(v)
            except Exception:
                continue
        return 0

    def _maybe_move_trade_stop_to_breakeven(
        self,
        *,
        db,
        agent: WorkbenchAgentSessionModel,
        session: SimulationSession,
        trade: SimulationTrade,
        price: float,
        now: datetime,
    ) -> Optional[Dict[str, Any]]:
        snap = agent.last_snapshot_json if isinstance(agent.last_snapshot_json, dict) else {}
        raw_triggers = snap.get("agent_trade_triggers") if isinstance(snap.get("agent_trade_triggers"), list) else []
        if not raw_triggers:
            return None
        target_trade_id = int(getattr(trade, "id", 0) or 0)
        if target_trade_id <= 0:
            return None
        matched_idx = -1
        matched_row: Optional[Dict[str, Any]] = None
        for idx, raw in enumerate(raw_triggers[:200]):
            row = raw if isinstance(raw, dict) else {}
            if not row:
                continue
            if self._trigger_trade_id(row) != target_trade_id:
                continue
            trade_args = row.get("trade_args") if isinstance(row.get("trade_args"), dict) else {}
            if not bool(trade_args.get("breakeven_at_1r", False)):
                continue
            matched_idx = idx
            matched_row = dict(row)
            break
        if matched_idx < 0 or not isinstance(matched_row, dict):
            return None

        be_meta = matched_row.get("breakeven") if isinstance(matched_row.get("breakeven"), dict) else {}
        if bool(be_meta.get("moved_to_entry", False)):
            return None

        try:
            direction = str(trade.direction or "").upper()
            entry_price = float(trade.entry_price)
            stop_loss = float(trade.stop_loss)
            px = float(price)
        except Exception:
            return None
        if direction not in {"BUY", "SELL"}:
            return None
        if not (math.isfinite(entry_price) and math.isfinite(stop_loss) and math.isfinite(px)):
            return None

        risk_distance = abs(float(entry_price) - float(stop_loss))
        if risk_distance <= max(1e-9, abs(float(entry_price)) * 1e-9):
            return None
        one_r_level = float(entry_price + risk_distance) if direction == "BUY" else float(entry_price - risk_distance)
        hit_one_r = bool(px >= one_r_level) if direction == "BUY" else bool(px <= one_r_level)
        if not hit_one_r:
            return None

        moved = False
        old_stop = float(stop_loss)
        new_stop = float(entry_price)
        eps = max(1e-9, abs(float(entry_price)) * 1e-9)
        if direction == "BUY":
            if old_stop < (new_stop - eps):
                trade.stop_loss = float(new_stop)
                db.add(trade)
                moved = True
        else:
            if old_stop > (new_stop + eps):
                trade.stop_loss = float(new_stop)
                db.add(trade)
                moved = True

        # Keep in-memory engine stop aligned with persisted DB stop.
        if moved:
            try:
                from ..api.simulation_routes import _get_or_create_engine
                engine = _get_or_create_engine(session=session, db=db)
                if isinstance(getattr(engine, "open_positions", None), list):
                    for pos in engine.open_positions:
                        if not isinstance(pos, dict):
                            continue
                        try:
                            if int(pos.get("id") or 0) == int(target_trade_id):
                                pos["stop_loss"] = float(new_stop)
                                break
                        except Exception:
                            continue
            except Exception:
                pass

        # Persist trigger-side breakeven state for restart-safe visibility.
        row2 = dict(matched_row)
        be2 = dict(be_meta)
        be2["enabled"] = True
        be2["armed_at"] = str(be2.get("armed_at") or row2.get("executed_at") or row2.get("created_at") or self._safe_iso(now))
        be2["initial_risk_distance"] = float(round(risk_distance, 6))
        be2["one_r_level"] = float(round(one_r_level, 6))
        be2["moved_to_entry"] = True
        be2["moved_at"] = self._safe_iso(now)
        be2["move_price"] = float(px)
        be2["old_stop_loss"] = float(old_stop)
        be2["new_stop_loss"] = float(new_stop)
        row2["breakeven"] = be2
        new_rows: List[Dict[str, Any]] = []
        for i, raw in enumerate(raw_triggers[:200]):
            if i == matched_idx:
                new_rows.append(row2)
            else:
                new_rows.append(dict(raw) if isinstance(raw, dict) else {})
        new_snap = dict(snap) if isinstance(snap, dict) else {}
        new_snap["agent_trade_triggers"] = new_rows
        agent.last_snapshot_json = new_snap
        agent.updated_at = self._utc_now()
        db.add(agent)

        return {
            "source": "agent_watchdog",
            "trigger_id": str(row2.get("id") or ""),
            "trade_id": int(target_trade_id),
            "direction": str(direction),
            "entry_price": float(entry_price),
            "one_r_level": float(one_r_level),
            "price": float(px),
            "old_stop_loss": float(old_stop),
            "new_stop_loss": float(new_stop),
            "moved": bool(moved),
        }

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
            # Feed freshness timestamp:
            # prefer live_stream.pushed_at_ms, fallback to snapshot ts.
            asof_time = 0
            live_stream = tool_state.get("live_stream") if isinstance(tool_state.get("live_stream"), dict) else {}
            if isinstance(live_stream, dict):
                try:
                    pushed_at_ms = float(live_stream.get("pushed_at_ms") or 0.0)
                    if math.isfinite(pushed_at_ms) and pushed_at_ms > 0:
                        asof_time = int(pushed_at_ms / 1000.0)
                except Exception:
                    asof_time = 0
            if asof_time <= 0:
                ts_raw = str(snap.get("ts") or "").strip()
                if ts_raw:
                    try:
                        ts_dt = datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
                        if ts_dt.tzinfo is None:
                            ts_dt = ts_dt.replace(tzinfo=timezone.utc)
                        asof_time = int(ts_dt.timestamp())
                    except Exception:
                        asof_time = 0
            if asof_time > 0:
                out["asof_time"] = int(asof_time)
            return out
        except Exception:
            return None

    @staticmethod
    def _live_bar_fallback_from_provider(
        *,
        session: SimulationSession,
        now: datetime,
    ) -> Optional[Dict[str, Any]]:
        """Fallback live-bar source when agent snapshot has no fresh LIVE_TICK.

        This keeps trigger scheduling functional even when agent loop/tool-state
        pushes are temporarily unavailable.
        """
        try:
            from ..api import simulation_routes as sim_routes

            service = sim_routes._get_mt5_service_singleton()
            symbol = str(session.symbol or "").strip() or "XAUUSD"
            timeframe = str(session.timeframe or "M15").strip().upper() or "M15"
            bars = service.get_recent_candles(
                symbol=symbol,
                timeframe=timeframe,
                count=2,
            )
            if not isinstance(bars, list) or len(bars) == 0:
                return None
            lb = bars[-1] if isinstance(bars[-1], dict) else None
            if not isinstance(lb, dict):
                return None
            t = int(lb.get("time_unix") or lb.get("time") or 0)
            o = float(lb.get("open"))
            h = float(lb.get("high"))
            l = float(lb.get("low"))
            c = float(lb.get("close"))
            v = float(lb.get("volume") or 0.0)
            if t <= 0:
                return None
            if not all(math.isfinite(x) for x in (o, h, l, c, v)):
                return None
            return {
                "time": int(t),
                "open": float(o),
                "high": float(h),
                "low": float(l),
                "close": float(c),
                "volume": float(v),
                "asof_time": int(now.timestamp()),
            }
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

    @staticmethod
    def _parse_iso_utc(v: Any) -> Optional[datetime]:
        raw = str(v or "").strip()
        if not raw:
            return None
        try:
            dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        except Exception:
            return None
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc)

    @staticmethod
    def _is_retryable_execution_error(error_text: str, *, retry_guardrail_blocks: bool) -> bool:
        s = str(error_text or "").strip().lower()
        if not s:
            return False
        # Permanent errors should fail fast.
        permanent_markers = {
            "permission_denied",
            "invalid_",
            "rr_mismatch",
            "rr_below_min",
            "lot_size_mismatch_with_risk_model",
            "scheduled_trigger_mismatch_with_proposal",
            "missing_mtf_proposal_for_schedule",
            "agent_session_not_found",
        }
        if any(marker in s for marker in permanent_markers):
            return False
        if "blocked:requires_user_confirm_for_trade" in s:
            return False
        if s.startswith("blocked:guardrail:"):
            if not retry_guardrail_blocks:
                return False
            return any(x in s for x in {"outside_session_window", "high_impact_news"})
        transient_markers = {
            "timeout",
            "temporarily",
            "market closed",
            "off quotes",
            "requote",
            "price changed",
            "trade context busy",
            "connection",
            "service unavailable",
            "network",
            "too many requests",
            "rate limit",
            "guardrail:",
        }
        return any(marker in s for marker in transient_markers)

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
        live_bar_max_age_sec: float = 120.0,
    ) -> List[WorkbenchAgentEventModel]:
        event_rows: List[WorkbenchAgentEventModel] = []
        snap = agent.last_snapshot_json if isinstance(agent.last_snapshot_json, dict) else {}
        raw_triggers = snap.get("agent_trade_triggers") if isinstance(snap.get("agent_trade_triggers"), list) else []
        if not raw_triggers:
            return event_rows
        try:
            from ..api.simulation_routes import _normalize_agent_trigger_condition
        except Exception:
            _normalize_agent_trigger_condition = None
        cfg = agent.config_json if isinstance(agent.config_json, dict) else {}
        perms = cfg.get("agent_permissions") if isinstance(cfg.get("agent_permissions"), dict) else {}
        trigger_requires_approval_default = bool(cfg.get("watchdog_trigger_requires_approval", False))
        changed = False
        next_triggers: List[Dict[str, Any]] = []

        def _extract_last_live_bar(trigger_row: Dict[str, Any]) -> Optional[Dict[str, Any]]:
            lb = trigger_row.get("_last_live_bar") if isinstance(trigger_row.get("_last_live_bar"), dict) else None
            if not isinstance(lb, dict):
                return None
            try:
                ts = int(lb.get("time") or 0)
                close = float(lb.get("close"))
                if ts <= 0 or (not math.isfinite(close)):
                    return None
                return {"time": int(ts), "close": float(close)}
            except Exception:
                return None

        def _condition_side(cond_name: Any) -> Optional[str]:
            c = _canonical_condition(cond_name)
            if c in {"close_below", "price_below", "sweep_below"}:
                return "below"
            if c in {"close_above", "price_above", "sweep_above"}:
                return "above"
            return None

        def _canonical_condition(cond_name: Any) -> str:
            raw = cond_name
            if callable(_normalize_agent_trigger_condition):
                try:
                    norm = _normalize_agent_trigger_condition(raw)
                    if norm:
                        raw = norm
                except Exception:
                    raw = cond_name
            return str(raw or "").strip().lower()

        def _is_reclaim_pair(pre_cond_name: Any, cond_name: Any) -> bool:
            pre_side = _condition_side(pre_cond_name)
            cond_side = _condition_side(cond_name)
            return pre_side in {"above", "below"} and cond_side in {"above", "below"} and pre_side != cond_side

        def _evaluate_live_touch(cond_name: str, level_value: float) -> Tuple[str, Optional[float], Optional[int]]:
            if not math.isfinite(level_value):
                return ("no_eval", None, None)
            if not (live_bar_fresh and isinstance(current_live_bar, dict)):
                return ("no_eval", None, None)
            eval_tm: Optional[int] = None
            try:
                ltm = int(current_live_bar.get("time") or 0)
                if ltm > 0:
                    eval_tm = ltm
            except Exception:
                eval_tm = None
            side = _condition_side(cond_name)
            live_close: Optional[float] = None
            try:
                lc = float(current_live_bar.get("close"))
                if math.isfinite(lc):
                    live_close = float(lc)
            except Exception:
                live_close = None
            if cond_name == "sweep_below":
                try:
                    lo = float(current_live_bar.get("low"))
                    if math.isfinite(lo) and live_close is not None:
                        hit = bool(lo <= level_value and live_close >= level_value)
                        return ("hit" if hit else "miss", float(lo), eval_tm)
                except Exception:
                    return ("no_eval", None, eval_tm)
                return ("no_eval", None, eval_tm)
            if cond_name == "sweep_above":
                try:
                    hi = float(current_live_bar.get("high"))
                    if math.isfinite(hi) and live_close is not None:
                        hit = bool(hi >= level_value and live_close <= level_value)
                        return ("hit" if hit else "miss", float(hi), eval_tm)
                except Exception:
                    return ("no_eval", None, eval_tm)
                return ("no_eval", None, eval_tm)
            if side == "below":
                try:
                    lo = float(current_live_bar.get("low"))
                    if math.isfinite(lo):
                        return ("hit" if bool(lo <= level_value) else "miss", float(lo), eval_tm)
                except Exception:
                    return ("no_eval", None, eval_tm)
                return ("no_eval", None, eval_tm)
            if side == "above":
                try:
                    hi = float(current_live_bar.get("high"))
                    if math.isfinite(hi):
                        return ("hit" if bool(hi >= level_value) else "miss", float(hi), eval_tm)
                except Exception:
                    return ("no_eval", None, eval_tm)
                return ("no_eval", None, eval_tm)
            return ("invalid_condition", None, eval_tm)

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
            if trigger_requires_approval:
                # Approval-gated triggers should transition to pending_approval instead of
                # failing early on permission checks. Force place permission on the
                # watchdog path while keeping explicit confirmation required.
                trigger_perms["can_place_trades"] = True
                trigger_perms["requires_user_confirm_for_trade"] = True
            else:
                # Trigger-driven entries should auto-execute by default once condition is met.
                trigger_perms["requires_user_confirm_for_trade"] = False
            try:
                trigger_max_retries = int(
                    trigger_guardrails.get("max_execution_retries")
                    if isinstance(trigger_guardrails, dict) and trigger_guardrails.get("max_execution_retries") is not None
                    else cfg.get("watchdog_trigger_max_retries", os.getenv("AGENT_WATCHDOG_TRIGGER_MAX_RETRIES", 6))
                )
            except Exception:
                trigger_max_retries = 6
            trigger_max_retries = max(0, min(20, int(trigger_max_retries)))
            try:
                retry_backoff_base_sec = float(
                    trigger_guardrails.get("retry_backoff_base_sec")
                    if isinstance(trigger_guardrails, dict) and trigger_guardrails.get("retry_backoff_base_sec") is not None
                    else cfg.get("watchdog_trigger_retry_backoff_base_sec", os.getenv("AGENT_WATCHDOG_TRIGGER_RETRY_BACKOFF_BASE_SEC", 5))
                )
            except Exception:
                retry_backoff_base_sec = 5.0
            retry_backoff_base_sec = max(1.0, min(300.0, float(retry_backoff_base_sec)))
            try:
                retry_backoff_cap_sec = float(
                    trigger_guardrails.get("retry_backoff_cap_sec")
                    if isinstance(trigger_guardrails, dict) and trigger_guardrails.get("retry_backoff_cap_sec") is not None
                    else cfg.get("watchdog_trigger_retry_backoff_cap_sec", os.getenv("AGENT_WATCHDOG_TRIGGER_RETRY_BACKOFF_CAP_SEC", 300))
                )
            except Exception:
                retry_backoff_cap_sec = 300.0
            retry_backoff_cap_sec = max(float(retry_backoff_base_sec), min(1800.0, float(retry_backoff_cap_sec)))
            retry_guardrail_blocks = bool(
                trigger_guardrails.get("retry_on_guardrail_block", True)
                if isinstance(trigger_guardrails, dict)
                else True
            )

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
            next_retry_dt = self._parse_iso_utc(t.get("next_retry_at"))
            if next_retry_dt is not None and now < next_retry_dt:
                next_triggers.append(t)
                continue

            live_bar_fresh = self._is_live_bar_fresh(
                now=now,
                live_bar=current_live_bar if isinstance(current_live_bar, dict) else None,
                max_age_sec=float(max(5.0, float(live_bar_max_age_sec))),
            )
            eval_closed_bar = closed_bar if isinstance(closed_bar, dict) else None
            cur_live_ts: int = 0
            cur_live_close: Optional[float] = None
            if live_bar_fresh and isinstance(current_live_bar, dict):
                try:
                    cur_live_ts = int(current_live_bar.get("time") or 0)
                    cur_live_close_val = float(current_live_bar.get("close"))
                    if cur_live_ts > 0 and math.isfinite(cur_live_close_val):
                        cur_live_close = float(cur_live_close_val)
                    else:
                        cur_live_ts = 0
                        cur_live_close = None
                except Exception:
                    cur_live_ts = 0
                    cur_live_close = None

            # Restart resilience for close_* conditions:
            # when in-memory prev live bar cache is empty, recover last closed bar
            # from persisted per-trigger marker.
            if eval_closed_bar is None and cur_live_ts > 0 and cur_live_close is not None:
                last_live = _extract_last_live_bar(t)
                if isinstance(last_live, dict):
                    try:
                        prev_ts = int(last_live.get("time") or 0)
                        prev_close = float(last_live.get("close"))
                        if prev_ts > 0 and math.isfinite(prev_close) and cur_live_ts > prev_ts:
                            eval_closed_bar = {"time": int(prev_ts), "close": float(prev_close)}
                    except Exception:
                        pass

            if cur_live_ts > 0 and cur_live_close is not None:
                prev_live_marker = _extract_last_live_bar(t)
                prev_ts = int(prev_live_marker.get("time") or 0) if isinstance(prev_live_marker, dict) else 0
                prev_close = float(prev_live_marker.get("close")) if isinstance(prev_live_marker, dict) else None
                if (cur_live_ts != prev_ts) or (prev_close is None) or (abs(float(prev_close) - float(cur_live_close)) > 1e-9):
                    t["_last_live_bar"] = {"time": int(cur_live_ts), "close": float(cur_live_close)}
                    changed = True

            def _evaluate_condition(cond_name: str, level_value: float) -> Tuple[str, Optional[float], Optional[int]]:
                eval_px: Optional[float] = None
                eval_tm: Optional[int] = None
                if cond_name in {"close_below", "close_above"}:
                    if isinstance(eval_closed_bar, dict):
                        try:
                            cpx = float(eval_closed_bar.get("close"))
                            ctm = int(eval_closed_bar.get("time") or 0)
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
                        if not live_bar_fresh:
                            return ("no_eval", None, None)
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
                if cond_name == "sweep_below":
                    touch_state, touch_px, touch_tm = _evaluate_live_touch(cond_name, level_value)
                    return (touch_state, touch_px, touch_tm)
                if cond_name == "sweep_above":
                    touch_state, touch_px, touch_tm = _evaluate_live_touch(cond_name, level_value)
                    return (touch_state, touch_px, touch_tm)
                return ("invalid_condition", eval_px, eval_tm)

            cond = _canonical_condition(t.get("condition"))
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
                cancel_cond = _canonical_condition(cancel_rule.get("condition"))
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
            pre_hit_this_cycle = False
            if state not in {"waiting_precondition", "waiting_entry"}:
                state = "waiting_precondition" if isinstance(pre, dict) else "waiting_entry"
                t["state"] = state
                changed = True

            if state == "waiting_precondition":
                if not isinstance(pre, dict):
                    t["state"] = "waiting_entry"
                    changed = True
                else:
                    pcond = _canonical_condition(pre.get("condition"))
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
                    # Reclaim-touch assist:
                    # if precondition/entry forms a reclaim pair, arm precondition on
                    # intrabar touch so brief sweeps are not missed between scans.
                    if p_state in {"no_eval", "miss"} and _is_reclaim_pair(pcond, cond):
                        touch_state, touch_px, touch_tm = _evaluate_live_touch(pcond, float(plevel))
                        if touch_state == "hit":
                            p_state = "hit"
                            p_eval_px = float(touch_px) if touch_px is not None else None
                            _p_eval_tm = int(touch_tm) if (touch_tm is not None and touch_tm > 0) else _p_eval_tm
                    if p_state in {"no_eval", "miss"}:
                        next_triggers.append(t)
                        continue
                    pre2 = dict(pre)
                    pre2["hit_at"] = self._safe_iso(now)
                    pre2["hit_price"] = float(p_eval_px) if p_eval_px is not None else None
                    t["precondition"] = pre2
                    t["state"] = "waiting_entry"
                    t["armed_at"] = self._safe_iso(now)
                    pre_hit_this_cycle = True
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

            entry_eval_mode = str(t.get("entry_evaluation_mode") or "").strip().lower()
            reclaim_touch_entry = bool(entry_eval_mode == "reclaim_touch")
            if (not reclaim_touch_entry) and isinstance(t.get("precondition"), dict):
                reclaim_touch_entry = _is_reclaim_pair((t.get("precondition") or {}).get("condition"), cond)
            if pre_hit_this_cycle and cond in {"close_below", "close_above"}:
                # Entry cannot be satisfied by the already-closed prior bar once the
                # precondition has just armed on the current scan. Same-scan execution
                # must come from the live reclaim/touch, not a stale historical close.
                c_state, eval_price, eval_time = ("no_eval", None, None)
            else:
                c_state, eval_price, eval_time = _evaluate_condition(cond, float(level))
            if c_state in {"no_eval", "miss"} and reclaim_touch_entry:
                touch_state, touch_px, touch_tm = _evaluate_live_touch(cond, float(level))
                if touch_state == "hit":
                    c_state = "hit"
                    eval_price = float(touch_px) if touch_px is not None else eval_price
                    eval_time = int(touch_tm) if (touch_tm is not None and touch_tm > 0) else eval_time
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
            dynamic_stop_meta: Optional[Dict[str, Any]] = None
            if bool(place_args.get("dynamic_stop_from_precondition", False)):
                pre_obj = t.get("precondition") if isinstance(t.get("precondition"), dict) else {}
                hit_price_val = pre_obj.get("hit_price")
                hit_price = None
                hit_price_source = "precondition_hit_price"
                try:
                    hp = float(hit_price_val)
                    if math.isfinite(hp) and hp > 0:
                        hit_price = float(hp)
                except Exception:
                    hit_price = None
                if hit_price is None:
                    try:
                        hp_fallback = float(pre_obj.get("trigger_price"))
                        if math.isfinite(hp_fallback) and hp_fallback > 0:
                            hit_price = float(hp_fallback)
                            hit_price_source = "precondition_trigger_price_fallback"
                    except Exception:
                        hit_price = None
                stop_buffer = 0.0
                try:
                    stop_buffer = float(place_args.get("dynamic_stop_buffer_points") or 0.0)
                    if not math.isfinite(stop_buffer):
                        stop_buffer = 0.0
                except Exception:
                    stop_buffer = 0.0
                stop_buffer = max(0.0, float(stop_buffer))
                if hit_price is not None:
                    direction = str(place_args.get("direction") or t.get("direction") or "").strip().upper()
                    base_stop = None
                    try:
                        base = float(place_args.get("stop_loss"))
                        if math.isfinite(base) and base > 0:
                            base_stop = float(base)
                    except Exception:
                        base_stop = None
                    resolved_stop: Optional[float] = None
                    if direction == "BUY":
                        candidate = float(hit_price) - float(stop_buffer)
                        if math.isfinite(candidate) and candidate > 0:
                            resolved_stop = float(candidate if base_stop is None else min(base_stop, candidate))
                    elif direction == "SELL":
                        candidate = float(hit_price) + float(stop_buffer)
                        if math.isfinite(candidate) and candidate > 0:
                            resolved_stop = float(candidate if base_stop is None else max(base_stop, candidate))
                    if resolved_stop is not None:
                        place_args["stop_loss"] = float(resolved_stop)
                        dynamic_stop_meta = {
                            "enabled": True,
                            "resolved_at": self._safe_iso(now),
                            "from_precondition_hit_price": float(hit_price),
                            "hit_price_source": str(hit_price_source),
                            "buffer_points": float(stop_buffer),
                            "base_stop_loss": float(base_stop) if base_stop is not None else None,
                            "resolved_stop_loss": float(resolved_stop),
                        }
                else:
                    t["dynamic_stop_warning"] = "missing_precondition_hit_price"
                    changed = True

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
                if bool(place_args.get("breakeven_at_1r", False)):
                    trade_row = t.get("result") if isinstance(t.get("result"), dict) else {}
                    entry_px = None
                    stop_px = None
                    try:
                        ep = float(trade_row.get("entry_price"))
                        if math.isfinite(ep):
                            entry_px = float(ep)
                    except Exception:
                        entry_px = None
                    if entry_px is None:
                        try:
                            ep2 = float(eval_price)
                            if math.isfinite(ep2):
                                entry_px = float(ep2)
                        except Exception:
                            entry_px = None
                    try:
                        sp = float(place_args.get("stop_loss"))
                        if math.isfinite(sp):
                            stop_px = float(sp)
                    except Exception:
                        stop_px = None
                    risk_dist = (
                        abs(float(entry_px) - float(stop_px))
                        if (entry_px is not None and stop_px is not None)
                        else None
                    )
                    t["breakeven"] = {
                        "enabled": True,
                        "armed_at": self._safe_iso(now),
                        "initial_risk_distance": float(risk_dist) if risk_dist is not None else None,
                        "moved_to_entry": False,
                    }
                t.pop("next_retry_at", None)
                t.pop("last_error", None)
                if isinstance(dynamic_stop_meta, dict):
                    t["dynamic_stop"] = dict(dynamic_stop_meta)
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
                            "dynamic_stop": dict(dynamic_stop_meta) if isinstance(dynamic_stop_meta, dict) else None,
                            "trade": result.get("data") if isinstance(result.get("data"), dict) else {},
                        },
                        created_at=self._utc_now(),
                    )
                )
            elif bool(result.get("requires_confirmation")) and isinstance(result.get("pending_action"), dict):
                t["status"] = "pending_approval"
                t["pending_at"] = self._safe_iso(now)
                t["pending_action"] = result.get("pending_action")
                t.pop("next_retry_at", None)
                if isinstance(dynamic_stop_meta, dict):
                    t["dynamic_stop"] = dict(dynamic_stop_meta)
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
                err_text = str(result.get("error") or "trigger_execution_failed")[:280]
                attempts_prev = int(t.get("execution_attempts") or 0)
                is_guardrail_block = str(err_text).strip().lower().startswith("blocked:guardrail:")
                attempts = attempts_prev + (0 if (is_guardrail_block and bool(retry_guardrail_blocks)) else 1)
                retryable = self._is_retryable_execution_error(
                    err_text,
                    retry_guardrail_blocks=bool(retry_guardrail_blocks),
                )
                can_retry = bool(retryable and attempts <= int(trigger_max_retries))
                if can_retry and exp_dt is not None and now >= exp_dt:
                    can_retry = False
                if can_retry:
                    backoff_sec = min(
                        float(retry_backoff_cap_sec),
                        float(retry_backoff_base_sec) * float(max(1.0, 2.0 ** max(0, attempts - 1))),
                    )
                    retry_at = now + timedelta(seconds=float(backoff_sec))
                    if exp_dt is not None and retry_at >= exp_dt:
                        can_retry = False
                if can_retry:
                    t["status"] = "pending"
                    t["state"] = "waiting_entry"
                    t["execution_attempts"] = int(attempts)
                    t["last_error"] = str(err_text)
                    t["last_failed_at"] = self._safe_iso(now)
                    t["next_retry_at"] = self._safe_iso(retry_at)
                    if isinstance(dynamic_stop_meta, dict):
                        t["dynamic_stop"] = dict(dynamic_stop_meta)
                    changed = True
                    event_rows.append(
                        WorkbenchAgentEventModel(
                            agent_session_id=int(agent.id),
                            event_type="WATCHDOG_ENTRY_RETRY_SCHEDULED",
                            severity="warning",
                            payload_json={
                                "source": "agent_watchdog",
                                "trigger_id": str(t.get("id") or ""),
                                "condition": cond,
                                "trigger_price": float(level),
                                "hit_price": float(eval_price),
                                "error": str(err_text),
                                "attempt": int(attempts),
                                "max_retries": int(trigger_max_retries),
                                "next_retry_at": self._safe_iso(retry_at),
                            },
                            created_at=self._utc_now(),
                        )
                    )
                else:
                    t["status"] = "failed"
                    t["failed_at"] = self._safe_iso(now)
                    t["error"] = str(err_text)
                    t["execution_attempts"] = int(attempts)
                    if isinstance(dynamic_stop_meta, dict):
                        t["dynamic_stop"] = dict(dynamic_stop_meta)
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
                                "error": str(err_text),
                                "attempt": int(attempts),
                                "max_retries": int(trigger_max_retries),
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
                if self._backend_live_relay_enabled(session):
                    continue
                agent_id = int(agent.id)
                cfg = self._watchdog_cfg(agent)
                interval_sec = float(cfg.get("interval_sec") or 5.0)
                tf_minutes = self._timeframe_minutes(getattr(session, "timeframe", None))
                # Ensure fast-timeframe sessions are sampled multiple times per bar.
                # Example: M1 -> <=3s, M5 -> <=15s.
                if tf_minutes > 0:
                    cadence_cap = max(1.0, min(30.0, (float(tf_minutes) * 60.0) / 20.0))
                    interval_sec = min(float(interval_sec), float(cadence_cap))
                last_scan = self._last_scan_at_by_agent.get(agent_id)
                if last_scan is not None:
                    elapsed = (now - last_scan).total_seconds()
                    if elapsed < interval_sec:
                        continue
                self._last_scan_at_by_agent[agent_id] = now

                live_bar = self._live_bar_from_agent_snapshot(agent)
                if live_bar is None:
                    live_bar = self._live_bar_fallback_from_provider(session=session, now=now)
                if live_bar is None:
                    continue
                live_bar_max_age_sec = float(cfg.get("live_bar_max_age_sec") or max(interval_sec * 3.0, 120.0))
                if not self._is_live_bar_fresh(
                    now=now,
                    live_bar=live_bar,
                    max_age_sec=float(live_bar_max_age_sec),
                ):
                    # Snapshot may be stale while provider feed is healthy; retry via provider.
                    fallback_live = self._live_bar_fallback_from_provider(session=session, now=now)
                    if isinstance(fallback_live, dict) and self._is_live_bar_fresh(
                        now=now,
                        live_bar=fallback_live,
                        max_age_sec=float(live_bar_max_age_sec),
                    ):
                        live_bar = fallback_live
                    else:
                        with self._live_bar_cache_lock:
                            prev_warn = self._last_stale_live_warn_at_by_agent.get(agent_id)
                        if prev_warn is None or (now - prev_warn).total_seconds() >= 300.0:
                            logger.warning(
                                "Agent watchdog skipped stale live bar: agent_id=%s sim_id=%s bar_time=%s asof_time=%s max_age_sec=%.1f",
                                int(agent_id),
                                int(sim_id),
                                int(live_bar.get("time") or 0),
                                int(live_bar.get("asof_time") or 0),
                                float(live_bar_max_age_sec),
                            )
                            with self._live_bar_cache_lock:
                                self._last_stale_live_warn_at_by_agent[int(agent_id)] = now
                        continue
                price = float(live_bar["close"])
                with self._get_agent_eval_lock(agent_id):
                    closed_bar: Optional[Dict[str, Any]] = None
                    with self._live_bar_cache_lock:
                        prev_live = self._last_live_bar_by_agent.get(agent_id)
                    if isinstance(prev_live, dict):
                        try:
                            prev_t = int(prev_live.get("time") or 0)
                            prev_c = float(prev_live.get("close"))
                            cur_t = int(live_bar.get("time") or 0)
                            if cur_t > prev_t and prev_t > 0 and math.isfinite(prev_c):
                                closed_bar = {"time": int(prev_t), "close": float(prev_c)}
                        except Exception:
                            closed_bar = None

                    trigger_events = self._process_entry_triggers(
                        db=db,
                        agent=agent,
                        session=session,
                        now=now,
                        current_price=float(price),
                        closed_bar=closed_bar,
                        current_live_bar=live_bar,
                        live_bar_max_age_sec=float(live_bar_max_age_sec),
                    )
                    with self._live_bar_cache_lock:
                        self._last_live_bar_by_agent[int(agent_id)] = dict(live_bar)
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
                    be_payload = self._maybe_move_trade_stop_to_breakeven(
                        db=db,
                        agent=agent,
                        session=session,
                        trade=trade,
                        price=float(price),
                        now=now,
                    )
                    if isinstance(be_payload, dict):
                        event_rows.append(
                            WorkbenchAgentEventModel(
                                agent_session_id=int(agent.id),
                                event_type="WATCHDOG_BREAKEVEN_MOVED",
                                severity="info",
                                payload_json=be_payload,
                                created_at=self._utc_now(),
                            )
                        )
                        try:
                            db.refresh(trade)
                        except Exception:
                            pass
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
            with self._live_bar_cache_lock:
                for aid in list(self._last_live_bar_by_agent.keys()):
                    if aid not in active_agent_ids:
                        self._last_live_bar_by_agent.pop(aid, None)
                for aid in list(self._last_stale_live_warn_at_by_agent.keys()):
                    if aid not in active_agent_ids:
                        self._last_stale_live_warn_at_by_agent.pop(aid, None)
            with self._agent_eval_locks_guard:
                for aid in list(self._agent_eval_locks.keys()):
                    if aid not in active_agent_ids:
                        self._agent_eval_locks.pop(aid, None)

            needs_commit = bool(event_rows) or bool(db.new) or bool(db.dirty) or bool(db.deleted)
            if needs_commit:
                for ev in event_rows:
                    db.add(ev)
                db.commit()
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

    def process_live_tick(
        self,
        *,
        db,
        agent: WorkbenchAgentSessionModel,
        session: SimulationSession,
        live_bar: Dict[str, Any],
        now: Optional[datetime] = None,
        auto_commit: bool = True,
    ) -> Dict[str, Any]:
        if not isinstance(live_bar, dict):
            return {"ok": False, "error": "invalid_live_bar"}
        try:
            price = float(live_bar.get("close"))
        except Exception:
            return {"ok": False, "error": "invalid_live_bar_close"}
        if not math.isfinite(price):
            return {"ok": False, "error": "invalid_live_bar_close"}

        now_utc = now if isinstance(now, datetime) else self._utc_now()
        agent_id = int(agent.id)
        cfg = self._watchdog_cfg(agent)

        with self._get_agent_eval_lock(agent_id):
            closed_bar: Optional[Dict[str, Any]] = None
            with self._live_bar_cache_lock:
                prev_live = self._last_live_bar_by_agent.get(agent_id)
            if isinstance(prev_live, dict):
                try:
                    prev_t = int(prev_live.get("time") or 0)
                    prev_c = float(prev_live.get("close"))
                    cur_t = int(live_bar.get("time") or 0)
                    if cur_t > prev_t and prev_t > 0 and math.isfinite(prev_c):
                        closed_bar = {"time": int(prev_t), "close": float(prev_c)}
                except Exception:
                    closed_bar = None

            event_rows = self._process_entry_triggers(
                db=db,
                agent=agent,
                session=session,
                now=now_utc,
                current_price=float(price),
                closed_bar=closed_bar,
                current_live_bar=live_bar,
                live_bar_max_age_sec=float(cfg.get("live_bar_max_age_sec") or 120.0),
            )
            with self._live_bar_cache_lock:
                self._last_live_bar_by_agent[agent_id] = dict(live_bar)
            open_trades = (
                db.query(SimulationTrade)
                .filter(SimulationTrade.session_id == int(session.id))
                .filter(SimulationTrade.status == "open")
                .all()
            )
            for trade in open_trades:
                be_payload = self._maybe_move_trade_stop_to_breakeven(
                    db=db,
                    agent=agent,
                    session=session,
                    trade=trade,
                    price=float(price),
                    now=now_utc,
                )
                if isinstance(be_payload, dict):
                    event_rows.append(
                        WorkbenchAgentEventModel(
                            agent_session_id=int(agent.id),
                            event_type="WATCHDOG_BREAKEVEN_MOVED",
                            severity="info",
                            payload_json=be_payload,
                            created_at=self._utc_now(),
                        )
                    )

        if event_rows:
            for ev in event_rows:
                db.add(ev)
        if auto_commit:
            needs_commit = bool(event_rows) or bool(db.new) or bool(db.dirty) or bool(db.deleted)
            if needs_commit:
                db.commit()
        return {
            "ok": True,
            "trigger_events_count": int(len(event_rows)),
            "trigger_event_types": [str(getattr(ev, "event_type", "")).upper() for ev in event_rows],
            "closed_bar_used": bool(isinstance(closed_bar, dict)),
        }

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


_WATCHDOG_SINGLETON: Optional[AgentWatchdogService] = None
_WATCHDOG_SINGLETON_PID: Optional[int] = None
_WATCHDOG_SINGLETON_GUARD = threading.RLock()


def get_agent_watchdog_service() -> AgentWatchdogService:
    global _WATCHDOG_SINGLETON, _WATCHDOG_SINGLETON_PID
    current_pid = int(os.getpid())
    with _WATCHDOG_SINGLETON_GUARD:
        if _WATCHDOG_SINGLETON is not None and _WATCHDOG_SINGLETON_PID != current_pid:
            try:
                _WATCHDOG_SINGLETON.stop()
            except Exception:
                pass
            _WATCHDOG_SINGLETON = None
            _WATCHDOG_SINGLETON_PID = None
        if _WATCHDOG_SINGLETON is None:
            _WATCHDOG_SINGLETON = AgentWatchdogService()
            _WATCHDOG_SINGLETON_PID = current_pid
    return _WATCHDOG_SINGLETON
