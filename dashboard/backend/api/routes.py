"""
FastAPI REST API Routes for Trading Dashboard
"""

from fastapi import APIRouter, Depends, HTTPException, BackgroundTasks, Query, Request
from fastapi.responses import StreamingResponse
from starlette.concurrency import run_in_threadpool
from sqlalchemy.orm import Session
from typing import Any, Dict, List, Optional
from datetime import datetime, timedelta, timezone, date
from dataclasses import asdict
import json
import io
import csv
import math
import time
import uuid
from pathlib import Path

import pandas as pd
import numpy as np
from openpyxl import Workbook

from ..models.database import (
    get_db, init_db,
    BacktestConfigModel, BacktestResultModel, BacktestTradeModel,
    LiveTradeModel, DailyPerformanceModel, MLModelRecord, RetrainingLogModel,
    OptionsEdgeScanRunModel, OptionsEdgeStockSnapshotModel, OptionsEdgeCandidateScoreModel,
    OptionsEdgeTradeCandidateModel, OptionsEdgeBacktestRunModel, OptionsEdgeTradeJournalModel,
    CSPScreenRunModel, CSPCandidateModel, CSPTradeModel, CSPBacktestRunModel,
    AIBotRunModel,
    RLOnlineLogModel,
    BacktestStatus, TradeDirection, TradeStatus
)
from ..models.schemas import (
    BacktestConfigCreate, BacktestConfig, BacktestConfigUpdate,
    BacktestResultResponse, BacktestResultSummary,
    TradeResponse, PerformanceMetrics,
    DashboardStats, LiveStatus,
    ExportRequest, BacktestComparison,
    OptionsEdgeScanRequest, OptionsEdgeScanResponse, OptionsEdgeScanDetailResponse,
    OptionsEdgeCandidateResponse, OptionsEdgeTradeCandidateResponse,
    OptionsEdgeLiveScanRequest, OptionsEdgeProviderStatusResponse,
    OptionsEdgeProviderProbeResponse,
    OptionsEdgeBacktestRequest, OptionsEdgeBacktestResponse,
    OptionsEdgeScanReportResponse,
    OptionsEdgePositionSizingRequest, OptionsEdgePositionSizingResponse,
    OptionsEdgePositionSizingItem,
    OptionsEdgeJournalTrackRequest, OptionsEdgeJournalCloseRequest,
    OptionsEdgeJournalEntryResponse, OptionsEdgeJournalStatsResponse,
    CSPScreenRequest, CSPScreenRunResponse, CSPCandidateResponse,
    CSPBacktestRequest, CSPBacktestRunResponse,
    AIBotOptionsEdgePlanRequest, AIBotExecutionDecision, AIBotRunResponse,
)
from ..services.backtest_service import BacktestService
from ..services.live_service import LiveTradingService
from ..core.phase01_validator import Phase01Validator, Phase01GateConfig
from ..core.options_edge import (
    OptionsEdgeScanEngine,
    DEFAULT_GATE_CONFIG,
    DEFAULT_SCORE_WEIGHTS,
    normalize_universe_dataframe,
    OptionsStrategyBuilder,
    DEFAULT_BUILDER_CONFIG,
    normalize_option_chain_dataframe,
    PolygonOptionsConnector,
    OptionsEdgeBacktestEngine,
    OptionsEdgeReporter,
    CSPScreener,
    CSPLifecycleEngine,
    CSPScreenConfig,
    CSPBacktestConfig,
    CSPExecutionBridge,
)
from ..core.ai_bot import OptionsEdgeAIBotAgent

router = APIRouter()


def _safe_float(value, default: float = 0.0) -> float:
    """Convert nullable/non-finite numeric values into safe finite floats."""
    try:
        if value is None:
            return float(default)
        v = float(value)
        if math.isnan(v) or math.isinf(v):
            return float(default)
        return v
    except Exception:
        return float(default)


@router.get("/telegram/automation/state")
def telegram_automation_state(limit: int = Query(120, ge=20, le=500)):
    """Telegram confirmation automation control-panel state."""
    try:
        from ..main import telegram_bridge_service, telegram_user_listener_service  # local import to avoid module-cycle at import time

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable"}
        out = svc.get_telegram_automation_state(limit=int(limit))
        try:
            out["user_listener"] = telegram_user_listener_service.status() if telegram_user_listener_service is not None else {"ok": False, "error": "user_listener_unavailable"}
        except Exception as exc:
            out["user_listener"] = {"ok": False, "error": f"user_listener_state_failed:{type(exc).__name__}:{str(exc)[:180]}"}
        return out
    except Exception as exc:
        # Do not break UI polling loop on transient runtime errors.
        return {
            "ok": False,
            "error": f"telegram_automation_state_failed:{type(exc).__name__}:{str(exc)[:180]}",
            "config": {
                "enabled": False,
                "channels": [],
                "default_timeframe": "M5",
                "default_lot": 0.05,
                "distribution_mode": "equal",
                "require_confirm": True,
                "confirm_window_sec": 1800.0,
                "evaluation_mode": "deterministic",
                "ai_provider": "claude",
                "ai_model": "",
                "ai_timeout_sec": 10.0,
            },
            "pending_confirm_count": 0,
            "active_ladder_count": 0,
            "feed": [],
            "execution_logs": [],
            "execution_report": {"ok": True, "rows": [], "count": 0, "generated_at": datetime.now(timezone.utc).isoformat()},
            "user_listener": {"ok": False, "error": "state_unavailable"},
        }


@router.get("/telegram/automation/execution-report")
def telegram_automation_execution_report(limit: int = Query(200, ge=10, le=1000)):
    """Aggregated execution performance report by source+symbol+timeframe combo."""
    try:
        from ..main import telegram_bridge_service  # local import to avoid module-cycle at import time

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable", "rows": [], "count": 0}
        return svc.get_automation_execution_report(limit=int(limit))
    except Exception as exc:
        raise HTTPException(500, f"telegram_automation_execution_report_failed:{type(exc).__name__}:{str(exc)[:180]}")


@router.post("/telegram/automation/config")
def telegram_automation_config(payload: Dict[str, Any]):
    """Persist Telegram confirmation automation config into dashboard/.env and return refreshed state."""
    try:
        from ..main import telegram_bridge_service  # local import to avoid module-cycle at import time

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable"}
        return svc.update_telegram_automation_config(payload if isinstance(payload, dict) else {})
    except Exception as exc:
        raise HTTPException(500, f"telegram_automation_config_failed:{type(exc).__name__}:{str(exc)[:180]}")


@router.post("/telegram/automation/simulate-message")
def telegram_automation_simulate_message(payload: Dict[str, Any]):
    """
    Inject a synthetic channel message into telegram automation flow.
    Intended for smoke tests of signal parsing -> execution path.
    """
    try:
        from ..main import telegram_bridge_service  # local import to avoid module-cycle at import time

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable"}
        p = payload if isinstance(payload, dict) else {}
        text = str(p.get("text") or "").strip()
        if not text:
            return {"ok": False, "error": "missing_text"}
        source_title = str(p.get("source_title") or "Synthetic Channel").strip() or "Synthetic Channel"
        source_username = str(p.get("source_username") or "").strip() or None
        source_id = int(float(p.get("source_id") or -9001))
        chat_id_raw = p.get("chat_id")
        if chat_id_raw is None:
            chat_id = int(svc._allowed_chat_id() or 900001)  # type: ignore[attr-defined]
        else:
            chat_id = int(float(chat_id_raw))
        push_only = bool(p.get("push_only", False))

        chat = {
            "id": int(source_id),
            "type": "channel",
            "title": str(source_title),
            "username": source_username,
        }
        msg = {
            "text": str(text),
            "chat": dict(chat),
            "sender_chat": dict(chat),
            "message_id": int(float(p.get("message_id") or 0)),
            "date": datetime.now(timezone.utc).isoformat(),
        }

        out = svc._handle_confirmation_signal_message(  # type: ignore[attr-defined]
            chat_id=int(chat_id),
            msg=msg,
            chat=chat,
            text=str(text),
            push_only=bool(push_only),
        )
        state = svc.get_telegram_automation_state(limit=80)

        # Include quick MT5 snapshot for smoke-test evidence.
        live = LiveTradingService()
        acc = live.get_account_info()
        positions = live.get_open_positions(symbol=None)
        xau_deals = live.get_recent_deals(days=1, symbol="XAUUSD")
        return {
            "ok": True,
            "simulated": {
                "chat_id": int(chat_id),
                "source_title": str(source_title),
                "push_only": bool(push_only),
            },
            "result_text": ("" if out is None else str(out)),
            "state": {
                "pending_confirm_count": int(state.get("pending_confirm_count") or 0),
                "active_ladder_count": int(state.get("active_ladder_count") or 0),
                "feed_rows": len(state.get("feed") or []),
            },
            "mt5": {
                "account_ok": bool(isinstance(acc, dict) and "error" not in acc),
                "account_login": (acc.get("login") if isinstance(acc, dict) else None),
                "open_positions_count": len(positions or []),
                "xau_deals_1d_count": len(xau_deals or []),
                "open_positions_preview": [
                    {
                        "ticket": int((r or {}).get("ticket") or 0),
                        "symbol": str((r or {}).get("symbol") or ""),
                        "direction": str((r or {}).get("direction") or ""),
                        "lot_size": float((r or {}).get("lot_size") or 0.0),
                        "comment": str((r or {}).get("comment") or ""),
                    }
                    for r in (positions or [])[:8]
                ],
            },
        }
    except Exception as exc:
        raise HTTPException(500, f"telegram_automation_simulate_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.get("/telegram/user-listener/state")
def telegram_user_listener_state():
    """State for Telethon-based channel listener (non-bot Telegram account)."""
    try:
        from ..main import telegram_user_listener_service  # local import to avoid module-cycle at import time

        svc = telegram_user_listener_service
        if svc is None:
            return {"ok": False, "error": "telegram_user_listener_unavailable"}
        return svc.status()
    except Exception as exc:
        raise HTTPException(500, f"telegram_user_listener_state_failed:{type(exc).__name__}:{str(exc)[:180]}")


@router.post("/telegram/user-listener/config")
def telegram_user_listener_config(payload: Dict[str, Any]):
    """Persist user-listener config in dashboard/.env and return refreshed state."""
    try:
        from ..main import telegram_user_listener_service  # local import to avoid module-cycle at import time

        svc = telegram_user_listener_service
        if svc is None:
            return {"ok": False, "error": "telegram_user_listener_unavailable"}
        return svc.update_config(payload if isinstance(payload, dict) else {})
    except Exception as exc:
        raise HTTPException(500, f"telegram_user_listener_config_failed:{type(exc).__name__}:{str(exc)[:180]}")


@router.post("/telegram/user-listener/start")
def telegram_user_listener_start():
    """Start user-listener immediately (if enabled/configured)."""
    try:
        from ..main import telegram_user_listener_service  # local import to avoid module-cycle at import time

        svc = telegram_user_listener_service
        if svc is None:
            return {"ok": False, "error": "telegram_user_listener_unavailable"}
        svc.start()
        out = svc.status()
        out["action"] = "start"
        return out
    except Exception as exc:
        raise HTTPException(500, f"telegram_user_listener_start_failed:{type(exc).__name__}:{str(exc)[:180]}")


@router.post("/telegram/user-listener/stop")
def telegram_user_listener_stop():
    """Stop user-listener runtime loop."""
    try:
        from ..main import telegram_user_listener_service  # local import to avoid module-cycle at import time

        svc = telegram_user_listener_service
        if svc is None:
            return {"ok": False, "error": "telegram_user_listener_unavailable"}
        svc.stop()
        out = svc.status()
        out["action"] = "stop"
        return out
    except Exception as exc:
        raise HTTPException(500, f"telegram_user_listener_stop_failed:{type(exc).__name__}:{str(exc)[:180]}")


@router.post("/telegram/user-listener/send-code")
def telegram_user_listener_send_code(payload: Dict[str, Any]):
    """Request Telegram login code for a phone number."""
    svc = None
    try:
        from ..main import telegram_user_listener_service  # local import to avoid module-cycle at import time

        svc = telegram_user_listener_service
        if svc is None:
            return {"ok": False, "error": "telegram_user_listener_unavailable"}
        phone = str((payload or {}).get("phone") or "").strip()
        if not phone:
            return {"ok": False, "error": "missing_phone"}
        out = svc.send_login_code(phone)
        state = svc.status()
        return {"ok": bool(out.get("ok")), "result": out, "state": state}
    except Exception as exc:
        try:
            state = svc.status() if svc is not None else {"ok": False, "error": "telegram_user_listener_unavailable"}
        except Exception:
            state = {"ok": False, "error": "state_unavailable"}
        return {
            "ok": False,
            "result": {"ok": False, "error": f"telegram_user_listener_send_code_failed:{type(exc).__name__}:{str(exc)[:180]}"},
            "state": state,
        }


@router.post("/telegram/user-listener/verify-code")
def telegram_user_listener_verify_code(payload: Dict[str, Any]):
    """Verify Telegram login code (and optional 2FA password)."""
    svc = None
    try:
        from ..main import telegram_user_listener_service  # local import to avoid module-cycle at import time

        svc = telegram_user_listener_service
        if svc is None:
            return {"ok": False, "error": "telegram_user_listener_unavailable"}
        p = payload if isinstance(payload, dict) else {}
        phone = str(p.get("phone") or "").strip()
        code = str(p.get("code") or "").strip()
        password = p.get("password")
        out = svc.verify_login_code(
            phone=phone,
            code=code,
            password=(str(password).strip() if password is not None else None),
            phone_code_hash=(str(p.get("phone_code_hash") or "").strip() or None),
            pending_session=(str(p.get("pending_session") or "").strip() or None),
        )
        if bool(out.get("ok")):
            # If listener is enabled in config, automatically start after successful login.
            try:
                if bool(svc.status().get("enabled")):
                    svc.start()
            except Exception:
                pass
        state = svc.status()
        return {"ok": bool(out.get("ok")), "result": out, "state": state}
    except Exception as exc:
        try:
            state = svc.status() if svc is not None else {"ok": False, "error": "telegram_user_listener_unavailable"}
        except Exception:
            state = {"ok": False, "error": "state_unavailable"}
        return {
            "ok": False,
            "result": {"ok": False, "error": f"telegram_user_listener_verify_code_failed:{type(exc).__name__}:{str(exc)[:180]}"},
            "state": state,
        }


@router.get("/mt4/log-automation/state")
def mt4_log_automation_state(limit: int = Query(200, ge=20, le=1000)):
    """MT4 log automation state and discovered indicator activity."""
    try:
        from ..main import mt4_log_automation_service, telegram_bridge_service  # local import to avoid module-cycle at import time

        svc = mt4_log_automation_service
        if svc is None:
            return {"ok": False, "error": "mt4_log_automation_unavailable"}
        out = svc.get_state(limit=int(limit))
        try:
            if telegram_bridge_service is not None:
                out["execution_logs"] = telegram_bridge_service.get_automation_execution_logs(limit=min(300, int(limit)))
                out["execution_report"] = telegram_bridge_service.get_automation_execution_report(limit=200)
                out["mt4_bot_monitor"] = telegram_bridge_service.get_mt4_indicator_bot_monitor(
                    limit=300,
                    instance_rows=(out.get("instances") if isinstance(out.get("instances"), list) else []),
                    recent_events=(
                        out.get("events_recent_24h")
                        if isinstance(out.get("events_recent_24h"), list)
                        else (out.get("events") if isinstance(out.get("events"), list) else [])
                    ),
                )
            else:
                out["execution_logs"] = []
                out["execution_report"] = {"ok": True, "rows": [], "count": 0}
                out["mt4_bot_monitor"] = {
                    "ok": True,
                    "rows": [],
                    "active_count": 0,
                    "bot_rows": [],
                    "bot_active_count": 0,
                    "bot_open_count": 0,
                    "bot_idle_count": 0,
                }
        except Exception:
            out["execution_logs"] = []
            out["execution_report"] = {"ok": True, "rows": [], "count": 0}
            out["mt4_bot_monitor"] = {
                "ok": True,
                "rows": [],
                "active_count": 0,
                "bot_rows": [],
                "bot_active_count": 0,
                "bot_open_count": 0,
                "bot_idle_count": 0,
            }
        return out
    except Exception as exc:
        raise HTTPException(500, f"mt4_log_automation_state_failed:{type(exc).__name__}:{str(exc)[:180]}")


@router.post("/mt4/log-automation/config")
def mt4_log_automation_config(payload: Dict[str, Any]):
    """Persist MT4 log automation config and apply runtime changes."""
    try:
        from ..main import mt4_log_automation_service  # local import to avoid module-cycle at import time

        svc = mt4_log_automation_service
        if svc is None:
            return {"ok": False, "error": "mt4_log_automation_unavailable"}
        return svc.update_config(payload if isinstance(payload, dict) else {})
    except Exception as exc:
        raise HTTPException(500, f"mt4_log_automation_config_failed:{type(exc).__name__}:{str(exc)[:180]}")


@router.post("/mt4/log-automation/indicator-automation")
def mt4_log_indicator_automation(payload: Dict[str, Any]):
    """Enable/disable automation for a discovered indicator profile."""
    try:
        from ..main import mt4_log_automation_service  # local import to avoid module-cycle at import time

        svc = mt4_log_automation_service
        if svc is None:
            return {"ok": False, "error": "mt4_log_automation_unavailable"}
        p = payload if isinstance(payload, dict) else {}
        indicator = str(p.get("indicator") or "").strip()
        enabled = p.get("enabled") if "enabled" in p else None
        lot_size = p.get("lot_size") if "lot_size" in p else None
        enabled_bool: Optional[bool] = None
        if enabled is not None:
            enabled_bool = bool(enabled)
        lot_val: Optional[float] = None
        if lot_size is not None:
            try:
                lot_val = float(lot_size)
            except Exception:
                return {"ok": False, "error": "invalid_lot_size"}
        return svc.update_indicator_settings(
            indicator=indicator,
            enabled=enabled_bool,
            lot_size=lot_val,
        )
    except Exception as exc:
        raise HTTPException(500, f"mt4_log_indicator_automation_failed:{type(exc).__name__}:{str(exc)[:180]}")


@router.post("/mt4/log-automation/instance-automation")
def mt4_log_instance_automation(payload: Dict[str, Any]):
    """Enable/disable automation for a specific indicator chart instance (indicator+symbol+timeframe)."""
    try:
        from ..main import mt4_log_automation_service  # local import to avoid module-cycle at import time

        svc = mt4_log_automation_service
        if svc is None:
            return {"ok": False, "error": "mt4_log_automation_unavailable"}
        p = payload if isinstance(payload, dict) else {}
        indicator = str(p.get("indicator") or "").strip()
        symbol = str(p.get("symbol") or "").strip().upper()
        timeframe = str(p.get("timeframe") or "").strip().upper()
        enabled = p.get("enabled") if "enabled" in p else None
        lot_size = p.get("lot_size") if "lot_size" in p else None
        enabled_bool: Optional[bool] = None
        if enabled is not None:
            enabled_bool = bool(enabled)
        lot_val: Optional[float] = None
        if lot_size is not None:
            try:
                lot_val = float(lot_size)
            except Exception:
                return {"ok": False, "error": "invalid_lot_size"}
        return svc.update_instance_settings(
            indicator=indicator,
            symbol=symbol,
            timeframe=timeframe,
            enabled=enabled_bool,
            lot_size=lot_val,
        )
    except Exception as exc:
        raise HTTPException(500, f"mt4_log_instance_automation_failed:{type(exc).__name__}:{str(exc)[:180]}")


@router.get("/mt4/log-automation/indicator-logs")
def mt4_log_indicator_logs(
    indicator: str = Query(..., min_length=1),
    limit: int = Query(200, ge=20, le=1000),
    alerts_only: bool = Query(True),
):
    """Get latest log rows for a specific indicator profile."""
    try:
        from ..main import mt4_log_automation_service  # local import to avoid module-cycle at import time

        svc = mt4_log_automation_service
        if svc is None:
            return {"ok": False, "error": "mt4_log_automation_unavailable"}
        return svc.get_indicator_logs_filtered(indicator=str(indicator), limit=int(limit), alerts_only=bool(alerts_only))
    except Exception as exc:
        raise HTTPException(500, f"mt4_log_indicator_logs_failed:{type(exc).__name__}:{str(exc)[:180]}")


@router.post("/mt4/log-automation/simulate-signal")
def mt4_log_simulate_signal(payload: Dict[str, Any]):
    """
    Inject a synthetic MT4 bridge signal (diagnostics only).
    This endpoint now uses the bridge ingest path directly.
    """
    try:
        from ..main import telegram_bridge_service  # local import to avoid module-cycle at import time

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable"}
        p = payload if isinstance(payload, dict) else {}
        indicator = str(p.get("indicator") or "").strip() or "Alchemy Pulse Indicateor"
        signal_hint = str(p.get("signal_hint") or "").strip().upper() or "SELL"
        symbol = str(p.get("symbol") or "").strip().upper() or "XAUUSDM"
        timeframe = str(p.get("timeframe") or "").strip().upper() or "M1"
        message = str(p.get("message") or "").strip() or f"{indicator}: {signal_hint} {symbol}"
        event_ts = str(p.get("event_ts") or datetime.now(timezone.utc).isoformat())
        signal_profile = str(p.get("signal_profile") or "").strip().lower()
        lot_override = p.get("lot_override")

        mt_payload: Dict[str, Any] = {
            "indicator": indicator,
            "symbol": symbol,
            "timeframe": timeframe,
            "signal_hint": signal_hint,
            "signal_profile": signal_profile,
            "message": message,
            "event_ts": event_ts,
            "ingest_source": "bridge",
            "bridge_event_type": "signal",
        }
        if lot_override is not None:
            try:
                mt_payload["lot_override"] = float(lot_override)
            except Exception:
                return {"ok": False, "error": "invalid_lot_override"}

        out = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=mt_payload)
        state = svc.get_telegram_automation_state(limit=80)
        return {
            "ok": True,
            "input": mt_payload,
            "result": out,
            "state": {
                "pending_confirm_count": int(state.get("pending_confirm_count") or 0),
                "active_ladder_count": int(state.get("active_ladder_count") or 0),
                "execution_logs_count": len(state.get("execution_logs") or []),
            },
        }
    except Exception as exc:
        raise HTTPException(500, f"mt4_log_simulate_signal_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.post("/mt4/bridge/signal")
def mt4_bridge_signal_ingest(payload: Dict[str, Any], request: Request):
    """
    Direct MT4 bridge ingest endpoint.

    Intended for MT4 EAs/scripts that POST BUY/SELL signals directly to backend,
    bypassing terminal log-tail dependency.
    """
    try:
        from ..main import telegram_bridge_service  # local import to avoid module-cycle at import time
        from ..services.telegram_bridge_service import TelegramBridgeService

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable"}

        p = payload if isinstance(payload, dict) else {}
        expected_token = str(TelegramBridgeService._get_env_value("MT4_BRIDGE_INGEST_TOKEN", "")).strip()
        provided_token = str(request.headers.get("x-mt4-bridge-token") or p.get("bridge_token") or "").strip()
        if expected_token and (provided_token != expected_token):
            raise HTTPException(status_code=401, detail="mt4_bridge_auth_failed")

        direction_raw = str(p.get("signal_hint") or p.get("direction") or "").strip().upper()
        direction = "BUY" if direction_raw in {"BUY", "LONG", "UP"} else ("SELL" if direction_raw in {"SELL", "SHORT", "DOWN"} else direction_raw)

        tf_raw = str(p.get("timeframe") or p.get("tf") or "").strip().upper()
        tf_map = {
            "1": "M1",
            "5": "M5",
            "15": "M15",
            "30": "M30",
            "60": "H1",
            "240": "H4",
            "1440": "D1",
            "10080": "W1",
            "43200": "MN1",
        }
        timeframe = tf_map.get(tf_raw, tf_raw or "M5")

        bridge_payload: Dict[str, Any] = {
            "indicator": str(p.get("indicator") or p.get("indicator_name") or "MT4Bridge"),
            "signal_hint": str(direction or ""),
            "symbol": str(p.get("symbol") or p.get("pair") or "").strip().upper(),
            "timeframe": str(timeframe or "M5"),
            "signal_profile": str(p.get("signal_profile") or p.get("profile") or "generic").strip().lower(),
            "message": str(p.get("message") or p.get("raw_text") or "").strip(),
            "event_ts": str(p.get("event_ts") or datetime.now(timezone.utc).isoformat()),
            "ingest_source": "bridge",
            "bridge_event_type": str(p.get("bridge_event_type") or p.get("event_type") or "signal").strip().lower() or "signal",
        }
        lot_override = p.get("lot_override")
        if lot_override is not None:
            try:
                bridge_payload["lot_override"] = float(lot_override)
            except Exception:
                return {"ok": False, "error": "invalid_lot_override"}
        # Pass-through telemetry fields used by RSI bridge EAs.
        if "rsi_value" in p:
            try:
                bridge_payload["rsi_value"] = float(p.get("rsi_value"))
            except Exception:
                return {"ok": False, "error": "invalid_rsi_value"}
        if "value" in p and "rsi_value" not in bridge_payload:
            try:
                bridge_payload["value"] = float(p.get("value"))
            except Exception:
                return {"ok": False, "error": "invalid_telemetry_value"}
        if "indicator_tf" in p:
            bridge_payload["indicator_tf"] = str(p.get("indicator_tf") or "").strip().upper()
        if "rsi_period" in p:
            try:
                bridge_payload["rsi_period"] = float(p.get("rsi_period"))
            except Exception:
                return {"ok": False, "error": "invalid_rsi_period"}
        if p.get("event_id") is not None:
            bridge_payload["event_id"] = str(p.get("event_id") or "").strip()
        if p.get("event_attempt") is not None:
            try:
                bridge_payload["event_attempt"] = int(float(p.get("event_attempt")))
            except Exception:
                return {"ok": False, "error": "invalid_event_attempt"}
        for key in (
            "bridge_version",
            "resolved_signal",
            "confirmed_direction",
            "pending_direction",
            "pending_age_sec",
            "confirm_seconds",
            "resolved_signal_shift",
            "resolved_signal_bar_time",
            "resolved_signal_bar_unix",
            "resolved_raw_buy",
            "resolved_raw_sell",
            "last_signal_direction",
            "last_signal_bar_time",
            "last_signal_bar_unix",
            "last_signal_value",
            "last_signal_raw_buy",
            "last_signal_raw_sell",
            "secondary_enabled",
            "secondary_indicator",
            "secondary_signal",
            "secondary_raw_signal",
            "secondary_resolved_signal",
            "secondary_signal_shift",
            "secondary_bar_time",
            "secondary_resolved_bar_time",
            "secondary_raw_buy",
            "secondary_raw_sell",
            "secondary_require_agreement",
            "secondary_governor_enabled",
            "secondary_entry_gate_enabled",
            "secondary_entry_enabled",
            "secondary_entry",
            "secondary_sl_enabled",
            "secondary_stop_loss",
            "secondary_tp_enabled",
            "secondary_tp1",
            "secondary_tp2",
            "secondary_tp3",
            "secondary_tp4",
            "secondary_tp5",
        ):
            if key in p:
                bridge_payload[key] = p.get(key)

        out = svc.ingest_indicator_bridge_signal(terminal_family="mt4", payload=bridge_payload)
        return {
            "ok": bool((out or {}).get("ok", True)),
            "result": out,
            "accepted_payload": bridge_payload,
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(500, f"mt4_bridge_signal_ingest_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.post("/mt5/bridge/signal")
def mt5_bridge_signal_ingest(payload: Dict[str, Any], request: Request):
    """Direct MT5 iCustom bridge ingest endpoint."""
    try:
        from ..main import telegram_bridge_service  # local import to avoid module-cycle at import time
        from ..services.telegram_bridge_service import TelegramBridgeService

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable"}

        p = payload if isinstance(payload, dict) else {}
        expected_token = str(TelegramBridgeService._get_env_value("MT5_BRIDGE_INGEST_TOKEN", "")).strip()
        provided_token = str(request.headers.get("x-mt5-bridge-token") or p.get("bridge_token") or "").strip()
        if expected_token and (provided_token != expected_token):
            raise HTTPException(status_code=401, detail="mt5_bridge_auth_failed")

        direction_raw = str(p.get("signal_hint") or p.get("direction") or "").strip().upper()
        direction = "BUY" if direction_raw in {"BUY", "LONG", "UP"} else ("SELL" if direction_raw in {"SELL", "SHORT", "DOWN"} else direction_raw)

        tf_raw = str(p.get("timeframe") or p.get("tf") or "").strip().upper()
        tf_map = {
            "1": "M1",
            "5": "M5",
            "15": "M15",
            "30": "M30",
            "60": "H1",
            "240": "H4",
            "1440": "D1",
            "10080": "W1",
            "43200": "MN1",
        }
        timeframe = tf_map.get(tf_raw, tf_raw or "M5")

        bridge_payload: Dict[str, Any] = {
            "indicator": str(p.get("indicator") or p.get("indicator_name") or "MT5Bridge"),
            "signal_hint": str(direction or ""),
            "symbol": str(p.get("symbol") or p.get("pair") or "").strip().upper(),
            "timeframe": str(timeframe or "M5"),
            "signal_profile": str(p.get("signal_profile") or p.get("profile") or "generic").strip().lower(),
            "message": str(p.get("message") or p.get("raw_text") or "").strip(),
            "event_ts": str(p.get("event_ts") or datetime.now(timezone.utc).isoformat()),
            "ingest_source": "bridge",
            "bridge_event_type": str(p.get("bridge_event_type") or p.get("event_type") or "signal").strip().lower() or "signal",
        }
        lot_override = p.get("lot_override")
        if lot_override is not None:
            try:
                bridge_payload["lot_override"] = float(lot_override)
            except Exception:
                return {"ok": False, "error": "invalid_lot_override"}
        # Pass-through telemetry fields used by RSI bridge EAs.
        if "rsi_value" in p:
            try:
                bridge_payload["rsi_value"] = float(p.get("rsi_value"))
            except Exception:
                return {"ok": False, "error": "invalid_rsi_value"}
        if "value" in p and "rsi_value" not in bridge_payload:
            try:
                bridge_payload["value"] = float(p.get("value"))
            except Exception:
                return {"ok": False, "error": "invalid_telemetry_value"}
        if "indicator_tf" in p:
            bridge_payload["indicator_tf"] = str(p.get("indicator_tf") or "").strip().upper()
        if "rsi_period" in p:
            try:
                bridge_payload["rsi_period"] = float(p.get("rsi_period"))
            except Exception:
                return {"ok": False, "error": "invalid_rsi_period"}
        if p.get("event_id") is not None:
            bridge_payload["event_id"] = str(p.get("event_id") or "").strip()
        if p.get("event_attempt") is not None:
            try:
                bridge_payload["event_attempt"] = int(float(p.get("event_attempt")))
            except Exception:
                return {"ok": False, "error": "invalid_event_attempt"}
        for key in (
            "bridge_version",
            "resolved_signal",
            "confirmed_direction",
            "pending_direction",
            "pending_age_sec",
            "confirm_seconds",
            "resolved_signal_shift",
            "resolved_signal_bar_time",
            "resolved_signal_bar_unix",
            "resolved_raw_buy",
            "resolved_raw_sell",
            "last_signal_direction",
            "last_signal_bar_time",
            "last_signal_bar_unix",
            "last_signal_value",
            "last_signal_raw_buy",
            "last_signal_raw_sell",
            "secondary_enabled",
            "secondary_indicator",
            "secondary_signal",
            "secondary_raw_signal",
            "secondary_resolved_signal",
            "secondary_signal_shift",
            "secondary_bar_time",
            "secondary_resolved_bar_time",
            "secondary_raw_buy",
            "secondary_raw_sell",
            "secondary_require_agreement",
            "secondary_governor_enabled",
            "secondary_entry_gate_enabled",
            "secondary_entry_enabled",
            "secondary_entry",
            "secondary_sl_enabled",
            "secondary_stop_loss",
            "secondary_tp_enabled",
            "secondary_tp1",
            "secondary_tp2",
            "secondary_tp3",
            "secondary_tp4",
            "secondary_tp5",
        ):
            if key in p:
                bridge_payload[key] = p.get(key)

        out = svc.ingest_indicator_bridge_signal(terminal_family="mt5", payload=bridge_payload)
        return {
            "ok": bool((out or {}).get("ok", True)),
            "result": out,
            "accepted_payload": bridge_payload,
        }
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(500, f"mt5_bridge_signal_ingest_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.get("/indicator-bridge/state")
def indicator_bridge_state(
    limit: int = Query(300, ge=20, le=2000),
    active_only: bool = Query(False),
    include_audit: bool = Query(True),
    include_liquidity: bool = Query(True),
    include_rsi: bool = Query(True),
    include_ohlc: bool = Query(True),
    include_execution_report: bool = Query(True),
):
    """Bridge-only MT4/MT5 indicator bot monitor state."""
    try:
        from ..main import telegram_bridge_service

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable"}
        return svc.get_indicator_bridge_state(
            limit=int(limit),
            active_only=bool(active_only),
            include_audit=bool(include_audit),
            include_liquidity=bool(include_liquidity),
            include_rsi=bool(include_rsi),
            include_ohlc_replay=bool(include_ohlc),
            include_execution_report=bool(include_execution_report),
        )
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_state_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.get("/indicator-bridge/open-trade/prices")
def indicator_bridge_open_trade_prices(
    tickets: str = Query("", max_length=4000),
):
    """Fast broker-price snapshot for currently displayed indicator trades."""
    try:
        from ..main import telegram_bridge_service

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable", "rows": [], "count": 0}
        parsed: List[int] = []
        for part in str(tickets or "").split(","):
            raw = str(part or "").strip()
            if not raw:
                continue
            try:
                value = int(float(raw))
            except Exception:
                continue
            if value > 0:
                parsed.append(int(value))
        # Keep the endpoint intentionally narrow; it is called frequently by the UI.
        parsed = list(dict.fromkeys(parsed))[:300]
        return svc.get_indicator_open_trade_price_snapshot(tickets=parsed)
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_open_trade_prices_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.get("/indicator-bridge/execution-log")
def indicator_bridge_execution_log(
    limit: int = Query(1000, ge=20, le=5000),
):
    """Separated audit lane for Indicator Automation V2.

    The main state endpoint is polled frequently by the dashboard. Audit rows
    can involve larger in-memory/history scans, so they are fetched on a slower
    lane to keep live telemetry responsive.
    """
    try:
        from ..main import telegram_bridge_service

        svc = telegram_bridge_service
        if svc is None:
            return {
                "ok": False,
                "error": "telegram_bridge_unavailable",
                "execution_logs": {"ok": False, "rows": [], "count": 0},
                "liquidity_audit_logs": {"ok": False, "rows": [], "count": 0},
            }
        audit = svc.get_indicator_execution_audit_rows(limit=int(limit), resolve_history_pnl=False)
        if hasattr(svc, "_split_indicator_liquidity_audit_logs"):
            execution_logs, liquidity_audit_logs = svc._split_indicator_liquidity_audit_logs(audit)
        else:
            execution_logs, liquidity_audit_logs = audit, {"ok": True, "rows": [], "count": 0}
        return {
            "ok": True,
            "execution_logs": execution_logs,
            "liquidity_audit_logs": liquidity_audit_logs,
        }
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_execution_log_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.post("/indicator-bridge/risk-settings")
def indicator_bridge_risk_settings(payload: Dict[str, Any]):
    """Persist global Indicator Automation V2 risk settings."""
    try:
        from ..main import telegram_bridge_service

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable"}
        p = payload if isinstance(payload, dict) else {}
        daily_target = p.get("daily_target_usd") if "daily_target_usd" in p else p.get("daily_target")
        daily_max_loss = p.get("daily_max_loss_usd") if "daily_max_loss_usd" in p else p.get("daily_max_loss")
        bypass_target_guard = p.get("daily_target_guard_bypass_today")
        target_val = None
        max_loss_val = None
        bypass_val = None
        if daily_target is not None:
            try:
                target_val = float(daily_target)
            except Exception:
                return {"ok": False, "error": "invalid_daily_target_usd"}
        if daily_max_loss is not None:
            try:
                max_loss_val = float(daily_max_loss)
            except Exception:
                return {"ok": False, "error": "invalid_daily_max_loss_usd"}
        if bypass_target_guard is not None:
            raw = str(bypass_target_guard).strip().lower()
            bypass_val = bool(bypass_target_guard is True or raw in {"1", "true", "yes", "on"})
        result = svc.update_indicator_bridge_risk_settings(
            daily_target_usd=target_val,
            daily_max_loss_usd=max_loss_val,
            daily_target_guard_bypass_today=bypass_val,
        )
        return {
            "ok": bool((result or {}).get("ok", True)),
            "update_result": result,
            "risk_settings": svc.get_indicator_bridge_risk_settings(),
        }
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_risk_settings_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.post("/indicator-bridge/symbol-sessions")
def indicator_bridge_symbol_sessions(payload: Dict[str, Any]):
    """Persist indicator+symbol allowed trading windows for Indicator Automation V2."""
    try:
        from ..main import telegram_bridge_service

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable"}
        p = payload if isinstance(payload, dict) else {}
        sessions = p.get("sessions")
        if not isinstance(sessions, dict):
            return {"ok": False, "error": "invalid_sessions"}
        result = svc.update_indicator_bridge_trade_block_windows(sessions=dict(sessions))
        return {
            "ok": bool((result or {}).get("ok", True)),
            "update_result": result,
            "trade_block_windows": svc.get_indicator_bridge_trade_block_windows(),
            "symbol_sessions": svc.get_indicator_bridge_symbol_sessions(),
        }
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_symbol_sessions_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.post("/indicator-bridge/dual-gate-settings")
def indicator_bridge_dual_gate_settings(payload: Dict[str, Any]):
    """Persist global Dual Indicator Gate settings."""
    try:
        from ..main import telegram_bridge_service

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable"}
        p = payload if isinstance(payload, dict) else {}
        enabled_raw = p.get("none_close_enabled")
        enabled = None
        if enabled_raw is not None:
            if isinstance(enabled_raw, bool):
                enabled = bool(enabled_raw)
            else:
                enabled = str(enabled_raw).strip().lower() in {"1", "true", "yes", "on"}
        result = svc.update_indicator_bridge_dual_gate_settings(none_close_enabled=enabled)
        return {
            "ok": bool((result or {}).get("ok", True)),
            "update_result": result,
            "dual_gate_settings": svc.get_indicator_bridge_dual_gate_settings(),
        }
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_dual_gate_settings_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.post("/indicator-bridge/liquidity-governor-settings")
def indicator_bridge_liquidity_governor_settings(payload: Dict[str, Any]):
    """Persist global liquidity-context governor settings for Indicator Automation V2."""
    try:
        from ..main import telegram_bridge_service

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable"}
        p = payload if isinstance(payload, dict) else {}

        def _bool_or_none(value: Any) -> Optional[bool]:
            if value is None:
                return None
            if isinstance(value, bool):
                return bool(value)
            return str(value).strip().lower() in {"1", "true", "yes", "on"}

        def _int_or_none(value: Any, name: str) -> Optional[int]:
            if value is None:
                return None
            try:
                return int(float(value))
            except Exception:
                raise ValueError(str(name))

        def _float_or_none(value: Any, name: str) -> Optional[float]:
            if value is None:
                return None
            try:
                return float(value)
            except Exception:
                raise ValueError(str(name))

        try:
            result = svc.update_indicator_bridge_liquidity_context_governor_settings(
                enabled=_bool_or_none(p.get("enabled")),
                context_timeframe=(p.get("context_timeframe") if "context_timeframe" in p else None),
                lookback_bars=_int_or_none(p.get("lookback_bars"), "lookback_bars"),
                freshness_bars=_int_or_none(p.get("freshness_bars"), "freshness_bars"),
                min_rejection_ratio=_float_or_none(p.get("min_rejection_ratio"), "min_rejection_ratio"),
                allow_continuation=_bool_or_none(p.get("allow_continuation")),
                block_on_no_setup=_bool_or_none(p.get("block_on_no_setup")),
            )
        except ValueError as exc:
            return {"ok": False, "error": f"invalid_{str(exc)}"}
        return {
            "ok": bool((result or {}).get("ok", True)),
            "update_result": result,
            "liquidity_context_governor": svc.get_indicator_bridge_liquidity_context_governor_settings(),
            "liquidity_context_watchlist": svc.get_indicator_bridge_liquidity_context_watchlist(),
        }
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_liquidity_governor_settings_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.post("/indicator-bridge/liquidity-opportunity-scan")
def indicator_bridge_liquidity_opportunity_scan(payload: Dict[str, Any]):
    """Scan arbitrary symbols with the same Workbench liquidity context engine used by the governor."""
    try:
        from ..main import telegram_bridge_service

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable", "rows": [], "count": 0}
        p = payload if isinstance(payload, dict) else {}
        symbols = p.get("symbols")
        if symbols is None:
            symbols = p.get("symbols_csv") or p.get("text") or ""
        max_symbols = p.get("max_symbols", 12)
        try:
            max_symbols_int = int(float(max_symbols))
        except Exception:
            max_symbols_int = 12
        return svc.scan_indicator_liquidity_opportunities(
            symbols=symbols,
            context_timeframe=(p.get("context_timeframe") if "context_timeframe" in p else None),
            max_symbols=int(max_symbols_int),
        )
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_liquidity_opportunity_scan_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.post("/indicator-bridge/liquidity-watchlist")
def indicator_bridge_liquidity_watchlist(payload: Dict[str, Any]):
    """Persist symbols that should always be shown in the live liquidity context panel."""
    try:
        from ..main import telegram_bridge_service

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable"}
        p = payload if isinstance(payload, dict) else {}
        result = svc.update_indicator_bridge_liquidity_context_watchlist(
            symbols=p.get("symbols") or p.get("symbols_csv") or "",
            context_timeframe=(p.get("context_timeframe") if "context_timeframe" in p else None),
            action=str(p.get("action") or "add"),
        )
        return {
            "ok": bool((result or {}).get("ok", True)),
            "update_result": result,
            "liquidity_context_watchlist": svc.get_indicator_bridge_liquidity_context_watchlist(),
        }
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_liquidity_watchlist_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.get("/indicator-bridge/rsi-telemetry")
def indicator_bridge_rsi_telemetry(
    limit: int = Query(500, ge=20, le=5000),
    terminal_family: str = Query("", pattern="^(|mt4|mt5)$"),
):
    """Latest RSI telemetry rows pushed by dedicated MT4/MT5 RSI bridge EAs."""
    try:
        from ..main import telegram_bridge_service

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable", "rows": [], "count": 0, "seq": 0}
        fam = str(terminal_family or "").strip().lower() or None
        return svc.get_indicator_rsi_telemetry(limit=int(limit), terminal_family=fam)
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_rsi_telemetry_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.get("/indicator-bridge/rsi-telemetry/stream")
def indicator_bridge_rsi_telemetry_stream(
    limit: int = Query(500, ge=20, le=5000),
    terminal_family: str = Query("", pattern="^(|mt4|mt5)$"),
):
    """Server-Sent Events stream for real-time RSI telemetry UI updates."""

    fam = str(terminal_family or "").strip().lower() or None
    lim = int(max(20, min(5000, int(limit or 500))))

    def _event_gen():
        last_seq = -1
        idle_loops = 0
        while True:
            try:
                from ..main import telegram_bridge_service

                svc = telegram_bridge_service
                if svc is None:
                    payload = {"ok": False, "error": "telegram_bridge_unavailable", "rows": [], "count": 0, "seq": 0}
                else:
                    payload = svc.get_indicator_rsi_telemetry(limit=lim, terminal_family=fam)
                seq = int((payload or {}).get("seq") or 0)
                if seq != last_seq:
                    last_seq = int(seq)
                    idle_loops = 0
                    yield "event: rsi\n"
                    yield f"id: {last_seq}\n"
                    yield f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
                else:
                    idle_loops += 1
                    if idle_loops >= 10:
                        idle_loops = 0
                        yield ": keepalive\n\n"
            except GeneratorExit:
                break
            except Exception as exc:
                err = {"ok": False, "error": f"rsi_stream_failed:{type(exc).__name__}:{str(exc)[:180]}"}
                yield "event: error\n"
                yield f"data: {json.dumps(err, ensure_ascii=False)}\n\n"
            time.sleep(1.0)

    headers = {
        "Cache-Control": "no-cache",
        "Connection": "keep-alive",
        "X-Accel-Buffering": "no",
    }
    return StreamingResponse(_event_gen(), media_type="text/event-stream", headers=headers)


@router.post("/indicator-bridge/instance-automation")
def indicator_bridge_instance_automation(payload: Dict[str, Any]):
    """Enable/disable automation for a specific MT4/MT5 bridge chart instance."""
    try:
        from ..main import telegram_bridge_service

        svc = telegram_bridge_service
        if svc is None:
            return {"ok": False, "error": "telegram_bridge_unavailable"}
        p = payload if isinstance(payload, dict) else {}
        terminal_family = str(p.get("terminal_family") or p.get("family") or "mt4").strip().lower() or "mt4"
        indicator = str(p.get("indicator") or "").strip()
        symbol = str(p.get("symbol") or "").strip().upper()
        timeframe = str(p.get("timeframe") or "").strip().upper()
        enabled = p.get("enabled") if "enabled" in p else None
        lot_size = p.get("lot_size") if "lot_size" in p else None
        mode_advanced_enabled = p.get("mode_advanced_enabled") if "mode_advanced_enabled" in p else None
        mode_advanced_v2_enabled = p.get("mode_advanced_v2_enabled") if "mode_advanced_v2_enabled" in p else None
        mode_normal_enabled = p.get("mode_normal_enabled") if "mode_normal_enabled" in p else None
        mode_sync_enabled = p.get("mode_sync_enabled") if "mode_sync_enabled" in p else None
        mode_advanced_lot = p.get("mode_advanced_lot") if "mode_advanced_lot" in p else None
        mode_advanced_v2_lot = p.get("mode_advanced_v2_lot") if "mode_advanced_v2_lot" in p else None
        mode_normal_lot = p.get("mode_normal_lot") if "mode_normal_lot" in p else None
        mode_sync_lot = p.get("mode_sync_lot") if "mode_sync_lot" in p else None
        advanced_v2_policies = p.get("advanced_v2_policies") if "advanced_v2_policies" in p else None
        signal_confirm_sec = p.get("signal_confirm_sec") if "signal_confirm_sec" in p else None
        entry_exit_exit_wait_for_blank = (
            p.get("entry_exit_exit_wait_for_blank")
            if "entry_exit_exit_wait_for_blank" in p
            else (p.get("exit_wait_for_blank") if "exit_wait_for_blank" in p else None)
        )
        entry_exit_exit_mode = (
            p.get("entry_exit_exit_mode")
            if "entry_exit_exit_mode" in p
            else (p.get("exit_mode") if "exit_mode" in p else None)
        )
        entry_exit_exit_modes = (
            p.get("entry_exit_exit_modes")
            if "entry_exit_exit_modes" in p
            else (p.get("exit_modes") if "exit_modes" in p else None)
        )
        entry_exit_lifecycle_mode = (
            p.get("entry_exit_lifecycle_mode")
            if "entry_exit_lifecycle_mode" in p
            else (p.get("lifecycle_mode") if "lifecycle_mode" in p else None)
        )
        entry_exit_lifecycle_modes = (
            p.get("entry_exit_lifecycle_modes")
            if "entry_exit_lifecycle_modes" in p
            else (p.get("lifecycle_modes") if "lifecycle_modes" in p else None)
        )
        sync_direction_tf = p.get("sync_direction_tf") if "sync_direction_tf" in p else p.get("sync_anchor_tf")
        sync_entry_tf = p.get("sync_entry_tf") if "sync_entry_tf" in p else p.get("sync_trigger_tf")
        sync_exit_tf = p.get("sync_exit_tf") if "sync_exit_tf" in p else p.get("sync_trigger_tf")
        sync_reentry_enabled = p.get("sync_reentry_enabled") if "sync_reentry_enabled" in p else None
        half_be_enabled = p.get("half_be_enabled") if "half_be_enabled" in p else None
        half_be_tp_index = p.get("half_be_tp_index") if "half_be_tp_index" in p else None
        atomic_sl_widen_enabled = p.get("atomic_sl_widen_enabled") if "atomic_sl_widen_enabled" in p else None
        atomic_sl_widen_tight_pct = p.get("atomic_sl_widen_tight_pct") if "atomic_sl_widen_tight_pct" in p else None
        atomic_sl_widen_normal_pct = p.get("atomic_sl_widen_normal_pct") if "atomic_sl_widen_normal_pct" in p else None
        atomic_sl_widen_wide_pct = p.get("atomic_sl_widen_wide_pct") if "atomic_sl_widen_wide_pct" in p else None
        def _optional_bool(v: Any) -> Optional[bool]:
            if v is None:
                return None
            if isinstance(v, bool):
                return bool(v)
            return str(v).strip().lower() in {"1", "true", "yes", "on", "y"}
        lot_val = None
        if lot_size is not None:
            try:
                lot_val = float(lot_size)
            except Exception:
                return {"ok": False, "error": "invalid_lot_size"}
        mode_advanced_lot_val = None
        if mode_advanced_lot is not None:
            try:
                mode_advanced_lot_val = float(mode_advanced_lot)
            except Exception:
                return {"ok": False, "error": "invalid_mode_advanced_lot"}
        mode_advanced_v2_lot_val = None
        if mode_advanced_v2_lot is not None:
            try:
                mode_advanced_v2_lot_val = float(mode_advanced_v2_lot)
            except Exception:
                return {"ok": False, "error": "invalid_mode_advanced_v2_lot"}
        mode_normal_lot_val = None
        if mode_normal_lot is not None:
            try:
                mode_normal_lot_val = float(mode_normal_lot)
            except Exception:
                return {"ok": False, "error": "invalid_mode_normal_lot"}
        mode_sync_lot_val = None
        if mode_sync_lot is not None:
            try:
                mode_sync_lot_val = float(mode_sync_lot)
            except Exception:
                return {"ok": False, "error": "invalid_mode_sync_lot"}
        signal_confirm_sec_val = None
        if signal_confirm_sec is not None:
            try:
                signal_confirm_sec_val = float(signal_confirm_sec)
            except Exception:
                return {"ok": False, "error": "invalid_signal_confirm_sec"}
        half_be_tp_index_val = None
        if half_be_tp_index is not None:
            try:
                half_be_tp_index_val = int(float(half_be_tp_index))
            except Exception:
                return {"ok": False, "error": "invalid_half_be_tp_index"}
        atomic_sl_widen_tight_pct_val = None
        if atomic_sl_widen_tight_pct is not None:
            try:
                atomic_sl_widen_tight_pct_val = float(atomic_sl_widen_tight_pct)
            except Exception:
                return {"ok": False, "error": "invalid_atomic_sl_widen_tight_pct"}
        atomic_sl_widen_normal_pct_val = None
        if atomic_sl_widen_normal_pct is not None:
            try:
                atomic_sl_widen_normal_pct_val = float(atomic_sl_widen_normal_pct)
            except Exception:
                return {"ok": False, "error": "invalid_atomic_sl_widen_normal_pct"}
        atomic_sl_widen_wide_pct_val = None
        if atomic_sl_widen_wide_pct is not None:
            try:
                atomic_sl_widen_wide_pct_val = float(atomic_sl_widen_wide_pct)
            except Exception:
                return {"ok": False, "error": "invalid_atomic_sl_widen_wide_pct"}
        result = svc.update_indicator_bridge_instance_settings(
            terminal_family=str(terminal_family),
            indicator=str(indicator),
            symbol=str(symbol),
            timeframe=str(timeframe),
            enabled=(bool(enabled) if enabled is not None else None),
            lot_size=lot_val,
            mode_advanced_enabled=(bool(mode_advanced_enabled) if mode_advanced_enabled is not None else None),
            mode_advanced_v2_enabled=(bool(mode_advanced_v2_enabled) if mode_advanced_v2_enabled is not None else None),
            mode_normal_enabled=(bool(mode_normal_enabled) if mode_normal_enabled is not None else None),
            mode_sync_enabled=(bool(mode_sync_enabled) if mode_sync_enabled is not None else None),
            mode_advanced_lot=mode_advanced_lot_val,
            mode_advanced_v2_lot=mode_advanced_v2_lot_val,
            mode_normal_lot=mode_normal_lot_val,
            mode_sync_lot=mode_sync_lot_val,
            advanced_v2_policies=(dict(advanced_v2_policies) if isinstance(advanced_v2_policies, dict) else None),
            signal_confirm_sec=signal_confirm_sec_val,
            entry_exit_exit_wait_for_blank=(bool(entry_exit_exit_wait_for_blank) if entry_exit_exit_wait_for_blank is not None else None),
            entry_exit_exit_mode=(str(entry_exit_exit_mode) if entry_exit_exit_mode is not None else None),
            entry_exit_exit_modes=([str(x) for x in entry_exit_exit_modes] if isinstance(entry_exit_exit_modes, list) else None),
            entry_exit_lifecycle_mode=(str(entry_exit_lifecycle_mode) if entry_exit_lifecycle_mode is not None else None),
            entry_exit_lifecycle_modes=([str(x) for x in entry_exit_lifecycle_modes] if isinstance(entry_exit_lifecycle_modes, list) else None),
            sync_direction_tf=(str(sync_direction_tf) if sync_direction_tf is not None else None),
            sync_entry_tf=(str(sync_entry_tf) if sync_entry_tf is not None else None),
            sync_exit_tf=(str(sync_exit_tf) if sync_exit_tf is not None else None),
            sync_reentry_enabled=(bool(sync_reentry_enabled) if sync_reentry_enabled is not None else None),
            half_be_enabled=(bool(half_be_enabled) if half_be_enabled is not None else None),
            half_be_tp_index=half_be_tp_index_val,
            atomic_sl_widen_enabled=_optional_bool(atomic_sl_widen_enabled),
            atomic_sl_widen_tight_pct=atomic_sl_widen_tight_pct_val,
            atomic_sl_widen_normal_pct=atomic_sl_widen_normal_pct_val,
            atomic_sl_widen_wide_pct=atomic_sl_widen_wide_pct_val,
        )
        return {
            "ok": bool((result or {}).get("ok", True)),
            "update_result": result,
        }
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_instance_automation_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.post("/indicator-bridge/open-trade/close")
def indicator_bridge_open_trade_close(payload: Dict[str, Any]):
    """Manually close a live broker position shown in Indicator Automation V2."""
    try:
        from ..main import telegram_bridge_service

        p = payload if isinstance(payload, dict) else {}
        try:
            ticket = int(float(p.get("ticket") or p.get("position_ticket") or 0))
        except Exception:
            ticket = 0
        symbol = str(p.get("symbol") or "").strip().upper()
        if ticket <= 0:
            return {"ok": False, "error": "invalid_ticket"}
        if not symbol:
            return {"ok": False, "error": "missing_symbol"}

        live = LiveTradingService()
        close_result = live.close_position(
            symbol=str(symbol),
            position_ticket=int(ticket),
            comment="manual_indicator_close",
        )
        ok = bool((close_result or {}).get("ok"))

        audit_logged = False
        if ok and telegram_bridge_service is not None:
            try:
                open_meta = telegram_bridge_service._find_execution_open_meta_for_ticket(int(ticket))  # type: ignore[attr-defined]
                row = dict(open_meta or {})
                row["broker_ticket"] = int(ticket)
                row["symbol"] = str(symbol)
                row["created_at"] = str(row.get("opened_at") or "")
                telegram_bridge_service._append_closed_execution_log_from_row(  # type: ignore[attr-defined]
                    row=row,
                    reason="manual_close",
                    svc=live,
                    event_ts=datetime.now(timezone.utc),
                )
                audit_logged = True
            except Exception:
                audit_logged = False

        return {
            "ok": bool(ok),
            "executed": bool(ok),
            "ticket": int(ticket),
            "symbol": str(symbol),
            "close_result": close_result,
            "audit_logged": bool(audit_logged),
            "error": (None if ok else str((close_result or {}).get("error") or "close_failed")),
        }
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_open_trade_close_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.post("/indicator-bridge/open-trade/sl-be")
def indicator_bridge_open_trade_sl_be(payload: Dict[str, Any]):
    """Move a live broker position SL to break-even for Indicator Automation V2."""
    try:
        p = payload if isinstance(payload, dict) else {}
        try:
            ticket = int(float(p.get("ticket") or p.get("position_ticket") or 0))
        except Exception:
            ticket = 0
        symbol = str(p.get("symbol") or "").strip().upper()
        if ticket <= 0:
            return {"ok": False, "error": "invalid_ticket"}
        if not symbol:
            return {"ok": False, "error": "missing_symbol"}

        live = LiveTradingService()
        positions = live.get_open_positions(symbol=str(symbol))
        pos = None
        for row in positions or []:
            try:
                if int(row.get("ticket") or 0) == int(ticket):
                    pos = dict(row)
                    break
            except Exception:
                continue
        if not pos:
            return {"ok": False, "error": "position_not_found", "ticket": int(ticket), "symbol": str(symbol)}

        direction = str(pos.get("direction") or "").strip().upper()
        entry = float(pos.get("entry_price") or 0.0)
        cur_sl = _safe_optional_float(pos.get("stop_loss"))
        cur_tp = _safe_optional_float(pos.get("take_profit"))
        if direction not in {"BUY", "SELL"}:
            return {"ok": False, "error": "invalid_position_direction", "ticket": int(ticket), "direction": direction}
        if not math.isfinite(float(entry)) or float(entry) <= 0.0:
            return {"ok": False, "error": "invalid_entry_price", "ticket": int(ticket), "entry_price": entry}

        # Do not worsen an already protected runner. BE-or-better is a safe no-op.
        if cur_sl is not None and float(cur_sl) > 0.0:
            if direction == "BUY" and float(cur_sl) >= float(entry):
                return {
                    "ok": True,
                    "executed": False,
                    "updated": False,
                    "reason": "sl_already_at_or_better_be",
                    "ticket": int(ticket),
                    "symbol": str(pos.get("symbol") or symbol),
                    "direction": direction,
                    "entry_price": float(entry),
                    "stop_loss": float(cur_sl),
                }
            if direction == "SELL" and float(cur_sl) <= float(entry):
                return {
                    "ok": True,
                    "executed": False,
                    "updated": False,
                    "reason": "sl_already_at_or_better_be",
                    "ticket": int(ticket),
                    "symbol": str(pos.get("symbol") or symbol),
                    "direction": direction,
                    "entry_price": float(entry),
                    "stop_loss": float(cur_sl),
                }

        modify_result = live.modify_position_sl_tp(
            symbol=str(pos.get("symbol") or symbol),
            position_ticket=int(ticket),
            stop_loss=float(entry),
            take_profit=(float(cur_tp) if cur_tp is not None and float(cur_tp) > 0.0 else None),
            comment="manual_sl_be",
        )
        ok = bool((modify_result or {}).get("ok"))
        return {
            "ok": bool(ok),
            "executed": bool(ok),
            "updated": bool(ok),
            "ticket": int(ticket),
            "symbol": str(pos.get("symbol") or symbol),
            "direction": direction,
            "entry_price": float(entry),
            "previous_stop_loss": (float(cur_sl) if cur_sl is not None else None),
            "stop_loss": float(entry) if ok else None,
            "modify_result": modify_result,
            "error": (None if ok else str((modify_result or {}).get("error") or "sl_be_failed")),
        }
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_open_trade_sl_be_failed:{type(exc).__name__}:{str(exc)[:220]}")


@router.get("/indicator-bridge/execution-log/export")
def indicator_bridge_execution_log_export(
    format: str = Query("csv", pattern="^(csv|xlsx)$"),
    limit: int = Query(1000, ge=20, le=5000),
):
    """Export MT4/MT5 indicator execution audit rows as CSV or XLSX."""
    try:
        from ..main import telegram_bridge_service

        svc = telegram_bridge_service
        if svc is None:
            raise HTTPException(500, "telegram_bridge_unavailable")
        audit = svc.get_indicator_execution_audit_rows(limit=int(limit))
        rows = audit.get("rows") if isinstance(audit, dict) else []
        rows = rows if isinstance(rows, list) else []
        columns = [
            ("event_ts", "Event Time"),
            ("opened_at", "Opened At"),
            ("closed_at", "Closed At"),
            ("terminal_family", "Terminal"),
            ("indicator", "Indicator"),
            ("symbol", "Symbol"),
            ("timeframe", "Timeframe"),
            ("direction", "Direction"),
            ("lot", "Lot"),
            ("status", "Status"),
            ("execution_mode", "Execution Mode"),
            ("ticket", "Ticket"),
            ("order_number", "Order Number"),
            ("session_name", "Session"),
            ("max_profit", "Max Profit"),
            ("max_loss", "Max Loss"),
            ("highest_tp_reached", "Highest TP Reached"),
            ("highest_tp_price", "Highest TP Price"),
            ("highest_tp_updated_at", "Highest TP Updated At"),
            ("next_tp_index", "Next TP Index"),
            ("total_tps", "Total TPs"),
            ("realized_pnl", "Realized PnL"),
            ("shadow_outcome", "Shadow Outcome"),
            ("shadow_reason", "Shadow Reason"),
            ("shadow_mfe_price", "Shadow MFE Price"),
            ("shadow_mae_price", "Shadow MAE Price"),
            ("shadow_estimated_missed_profit_score", "Shadow Missed Profit Score"),
            ("shadow_estimated_avoided_loss_score", "Shadow Avoided Loss Score"),
            ("stop_loss", "Stop Loss"),
            ("final_tp", "Final TP"),
            ("close_reason", "Close Reason"),
            ("message", "Message"),
            ("combo_key", "Combo Key"),
            ("source_tag", "Source Tag"),
        ]
        ts_label = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        if str(format).lower() == "xlsx":
            wb = Workbook()
            ws = wb.active
            ws.title = "Indicator Audit"
            ws.append([label for _key, label in columns])
            for row in rows:
                item = row if isinstance(row, dict) else {}
                ws.append([item.get(key) for key, _label in columns])
            out = io.BytesIO()
            wb.save(out)
            out.seek(0)
            headers = {"Content-Disposition": f'attachment; filename="indicator_execution_audit_{ts_label}.xlsx"'}
            return StreamingResponse(
                out,
                media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                headers=headers,
            )

        out = io.StringIO()
        writer = csv.writer(out)
        writer.writerow([label for _key, label in columns])
        for row in rows:
            item = row if isinstance(row, dict) else {}
            writer.writerow([item.get(key) for key, _label in columns])
        data = io.BytesIO(out.getvalue().encode("utf-8-sig"))
        headers = {"Content-Disposition": f'attachment; filename="indicator_execution_audit_{ts_label}.csv"'}
        return StreamingResponse(data, media_type="text/csv; charset=utf-8", headers=headers)
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(500, f"indicator_bridge_execution_log_export_failed:{type(exc).__name__}:{str(exc)[:220]}")


def _safe_optional_float(value) -> Optional[float]:
    """Return finite float or None for nullable DB fields."""
    try:
        if value is None:
            return None
        v = float(value)
        if math.isnan(v) or math.isinf(v):
            return None
        return v
    except Exception:
        return None


def _json_safe(value):
    """Recursively sanitize structures so JSON encoding cannot fail on NaN/Inf."""
    if isinstance(value, dict):
        return {k: _json_safe(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_json_safe(v) for v in value]
    if isinstance(value, float):
        if math.isnan(value) or math.isinf(value):
            return None
        return value
    return value


def _calculate_position_size(
    account_balance: float,
    risk_pct: float,
    max_loss_per_contract: float,
    commission_per_leg: float = 0.65,
    legs_count: int = 2,
    max_contracts_cap: int = 50,
) -> Dict[str, Any]:
    """Contract sizing with fixed-fraction risk and round-trip commission."""
    if account_balance <= 0 or risk_pct <= 0 or max_loss_per_contract <= 0:
        return {
            "max_contracts": 0,
            "risk_budget_usd": 0.0,
            "risk_per_contract_usd": 0.0,
            "total_risk_usd": 0.0,
            "remaining_budget_usd": 0.0,
            "account_risk_pct": 0.0,
            "skip_reason": "invalid_inputs",
        }

    risk_budget = float(account_balance) * (float(risk_pct) / 100.0)
    round_trip_commission = max(0.0, float(commission_per_leg)) * max(1, int(legs_count)) * 2.0
    risk_per_contract = max(0.0, float(max_loss_per_contract)) + round_trip_commission
    max_contracts = int(min(max_contracts_cap, math.floor(risk_budget / max(risk_per_contract, 1e-9))))

    if max_contracts <= 0:
        return {
            "max_contracts": 0,
            "risk_budget_usd": round(risk_budget, 4),
            "risk_per_contract_usd": round(risk_per_contract, 4),
            "total_risk_usd": 0.0,
            "remaining_budget_usd": round(risk_budget, 4),
            "account_risk_pct": 0.0,
            "skip_reason": "max_loss_exceeds_risk_budget",
        }

    total_risk = float(max_contracts) * risk_per_contract
    return {
        "max_contracts": int(max_contracts),
        "risk_budget_usd": round(risk_budget, 4),
        "risk_per_contract_usd": round(risk_per_contract, 4),
        "total_risk_usd": round(total_risk, 4),
        "remaining_budget_usd": round(risk_budget - total_risk, 4),
        "account_risk_pct": round((total_risk / max(float(account_balance), 1e-9)) * 100.0, 4),
        "skip_reason": None,
    }


def _options_edge_journal_response(row: OptionsEdgeTradeJournalModel) -> OptionsEdgeJournalEntryResponse:
    return OptionsEdgeJournalEntryResponse(
        journal_id=row.journal_id,
        status=row.status,
        created_at=row.created_at,
        closed_at=row.closed_at,
        scan_id=row.scan_id,
        trade_candidate_id=row.trade_candidate_id,
        symbol=row.symbol,
        structure_type=row.structure_type,
        expiry_date=row.expiry_date,
        dte_at_entry=row.dte_at_entry,
        entry_credit=_safe_optional_float(row.entry_credit),
        max_profit=_safe_optional_float(row.max_profit),
        max_loss=_safe_optional_float(row.max_loss),
        pop_est=_safe_optional_float(row.pop_est),
        contracts=int(row.contracts or 1),
        account_balance_at_entry=_safe_optional_float(row.account_balance_at_entry),
        risk_pct_at_entry=_safe_optional_float(row.risk_pct_at_entry),
        portfolio_scope_key=str(row.portfolio_scope_key or "").strip() or None,
        portfolio_scope_profile=str(row.portfolio_scope_profile or "").strip() or None,
        portfolio_scope_broker=str(row.portfolio_scope_broker or "").strip() or None,
        portfolio_scope_account_login=str(row.portfolio_scope_account_login or "").strip() or None,
        portfolio_scope_account_server=str(row.portfolio_scope_account_server or "").strip() or None,
        exit_credit=_safe_optional_float(row.exit_credit),
        actual_pnl=_safe_optional_float(row.actual_pnl),
        actual_pnl_total=_safe_optional_float(row.actual_pnl_total),
        exit_reason=row.exit_reason,
        hold_days=int(row.hold_days) if row.hold_days is not None else None,
        notes=row.notes,
        legs_json=row.legs_json if isinstance(row.legs_json, list) else [],
    )


def _options_edge_backtest_response(row: OptionsEdgeBacktestRunModel) -> OptionsEdgeBacktestResponse:
    return OptionsEdgeBacktestResponse(
        run_id=row.run_id,
        created_at=row.created_at,
        status=row.status,
        scans_used=int(row.scans_used or 0),
        trades_simulated=int(row.trades_simulated or 0),
        mode=str((row.metrics_json or {}).get("mode", "deterministic_proxy")),
        metrics=row.metrics_json if isinstance(row.metrics_json, dict) else {},
        walk_forward=row.walk_forward_json if isinstance(row.walk_forward_json, dict) else {},
        stress=row.stress_json if isinstance(row.stress_json, dict) else {},
        equity_curve=row.equity_curve_json if isinstance(row.equity_curve_json, list) else [],
        trade_log=row.trade_log_json if isinstance(row.trade_log_json, list) else [],
        notes=row.notes_json if isinstance(row.notes_json, list) else [],
        request=row.request_json if isinstance(row.request_json, dict) else {},
    )


def _csp_screen_response(row: CSPScreenRunModel, candidates: Optional[List[CSPCandidateModel]] = None) -> CSPScreenRunResponse:
    cand_rows = candidates if candidates is not None else []
    out_candidates: List[CSPCandidateResponse] = []
    for c in cand_rows:
        fundamentals = c.fundamentals_json if isinstance(c.fundamentals_json, dict) else {}
        gate_reasons_raw = c.gate_reasons if isinstance(c.gate_reasons, list) else []
        out_candidates.append(
            CSPCandidateResponse(
                symbol=str(c.symbol),
                sector=c.sector,
                industry=c.industry,
                regime=str(c.regime or "normal"),
                iv_rank=_safe_optional_float(c.iv_rank),
                option_volume=_safe_optional_float(c.option_volume),
                pe_current=_safe_optional_float(c.pe_current),
                pe_5y_avg=_safe_optional_float(c.pe_5y_avg),
                pe_10y_avg=_safe_optional_float(c.pe_10y_avg),
                price_vs_sma200=_safe_optional_float(c.price_vs_sma200),
                fundamentals=fundamentals,
                gate_reasons=[str(x) for x in gate_reasons_raw if str(x).strip()],
            )
        )
    return CSPScreenRunResponse(
        id=int(row.id),
        run_date=row.run_date,
        total_symbols_screened=int(row.total_symbols_screened or 0),
        candidates_passed=int(row.candidates_passed or 0),
        config=row.config_json if isinstance(row.config_json, dict) else {},
        summary=row.summary_json if isinstance(row.summary_json, dict) else {},
        candidates=out_candidates,
    )


def _csp_backtest_response(row: CSPBacktestRunModel) -> CSPBacktestRunResponse:
    return CSPBacktestRunResponse(
        id=int(row.id),
        run_date=row.run_date,
        start_date=row.start_date,
        end_date=row.end_date,
        initial_capital=_safe_optional_float(row.initial_capital),
        final_capital=_safe_optional_float(row.final_capital),
        status=str(row.status or "COMPLETED"),
        error=row.error,
        config=row.config_json if isinstance(row.config_json, dict) else {},
        results=row.results_json if isinstance(row.results_json, dict) else {},
        equity_curve=row.equity_curve_json if isinstance(row.equity_curve_json, list) else [],
        trades=row.trades_json if isinstance(row.trades_json, list) else [],
    )


def _ai_bot_run_response(row: AIBotRunModel) -> AIBotRunResponse:
    plan_raw = row.execution_plan_json if isinstance(row.execution_plan_json, list) else []
    plan = []
    for p in plan_raw:
        if not isinstance(p, dict):
            continue
        plan.append(
            AIBotExecutionDecision(
                symbol=str(p.get("symbol") or "?"),
                action=str(p.get("action") or "SKIP"),
                structure_type=(str(p.get("structure_type")) if p.get("structure_type") is not None else None),
                trade_candidate_id=(int(p.get("trade_candidate_id")) if p.get("trade_candidate_id") is not None else None),
                contracts=int(p.get("contracts") or 0),
                confidence=_safe_float(p.get("confidence"), 0.0),
                reason=str(p.get("reason") or ""),
                evidence=p.get("evidence") if isinstance(p.get("evidence"), dict) else {},
            )
        )
    return AIBotRunResponse(
        run_id=row.run_id,
        created_at=row.created_at,
        status=str(row.status or "COMPLETED"),
        strategy_id=str(row.strategy_id or ""),
        context_id=str(row.context_id or ""),
        provider=str(row.provider or "deterministic"),
        llm_model_label=(str(row.model_label) if row.model_label else None),
        report=row.report_json if isinstance(row.report_json, dict) else {},
        execution_plan=plan,
        notes=row.notes_json if isinstance(row.notes_json, list) else [],
        error=row.error,
    )


def _build_payoff_curve(legs: List[Dict[str, Any]], points: int = 33) -> List[Dict[str, float]]:
    """
    Build simple expiration payoff curve from strategy legs for UI plotting.
    """
    if not isinstance(legs, list) or len(legs) == 0:
        return []
    strikes = []
    for leg in legs:
        k = _safe_float((leg or {}).get("strike"), np.nan)
        if np.isfinite(k) and k > 0:
            strikes.append(float(k))
    if len(strikes) == 0:
        return []

    lo = max(0.01, min(strikes) * 0.75)
    hi = max(lo + 0.01, max(strikes) * 1.25)
    xs = np.linspace(lo, hi, num=max(9, int(points)))
    out: List[Dict[str, float]] = []

    for x in xs:
        pnl = 0.0
        for leg in legs:
            leg = leg or {}
            action = str(leg.get("action") or "").upper()
            otype = str(leg.get("option_type") or "").upper()
            strike = _safe_float(leg.get("strike"), np.nan)
            premium = _safe_float(leg.get("mid"), 0.0)
            if not np.isfinite(strike):
                continue
            if otype == "C":
                intrinsic = max(float(x) - float(strike), 0.0)
            elif otype == "P":
                intrinsic = max(float(strike) - float(x), 0.0)
            else:
                intrinsic = 0.0
            if action == "SELL":
                pnl += premium - intrinsic
            else:
                pnl += -premium + intrinsic
        out.append({"price": round(float(x), 4), "pnl": round(float(pnl * 100.0), 4)})
    return out


def _journal_open_risk_usd(db: Session) -> float:
    rows = db.query(OptionsEdgeTradeJournalModel).filter(
        OptionsEdgeTradeJournalModel.status == "OPEN"
    ).all()
    total = 0.0
    for r in rows:
        total += _safe_float(r.max_loss, 0.0) * max(1, int(r.contracts or 1))
    return float(total)


def _live_trade_net_pnl(tr) -> float:
    """Conservative net approximation from stored live-trade fields."""
    return float(
        _safe_float(getattr(tr, "profit_loss", 0.0), 0.0)
        + _safe_float(getattr(tr, "commission", 0.0), 0.0)
        + _safe_float(getattr(tr, "swap", 0.0), 0.0)
    )


def _load_options_universe_csv(csv_file: str) -> pd.DataFrame:
    """
    Load options-edge universe snapshot from CSV in dashboard/data.
    """
    if not csv_file:
        raise HTTPException(status_code=400, detail="csv_file is empty")
    if ".." in csv_file or "/" in csv_file or "\\" in csv_file:
        raise HTTPException(status_code=400, detail="Invalid csv_file path")

    dashboard_data_dir = Path(__file__).resolve().parent.parent.parent / "data"
    candidates = [
        dashboard_data_dir / "options" / csv_file,
        dashboard_data_dir / "historical" / csv_file,
        dashboard_data_dir / csv_file,
    ]
    csv_path = None
    for c in candidates:
        if c.exists() and c.suffix.lower() == ".csv":
            csv_path = c
            break
    if csv_path is None:
        raise HTTPException(status_code=404, detail=f"CSV not found: {csv_file}")

    try:
        raw = pd.read_csv(csv_path)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to parse CSV: {e}")

    df = normalize_universe_dataframe(raw)
    if df.empty:
        raise HTTPException(status_code=400, detail="CSV produced empty universe after normalization")
    return df


def _load_option_chain_csv(csv_file: str) -> pd.DataFrame:
    """
    Load option-chain snapshot CSV from dashboard/data.
    """
    if not csv_file:
        raise HTTPException(status_code=400, detail="chain_csv_file is empty")
    if ".." in csv_file or "/" in csv_file or "\\" in csv_file:
        raise HTTPException(status_code=400, detail="Invalid chain_csv_file path")

    dashboard_data_dir = Path(__file__).resolve().parent.parent.parent / "data"
    candidates = [
        dashboard_data_dir / "options" / csv_file,
        dashboard_data_dir / "historical" / csv_file,
        dashboard_data_dir / csv_file,
    ]
    csv_path = None
    for c in candidates:
        if c.exists() and c.suffix.lower() == ".csv":
            csv_path = c
            break
    if csv_path is None:
        raise HTTPException(status_code=404, detail=f"Chain CSV not found: {csv_file}")

    try:
        raw = pd.read_csv(csv_path)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to parse chain CSV: {e}")

    chain = normalize_option_chain_dataframe(raw)
    if chain.empty:
        raise HTTPException(status_code=400, detail="Chain CSV produced empty option chain after normalization")
    return chain


# ========================== Health Check ==========================

@router.get("/health")
async def health_check():
    """Health check endpoint"""
    return {"status": "healthy", "timestamp": datetime.now(timezone.utc).isoformat()}


# ========================== Options Edge (Phase 1) ==========================

@router.get("/options-edge/providers/polygon/status", response_model=OptionsEdgeProviderStatusResponse)
async def get_options_edge_polygon_status():
    connector = PolygonOptionsConnector()
    st = connector.status()
    return OptionsEdgeProviderStatusResponse(
        provider=str(st.get("provider", "polygon")),
        configured=bool(st.get("configured", False)),
        api_key_masked=st.get("api_key_masked"),
        base_url=st.get("base_url"),
        warnings=st.get("warnings") if isinstance(st.get("warnings"), list) else [],
    )


@router.get("/options-edge/providers/polygon/probe", response_model=OptionsEdgeProviderProbeResponse)
async def probe_options_edge_polygon_entitlements(
    symbol: str = Query("AAPL", description="Underlying symbol to probe"),
):
    connector = PolygonOptionsConnector()
    probe = connector.probe_entitlements(symbol=symbol)
    return OptionsEdgeProviderProbeResponse(
        provider=str(probe.get("provider", "polygon")),
        symbol=str(probe.get("symbol", symbol)).upper(),
        configured=bool(probe.get("configured", False)),
        api_key_masked=probe.get("api_key_masked"),
        results=probe.get("results") if isinstance(probe.get("results"), list) else [],
    )


@router.get("/options-edge/universe/sp500")
async def get_options_edge_sp500_universe(
    limit: int = Query(475, ge=1, le=600),
):
    connector = PolygonOptionsConnector()
    symbols = await run_in_threadpool(connector.get_sp500_symbols, int(limit))
    return {
        "count": len(symbols),
        "symbols": symbols,
        "source": "local_csv_or_fallback",
    }


@router.post("/options-edge/scan/run-live", response_model=OptionsEdgeScanResponse)
async def run_options_edge_scan_live(
    request: OptionsEdgeLiveScanRequest,
    db: Session = Depends(get_db),
):
    provider = str(request.provider or "polygon").lower().strip()
    if provider != "polygon":
        raise HTTPException(status_code=400, detail=f"Unsupported provider: {provider}")
    if request.max_dte < request.min_dte:
        raise HTTPException(status_code=400, detail="max_dte must be >= min_dte")

    connector = PolygonOptionsConnector()
    st = connector.status()
    if not bool(st.get("configured", False)):
        raise HTTPException(status_code=400, detail="POLYGON_API_KEY missing or not configured")

    symbols = [str(s or "").upper().strip() for s in (request.symbols or [])]
    symbols = [s for s in symbols if s]
    if bool(request.use_sp500):
        sp500_syms = await run_in_threadpool(connector.get_sp500_symbols, int(request.sp500_limit))
        symbols = sorted(list(dict.fromkeys((symbols + list(sp500_syms)))))
    if len(symbols) == 0:
        raise HTTPException(status_code=400, detail="Provide symbols[] or enable use_sp500.")

    try:
        ds = await run_in_threadpool(
            connector.build_live_dataset,
            symbols,
            request.min_dte,
            request.max_dte,
            request.lookback_days,
            request.default_days_to_earnings,
            request.include_news,
            request.include_analyst,
            request.news_limit,
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Live data fetch failed: {e}")

    if ds.universe_df is None or ds.universe_df.empty:
        detail = "Live data fetch produced empty universe"
        meta = ds.metadata if isinstance(ds.metadata, dict) else {}
        if isinstance(meta.get("failed_symbols"), dict) and len(meta["failed_symbols"]) > 0:
            detail += f" | failed: {meta['failed_symbols']}"
        raise HTTPException(status_code=400, detail=detail)

    universe_rows = []
    for _, r in ds.universe_df.iterrows():
        tr = _safe_float(r.get("trend_20d_return"), np.nan)
        sk = _safe_float(r.get("put_call_skew"), np.nan)
        universe_rows.append(
            {
                "symbol": str(r.get("symbol", "")).upper(),
                "sector": str(r.get("sector", "UNKNOWN")),
                "price": _safe_float(r.get("price"), 0.0),
                "iv30": _safe_float(r.get("iv30"), 0.0),
                "hv30": _safe_float(r.get("hv30"), 0.0),
                "iv_rank_252": _safe_float(r.get("iv_rank_252"), 0.0),
                "avg_opt_volume_30d": _safe_float(r.get("avg_opt_volume_30d"), 0.0),
                "avg_oi_30d": _safe_float(r.get("avg_oi_30d"), 0.0),
                "avg_bid_ask_pct": _safe_float(r.get("avg_bid_ask_pct"), 1.0),
                "days_to_earnings": _safe_float(r.get("days_to_earnings"), request.default_days_to_earnings),
                "borrow_rate": _safe_optional_float(r.get("borrow_rate")),
                "earnings_date": r.get("earnings_date"),
                "trend_20d_return": None if not np.isfinite(tr) else float(tr),
                "put_call_skew": None if not np.isfinite(sk) else float(sk),
            }
        )

    option_chain_rows = ds.chain_df.to_dict("records") if (request.build_strategies and ds.chain_df is not None and not ds.chain_df.empty) else None

    scan_req = OptionsEdgeScanRequest(
        universe=universe_rows,
        option_chain=option_chain_rows,
        build_strategies=bool(request.build_strategies),
        top_n=int(request.top_n),
        max_sector_fraction=float(request.max_sector_fraction),
        gate_config=request.gate_config,
        score_weights=request.score_weights,
        builder_config=request.builder_config,
        llm_model=request.llm_model,
        llm_cost_usd=float(request.llm_cost_usd),
    )

    base_resp = await run_options_edge_scan(scan_req, db)

    # Persist and return live metadata in summary.
    row = db.query(OptionsEdgeScanRunModel).filter(OptionsEdgeScanRunModel.scan_id == base_resp.scan_id).first()
    merged_summary = dict(base_resp.summary or {})
    merged_summary["live_provider"] = "polygon"
    merged_summary["requested_symbol_count"] = len(symbols)
    merged_summary["live_data"] = _json_safe(ds.metadata or {})
    if row:
        row.summary_json = _json_safe(merged_summary)
        db.commit()

    return OptionsEdgeScanResponse(
        scan_id=base_resp.scan_id,
        scan_ts=base_resp.scan_ts,
        status=base_resp.status,
        summary=merged_summary,
        selected_symbols=base_resp.selected_symbols,
    )


@router.post("/options-edge/scan/run", response_model=OptionsEdgeScanResponse)
async def run_options_edge_scan(
    request: OptionsEdgeScanRequest,
    db: Session = Depends(get_db),
):
    """
    Run deterministic options volatility edge scan and persist results.
    """
    if request.universe and len(request.universe) > 0:
        df = normalize_universe_dataframe(pd.DataFrame([r.model_dump() for r in request.universe]))
    elif request.csv_file:
        df = _load_options_universe_csv(request.csv_file)
    else:
        raise HTTPException(status_code=400, detail="Provide either universe[] or csv_file")

    t0 = time.time()
    engine = OptionsEdgeScanEngine(
        gate_config=request.gate_config or DEFAULT_GATE_CONFIG,
        score_weights=request.score_weights or DEFAULT_SCORE_WEIGHTS,
        top_n=request.top_n,
        max_sector_fraction=request.max_sector_fraction,
    )
    result = engine.run(df)
    elapsed = time.time() - t0

    scan_id = uuid.uuid4().hex[:16]
    scan_ts = datetime.now(timezone.utc)

    db_scan = OptionsEdgeScanRunModel(
        scan_id=scan_id,
        scan_ts=scan_ts,
        status="COMPLETED",
        universe_size=int(result.summary.get("universe_size", 0)),
        passed_gate_count=int(result.summary.get("passed_gate_count", 0)),
        selected_count=int(result.summary.get("selected_count", 0)),
        top_n=int(request.top_n),
        max_sector_fraction=float(request.max_sector_fraction),
        gate_config=request.gate_config or DEFAULT_GATE_CONFIG,
        score_config=request.score_weights or DEFAULT_SCORE_WEIGHTS,
        summary_json=_json_safe(result.summary),
        llm_model=request.llm_model,
        llm_cost_usd=float(request.llm_cost_usd or 0.0),
        latency_sec=float(elapsed),
    )
    db.add(db_scan)

    for s in result.snapshots:
        db.add(OptionsEdgeStockSnapshotModel(
            scan_id=scan_id,
            symbol=str(s.get("symbol", "")),
            sector=str(s.get("sector", "UNKNOWN")),
            price=_safe_float(s.get("price"), 0.0),
            iv30=_safe_float(s.get("iv30"), 0.0),
            hv30=_safe_float(s.get("hv30"), 0.0),
            iv_rank_252=_safe_float(s.get("iv_rank_252"), 0.0),
            iv_hv_spread=_safe_float(s.get("iv_hv_spread"), 0.0),
            avg_opt_volume_30d=_safe_float(s.get("avg_opt_volume_30d"), 0.0),
            avg_oi_30d=_safe_float(s.get("avg_oi_30d"), 0.0),
            avg_bid_ask_pct=_safe_float(s.get("avg_bid_ask_pct"), 0.0),
            earnings_date=str(s.get("earnings_date")) if s.get("earnings_date") is not None else None,
            days_to_earnings=_safe_float(s.get("days_to_earnings"), 0.0),
            borrow_rate=_safe_optional_float(s.get("borrow_rate")),
            gate_pass=bool(s.get("gate_pass", False)),
            gate_reasons=_json_safe(s.get("gate_reasons", [])),
        ))

    score_rows_by_symbol = {}
    for c in result.scores:
        row_obj = OptionsEdgeCandidateScoreModel(
            scan_id=scan_id,
            symbol=str(c.get("symbol", "")),
            sector=str(c.get("sector", "UNKNOWN")),
            rank_global=int(c["rank_global"]) if c.get("rank_global") is not None else None,
            rank_in_sector=int(c["rank_in_sector"]) if c.get("rank_in_sector") is not None else None,
            selected=bool(c.get("selected", False)),
            score_total=_safe_float(c.get("score_total"), 0.0),
            score_vol_edge=_safe_float(c.get("score_vol_edge"), 0.0),
            score_liquidity=_safe_float(c.get("score_liquidity"), 0.0),
            score_event_timing=_safe_float(c.get("score_event_timing"), 0.0),
            score_risk=_safe_float(c.get("score_risk"), 0.0),
            penalty_sector_concentration=_safe_float(c.get("penalty_sector_concentration"), 0.0),
            builder_status="skipped" if bool(c.get("selected", False)) else "not_selected",
            builder_policy=None,
            builder_reasons=[],
        )
        db.add(row_obj)
        score_rows_by_symbol[row_obj.symbol] = row_obj

    # Phase 2: build options strategies for selected symbols when chain is provided.
    built_count = 0
    built_symbols = 0
    rejected_symbols = 0
    if request.build_strategies:
        chain_df: Optional[pd.DataFrame] = None
        if request.option_chain and len(request.option_chain) > 0:
            chain_df = normalize_option_chain_dataframe(pd.DataFrame(request.option_chain))
        elif request.chain_csv_file:
            chain_df = _load_option_chain_csv(request.chain_csv_file)

        if chain_df is not None and not chain_df.empty:
            builder = OptionsStrategyBuilder(config=request.builder_config or DEFAULT_BUILDER_CONFIG)
            snap_map = {str(s["symbol"]): s for s in result.snapshots}
            for sym in result.selected_symbols:
                snap = snap_map.get(sym)
                if not snap:
                    continue
                spot = _safe_float(snap.get("price"), np.nan)
                ivr = _safe_float(snap.get("iv_rank_252"), np.nan)
                trend = _safe_float(snap.get("trend_20d_return"), np.nan)
                skew = _safe_float(snap.get("put_call_skew"), np.nan)
                outcome = builder.build_for_symbol_diagnostics(
                    symbol=sym,
                    spot=spot,
                    chain_df=chain_df,
                    iv_rank_252=ivr,
                    trend_20d_return=trend,
                    put_call_skew=skew,
                )

                score_obj = score_rows_by_symbol.get(sym)
                if score_obj is not None:
                    score_obj.builder_policy = outcome.chosen_policy
                    score_obj.builder_reasons = _json_safe(outcome.rejection_reasons)
                    score_obj.builder_status = "built" if len(outcome.strategies) > 0 else "rejected"

                if len(outcome.strategies) > 0:
                    built_symbols += 1
                else:
                    rejected_symbols += 1

                for b in outcome.strategies:
                    db.add(OptionsEdgeTradeCandidateModel(
                        scan_id=scan_id,
                        symbol=b.symbol,
                        structure_type=b.structure_type,
                        expiry_date=b.expiry_date,
                        dte=int(b.dte) if b.dte is not None else None,
                        legs_json=_json_safe(b.legs),
                        net_credit=_safe_float(b.net_credit, 0.0),
                        max_profit=_safe_float(b.max_profit, 0.0),
                        max_loss=_safe_float(b.max_loss, 0.0),
                        pop_est=_safe_float(b.pop_est, 0.0),
                        delta_net=_safe_float(b.delta_net, 0.0),
                        theta_net=_safe_float(b.theta_net, 0.0),
                        vega_net=_safe_float(b.vega_net, 0.0),
                        breakeven_low=_safe_optional_float(b.breakeven_low),
                        breakeven_high=_safe_optional_float(b.breakeven_high),
                        quality_flags=_json_safe(b.quality_flags),
                    ))
                    built_count += 1

            # Update summary with strategy-builder stats.
            summary_obj = dict(result.summary or {})
            summary_obj["trade_candidates_built"] = int(built_count)
            summary_obj["symbols_with_trade_candidates"] = int(built_symbols)
            summary_obj["symbols_rejected_by_builder"] = int(rejected_symbols)
            db_scan.summary_json = _json_safe(summary_obj)

    db.commit()

    return OptionsEdgeScanResponse(
        scan_id=scan_id,
        scan_ts=scan_ts,
        status="COMPLETED",
        summary=dict(
            result.summary or {},
            trade_candidates_built=int(built_count),
            symbols_with_trade_candidates=int(built_symbols),
            symbols_rejected_by_builder=int(rejected_symbols),
        ),
        selected_symbols=result.selected_symbols,
    )


@router.get("/options-edge/scan/{scan_id}", response_model=OptionsEdgeScanDetailResponse)
async def get_options_edge_scan(scan_id: str, db: Session = Depends(get_db)):
    row = db.query(OptionsEdgeScanRunModel).filter(OptionsEdgeScanRunModel.scan_id == scan_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="Scan not found")

    return OptionsEdgeScanDetailResponse(
        scan_id=row.scan_id,
        scan_ts=row.scan_ts,
        status=row.status,
        universe_size=row.universe_size or 0,
        passed_gate_count=row.passed_gate_count or 0,
        selected_count=row.selected_count or 0,
        top_n=row.top_n or 8,
        max_sector_fraction=row.max_sector_fraction or 0.35,
        gate_config=row.gate_config,
        score_config=row.score_config,
        summary=row.summary_json,
        llm_model=row.llm_model,
        llm_cost_usd=row.llm_cost_usd or 0.0,
        latency_sec=row.latency_sec or 0.0,
        error=row.error,
    )


@router.get("/options-edge/scans", response_model=List[OptionsEdgeScanDetailResponse])
async def list_options_edge_scans(
    limit: int = Query(20, ge=1, le=200),
    db: Session = Depends(get_db),
):
    rows = db.query(OptionsEdgeScanRunModel).order_by(
        OptionsEdgeScanRunModel.scan_ts.desc()
    ).limit(limit).all()
    return [
        OptionsEdgeScanDetailResponse(
            scan_id=row.scan_id,
            scan_ts=row.scan_ts,
            status=row.status,
            universe_size=row.universe_size or 0,
            passed_gate_count=row.passed_gate_count or 0,
            selected_count=row.selected_count or 0,
            top_n=row.top_n or 8,
            max_sector_fraction=row.max_sector_fraction or 0.35,
            gate_config=row.gate_config,
            score_config=row.score_config,
            summary=row.summary_json,
            llm_model=row.llm_model,
            llm_cost_usd=row.llm_cost_usd or 0.0,
            latency_sec=row.latency_sec or 0.0,
            error=row.error,
        )
        for row in rows
    ]


@router.get("/options-edge/scan/{scan_id}/candidates", response_model=List[OptionsEdgeCandidateResponse])
async def get_options_edge_candidates(
    scan_id: str,
    selected_only: bool = Query(True, description="Return only selected symbols"),
    db: Session = Depends(get_db),
):
    q = db.query(OptionsEdgeCandidateScoreModel).filter(
        OptionsEdgeCandidateScoreModel.scan_id == scan_id
    )
    if selected_only:
        q = q.filter(OptionsEdgeCandidateScoreModel.selected == True)  # noqa: E712
    rows = q.order_by(
        OptionsEdgeCandidateScoreModel.selected.desc(),
        OptionsEdgeCandidateScoreModel.rank_global.asc(),
        OptionsEdgeCandidateScoreModel.score_total.desc(),
    ).all()
    return [
        OptionsEdgeCandidateResponse(
            symbol=r.symbol,
            sector=r.sector,
            selected=bool(r.selected),
            rank_global=r.rank_global,
            rank_in_sector=r.rank_in_sector,
            score_total=float(r.score_total or 0.0),
            score_vol_edge=float(r.score_vol_edge or 0.0),
            score_liquidity=float(r.score_liquidity or 0.0),
            score_event_timing=float(r.score_event_timing or 0.0),
            score_risk=float(r.score_risk or 0.0),
            penalty_sector_concentration=float(r.penalty_sector_concentration or 0.0),
            builder_status=r.builder_status,
            builder_policy=r.builder_policy,
            builder_reasons=r.builder_reasons if isinstance(r.builder_reasons, list) else [],
        )
        for r in rows
    ]


@router.get("/options-edge/scan/{scan_id}/trades", response_model=List[OptionsEdgeTradeCandidateResponse])
async def get_options_edge_trade_candidates(
    scan_id: str,
    symbol: Optional[str] = Query(None, description="Optional symbol filter"),
    db: Session = Depends(get_db),
):
    q = db.query(OptionsEdgeTradeCandidateModel).filter(
        OptionsEdgeTradeCandidateModel.scan_id == scan_id
    )
    if symbol:
        q = q.filter(OptionsEdgeTradeCandidateModel.symbol == symbol.upper())
    rows = q.order_by(
        OptionsEdgeTradeCandidateModel.symbol.asc(),
        OptionsEdgeTradeCandidateModel.pop_est.desc(),
    ).all()
    return [
        OptionsEdgeTradeCandidateResponse(
            id=r.id,
            symbol=r.symbol,
            structure_type=r.structure_type,
            expiry_date=r.expiry_date,
            dte=r.dte,
            net_credit=float(r.net_credit) if r.net_credit is not None else None,
            max_profit=float(r.max_profit) if r.max_profit is not None else None,
            max_loss=float(r.max_loss) if r.max_loss is not None else None,
            pop_est=float(r.pop_est) if r.pop_est is not None else None,
            delta_net=float(r.delta_net) if r.delta_net is not None else None,
            theta_net=float(r.theta_net) if r.theta_net is not None else None,
            vega_net=float(r.vega_net) if r.vega_net is not None else None,
            breakeven_low=float(r.breakeven_low) if r.breakeven_low is not None else None,
            breakeven_high=float(r.breakeven_high) if r.breakeven_high is not None else None,
            quality_flags=r.quality_flags if isinstance(r.quality_flags, list) else [],
            legs_json=r.legs_json if isinstance(r.legs_json, list) else [],
            payoff_curve=_build_payoff_curve(r.legs_json if isinstance(r.legs_json, list) else []),
        )
        for r in rows
    ]


@router.get("/options-edge/scan/{scan_id}/report", response_model=OptionsEdgeScanReportResponse)
async def get_options_edge_scan_report(
    scan_id: str,
    llm_model: Optional[str] = Query(None, description="Optional model label for report metadata"),
    db: Session = Depends(get_db),
    llm_provider: Optional[str] = Query(
        None,
        description="Optional report provider: deterministic | local_gptoss_http | anthropic_claude",
    ),
):
    scan = db.query(OptionsEdgeScanRunModel).filter(OptionsEdgeScanRunModel.scan_id == scan_id).first()
    if not scan:
        raise HTTPException(status_code=404, detail="Scan not found")

    cand_rows = db.query(OptionsEdgeCandidateScoreModel).filter(
        OptionsEdgeCandidateScoreModel.scan_id == scan_id
    ).all()
    trade_rows = db.query(OptionsEdgeTradeCandidateModel).filter(
        OptionsEdgeTradeCandidateModel.scan_id == scan_id
    ).all()

    candidates = []
    for r in cand_rows:
        candidates.append({
            "symbol": r.symbol,
            "sector": r.sector,
            "selected": bool(r.selected),
            "score_total": float(r.score_total or 0.0),
            "score_vol_edge": float(r.score_vol_edge or 0.0),
            "score_liquidity": float(r.score_liquidity or 0.0),
            "score_event_timing": float(r.score_event_timing or 0.0),
            "score_risk": float(r.score_risk or 0.0),
            "builder_status": r.builder_status,
        })
    trades = []
    for r in trade_rows:
        quality_flags = r.quality_flags if isinstance(r.quality_flags, list) else []
        trades.append({
            "symbol": r.symbol,
            "structure_type": r.structure_type,
            "pop_est": float(r.pop_est or 0.0),
            "max_profit": float(r.max_profit or 0.0),
            "max_loss": float(r.max_loss or 0.0),
            "quality_flags": quality_flags,
            "max_loss_is_proxy": bool("max_loss_proxy_unbounded" in quality_flags),
        })

    summary = scan.summary_json if isinstance(scan.summary_json, dict) else {}
    live_data = summary.get("live_data", {}) if isinstance(summary, dict) else {}
    symbol_insights = live_data.get("symbol_insights", {}) if isinstance(live_data, dict) else {}

    # Default to deterministic for responsive report retrieval; GPT/Claude are opt-in via query param.
    provider_from_query = bool(isinstance(llm_provider, str) and str(llm_provider).strip())
    resolved_provider = str(llm_provider).strip().lower() if provider_from_query else "deterministic"
    resolved_model = llm_model
    stored_label = str(scan.llm_model or "").strip()
    # Allow stored format: "<provider>:<model>" (e.g. local_gptoss_http:gpt-oss-20b)
    if stored_label:
        if ":" in stored_label:
            pfx, tail = stored_label.split(":", 1)
            pfx = pfx.strip().lower()
            if pfx in {"deterministic", "local_gptoss_http", "anthropic_claude"} and not provider_from_query:
                resolved_provider = pfx
            if not resolved_model and tail.strip() and pfx == resolved_provider:
                resolved_model = tail.strip()
        elif not resolved_model:
            resolved_model = stored_label

    reporter = OptionsEdgeReporter()
    report = await run_in_threadpool(
        reporter.build_report,
        scan={
            "scan_id": scan.scan_id,
            "universe_size": int(scan.universe_size or 0),
            "top_n": int(scan.top_n or 8),
        },
        candidates=candidates,
        trades=trades,
        symbol_insights=symbol_insights if isinstance(symbol_insights, dict) else {},
        llm_model=resolved_model or "deterministic",
        llm_provider=resolved_provider,
    )
    return OptionsEdgeScanReportResponse(scan_id=scan_id, **report)


@router.post("/ai-bots/options-edge/plan/{scan_id}", response_model=AIBotRunResponse)
async def run_ai_bot_options_edge_plan(
    scan_id: str,
    request: AIBotOptionsEdgePlanRequest,
    db: Session = Depends(get_db),
):
    """
    Generate an executable options-edge bot plan from a persisted scan.

    This endpoint is paper-first: it creates OPEN_PAPER actions when dry_run=true.
    """
    run_id = uuid.uuid4().hex[:16]
    created_at = datetime.now(timezone.utc)
    agent = OptionsEdgeAIBotAgent(db)
    try:
        result = agent.build_plan(
            scan_id=scan_id,
            provider=str(request.provider or "deterministic"),
            model_label=request.llm_model_label,
            account_balance=float(request.account_balance),
            risk_pct=float(request.risk_pct),
            max_contracts_cap=int(request.max_contracts_cap),
            dry_run=bool(request.dry_run),
            llm_url=request.llm_url,
            api_key=request.api_key,
        )
        row = AIBotRunModel(
            run_id=run_id,
            created_at=created_at,
            status=("COMPLETED_FALLBACK" if bool(result.get("fallback_used")) else "COMPLETED"),
            strategy_id="options_edge",
            context_id=scan_id,
            provider=str(result.get("provider") or request.provider or "deterministic"),
            model_label=str(result.get("model_label") or request.llm_model_label or ""),
            request_json=_json_safe(request.model_dump(exclude={"api_key"})),
            report_json=_json_safe(result.get("report") if isinstance(result.get("report"), dict) else {}),
            execution_plan_json=_json_safe(result.get("execution_plan") if isinstance(result.get("execution_plan"), list) else []),
            notes_json=_json_safe(result.get("notes") if isinstance(result.get("notes"), list) else []),
            error=None,
        )
        db.add(row)
        db.commit()
        db.refresh(row)
        return _ai_bot_run_response(row)
    except Exception as e:
        row = AIBotRunModel(
            run_id=run_id,
            created_at=created_at,
            status="FAILED",
            strategy_id="options_edge",
            context_id=scan_id,
            provider=str(request.provider or "deterministic"),
            model_label=request.llm_model_label,
            request_json=_json_safe(request.model_dump(exclude={"api_key"})),
            report_json={},
            execution_plan_json=[],
            notes_json=[],
            error=str(e),
        )
        db.add(row)
        db.commit()
        raise HTTPException(status_code=400, detail=f"AI bot planning failed: {e}")


@router.get("/ai-bots/runs/{run_id}", response_model=AIBotRunResponse)
async def get_ai_bot_run(run_id: str, db: Session = Depends(get_db)):
    row = db.query(AIBotRunModel).filter(AIBotRunModel.run_id == run_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="AI bot run not found")
    return _ai_bot_run_response(row)


@router.get("/ai-bots/runs", response_model=List[AIBotRunResponse])
async def list_ai_bot_runs(
    strategy_id: Optional[str] = Query(None),
    context_id: Optional[str] = Query(None),
    status: Optional[str] = Query(None),
    limit: int = Query(20, ge=1, le=500),
    db: Session = Depends(get_db),
):
    q = db.query(AIBotRunModel)
    if strategy_id:
        q = q.filter(AIBotRunModel.strategy_id == str(strategy_id))
    if context_id:
        q = q.filter(AIBotRunModel.context_id == str(context_id))
    if status:
        q = q.filter(AIBotRunModel.status == str(status).upper())
    rows = q.order_by(AIBotRunModel.created_at.desc()).limit(limit).all()
    return [_ai_bot_run_response(r) for r in rows]


@router.post("/options-edge/position-size", response_model=OptionsEdgePositionSizingResponse)
async def options_edge_position_size(request: OptionsEdgePositionSizingRequest):
    sizing: List[OptionsEdgePositionSizingItem] = []
    portfolio_total_risk = 0.0

    for t in request.trades:
        out = _calculate_position_size(
            account_balance=float(request.account_balance),
            risk_pct=float(request.risk_pct),
            max_loss_per_contract=float(t.max_loss),
            commission_per_leg=float(request.commission_per_leg),
            legs_count=int(t.legs_count),
            max_contracts_cap=int(request.max_contracts_cap),
        )
        item = OptionsEdgePositionSizingItem(
            symbol=t.symbol,
            structure_type=t.structure_type,
            max_contracts=int(out["max_contracts"]),
            risk_budget_usd=float(out["risk_budget_usd"]),
            risk_per_contract_usd=float(out["risk_per_contract_usd"]),
            total_risk_usd=float(out["total_risk_usd"]),
            remaining_budget_usd=float(out["remaining_budget_usd"]),
            account_risk_pct=float(out["account_risk_pct"]),
            skip_reason=out.get("skip_reason"),
        )
        sizing.append(item)
        portfolio_total_risk += float(item.total_risk_usd)

    return OptionsEdgePositionSizingResponse(
        ok=True,
        portfolio_total_risk_usd=round(float(portfolio_total_risk), 4),
        portfolio_risk_pct=round(float((portfolio_total_risk / max(float(request.account_balance), 1e-9)) * 100.0), 4),
        sizing=sizing,
    )


@router.post("/options-edge/journal/track", response_model=OptionsEdgeJournalEntryResponse)
async def options_edge_journal_track(
    request: OptionsEdgeJournalTrackRequest,
    db: Session = Depends(get_db),
):
    from Strategies.strategy_manager import StrategyManager

    trade = (
        db.query(OptionsEdgeTradeCandidateModel)
        .filter(OptionsEdgeTradeCandidateModel.id == int(request.trade_candidate_id))
        .first()
    )
    if not trade:
        raise HTTPException(status_code=404, detail="Trade candidate not found")
    if str(trade.scan_id) != str(request.scan_id):
        raise HTTPException(status_code=400, detail="trade_candidate_id does not belong to scan_id")

    journal_id = uuid.uuid4().hex[:16]
    scope = StrategyManager.current_portfolio_scope()
    row = OptionsEdgeTradeJournalModel(
        journal_id=journal_id,
        status="OPEN",
        scan_id=str(request.scan_id),
        trade_candidate_id=int(request.trade_candidate_id),
        symbol=str(trade.symbol),
        structure_type=str(trade.structure_type),
        legs_json=_json_safe(trade.legs_json if isinstance(trade.legs_json, list) else []),
        entry_credit=_safe_optional_float(trade.net_credit),
        max_profit=_safe_optional_float(trade.max_profit),
        max_loss=_safe_optional_float(trade.max_loss),
        pop_est=_safe_optional_float(trade.pop_est),
        expiry_date=trade.expiry_date,
        dte_at_entry=int(trade.dte) if trade.dte is not None else None,
        contracts=int(request.contracts),
        account_balance_at_entry=_safe_optional_float(request.account_balance_at_entry),
        risk_pct_at_entry=_safe_optional_float(request.risk_pct_at_entry),
        portfolio_scope_key=str(scope.get("scope_key") or "").strip() or None,
        portfolio_scope_profile=str(scope.get("profile") or "").strip() or None,
        portfolio_scope_broker=str(scope.get("broker_name") or "").strip() or None,
        portfolio_scope_account_login=str(scope.get("account_login") or "").strip() or None,
        portfolio_scope_account_server=str(scope.get("account_server") or "").strip() or None,
        notes=request.notes,
    )
    db.add(row)
    db.commit()
    db.refresh(row)
    return _options_edge_journal_response(row)


@router.post("/options-edge/journal/{journal_id}/close", response_model=OptionsEdgeJournalEntryResponse)
async def options_edge_journal_close(
    journal_id: str,
    request: OptionsEdgeJournalCloseRequest,
    db: Session = Depends(get_db),
):
    row = (
        db.query(OptionsEdgeTradeJournalModel)
        .filter(OptionsEdgeTradeJournalModel.journal_id == journal_id)
        .first()
    )
    if not row:
        raise HTTPException(status_code=404, detail="Journal entry not found")
    if str(row.status).upper() != "OPEN":
        raise HTTPException(status_code=400, detail="Journal entry is not OPEN")

    now_ts = datetime.now(timezone.utc).replace(tzinfo=None)
    created_ts = row.created_at or now_ts
    hold_days = max(0, (now_ts.date() - created_ts.date()).days)
    pnl_per_contract = _safe_float(request.actual_pnl, 0.0)
    contracts = max(1, int(row.contracts or 1))

    row.closed_at = now_ts
    row.status = "CLOSED"
    row.exit_credit = _safe_optional_float(request.exit_credit)
    row.actual_pnl = pnl_per_contract
    row.actual_pnl_total = float(pnl_per_contract * contracts)
    row.exit_reason = str(request.exit_reason or "manual")[:40]
    row.hold_days = int(hold_days)
    if request.notes:
        prev = str(row.notes or "").strip()
        row.notes = f"{prev}\n{request.notes}".strip() if prev else request.notes

    db.commit()
    db.refresh(row)
    return _options_edge_journal_response(row)


@router.get("/options-edge/journal", response_model=List[OptionsEdgeJournalEntryResponse])
async def options_edge_journal_list(
    status: Optional[str] = Query(None, description="OPEN | CLOSED | EXPIRED | CANCELLED"),
    limit: int = Query(200, ge=1, le=2000),
    db: Session = Depends(get_db),
):
    q = db.query(OptionsEdgeTradeJournalModel)
    if isinstance(status, str) and status.strip():
        q = q.filter(OptionsEdgeTradeJournalModel.status == status.strip().upper())
    rows = q.order_by(OptionsEdgeTradeJournalModel.created_at.desc()).limit(limit).all()
    return [_options_edge_journal_response(r) for r in rows]


@router.get("/options-edge/journal/stats", response_model=OptionsEdgeJournalStatsResponse)
async def options_edge_journal_stats(db: Session = Depends(get_db)):
    rows = db.query(OptionsEdgeTradeJournalModel).all()
    total = len(rows)
    open_count = sum(1 for r in rows if str(r.status).upper() == "OPEN")
    closed_rows = [r for r in rows if str(r.status).upper() == "CLOSED"]
    closed = len(closed_rows)
    pnl_vals = [float(_safe_float(r.actual_pnl_total, 0.0)) for r in closed_rows]
    wins = sum(1 for p in pnl_vals if p > 0)
    losses = sum(1 for p in pnl_vals if p < 0)
    hold_vals = [int(r.hold_days) for r in closed_rows if r.hold_days is not None]
    total_pnl = float(sum(pnl_vals))

    return OptionsEdgeJournalStatsResponse(
        total=int(total),
        open=int(open_count),
        closed=int(closed),
        wins=int(wins),
        losses=int(losses),
        win_rate=round(float((wins / closed) * 100.0), 4) if closed > 0 else 0.0,
        total_pnl=round(total_pnl, 4),
        avg_pnl=round(float(total_pnl / closed), 4) if closed > 0 else 0.0,
        avg_hold_days=round(float(sum(hold_vals) / len(hold_vals)), 4) if hold_vals else 0.0,
    )


@router.delete("/options-edge/journal/{journal_id}")
async def options_edge_journal_delete(journal_id: str, db: Session = Depends(get_db)):
    row = (
        db.query(OptionsEdgeTradeJournalModel)
        .filter(OptionsEdgeTradeJournalModel.journal_id == journal_id)
        .first()
    )
    if not row:
        raise HTTPException(status_code=404, detail="Journal entry not found")
    db.delete(row)
    db.commit()
    return {"ok": True, "journal_id": journal_id}


@router.post("/options-edge/backtest/run", response_model=OptionsEdgeBacktestResponse)
async def run_options_edge_backtest(
    request: OptionsEdgeBacktestRequest,
    db: Session = Depends(get_db),
):
    """
    Phase 3: run deterministic options-edge portfolio backtest + walk-forward/stress report.
    """
    engine = OptionsEdgeBacktestEngine(db)
    try:
        report = engine.run(request.model_dump())
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Options-edge backtest failed: {e}")

    run_id = uuid.uuid4().hex[:16]
    created_at = datetime.now(timezone.utc)
    metrics = report.get("metrics") if isinstance(report.get("metrics"), dict) else {}
    walk_forward = report.get("walk_forward") if isinstance(report.get("walk_forward"), dict) else {}
    stress = report.get("stress") if isinstance(report.get("stress"), dict) else {}
    notes = report.get("notes") if isinstance(report.get("notes"), list) else []
    equity_curve = report.get("equity_curve") if isinstance(report.get("equity_curve"), list) else []
    trade_log = report.get("trade_log") if isinstance(report.get("trade_log"), list) else []

    row = OptionsEdgeBacktestRunModel(
        run_id=run_id,
        created_at=created_at,
        status="COMPLETED",
        scans_used=int(report.get("scans_used", 0)),
        trades_simulated=int(metrics.get("total_trades", 0)),
        initial_balance=_safe_float(metrics.get("initial_balance"), 0.0),
        final_balance=_safe_float(metrics.get("final_balance"), 0.0),
        net_profit=_safe_float(metrics.get("net_profit"), 0.0),
        win_rate=_safe_float(metrics.get("win_rate"), 0.0),
        profit_factor=_safe_float(metrics.get("profit_factor"), 0.0),
        max_drawdown_pct=_safe_float(metrics.get("max_drawdown_pct"), 0.0),
        sharpe_ratio=_safe_float(metrics.get("sharpe_ratio"), 0.0),
        request_json=_json_safe(request.model_dump(mode="json")),
        metrics_json=_json_safe(dict(metrics, mode=str(report.get("mode", "deterministic_proxy")))),
        walk_forward_json=_json_safe(walk_forward),
        stress_json=_json_safe(stress),
        equity_curve_json=_json_safe(equity_curve),
        trade_log_json=_json_safe(trade_log),
        notes_json=_json_safe(notes),
    )
    db.add(row)
    db.commit()

    return _options_edge_backtest_response(row)


@router.get("/options-edge/backtest/{run_id}", response_model=OptionsEdgeBacktestResponse)
async def get_options_edge_backtest(run_id: str, db: Session = Depends(get_db)):
    row = db.query(OptionsEdgeBacktestRunModel).filter(OptionsEdgeBacktestRunModel.run_id == run_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="Options-edge backtest run not found")
    return _options_edge_backtest_response(row)


@router.get("/options-edge/backtests", response_model=List[OptionsEdgeBacktestResponse])
async def list_options_edge_backtests(
    limit: int = Query(20, ge=1, le=200),
    db: Session = Depends(get_db),
):
    rows = db.query(OptionsEdgeBacktestRunModel).order_by(
        OptionsEdgeBacktestRunModel.created_at.desc()
    ).limit(limit).all()
    return [_options_edge_backtest_response(r) for r in rows]


# ========================== CSP Strategy Endpoints ==========================

@router.post("/options-edge/csp/screen", response_model=CSPScreenRunResponse)
async def run_csp_screen(
    request: CSPScreenRequest,
    db: Session = Depends(get_db),
):
    provider = str(request.provider or "polygon").lower().strip()
    if provider != "polygon":
        raise HTTPException(status_code=400, detail=f"Unsupported provider: {provider}")

    connector = PolygonOptionsConnector()
    st = connector.status()
    if not bool(st.get("configured", False)):
        raise HTTPException(status_code=400, detail="POLYGON_API_KEY missing or not configured")

    symbols = [str(s or "").upper().strip() for s in (request.symbols or [])]
    symbols = [s for s in symbols if s]
    if bool(request.use_sp500):
        sp500_syms = await run_in_threadpool(connector.get_sp500_symbols, int(request.sp500_limit))
        symbols = sorted(list(dict.fromkeys((symbols + list(sp500_syms)))))
    if len(symbols) == 0:
        raise HTTPException(status_code=400, detail="Provide symbols[] or enable use_sp500.")

    try:
        ds = await run_in_threadpool(
            connector.build_live_dataset,
            symbols,
            21,   # Wider screening fetch window; entry engine still enforces CSP trade DTE config.
            75,
            45,   # lookback
            999.0,
            False,
            False,
            0,
        )
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"CSP live data fetch failed: {e}")

    if ds.universe_df is None or ds.universe_df.empty:
        failed = ds.metadata.get("failed_symbols") if isinstance(ds.metadata, dict) else {}
        fail_preview = {}
        if isinstance(failed, dict):
            for k, v in list(failed.items())[:5]:
                fail_preview[str(k)] = str(v)[:120]
        raise HTTPException(status_code=400, detail=f"CSP screen: empty universe from provider (failed={fail_preview})")

    overrides = {str(k).upper().strip(): (v if isinstance(v, dict) else {}) for k, v in (request.fundamentals_overrides or {}).items()}
    auto_fundamentals: Dict[str, Dict[str, Any]] = {}
    if bool(request.fetch_fundamentals) and hasattr(connector, "get_csp_fundamentals_batch"):
        try:
            spot_map: Dict[str, float] = {}
            if ds.universe_df is not None and not ds.universe_df.empty:
                for _, ur in ds.universe_df.iterrows():
                    ss = str(ur.get("symbol") or "").upper().strip()
                    if not ss:
                        continue
                    spot_map[ss] = _safe_float(ur.get("price"), np.nan)
            auto_fundamentals = await run_in_threadpool(
                connector.get_csp_fundamentals_batch,
                symbols,
                spot_map,
                bool(request.include_price_vs_sma200),
            )
            if not isinstance(auto_fundamentals, dict):
                auto_fundamentals = {}
        except Exception:
            auto_fundamentals = {}
    rows: List[Dict[str, Any]] = []
    for _, r in ds.universe_df.iterrows():
        sym = str(r.get("symbol", "")).upper().strip()
        ov = overrides.get(sym, {})
        af = auto_fundamentals.get(sym, {}) if isinstance(auto_fundamentals.get(sym), dict) else {}

        def _merge_num(name: str, fallback=np.nan):
            if name in ov:
                return _safe_float(ov.get(name), fallback)
            if name in af:
                return _safe_float(af.get(name), fallback)
            return _safe_float(r.get(name), fallback)

        rows.append(
            {
                "symbol": sym,
                "sector": str(ov.get("sector") or af.get("sector") or r.get("sector") or "UNKNOWN"),
                "industry": str(ov.get("industry") or af.get("industry") or ""),
                "revenue_growth_pct": _merge_num("revenue_growth_pct", np.nan),
                "eps_growth_5y_pct": _merge_num("eps_growth_5y_pct", np.nan),
                "eps_growth_fwd_pct": _merge_num("eps_growth_fwd_pct", np.nan),
                "profit_margin_pct": _merge_num("profit_margin_pct", np.nan),
                "total_assets": _merge_num("total_assets", np.nan),
                "total_liabilities": _merge_num("total_liabilities", np.nan),
                "free_cash_flow": _merge_num("free_cash_flow", np.nan),
                "iv_rank": _safe_float(ov.get("iv_rank"), _safe_float(af.get("iv_rank"), _safe_float(r.get("iv_rank_252"), np.nan))),
                "option_volume_30d": _safe_float(
                    ov.get("option_volume_30d"),
                    _safe_float(
                        af.get("option_volume_30d"),
                        _safe_float(r.get("liquidity_notional_proxy"), _safe_float(r.get("avg_opt_notional_30d"), _safe_float(r.get("avg_opt_volume_30d"), np.nan))),
                    ),
                ),
                "pe_current": _merge_num("pe_current", np.nan),
                "pe_5y_avg": _merge_num("pe_5y_avg", np.nan),
                "pe_10y_avg": _merge_num("pe_10y_avg", np.nan),
                "price_vs_sma200": _merge_num("price_vs_sma200", np.nan),
            }
        )
    screen_df = pd.DataFrame(rows)

    cfg = CSPScreenConfig(
        min_revenue_growth_pct=float(request.min_revenue_growth_pct),
        min_eps_growth_5y_pct=float(request.min_eps_growth_5y_pct),
        min_eps_growth_fwd_pct=float(request.min_eps_growth_fwd_pct),
        min_profit_margin_pct=float(request.min_profit_margin_pct),
        min_iv_rank=float(request.min_iv_rank),
        min_option_volume_30d=float(request.min_option_volume_30d),
        excluded_industries=list(request.excluded_industries or []),
    )
    screener = CSPScreener(config=cfg)
    result = screener.screen_dataframe(
        screen_df,
        vix_value=request.vix_value,
        vix_aggressive_threshold=float(request.vix_aggressive_threshold),
        sma200_touch_pct=float(request.sma200_touch_pct),
    )

    reason_counts: Dict[str, int] = {}
    for rej in result.rejected:
        for reason in (rej.get("reasons") or []):
            reason_counts[str(reason)] = reason_counts.get(str(reason), 0) + 1
    rejected_rows = []
    for rej in (result.rejected or []):
        if not isinstance(rej, dict):
            continue
        rejected_rows.append(
            {
                "symbol": str(rej.get("symbol") or ""),
                "reasons": [str(r) for r in (rej.get("reasons") or []) if str(r).strip()],
                "sector": str(rej.get("sector") or ""),
                "industry": str(rej.get("industry") or ""),
                "iv_rank": _safe_optional_float(rej.get("iv_rank")),
                "option_volume_30d": _safe_optional_float(rej.get("option_volume_30d")),
            }
        )

    db_run = CSPScreenRunModel(
        run_date=datetime.now(timezone.utc),
        total_symbols_screened=int(result.total_symbols_screened),
        candidates_passed=int(result.candidates_passed),
        config_json=_json_safe(request.model_dump(mode="json")),
        summary_json=_json_safe(
            dict(
                result.summary,
                top_rejection_reasons=sorted(reason_counts.items(), key=lambda x: x[1], reverse=True)[:20],
                rejected_rows=rejected_rows,
                provider="polygon",
                auto_fundamentals_loaded=int(len(auto_fundamentals)),
                )
        ),
    )
    db.add(db_run)
    db.flush()

    for cand in result.candidates:
        c = asdict(cand)
        fundamentals = {
            "revenue_growth_pct": _safe_float(c.get("revenue_growth_pct"), 0.0),
            "eps_growth_5y_pct": _safe_float(c.get("eps_growth_5y_pct"), 0.0),
            "eps_growth_fwd_pct": _safe_float(c.get("eps_growth_fwd_pct"), 0.0),
            "profit_margin_pct": _safe_float(c.get("profit_margin_pct"), 0.0),
            "assets_to_liabilities": _safe_float(c.get("assets_to_liabilities"), 0.0),
            "free_cash_flow": _safe_float(c.get("free_cash_flow"), 0.0),
        }
        db.add(
            CSPCandidateModel(
                screen_run_id=int(db_run.id),
                symbol=str(c.get("symbol") or ""),
                sector=str(c.get("sector") or "UNKNOWN"),
                industry=str(c.get("industry") or ""),
                fundamentals_json=_json_safe(fundamentals),
                iv_rank=_safe_optional_float(c.get("iv_rank")),
                option_volume=_safe_optional_float(c.get("option_volume_30d")),
                regime=str(c.get("regime") or "normal"),
                pe_current=_safe_optional_float(c.get("pe_current")),
                pe_5y_avg=_safe_optional_float(c.get("pe_5y_avg")),
                pe_10y_avg=_safe_optional_float(c.get("pe_10y_avg")),
                price_vs_sma200=_safe_optional_float(c.get("price_vs_sma200")),
                gate_reasons=[],
            )
        )
    db.commit()

    cand_rows = (
        db.query(CSPCandidateModel)
        .filter(CSPCandidateModel.screen_run_id == int(db_run.id))
        .order_by(CSPCandidateModel.iv_rank.desc())
        .all()
    )
    db.refresh(db_run)
    return _csp_screen_response(db_run, cand_rows)


@router.get("/options-edge/csp/screen/{screen_id}", response_model=CSPScreenRunResponse)
async def get_csp_screen(screen_id: int, db: Session = Depends(get_db)):
    row = db.query(CSPScreenRunModel).filter(CSPScreenRunModel.id == int(screen_id)).first()
    if not row:
        raise HTTPException(status_code=404, detail="CSP screen run not found")
    cands = (
        db.query(CSPCandidateModel)
        .filter(CSPCandidateModel.screen_run_id == int(screen_id))
        .order_by(CSPCandidateModel.iv_rank.desc())
        .all()
    )
    return _csp_screen_response(row, cands)


@router.get("/options-edge/csp/screens", response_model=List[CSPScreenRunResponse])
async def list_csp_screens(
    limit: int = Query(20, ge=1, le=200),
    db: Session = Depends(get_db),
):
    rows = (
        db.query(CSPScreenRunModel)
        .order_by(CSPScreenRunModel.run_date.desc())
        .limit(limit)
        .all()
    )
    return [_csp_screen_response(r, []) for r in rows]


@router.post("/options-edge/csp/backtest", response_model=CSPBacktestRunResponse)
async def run_csp_backtest(
    request: CSPBacktestRequest,
    db: Session = Depends(get_db),
):
    explicit_symbol = str(request.symbol or "").upper().strip()
    explicit_symbols = [str(s or "").upper().strip() for s in (request.symbols or [])]
    explicit_symbols = [s for s in explicit_symbols if s]

    target_symbols: List[str] = []
    symbol_meta: Dict[str, Dict[str, Any]] = {}
    if explicit_symbol:
        target_symbols = [explicit_symbol]
    elif explicit_symbols:
        target_symbols = sorted(list(dict.fromkeys(explicit_symbols)))
    else:
        cand_q = db.query(CSPCandidateModel)
        if request.screen_run_id is not None:
            cand_q = cand_q.filter(CSPCandidateModel.screen_run_id == int(request.screen_run_id))
        cands = cand_q.order_by(CSPCandidateModel.iv_rank.desc(), CSPCandidateModel.id.desc()).all()
        for c in cands:
            sym = str(c.symbol or "").upper().strip()
            if not sym:
                continue
            target_symbols.append(sym)
            symbol_meta[sym] = {
                "sector": str(c.sector or "UNKNOWN"),
                "iv_rank": _safe_float(c.iv_rank, 0.0),
                "regime": str(c.regime or "normal"),
            }
            if len(target_symbols) >= int(request.max_symbols):
                break
        if len(target_symbols) == 0:
            raise HTTPException(status_code=400, detail="No CSP candidate available. Run CSP screen first or pass symbol/symbols.")

    target_symbols = sorted(list(dict.fromkeys(target_symbols)))
    if len(target_symbols) > int(request.max_symbols):
        target_symbols = target_symbols[: int(request.max_symbols)]

    connector = PolygonOptionsConnector()
    st = connector.status()
    if not bool(st.get("configured", False)):
        raise HTTPException(status_code=400, detail="POLYGON_API_KEY missing or not configured")

    bars_by_symbol: Dict[str, pd.DataFrame] = {}
    for sym in target_symbols:
        bars = await run_in_threadpool(
            connector.get_daily_bars,
            sym,
            request.start_date.isoformat(),
            request.end_date.isoformat(),
        )
        if bars is not None and not bars.empty:
            bars_by_symbol[sym] = bars
    if len(bars_by_symbol) == 0:
        raise HTTPException(status_code=400, detail="No daily bars returned for requested symbols/date range")

    cfg = CSPBacktestConfig(
        initial_capital=float(request.initial_capital),
        max_concurrent_csps=int(request.max_concurrent_csps),
        max_portfolio_allocation_pct=float(request.max_portfolio_allocation_pct),
        max_sector_concentration=int(request.max_sector_concentration),
        max_single_stock_pct=float(request.max_single_stock_pct),
        target_dte_min=int(request.target_dte_min),
        target_dte_max=int(request.target_dte_max),
        normal_pop_min=float(request.normal_pop_min),
        normal_pop_max=float(request.normal_pop_max),
        normal_yield_min_pct=float(request.normal_yield_min_pct),
        normal_yield_max_pct=float(request.normal_yield_max_pct),
        hard_min_yield_pct=float(request.hard_min_yield_pct),
        aggressive_yield_min_pct=float(request.aggressive_yield_min_pct),
        aggressive_yield_max_pct=float(request.aggressive_yield_max_pct),
        vix_aggressive_threshold=float(request.vix_aggressive_threshold),
        sma200_touch_pct=float(request.sma200_touch_pct),
        iv_premium_factor=float(request.iv_premium_factor),
        iv_floor=float(request.iv_floor),
        risk_free_rate=float(request.risk_free_rate),
    )
    engine = CSPLifecycleEngine(cfg)
    use_portfolio_mode = bool(request.portfolio_mode) and len(bars_by_symbol) > 1
    if use_portfolio_mode:
        report = await run_in_threadpool(
            engine.run_portfolio_backtest,
            symbol_data=bars_by_symbol,
            symbol_meta=symbol_meta,
            start_date=request.start_date,
            end_date=request.end_date,
        )
    else:
        primary_symbol = sorted(list(bars_by_symbol.keys()))[0]
        report = await run_in_threadpool(
            engine.run_symbol_backtest,
            symbol=primary_symbol,
            market_df=bars_by_symbol[primary_symbol],
            start_date=request.start_date,
            end_date=request.end_date,
        )

    metrics = report.get("metrics") if isinstance(report.get("metrics"), dict) else {}
    trade_log = report.get("trade_log") if isinstance(report.get("trade_log"), list) else []
    symbol_reports = report.get("symbol_reports") if isinstance(report.get("symbol_reports"), dict) else {}
    symbol_metrics = {
        str(sym): (rep.get("metrics") if isinstance(rep, dict) and isinstance(rep.get("metrics"), dict) else {})
        for sym, rep in symbol_reports.items()
    }
    resolved_symbol = metrics.get("selected_symbols") if use_portfolio_mode else sorted(list(bars_by_symbol.keys()))[0]
    row = CSPBacktestRunModel(
        run_date=datetime.now(timezone.utc),
        start_date=request.start_date,
        end_date=request.end_date,
        initial_capital=float(request.initial_capital),
        final_capital=_safe_optional_float(metrics.get("final_capital")),
        status=str(report.get("status") or "COMPLETED"),
        error=report.get("error"),
        config_json=_json_safe(dict(request.model_dump(mode="json"), resolved_symbol=resolved_symbol)),
        results_json=_json_safe(dict(metrics, portfolio_mode=use_portfolio_mode, symbol_reports=symbol_metrics)),
        equity_curve_json=_json_safe(report.get("equity_curve") if isinstance(report.get("equity_curve"), list) else []),
        trades_json=_json_safe(trade_log),
    )
    db.add(row)
    db.flush()

    def _parse_iso_date(v):
        try:
            if v is None:
                return None
            return pd.to_datetime(str(v)).date()
        except Exception:
            return None

    state_map = {
        "open": "OPEN_CSP",
        "roll": "ROLLING",
        "expire_otm": "EXPIRED_OTM",
        "assigned": "ASSIGNED",
    }
    for ev in trade_log:
        if not isinstance(ev, dict):
            continue
        event = str(ev.get("event") or "").strip().lower()
        event_date = _parse_iso_date(ev.get("date"))
        strike_val = ev.get("new_strike") if event == "roll" else ev.get("strike")
        premium_total = ev.get("premium_total")
        if premium_total is None and ev.get("net_credit") is not None:
            premium_total = ev.get("net_credit")
        db.add(
            CSPTradeModel(
                backtest_run_id=int(row.id),
                symbol=str(ev.get("symbol") or (sorted(list(bars_by_symbol.keys()))[0] if len(bars_by_symbol) > 0 else "")),
                state=state_map.get(event, "CLOSED"),
                open_date=event_date if event in {"open", "roll"} else None,
                expiry_date=_parse_iso_date(ev.get("new_expiry") if event == "roll" else ev.get("expiry_date")),
                strike=_safe_optional_float(strike_val),
                premium_received=_safe_optional_float(_safe_float(premium_total, np.nan) / 100.0),
                cash_secured=_safe_optional_float(ev.get("cash_secured")),
                yield_pct=_safe_optional_float(ev.get("yield_pct")),
                delta_at_open=_safe_optional_float(ev.get("delta")),
                iv_at_open=_safe_optional_float(ev.get("iv")),
                regime=str(ev.get("regime")) if ev.get("regime") is not None else None,
                current_value=_safe_optional_float(ev.get("current_value")),
                close_date=event_date if event in {"expire_otm", "assigned"} else None,
                close_reason=event if event else None,
                total_premium_collected=_safe_optional_float(premium_total),
                rolls_json=_json_safe([ev]) if event == "roll" else None,
                assignment_cost=_safe_optional_float(ev.get("assignment_cost")),
                shares_assigned=100 if event == "assigned" else 0,
                realized_pnl=_safe_optional_float(ev.get("realized_pnl")),
                metadata_json=_json_safe(ev),
            )
        )

    db.commit()
    db.refresh(row)
    return _csp_backtest_response(row)


@router.get("/options-edge/csp/backtest/{run_id}", response_model=CSPBacktestRunResponse)
async def get_csp_backtest(run_id: int, db: Session = Depends(get_db)):
    row = db.query(CSPBacktestRunModel).filter(CSPBacktestRunModel.id == int(run_id)).first()
    if not row:
        raise HTTPException(status_code=404, detail="CSP backtest run not found")
    return _csp_backtest_response(row)


@router.get("/options-edge/csp/backtests", response_model=List[CSPBacktestRunResponse])
async def list_csp_backtests(
    limit: int = Query(20, ge=1, le=200),
    db: Session = Depends(get_db),
):
    rows = (
        db.query(CSPBacktestRunModel)
        .order_by(CSPBacktestRunModel.run_date.desc())
        .limit(limit)
        .all()
    )
    return [_csp_backtest_response(r) for r in rows]


@router.post("/options-edge/csp/execution/preview")
async def preview_csp_execution(
    request: Request,
    db: Session = Depends(get_db),
):
    body = await request.json()
    run_id = body.get("backtest_run_id")
    intents = body.get("intents")
    provider = str(body.get("provider") or "nautilus_ib").strip().lower()
    bridge = CSPExecutionBridge(provider=provider)

    if isinstance(intents, list) and len(intents) > 0:
        return {
            "ok": True,
            "provider": provider,
            "source": "provided_intents",
            "intents": intents,
        }

    if run_id is None:
        raise HTTPException(status_code=400, detail="Provide backtest_run_id or intents[]")

    row = db.query(CSPBacktestRunModel).filter(CSPBacktestRunModel.id == int(run_id)).first()
    if not row:
        raise HTTPException(status_code=404, detail="CSP backtest run not found")

    trade_log = row.trades_json if isinstance(row.trades_json, list) else []
    intents = bridge.preview_intents_from_trade_log(trade_log)
    return {
        "ok": True,
        "provider": provider,
        "source": f"csp_backtest_run:{run_id}",
        "intents": intents,
        "count": len(intents),
    }


@router.post("/options-edge/csp/execution/dispatch")
async def dispatch_csp_execution(
    request: Request,
):
    body = await request.json()
    provider = str(body.get("provider") or "nautilus_ib").strip().lower()
    dry_run = bool(body.get("dry_run", True))
    intents = body.get("intents")
    if not isinstance(intents, list) or len(intents) == 0:
        raise HTTPException(status_code=400, detail="intents[] is required")

    bridge = CSPExecutionBridge(provider=provider)
    result = bridge.dispatch(intents=intents, dry_run=dry_run)
    return result


# ========================== Dashboard Stats ==========================

@router.get("/dashboard/stats", response_model=DashboardStats)
async def get_dashboard_stats(db: Session = Depends(get_db)):
    """Get dashboard overview statistics"""
    # Count backtests
    total_backtests = db.query(BacktestResultModel).count()
    successful_backtests = db.query(BacktestResultModel).filter(
        BacktestResultModel.status == BacktestStatus.COMPLETED
    ).count()

    # Count live trades
    total_live_trades = db.query(LiveTradeModel).count()

    # Get best metrics from completed backtests
    best_win_rate = 0.0
    best_profit_factor = 0.0
    lowest_drawdown = 100.0

    completed_results = db.query(BacktestResultModel).filter(
        BacktestResultModel.status == BacktestStatus.COMPLETED
    ).all()

    for result in completed_results:
        if result.win_rate > best_win_rate:
            best_win_rate = result.win_rate
        if result.profit_factor > best_profit_factor:
            best_profit_factor = result.profit_factor
        if result.max_drawdown_percent < lowest_drawdown:
            lowest_drawdown = result.max_drawdown_percent

    return DashboardStats(
        total_backtests=total_backtests,
        successful_backtests=successful_backtests,
        total_live_trades=total_live_trades,
        best_win_rate=best_win_rate,
        best_profit_factor=best_profit_factor,
        lowest_drawdown=lowest_drawdown
    )


@router.get("/dashboard/live-status", response_model=LiveStatus)
async def get_live_status(symbol: str = Query("XAUUSD", description="Trading symbol")):
    """Get current live trading status"""
    service = LiveTradingService()
    return service.get_status(symbol=symbol)


# ========================== Backtest Configurations ==========================

@router.get("/configs", response_model=List[BacktestConfig])
async def list_configs(
    skip: int = 0,
    limit: int = 50,
    db: Session = Depends(get_db)
):
    """List all backtest configurations"""
    configs = db.query(BacktestConfigModel).offset(skip).limit(limit).all()
    return configs


@router.post("/configs", response_model=BacktestConfig)
async def create_config(
    config: BacktestConfigCreate,
    db: Session = Depends(get_db)
):
    """Create a new backtest configuration"""

    db_config = BacktestConfigModel(
        name=config.name,
        description=config.description,
        strategy_id=config.strategy_id,
        preset_name=config.preset_name,
        symbol=config.symbol,
        timeframe=config.timeframe.value,
        start_date=config.start_date,
        end_date=config.end_date,
        initial_balance=config.initial_balance,
        risk_percent=config.risk_percent,
        max_spread_usd=config.max_spread_usd,
        max_daily_loss_usd=config.max_daily_loss_usd,
        max_total_risk_usd=config.max_total_risk_usd,
        min_sl_usd=config.min_sl_usd,
        max_sl_usd=config.max_sl_usd,
        gold_rr_threshold=config.gold_rr_threshold,
        min_fvg_gap=config.min_fvg_gap,
        fvg_lookback=config.fvg_lookback,
        displacement_percentile=config.displacement_percentile,
        displacement_lookback=config.displacement_lookback,
        max_opposing_wick_ratio=config.max_opposing_wick_ratio,
        ob_lookback=config.ob_lookback,
        ob_min_body_percent=config.ob_min_body_percent,
        ob_validation_bars=config.ob_validation_bars,
        liquidity_wick_ratio=config.liquidity_wick_ratio,
        sweep_tolerance_usd=config.sweep_tolerance_usd,
        orb_start_time=config.orb_start_time,
        orb_end_time=config.orb_end_time,
        trade_start_time=config.trade_start_time,
        trade_end_time=config.trade_end_time,
        asian_start=config.asian_start,
        asian_end=config.asian_end,
        london_start=config.london_start,
        london_end=config.london_end,
        use_trailing=config.use_trailing,
        trailing_atr_period=config.trailing_atr_period,
        trailing_atr_multiplier=config.trailing_atr_multiplier,
        min_adr_for_trend=config.min_adr_for_trend,
        adr_period=config.adr_period,
        # Simulation settings
        contract_size=config.contract_size,
        simulate_spread=config.simulate_spread,
        use_variable_spread=config.use_variable_spread,
        simulate_slippage=config.simulate_slippage,
        slippage_atr_factor=config.slippage_atr_factor,
        commission_per_lot=config.commission_per_lot,
        simulate_swap=config.simulate_swap,
        swap_long_per_lot=config.swap_long_per_lot,
        swap_short_per_lot=config.swap_short_per_lot,
        # Bias & trade limits
        bias_min_strength=config.bias_min_strength,
        close_before_weekend=config.close_before_weekend,
        friday_close_hour=config.friday_close_hour,
        friday_close_minute=config.friday_close_minute,
        max_daily_trades=config.max_daily_trades,
        stop_after_first_win=config.stop_after_first_win,
        # Cross-asset regime filter
        enable_cross_asset_filter=config.enable_cross_asset_filter,
        regime_timeframe=config.regime_timeframe.value,
        regime_lookback_bars=config.regime_lookback_bars,
        regime_return_bars=config.regime_return_bars,
        regime_signal_threshold=config.regime_signal_threshold,
        regime_strong_threshold=config.regime_strong_threshold,
        regime_block_countertrend=config.regime_block_countertrend,
        regime_reduce_size_in_headwind=config.regime_reduce_size_in_headwind,
        regime_tailwind_risk_multiplier=config.regime_tailwind_risk_multiplier,
        regime_headwind_risk_multiplier=config.regime_headwind_risk_multiplier,
        regime_neutral_risk_multiplier=config.regime_neutral_risk_multiplier,
        regime_symbol_dxy=config.regime_symbol_dxy,
        regime_symbol_yield=config.regime_symbol_yield,
        regime_symbol_riskoff=config.regime_symbol_riskoff,
        regime_symbol_riskon=config.regime_symbol_riskon,
        regime_weight_dxy=config.regime_weight_dxy,
        regime_weight_yield=config.regime_weight_yield,
        regime_weight_riskoff=config.regime_weight_riskoff,
        regime_weight_riskon=config.regime_weight_riskon,
        # ML settings
        use_ml_filter=config.use_ml_filter,
        ml_min_win_probability=config.ml_min_win_probability,
        use_ml_dynamic_rr=config.use_ml_dynamic_rr,
        ml_base_strategy_id=config.ml_base_strategy_id,
        ml_model_id=config.ml_model_id,
        # Data source
        data_source=config.data_source,
        csv_files=config.csv_files,
    )

    db.add(db_config)
    db.commit()
    db.refresh(db_config)

    return db_config


@router.get("/configs/{config_id}", response_model=BacktestConfig)
async def get_config(config_id: int, db: Session = Depends(get_db)):
    """Get a specific backtest configuration"""
    config = db.query(BacktestConfigModel).filter(
        BacktestConfigModel.id == config_id
    ).first()

    if not config:
        raise HTTPException(status_code=404, detail="Configuration not found")

    return config


@router.put("/configs/{config_id}", response_model=BacktestConfig)
async def update_config(
    config_id: int,
    config_update: BacktestConfigUpdate,
    db: Session = Depends(get_db)
):
    """Update a backtest configuration"""
    db_config = db.query(BacktestConfigModel).filter(
        BacktestConfigModel.id == config_id
    ).first()

    if not db_config:
        raise HTTPException(status_code=404, detail="Configuration not found")

    update_data = config_update.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        if key in ("timeframe", "regime_timeframe") and value is not None and hasattr(value, "value"):
            value = value.value
        if hasattr(db_config, key):
            setattr(db_config, key, value)

    # If symbol changed, re-derive instrument-specific defaults
    if "symbol" in update_data:
        from ..core.instrument_specs import get_instrument
        inst = get_instrument(db_config.symbol)
        db_config.max_spread_usd = inst.max_spread
        db_config.min_sl_usd = inst.min_sl
        db_config.max_sl_usd = inst.max_sl
        db_config.contract_size = inst.contract_size
        db_config.gold_rr_threshold = inst.rr_threshold
        db_config.min_fvg_gap = inst.min_fvg_gap

    db.commit()
    db.refresh(db_config)

    return db_config


@router.delete("/configs/{config_id}")
async def delete_config(config_id: int, db: Session = Depends(get_db)):
    """Delete a backtest configuration"""
    db_config = db.query(BacktestConfigModel).filter(
        BacktestConfigModel.id == config_id
    ).first()

    if not db_config:
        raise HTTPException(status_code=404, detail="Configuration not found")

    # Also delete associated results
    db.query(BacktestResultModel).filter(
        BacktestResultModel.config_id == config_id
    ).delete()

    db.delete(db_config)
    db.commit()

    return {"status": "deleted", "config_id": config_id}


@router.post("/configs/{config_id}/duplicate", response_model=BacktestConfig)
async def duplicate_config(
    config_id: int,
    new_name: str = Query(..., description="Name for the duplicated config"),
    db: Session = Depends(get_db)
):
    """Duplicate a backtest configuration"""
    original = db.query(BacktestConfigModel).filter(
        BacktestConfigModel.id == config_id
    ).first()

    if not original:
        raise HTTPException(status_code=404, detail="Configuration not found")

    # Create new config with copied values
    new_config = BacktestConfigModel(
        name=new_name,
        description=f"Copy of {original.name}",
        strategy_id=original.strategy_id,
        preset_name=getattr(original, 'preset_name', None),
        symbol=original.symbol,
        timeframe=original.timeframe,
        start_date=original.start_date,
        end_date=original.end_date,
        initial_balance=original.initial_balance,
        risk_percent=original.risk_percent,
        max_spread_usd=original.max_spread_usd,
        max_daily_loss_usd=original.max_daily_loss_usd,
        max_total_risk_usd=original.max_total_risk_usd,
        min_sl_usd=original.min_sl_usd,
        max_sl_usd=original.max_sl_usd,
        gold_rr_threshold=original.gold_rr_threshold,
        min_fvg_gap=original.min_fvg_gap,
        fvg_lookback=original.fvg_lookback,
        displacement_percentile=original.displacement_percentile,
        displacement_lookback=original.displacement_lookback,
        max_opposing_wick_ratio=original.max_opposing_wick_ratio,
        ob_lookback=original.ob_lookback,
        ob_min_body_percent=original.ob_min_body_percent,
        ob_validation_bars=original.ob_validation_bars,
        liquidity_wick_ratio=original.liquidity_wick_ratio,
        sweep_tolerance_usd=original.sweep_tolerance_usd,
        orb_start_time=original.orb_start_time,
        orb_end_time=original.orb_end_time,
        trade_start_time=original.trade_start_time,
        trade_end_time=original.trade_end_time,
        asian_start=original.asian_start,
        asian_end=original.asian_end,
        london_start=original.london_start,
        london_end=original.london_end,
        use_trailing=original.use_trailing,
        trailing_atr_period=original.trailing_atr_period,
        trailing_atr_multiplier=original.trailing_atr_multiplier,
        min_adr_for_trend=original.min_adr_for_trend,
        adr_period=original.adr_period,
        # Simulation settings
        contract_size=original.contract_size,
        simulate_spread=original.simulate_spread,
        use_variable_spread=original.use_variable_spread,
        simulate_slippage=original.simulate_slippage,
        slippage_atr_factor=original.slippage_atr_factor,
        commission_per_lot=original.commission_per_lot,
        simulate_swap=original.simulate_swap,
        swap_long_per_lot=original.swap_long_per_lot,
        swap_short_per_lot=original.swap_short_per_lot,
        # Bias & trade limits
        bias_min_strength=original.bias_min_strength,
        close_before_weekend=original.close_before_weekend,
        friday_close_hour=original.friday_close_hour,
        friday_close_minute=original.friday_close_minute,
        max_daily_trades=getattr(original, 'max_daily_trades', 2),
        stop_after_first_win=getattr(original, 'stop_after_first_win', True),
        # Cross-asset regime filter
        enable_cross_asset_filter=getattr(original, 'enable_cross_asset_filter', False),
        regime_timeframe=getattr(original, 'regime_timeframe', 'M15'),
        regime_lookback_bars=getattr(original, 'regime_lookback_bars', 96),
        regime_return_bars=getattr(original, 'regime_return_bars', 8),
        regime_signal_threshold=getattr(original, 'regime_signal_threshold', 0.18),
        regime_strong_threshold=getattr(original, 'regime_strong_threshold', 0.40),
        regime_block_countertrend=getattr(original, 'regime_block_countertrend', True),
        regime_reduce_size_in_headwind=getattr(original, 'regime_reduce_size_in_headwind', True),
        regime_tailwind_risk_multiplier=getattr(original, 'regime_tailwind_risk_multiplier', 1.15),
        regime_headwind_risk_multiplier=getattr(original, 'regime_headwind_risk_multiplier', 0.50),
        regime_neutral_risk_multiplier=getattr(original, 'regime_neutral_risk_multiplier', 1.00),
        regime_symbol_dxy=getattr(original, 'regime_symbol_dxy', 'DXY,USDX,USDX.i'),
        regime_symbol_yield=getattr(original, 'regime_symbol_yield', 'US10Y,TNX,US10Y.cash'),
        regime_symbol_riskoff=getattr(original, 'regime_symbol_riskoff', 'VIX,VIX.cash,VOLX'),
        regime_symbol_riskon=getattr(original, 'regime_symbol_riskon', 'SPX500,US500,US30'),
        regime_weight_dxy=getattr(original, 'regime_weight_dxy', 0.40),
        regime_weight_yield=getattr(original, 'regime_weight_yield', 0.35),
        regime_weight_riskoff=getattr(original, 'regime_weight_riskoff', 0.15),
        regime_weight_riskon=getattr(original, 'regime_weight_riskon', 0.10),
        # ML settings
        use_ml_filter=getattr(original, 'use_ml_filter', False),
        ml_min_win_probability=getattr(original, 'ml_min_win_probability', 0.55),
        use_ml_dynamic_rr=getattr(original, 'use_ml_dynamic_rr', False),
        ml_base_strategy_id=getattr(original, 'ml_base_strategy_id', None),
        ml_model_id=getattr(original, 'ml_model_id', None),
        # Data source
        data_source=getattr(original, 'data_source', 'auto'),
        csv_files=getattr(original, 'csv_files', None),
    )

    db.add(new_config)
    db.commit()
    db.refresh(new_config)

    return new_config


# ========================== Backtest Execution ==========================

@router.post("/backtests/run/{config_id}")
async def run_backtest(
    config_id: int,
    background_tasks: BackgroundTasks,
    db: Session = Depends(get_db)
):
    """Start a backtest with the specified configuration"""
    config = db.query(BacktestConfigModel).filter(
        BacktestConfigModel.id == config_id
    ).first()

    if not config:
        raise HTTPException(status_code=404, detail="Configuration not found")

    # Create result record
    result = BacktestResultModel(
        config_id=config_id,
        status=BacktestStatus.PENDING,
        initial_balance=config.initial_balance
    )

    db.add(result)
    db.commit()
    db.refresh(result)

    result_id = result.id

    # Run backtest in background - pass IDs only, not ORM objects
    background_tasks.add_task(BacktestService.run_backtest_task, result_id, config_id)

    return {
        "status": "started",
        "result_id": result_id,
        "config_id": config_id,
        "message": "Backtest started in background"
    }


@router.post("/backtests/run-advanced/{config_id}")
async def run_advanced_backtest(
    config_id: int,
    background_tasks: BackgroundTasks,
    enable_event_trace: bool = Query(default=False),
    engine_mode: str = Query(default="advanced"),
    fallback_to_legacy_on_error: bool = Query(default=True),
    parity_check: bool = Query(default=False),
    require_parity_pass: bool = Query(default=False),
    max_trade_count_delta: float = Query(default=0.0, ge=0.0),
    max_net_profit_delta_pct: float = Query(default=0.5, ge=0.0),
    max_win_rate_delta: float = Query(default=0.25, ge=0.0),
    max_drawdown_delta: float = Query(default=0.5, ge=0.0),
    max_sharpe_delta: float = Query(default=0.10, ge=0.0),
    db: Session = Depends(get_db),
):
    """
    Start the advanced event-driven backtest module.

    This does not modify or replace the legacy backtest engine.
    """
    config = db.query(BacktestConfigModel).filter(
        BacktestConfigModel.id == config_id
    ).first()
    if not config:
        raise HTTPException(status_code=404, detail="Configuration not found")

    result = BacktestResultModel(
        config_id=config_id,
        status=BacktestStatus.PENDING,
        initial_balance=config.initial_balance,
    )
    db.add(result)
    db.commit()
    db.refresh(result)

    background_tasks.add_task(
        BacktestService.run_advanced_backtest_task,
        result.id,
        config_id,
        {
            "enable_event_trace": enable_event_trace,
            "engine_mode": engine_mode,
            "fallback_to_legacy_on_error": fallback_to_legacy_on_error,
            "parity_check": parity_check,
            "require_parity_pass": require_parity_pass,
            "parity_tolerances": {
                "max_trade_count_delta": max_trade_count_delta,
                "max_net_profit_delta_pct": max_net_profit_delta_pct,
                "max_win_rate_delta": max_win_rate_delta,
                "max_drawdown_delta": max_drawdown_delta,
                "max_sharpe_delta": max_sharpe_delta,
            },
        },
    )

    return {
        "status": "started",
        "mode": "advanced_event_driven",
        "result_id": result.id,
        "config_id": config_id,
        "message": "Advanced event-driven backtest started in background",
    }


@router.post("/backtests/walk-forward/{config_id}")
async def run_walk_forward(
    config_id: int,
    background_tasks: BackgroundTasks,
    in_sample_days: int = Query(default=180, ge=30, le=730),
    out_of_sample_days: int = Query(default=60, ge=7, le=365),
    step_days: int = Query(default=60, ge=1, le=365),
    optimization_metric: str = Query(default="sharpe_ratio"),
    min_trades_per_window: int = Query(default=15, ge=1, le=1000),
    max_workers: int = Query(default=4, ge=1, le=32),
    search_mode: str = Query(default="random"),
    random_samples: int = Query(default=200, ge=1, le=20000),
    random_seed: int = Query(default=42, ge=0, le=2_147_483_647),
    max_exhaustive_grid_size: int = Query(default=5000, ge=1, le=1000000),
    engine_mode: str = Query(default="legacy"),
    fallback_to_legacy_on_error: bool = Query(default=True),
    parity_check: bool = Query(default=False),
    require_parity_pass: bool = Query(default=False),
    max_trade_count_delta: float = Query(default=0.0, ge=0.0),
    max_net_profit_delta_pct: float = Query(default=0.5, ge=0.0),
    max_win_rate_delta: float = Query(default=0.25, ge=0.0),
    max_drawdown_delta: float = Query(default=0.5, ge=0.0),
    max_sharpe_delta: float = Query(default=0.10, ge=0.0),
    param_ranges_json: Optional[str] = Query(
        default=None,
        description="Optional JSON array: [{\"name\": \"param\", \"values\": [..]}, ...]",
    ),
    db: Session = Depends(get_db),
):
    """Start a walk-forward optimization run for a saved backtest config."""
    config = db.query(BacktestConfigModel).filter(
        BacktestConfigModel.id == config_id
    ).first()
    if not config:
        raise HTTPException(status_code=404, detail="Configuration not found")

    mode = (search_mode or "random").strip().lower()
    if mode not in {"random", "exhaustive"}:
        raise HTTPException(status_code=400, detail="search_mode must be 'random' or 'exhaustive'")
    eng_mode = (engine_mode or "legacy").strip().lower()
    if eng_mode not in {"legacy", "advanced"}:
        raise HTTPException(status_code=400, detail="engine_mode must be 'legacy' or 'advanced'")

    param_ranges = []
    if param_ranges_json:
        try:
            parsed = json.loads(param_ranges_json)
            if not isinstance(parsed, list):
                raise ValueError("param_ranges_json must be a JSON array")
            param_ranges = parsed
        except Exception as exc:
            raise HTTPException(status_code=400, detail=f"Invalid param_ranges_json: {exc}")

    result = BacktestResultModel(
        config_id=config_id,
        status=BacktestStatus.PENDING,
        initial_balance=config.initial_balance,
    )
    db.add(result)
    db.commit()
    db.refresh(result)

    wf_params = {
        "in_sample_days": in_sample_days,
        "out_of_sample_days": out_of_sample_days,
        "step_days": step_days,
        "optimization_metric": optimization_metric,
        "min_trades_per_window": min_trades_per_window,
        "max_workers": max_workers,
        "search_mode": mode,
        "random_samples": random_samples,
        "random_seed": random_seed,
        "max_exhaustive_grid_size": max_exhaustive_grid_size,
        "engine_mode": eng_mode,
        "fallback_to_legacy_on_error": fallback_to_legacy_on_error,
        "parity_check": parity_check,
        "require_parity_pass": require_parity_pass,
        "parity_tolerances": {
            "max_trade_count_delta": max_trade_count_delta,
            "max_net_profit_delta_pct": max_net_profit_delta_pct,
            "max_win_rate_delta": max_win_rate_delta,
            "max_drawdown_delta": max_drawdown_delta,
            "max_sharpe_delta": max_sharpe_delta,
        },
        "param_ranges": param_ranges,
    }
    background_tasks.add_task(
        BacktestService.run_walk_forward_task,
        result.id,
        config_id,
        wf_params,
    )

    return {
        "status": "started",
        "mode": "walk_forward",
        "result_id": result.id,
        "config_id": config_id,
        "message": "Walk-forward started in background",
    }


@router.post("/backtests/phase01/{config_id}")
async def run_phase01_validation(
    config_id: int,
    wf_folds: int = Query(default=6, ge=1, le=24),
    wf_test_days: int = Query(default=30, ge=7, le=365),
    wf_purge_days: int = Query(default=2, ge=0, le=30),
    mc_iterations: int = Query(default=500, ge=100, le=5000),
    mc_block_size: int = Query(default=5, ge=1, le=100),
    engine_mode: str = Query(default="legacy"),
    fallback_to_legacy_on_error: bool = Query(default=True),
    parity_check: bool = Query(default=False),
    require_parity_pass: bool = Query(default=False),
    max_trade_count_delta: float = Query(default=0.0, ge=0.0),
    max_net_profit_delta_pct: float = Query(default=0.5, ge=0.0),
    max_win_rate_delta: float = Query(default=0.25, ge=0.0),
    max_drawdown_delta: float = Query(default=0.5, ge=0.0),
    max_sharpe_delta: float = Query(default=0.10, ge=0.0),
    db: Session = Depends(get_db)
):
    """
    Execute Phase 0/1 gate validation for a saved config:
    - Freeze baseline (filter OFF)
    - Purged walk-forward ON/OFF comparison
    - Block-bootstrap Monte Carlo
    - Hard-gate decision
    """
    config = db.query(BacktestConfigModel).filter(
        BacktestConfigModel.id == config_id
    ).first()

    if not config:
        raise HTTPException(status_code=404, detail="Configuration not found")
    eng_mode = (engine_mode or "legacy").strip().lower()
    if eng_mode not in {"legacy", "advanced"}:
        raise HTTPException(status_code=400, detail="engine_mode must be 'legacy' or 'advanced'")

    # Build config exactly as backtest engine sees it
    strategy_id = getattr(config, "strategy_id", "orb_strategy")
    is_ml_strategy = str(strategy_id).endswith("_ml_strategy")
    if is_ml_strategy:
        base_cfg = asdict(BacktestService._model_to_ml_config(config))
    else:
        base_cfg = asdict(BacktestService._model_to_config(config))
    strategy_cfg = BacktestService._build_strategy_config(config)
    full_cfg = dict(base_cfg)
    full_cfg.update(strategy_cfg)

    gate = Phase01GateConfig(
        wf_folds=wf_folds,
        wf_test_days=wf_test_days,
        wf_purge_days=wf_purge_days,
        mc_iterations=mc_iterations,
        mc_block_size=mc_block_size,
        engine_mode=eng_mode,
        fallback_to_legacy_on_error=fallback_to_legacy_on_error,
        parity_check=parity_check,
        require_parity_pass=require_parity_pass,
        parity_tolerances={
            "max_trade_count_delta": max_trade_count_delta,
            "max_net_profit_delta_pct": max_net_profit_delta_pct,
            "max_win_rate_delta": max_win_rate_delta,
            "max_drawdown_delta": max_drawdown_delta,
            "max_sharpe_delta": max_sharpe_delta,
        },
    )

    validator = Phase01Validator()
    report = await run_in_threadpool(
        validator.run_phase01,
        strategy_id,
        (getattr(config, "preset_name", "default") or "default"),
        full_cfg,
        gate,
    )
    report["config_id"] = config_id
    report["config_name"] = config.name
    return report


@router.get("/backtests/status/{result_id}")
async def get_backtest_status(
    result_id: int,
    db: Session = Depends(get_db)
):
    """Get the status of a running backtest"""
    result = db.query(BacktestResultModel).filter(
        BacktestResultModel.id == result_id
    ).first()

    if not result:
        raise HTTPException(status_code=404, detail="Backtest result not found")

    return {
        "result_id": result.id,
        "status": result.status.value,
        "started_at": result.started_at,
        "completed_at": result.completed_at,
        "error_message": result.error_message
    }


# ========================== Backtest Results ==========================

@router.get("/backtests/results", response_model=List[BacktestResultSummary])
async def list_backtest_results(
    skip: int = 0,
    limit: int = 50,
    status: Optional[str] = None,
    db: Session = Depends(get_db)
):
    """List all backtest results"""
    query = db.query(BacktestResultModel)

    if status:
        query = query.filter(BacktestResultModel.status == BacktestStatus(status))

    results = query.order_by(BacktestResultModel.id.desc()).offset(skip).limit(limit).all()

    summaries = []
    for result in results:
        config = db.query(BacktestConfigModel).filter(
            BacktestConfigModel.id == result.config_id
        ).first()

        summaries.append(BacktestResultSummary(
            id=result.id,
            config_id=result.config_id,
            config_name=config.name if config else "Unknown",
            strategy_id=config.strategy_id if config else "orb_strategy",
            symbol=config.symbol if config else "XAUUSD",
            timeframe=config.timeframe if config else "M1",
            status=result.status.value,
            started_at=result.started_at,
            completed_at=result.completed_at,
            total_trades=result.total_trades,
            win_rate=result.win_rate,
            net_profit=result.net_profit,
            max_drawdown_percent=result.max_drawdown_percent
        ))

    return summaries


@router.get("/backtests/results/{result_id}")
async def get_backtest_result(
    result_id: int,
    db: Session = Depends(get_db)
):
    """Get detailed backtest result"""
    result = db.query(BacktestResultModel).filter(
        BacktestResultModel.id == result_id
    ).first()

    if not result:
        raise HTTPException(status_code=404, detail="Backtest result not found")

    config = db.query(BacktestConfigModel).filter(
        BacktestConfigModel.id == result.config_id
    ).first()

    metrics = PerformanceMetrics(
        total_trades=int(result.total_trades or 0),
        winning_trades=int(result.winning_trades or 0),
        losing_trades=int(result.losing_trades or 0),
        win_rate=_safe_float(result.win_rate),
        initial_balance=_safe_float(result.initial_balance),
        final_balance=_safe_float(result.final_balance),
        total_profit=_safe_float(result.total_profit),
        total_loss=_safe_float(result.total_loss),
        net_profit=_safe_float(result.net_profit),
        profit_factor=_safe_float(result.profit_factor),
        max_drawdown=_safe_float(result.max_drawdown),
        max_drawdown_percent=_safe_float(result.max_drawdown_percent),
        sharpe_ratio=_safe_float(result.sharpe_ratio),
        sortino_ratio=_safe_float(result.sortino_ratio),
        calmar_ratio=_safe_float(result.calmar_ratio),
        avg_win=_safe_float(result.avg_win),
        avg_loss=_safe_float(result.avg_loss),
        largest_win=_safe_float(result.largest_win),
        largest_loss=_safe_float(result.largest_loss),
        avg_trade_duration=_safe_float(result.avg_trade_duration),
        avg_rr_ratio=_safe_float(result.avg_rr_ratio),
        expectancy=_safe_float(result.expectancy)
    )

    return {
        "id": result.id,
        "config_id": result.config_id,
        "status": result.status.value,
        "started_at": result.started_at,
        "completed_at": result.completed_at,
        "error_message": result.error_message,
        "metrics": metrics,
        "equity_curve": _json_safe(result.equity_curve),
        "drawdown_curve": _json_safe(result.drawdown_curve),
        "daily_pnl": _json_safe(result.daily_pnl),
        "monthly_returns": _json_safe(result.monthly_returns),
        "regime_analysis": _json_safe(getattr(result, "regime_analysis", None)),
        "microstructure_analysis": _json_safe(getattr(result, "microstructure_analysis", None)),
        "walk_forward_report": _json_safe(getattr(result, "walk_forward_report", None)),
        "run_manifest": _json_safe(getattr(result, "run_manifest", None)),
        "data_hash": getattr(result, "data_hash", None),
        "config": config
    }


@router.get("/backtests/results/{result_id}/trades", response_model=List[TradeResponse])
async def get_backtest_trades(
    result_id: int,
    skip: int = 0,
    limit: int = 100,
    db: Session = Depends(get_db)
):
    """Get trades from a backtest result"""
    trades = db.query(BacktestTradeModel).filter(
        BacktestTradeModel.result_id == result_id
    ).offset(skip).limit(limit).all()

    return trades


@router.delete("/backtests/results/{result_id}")
async def delete_backtest_result(
    result_id: int,
    db: Session = Depends(get_db)
):
    """Delete a backtest result and its trades"""
    result = db.query(BacktestResultModel).filter(
        BacktestResultModel.id == result_id
    ).first()

    if not result:
        raise HTTPException(status_code=404, detail="Backtest result not found")

    # Delete trades
    db.query(BacktestTradeModel).filter(
        BacktestTradeModel.result_id == result_id
    ).delete()

    # Delete result
    db.delete(result)
    db.commit()

    return {"status": "deleted", "result_id": result_id}


# ========================== Comparison ==========================

@router.post("/backtests/compare")
async def compare_backtests(
    result_ids: List[int],
    db: Session = Depends(get_db)
):
    """Compare multiple backtest results"""
    if len(result_ids) < 2:
        raise HTTPException(
            status_code=400,
            detail="At least 2 backtest results required for comparison"
        )

    results = []
    configs = []
    equity_curves = {}

    for result_id in result_ids:
        result = db.query(BacktestResultModel).filter(
            BacktestResultModel.id == result_id
        ).first()

        if not result:
            raise HTTPException(
                status_code=404,
                detail=f"Backtest result {result_id} not found"
            )

        config = db.query(BacktestConfigModel).filter(
            BacktestConfigModel.id == result.config_id
        ).first()

        metrics = PerformanceMetrics(
            total_trades=result.total_trades,
            winning_trades=result.winning_trades,
            losing_trades=result.losing_trades,
            win_rate=result.win_rate,
            initial_balance=result.initial_balance,
            final_balance=result.final_balance,
            total_profit=result.total_profit,
            total_loss=result.total_loss,
            net_profit=result.net_profit,
            profit_factor=result.profit_factor,
            max_drawdown=result.max_drawdown,
            max_drawdown_percent=result.max_drawdown_percent,
            sharpe_ratio=result.sharpe_ratio,
            sortino_ratio=result.sortino_ratio,
            calmar_ratio=result.calmar_ratio,
            avg_win=result.avg_win,
            avg_loss=result.avg_loss,
            largest_win=result.largest_win,
            largest_loss=result.largest_loss,
            avg_trade_duration=result.avg_trade_duration,
            avg_rr_ratio=result.avg_rr_ratio,
            expectancy=result.expectancy
        )

        results.append({
            "result_id": result_id,
            "config_name": config.name if config else "Unknown",
            "metrics": metrics
        })

        configs.append(config)
        equity_curves[result_id] = result.equity_curve

    return {
        "comparison": results,
        "equity_curves": equity_curves
    }


# ========================== Export ==========================

@router.post("/backtests/export/{result_id}")
async def export_backtest(
    result_id: int,
    format: str = Query("csv", enum=["csv", "json"]),
    db: Session = Depends(get_db)
):
    """Export backtest results to file"""
    result = db.query(BacktestResultModel).filter(
        BacktestResultModel.id == result_id
    ).first()

    if not result:
        raise HTTPException(status_code=404, detail="Backtest result not found")

    trades = db.query(BacktestTradeModel).filter(
        BacktestTradeModel.result_id == result_id
    ).all()

    config = db.query(BacktestConfigModel).filter(
        BacktestConfigModel.id == result.config_id
    ).first()

    if format == "json":
        export_data = {
            "config": {
                "name": config.name if config else "Unknown",
                "symbol": config.symbol if config else "",
                "timeframe": config.timeframe if config else "",
                "start_date": config.start_date.isoformat() if config else None,
                "end_date": config.end_date.isoformat() if config else None,
            },
            "metrics": {
                "total_trades": result.total_trades,
                "win_rate": result.win_rate,
                "net_profit": result.net_profit,
                "profit_factor": result.profit_factor,
                "max_drawdown_percent": result.max_drawdown_percent,
                "sharpe_ratio": result.sharpe_ratio,
            },
            "trades": [
                {
                    "trade_number": t.trade_number,
                    "direction": t.direction.value,
                    "entry_time": t.entry_time.isoformat() if t.entry_time else None,
                    "exit_time": t.exit_time.isoformat() if t.exit_time else None,
                    "entry_price": t.entry_price,
                    "exit_price": t.exit_price,
                    "stop_loss": t.stop_loss,
                    "profit_loss": t.profit_loss,
                    "setup_type": t.setup_type,
                }
                for t in trades
            ],
            "equity_curve": result.equity_curve,
            "daily_pnl": result.daily_pnl,
            "microstructure_analysis": result.microstructure_analysis,
        }

        return StreamingResponse(
            io.BytesIO(json.dumps(export_data, indent=2).encode()),
            media_type="application/json",
            headers={
                "Content-Disposition": f"attachment; filename=backtest_{result_id}.json"
            }
        )

    else:  # CSV
        output = io.StringIO()
        writer = csv.writer(output)

        # Header
        writer.writerow([
            "Trade #", "Direction", "Entry Time", "Exit Time",
            "Entry Price", "Exit Price", "Stop Loss", "Take Profit",
            "Lot Size", "P&L", "R-Multiple", "Setup Type", "Exit Reason"
        ])

        # Data
        for t in trades:
            writer.writerow([
                t.trade_number,
                t.direction.value,
                t.entry_time.isoformat() if t.entry_time else "",
                t.exit_time.isoformat() if t.exit_time else "",
                t.entry_price,
                t.exit_price,
                t.stop_loss,
                t.take_profit,
                t.lot_size,
                t.profit_loss,
                t.r_multiple,
                t.setup_type,
                t.exit_reason
            ])

        return StreamingResponse(
            io.BytesIO(output.getvalue().encode()),
            media_type="text/csv",
            headers={
                "Content-Disposition": f"attachment; filename=backtest_{result_id}_trades.csv"
            }
        )


# ========================== Strategy Definitions (for Backtest Config) ==========================

@router.get("/preset-matrix")
async def get_preset_matrix():
    """Get the full preset matrix: all strategies x presets x instruments."""
    from ..core.strategy_registry import StrategyRegistry
    preset_order = {"conservative": 0, "default": 1, "aggressive": 2}
    matrix = []
    for strategy in StrategyRegistry.get_all_strategies():
        symbols = strategy.optimal_parameters.get("symbols", ["XAUUSD"])
        for symbol in symbols:
            for preset in sorted(strategy.presets, key=lambda p: preset_order.get(p.id, 99)):
                config = strategy.get_preset_config(preset.id, symbol)
                matrix.append({
                    "strategy_id": strategy.id,
                    "strategy_name": strategy.name,
                    "symbol": symbol,
                    "preset_id": preset.id,
                    "preset_name": preset.name,
                    "preset_description": preset.description,
                    "timeframe": config.get("timeframe", "M5"),
                    "risk_percent": config.get("risk_percent", 1.0),
                    "rr_ratio": config.get("rr_ratio") or config.get("min_rr_ratio") or config.get("gold_rr_threshold") or config.get("min_rr", 2.0),
                    "min_sl": config.get("min_sl_usd", 0),
                    "max_sl": config.get("max_sl_usd", 0),
                    "max_spread": config.get("max_spread_usd", 0),
                    "trade_start": config.get("trade_start_time", ""),
                    "trade_end": config.get("trade_end_time", ""),
                    "max_daily_trades": config.get("max_daily_trades", 0),
                    "commission": config.get("commission_per_lot", 0),
                })
    return matrix


@router.get("/strategy-definitions")
async def list_strategy_definitions():
    """List all available strategy definitions with their parameters"""
    from ..core.strategy_registry import StrategyRegistry
    strategies = StrategyRegistry.get_all_strategies()
    return [s.to_dict() for s in strategies]


@router.get("/strategy-definitions/list")
async def get_strategy_dropdown_list():
    """Get simplified list of strategies for dropdown selection"""
    from ..core.strategy_registry import StrategyRegistry
    return StrategyRegistry.get_strategy_list()


@router.get("/strategy-definitions/{strategy_id}")
async def get_strategy_definition(strategy_id: str):
    """Get full definition for a specific strategy"""
    from ..core.strategy_registry import StrategyRegistry
    strategy = StrategyRegistry.get_strategy(strategy_id)
    if not strategy:
        raise HTTPException(status_code=404, detail=f"Strategy '{strategy_id}' not found")
    return strategy.to_dict()


@router.get("/strategy-definitions/{strategy_id}/defaults")
async def get_strategy_defaults(strategy_id: str):
    """Get default parameter values for a strategy"""
    from ..core.strategy_registry import StrategyRegistry
    strategy = StrategyRegistry.get_strategy(strategy_id)
    if not strategy:
        raise HTTPException(status_code=404, detail=f"Strategy '{strategy_id}' not found")
    return strategy.get_defaults()


@router.get("/strategy-definitions/{strategy_id}/preset/{preset_id}")
async def get_strategy_preset(strategy_id: str, preset_id: str, symbol: str = None):
    """Get full configuration for a strategy preset, optionally instrument-adjusted."""
    from ..core.strategy_registry import StrategyRegistry
    strategy = StrategyRegistry.get_strategy(strategy_id)
    if not strategy:
        raise HTTPException(status_code=404, detail=f"Strategy '{strategy_id}' not found")
    return strategy.get_preset_config(preset_id, symbol)


@router.get("/strategy-definitions/{strategy_id}/ml-base")
async def get_strategy_ml_base(strategy_id: str):
    """Get the base strategy ID for ML strategies (returns null for non-ML)"""
    from ..core.strategy_registry import StrategyRegistry
    strategy = StrategyRegistry.get_strategy(strategy_id)
    if not strategy:
        raise HTTPException(status_code=404, detail=f"Strategy '{strategy_id}' not found")
    ml_base = strategy.optimal_parameters.get('ml_base_strategy_id')
    return {"ml_base_strategy_id": ml_base}


# ========================== Monitoring ==========================

@router.get("/monitoring/snapshot")
async def get_monitoring_snapshot(db: Session = Depends(get_db)):
    """Aggregated monitoring snapshot for the enterprise dashboard."""
    from ..services.monitoring_service import MonitoringService
    service = MonitoringService()
    return service.get_snapshot(db)


# ========================== Presets ==========================

@router.get("/presets/default-config")
async def get_default_config(symbol: str = Query("XAUUSD")):
    """Get default configuration values, derived from instrument specs"""
    from ..core.instrument_specs import get_instrument
    inst = get_instrument(symbol)
    return {
        "symbol": symbol,
        "timeframe": "M1",
        "initial_balance": 10000.0,
        "risk_percent": 1.0,
        "max_spread_usd": inst.max_spread,
        "max_daily_loss_usd": -150.0,
        "max_total_risk_usd": 200.0,
        "min_sl_usd": inst.min_sl,
        "max_sl_usd": inst.max_sl,
        "gold_rr_threshold": inst.rr_threshold,
        "min_fvg_gap": inst.min_fvg_gap,
        "fvg_lookback": 50,
        "displacement_percentile": 75,
        "displacement_lookback": 20,
        "max_opposing_wick_ratio": 0.4,
        "ob_lookback": 100,
        "ob_min_body_percent": 60,
        "ob_validation_bars": 3,
        "liquidity_wick_ratio": 0.6,
        "sweep_tolerance_usd": 0.20,
        "orb_start_time": "09:30",
        "orb_end_time": "09:45",
        "trade_start_time": "09:45",
        "trade_end_time": "16:00",
        "asian_start": "20:00",
        "asian_end": "02:00",
        "london_start": "03:00",
        "london_end": "12:00",
        "use_trailing": True,
        "trailing_atr_period": 14,
        "trailing_atr_multiplier": 1.5,
        "min_adr_for_trend": 20.0,
        "adr_period": 5
    }


@router.get("/presets/aggressive")
async def get_aggressive_preset(symbol: str = Query("XAUUSD")):
    """Get aggressive trading configuration"""
    default = await get_default_config(symbol=symbol)
    default.update({
        "risk_percent": 2.0,
        "max_daily_loss_usd": -300.0,
        "max_total_risk_usd": 400.0,
    })
    return default


@router.get("/presets/conservative")
async def get_conservative_preset(symbol: str = Query("XAUUSD")):
    """Get conservative trading configuration"""
    default = await get_default_config(symbol=symbol)
    default.update({
        "risk_percent": 0.5,
        "max_daily_loss_usd": -75.0,
        "max_total_risk_usd": 100.0,
        "ob_min_body_percent": 70,
    })
    return default


# ========================== Strategy Management ==========================

# Capital allocation endpoints - MUST come before parameterized routes
@router.get("/strategies/capital/allocation")
async def get_capital_allocation():
    """
    Get capital allocation status across all strategies.
    Shows account balance, allocated capital per strategy, and available capital.
    """
    try:
        import sys
        import os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.strategy_manager import StrategyManager

        manager = StrategyManager()

        account_balance = manager.get_account_balance()
        allocations = manager.get_allocated_capital()
        total_allocated = sum(allocations.values())
        options_open_risk = float(allocations.get("options_edge_manual", 0.0))

        return {
            "account_balance": account_balance,
            "allocations": allocations,
            "total_allocated": total_allocated,
            "available": (account_balance - total_allocated) if account_balance else None,
            "options_open_risk_usd": options_open_risk,
            "has_cross_system_risk": options_open_risk > 0.0,
            "mt5_connected": account_balance is not None
        }
    except Exception as e:
        import logging
        logging.error(f"Error getting capital allocation: {e}")
        return {
            "account_balance": None,
            "allocations": {},
            "total_allocated": 0,
            "available": None,
            "options_open_risk_usd": 0.0,
            "has_cross_system_risk": False,
            "mt5_connected": False,
            "error": str(e)
        }


@router.get("/portfolio/unified-overview")
async def get_unified_portfolio_overview(db: Session = Depends(get_db)):
    """
    Unified cross-system portfolio snapshot.

    Aggregates:
    - MT5/live strategy allocation + realized live-trade PnL
    - Options-edge journal open risk + realized journal PnL
    """
    try:
        import sys
        import os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.strategy_manager import StrategyManager

        manager = StrategyManager()
        account_balance = manager.get_account_balance()
        allocations = manager.get_allocated_capital()
        options_open_risk = float(allocations.get("options_edge_manual", 0.0))
        live_allocations = {k: float(v) for k, v in allocations.items() if k != "options_edge_manual"}
        live_allocated_total = float(sum(live_allocations.values()))

        today_start = datetime.combine(date.today(), datetime.min.time())

        live_closed_rows = db.query(LiveTradeModel).filter(
            LiveTradeModel.status == TradeStatus.CLOSED
        ).all()
        live_closed_total = float(sum(_live_trade_net_pnl(r) for r in live_closed_rows))
        live_closed_today = float(
            sum(_live_trade_net_pnl(r) for r in live_closed_rows if (r.exit_time and r.exit_time >= today_start))
        )
        live_open_count = int(
            db.query(LiveTradeModel).filter(LiveTradeModel.status == TradeStatus.OPEN).count()
        )

        opt_open_rows = db.query(OptionsEdgeTradeJournalModel).filter(
            OptionsEdgeTradeJournalModel.status == "OPEN"
        ).all()
        opt_closed_rows = db.query(OptionsEdgeTradeJournalModel).filter(
            OptionsEdgeTradeJournalModel.status == "CLOSED"
        ).all()
        opt_open_count = len(opt_open_rows)
        opt_open_risk = float(_journal_open_risk_usd(db))
        opt_closed_total = float(sum(_safe_float(r.actual_pnl_total, 0.0) for r in opt_closed_rows))
        opt_closed_today = float(
            sum(
                _safe_float(r.actual_pnl_total, 0.0)
                for r in opt_closed_rows
                if (r.closed_at and r.closed_at >= today_start)
            )
        )

        return {
            "as_of": datetime.now(timezone.utc).isoformat(),
            "mt5_connected": account_balance is not None,
            "account_balance": account_balance,
            "live_trading": {
                "allocated_capital_usd": round(live_allocated_total, 4),
                "allocations": live_allocations,
                "open_trades_count": live_open_count,
                "closed_pnl_total_usd": round(live_closed_total, 4),
                "closed_pnl_today_usd": round(live_closed_today, 4),
            },
            "options_edge": {
                "open_journal_count": int(opt_open_count),
                "open_risk_usd": round(opt_open_risk, 4),
                "closed_pnl_total_usd": round(opt_closed_total, 4),
                "closed_pnl_today_usd": round(opt_closed_today, 4),
            },
            "combined": {
                "known_open_risk_usd": round(float(live_allocated_total + options_open_risk), 4),
                "known_realized_pnl_total_usd": round(float(live_closed_total + opt_closed_total), 4),
                "known_realized_pnl_today_usd": round(float(live_closed_today + opt_closed_today), 4),
            },
        }
    except Exception as e:
        import logging
        logging.error(f"Error building unified portfolio overview: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/strategies/capital/validate")
async def validate_capital_allocation_endpoint(strategy_id: str, requested_capital: float):
    """
    Validate if a capital allocation is possible.
    Checks if the requested capital plus already allocated capital doesn't exceed account balance.
    """
    try:
        import sys
        import os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.strategy_manager import StrategyManager

        manager = StrategyManager()
        result = manager.validate_capital_allocation(strategy_id, requested_capital)

        return result
    except Exception as e:
        import logging
        logging.error(f"Error validating capital allocation: {e}")
        return {
            "valid": False,
            "message": f"Validation error: {str(e)}"
        }


@router.get("/strategies/portfolio/governor")
async def get_portfolio_governor_status(enforce: bool = Query(default=False)):
    """Get portfolio risk governor status and optional enforcement result."""
    try:
        import sys
        import os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.strategy_manager import StrategyManager

        manager = StrategyManager()
        return manager.evaluate_portfolio_governor(enforce=enforce)
    except Exception as e:
        import logging
        logging.error(f"Error getting portfolio governor status: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/strategies/portfolio/governor/config")
async def get_portfolio_governor_config():
    """Get portfolio risk governor configuration."""
    try:
        import sys
        import os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.strategy_manager import StrategyManager

        manager = StrategyManager()
        return manager.get_portfolio_governor_config()
    except Exception as e:
        import logging
        logging.error(f"Error getting governor config: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/strategies/portfolio/governor/config")
async def update_portfolio_governor_config(config: dict):
    """Update portfolio risk governor configuration."""
    try:
        import sys
        import os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.strategy_manager import StrategyManager

        manager = StrategyManager()
        saved = manager.save_portfolio_governor_config(config or {})
        return {"status": "ok", "config": saved}
    except Exception as e:
        import logging
        logging.error(f"Error updating governor config: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/strategies/portfolio/governor/clear-cooldown")
async def clear_portfolio_governor_cooldown():
    """Clear active governor cooldown and allow new starts."""
    try:
        import sys
        import os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.strategy_manager import StrategyManager

        manager = StrategyManager()
        state = manager.clear_portfolio_governor_cooldown()
        return {"status": "ok", "state": state}
    except Exception as e:
        import logging
        logging.error(f"Error clearing governor cooldown: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/strategies")
async def list_strategies():
    """List all available trading strategies"""
    from ..core.strategy_registry import StrategyRegistry

    strategies = []
    for s in StrategyRegistry.get_all_strategies():
        strategies.append({
            "id": s.id,
            "name": s.name,
            "description": s.description,
            "version": s.version,
            "timeframes": s.optimal_parameters.get("timeframes", []),
            "symbols": s.optimal_parameters.get("symbols", []),
            "ml_base_strategy_id": s.optimal_parameters.get("ml_base_strategy_id"),
            "status": "stopped",
        })

    # Try to get actual status from strategy manager
    try:
        import sys
        import os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.strategy_manager import StrategyManager

        manager = StrategyManager()
        for strategy in strategies:
            status = manager.get_strategy_status(strategy["id"])
            strategy["status"] = status
            state = manager.get_strategy_state(strategy["id"])
            if state:
                strategy["state"] = state
                # Also check is_running from state
                if state.get("is_running"):
                    strategy["status"] = "running"
    except Exception as e:
        import logging
        logging.error(f"Error getting strategy status: {e}")

    return strategies


@router.get("/strategies/{strategy_id}")
async def get_strategy(strategy_id: str):
    """Get details for a specific strategy"""
    strategies = await list_strategies()

    for strategy in strategies:
        if strategy["id"] == strategy_id:
            return strategy

    raise HTTPException(status_code=404, detail="Strategy not found")


@router.get("/strategies/{strategy_id}/state")
async def get_strategy_state(strategy_id: str):
    """Get current state of a running strategy"""
    try:
        import sys
        import os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.strategy_manager import StrategyManager

        manager = StrategyManager()
        state = manager.get_strategy_state(strategy_id)

        if state:
            # Ensure is_running is set based on status
            if state.get("is_running") or manager.get_strategy_status(strategy_id) == "running":
                state["is_running"] = True
                state["status"] = "running"
            return state

        return {
            "strategy_id": strategy_id,
            "status": "stopped",
            "is_connected": False,
            "is_running": False,
        }
    except Exception as e:
        import logging
        logging.error(f"Error getting strategy state: {e}")
        return {
            "strategy_id": strategy_id,
            "status": "error",
            "is_running": False,
            "error": str(e)
        }


@router.post("/strategies/{strategy_id}/start")
async def start_strategy(strategy_id: str, config: Optional[dict] = None):
    """Start a trading strategy with optional configuration"""
    try:
        import sys
        import os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.strategy_manager import StrategyManager

        manager = StrategyManager()
        result = manager.start_strategy(strategy_id, config)

        if result["success"]:
            return result
        else:
            raise HTTPException(status_code=400, detail=result["message"])
    except HTTPException:
        raise
    except Exception as e:
        import logging
        logging.error(f"Error starting strategy: {e}")
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/strategies/{strategy_id}/stop")
async def stop_strategy(strategy_id: str):
    """Stop a trading strategy"""
    try:
        import sys
        import os
        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))))
        from Strategies.strategy_manager import StrategyManager

        manager = StrategyManager()
        result = manager.stop_strategy(strategy_id)

        if result["success"]:
            return result
        else:
            raise HTTPException(status_code=400, detail=result["message"])
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ========================== ML Models ==========================

@router.post("/ml/train/{result_id}")
async def train_ml_model(
    result_id: int,
    strategy_id: str = Query(..., description="Base strategy ID to train for"),
    model_type: str = Query("xgboost", description="Model type: xgboost, lightgbm, lstm, cnn, transformer, ensemble"),
    use_hpo: bool = Query(False, description="Auto-tune hyperparameters via Optuna"),
    background_tasks: BackgroundTasks = None,
    db: Session = Depends(get_db)
):
    """Train ML models from a completed backtest result"""
    from ..services.ml_service import MLService

    # Validate model_type
    valid_types = ("xgboost", "lightgbm", "lstm", "cnn", "transformer", "ensemble")
    if model_type not in valid_types:
        raise HTTPException(status_code=400, detail=f"Invalid model_type '{model_type}'. Must be one of: {valid_types}")

    # Verify result exists
    result = db.query(BacktestResultModel).filter(
        BacktestResultModel.id == result_id
    ).first()
    if not result:
        raise HTTPException(status_code=404, detail="Backtest result not found")

    try:
        training_result = MLService.train_from_backtest(
            result_id, strategy_id,
            model_type=model_type, use_hpo=use_hpo
        )
        return {
            "status": "completed",
            "message": "ML model trained successfully",
            **training_result
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Training failed: {str(e)}")


@router.post("/ml/batch-train")
async def batch_train_ml_models(
    model_type: str = Query("xgboost", description="Model type for all models"),
    use_hpo: bool = Query(False, description="Auto-tune hyperparameters via Optuna"),
):
    """Train ML models for ALL strategies that have completed backtests.

    Finds the most recent completed backtest for each unique
    (strategy_id, symbol, timeframe) combination and trains a model.
    Runs in a threadpool to avoid blocking the API worker.
    """
    import asyncio
    from ..services.ml_service import MLService

    valid_types = ("xgboost", "lightgbm", "lstm", "cnn", "transformer", "ensemble")
    if model_type not in valid_types:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid model_type '{model_type}'. Must be one of: {valid_types}",
        )

    loop = asyncio.get_event_loop()
    results = await loop.run_in_executor(
        None,
        lambda: MLService.batch_train_all_strategies(
            model_type=model_type, use_hpo=use_hpo
        ),
    )

    success_count = sum(1 for r in results if r.get("status") == "success")
    error_count = sum(1 for r in results if r.get("status") == "error")

    return {
        "total": len(results),
        "success": success_count,
        "errors": error_count,
        "results": results,
    }


@router.get("/ml/models")
async def list_ml_models(db: Session = Depends(get_db)):
    """List all trained ML models"""
    from ..services.ml_service import MLService
    return MLService.list_models(db)


@router.get("/ml/models/matching")
async def get_matching_ml_models(
    strategy_id: str = Query(..., description="Base strategy ID (e.g. orb_strategy)"),
    symbol: str = Query(..., description="Symbol (e.g. XAUUSD)"),
    timeframe: str = Query(..., description="Timeframe (e.g. M1, M5)"),
    db: Session = Depends(get_db),
):
    """Find ML models matching a strategy/symbol/timeframe combination"""
    models = db.query(MLModelRecord).filter(
        MLModelRecord.strategy_id == strategy_id,
    ).order_by(MLModelRecord.trained_at.desc()).all()

    # Filter by symbol/timeframe (using getattr for backward compat with old records)
    results = []
    for m in models:
        m_symbol = getattr(m, 'symbol', None) or 'XAUUSD'
        m_timeframe = getattr(m, 'timeframe', None) or 'M1'
        if m_symbol == symbol and m_timeframe == timeframe:
            results.append({
                'id': m.id,
                'strategy_id': m.strategy_id,
                'symbol': m_symbol,
                'timeframe': m_timeframe,
                'model_type': getattr(m, 'model_type', None) or 'xgboost',
                'base_result_id': m.base_result_id,
                'trained_at': m.trained_at.isoformat() if m.trained_at else None,
                'total_trades': m.total_trades,
                'avg_accuracy': m.avg_accuracy,
                'avg_auc_roc': m.avg_auc_roc,
                'avg_f1': m.avg_f1,
                'avg_rr_mae': m.avg_rr_mae,
            })
    return results


@router.get("/ml/models/{model_id}")
async def get_ml_model(model_id: int, db: Session = Depends(get_db)):
    """Get details for a specific ML model"""
    from ..services.ml_service import MLService
    model = MLService.get_model(db, model_id)
    if not model:
        raise HTTPException(status_code=404, detail="ML model not found")
    return model


@router.delete("/ml/models/{model_id}")
async def delete_ml_model(model_id: int, db: Session = Depends(get_db)):
    """Delete a trained ML model"""
    from ..services.ml_service import MLService
    success = MLService.delete_model(db, model_id)
    if not success:
        raise HTTPException(status_code=404, detail="ML model not found")
    return {"status": "deleted", "model_id": model_id}


# ========================== ML Auto-Retrain ==========================

@router.get("/ml/retrain/status")
async def get_retrain_status():
    """Get auto-retrain scheduler status"""
    from ..main import auto_retrain_service
    return auto_retrain_service.get_status()


@router.post("/ml/retrain/trigger/{model_id}")
async def trigger_retrain(model_id: int):
    """Manually trigger retrain for a specific model"""
    from ..main import auto_retrain_service
    result = auto_retrain_service.trigger_retrain(model_id)
    if result.get("status") == "error":
        raise HTTPException(status_code=404, detail=result.get("message", "Unknown error"))
    return result


@router.post("/ml/retrain/config")
async def update_retrain_config(config: dict):
    """Update auto-retrain configuration"""
    from ..main import auto_retrain_service
    auto_retrain_service.update_config(
        interval_hours=config.get("interval_hours"),
        enabled=config.get("enabled"),
        quality_gate_tolerance=config.get("quality_gate_tolerance"),
    )
    return auto_retrain_service.get_status()


@router.get("/ml/retrain/logs")
async def get_retrain_logs(limit: int = Query(50, ge=1, le=200)):
    """Get recent retrain log entries"""
    from ..main import auto_retrain_service
    return auto_retrain_service.get_logs(limit=limit)


# ========================== Live Execution Quality ==========================

# ========================== ML Retrain from Live Data ==========================

@router.post("/ml/retrain-live/{model_id}")
async def retrain_with_live_data(model_id: int):
    """Retrain ML model using combined backtest + live trade data"""
    from ..services.live_data_retrain import LiveDataRetrainService
    service = LiveDataRetrainService()
    result = service.retrain_with_live_data(model_id)
    if result.get('status') == 'error':
        raise HTTPException(status_code=400, detail=result.get('message', 'Retrain failed'))
    return result


@router.get("/ml/live-trade-count")
async def get_live_trade_count(
    strategy_id: str = Query("orb_strategy"),
    symbol: str = Query("XAUUSD"),
    timeframe: str = Query("M1"),
):
    """Count live trades with ML features for a strategy scope"""
    from ..services.live_data_retrain import LiveDataRetrainService
    service = LiveDataRetrainService()
    return service.get_live_trade_count(strategy_id, symbol, timeframe)


# ========================== RL Online Learning ==========================

@router.get("/rl/online-status")
async def get_rl_online_status():
    """Get RL online learning buffer status"""
    try:
        import sys, os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.shared.rl_experience_buffer import RLExperienceBuffer
        from Strategies.RLStrategy.config import (
            RL_ONLINE_LEARNING, RL_ONLINE_BUFFER_SIZE,
            RL_ONLINE_MIN_BATCH, RL_ONLINE_UPDATE_INTERVAL_HOURS,
        )

        buffer = RLExperienceBuffer()
        status = buffer.get_status()
        status['enabled'] = RL_ONLINE_LEARNING
        status['min_batch'] = RL_ONLINE_MIN_BATCH
        status['update_interval_hours'] = RL_ONLINE_UPDATE_INTERVAL_HOURS
        return status
    except Exception as e:
        return {
            'enabled': False,
            'buffer_size': 0,
            'error': str(e),
        }


@router.post("/rl/online-config")
async def update_rl_online_config(config: dict):
    """Enable/disable RL online learning, set buffer size"""
    try:
        import json
        from pathlib import Path
        config_file = Path(__file__).parent.parent.parent / "data" / "rl_strategy_config.json"

        # Load existing config
        existing = {}
        if config_file.exists():
            with open(config_file, 'r') as f:
                existing = json.load(f)

        # Update with new values
        if 'enabled' in config:
            existing['rl_online_learning'] = config['enabled']
        if 'buffer_size' in config:
            existing['rl_online_buffer_size'] = config['buffer_size']
        if 'min_batch' in config:
            existing['rl_online_min_batch'] = config['min_batch']
        if 'update_interval' in config:
            existing['rl_online_update_interval'] = config['update_interval']

        config_file.parent.mkdir(parents=True, exist_ok=True)
        with open(config_file, 'w') as f:
            json.dump(existing, f, indent=2)

        return {'status': 'updated', 'config': existing}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/rl/online-logs")
async def get_rl_online_logs(
    limit: int = Query(50, ge=1, le=200),
    db: Session = Depends(get_db),
):
    """Get RL online update history"""
    from ..models.database import RLOnlineLogModel
    try:
        logs = db.query(RLOnlineLogModel).order_by(
            RLOnlineLogModel.id.desc()
        ).limit(limit).all()
        return [
            {
                'id': log.id,
                'updated_at': log.updated_at.isoformat() if log.updated_at else None,
                'experiences_count': log.experiences_count,
                'avg_reward': log.avg_reward,
                'model_path': log.model_path,
                'backup_path': log.backup_path,
                'status': log.status,
            }
            for log in logs
        ]
    except Exception:
        return []


# ========================== Adaptive Filter ==========================

@router.get("/adaptive-filter/state")
async def get_adaptive_filter_state():
    """Get all setup types with win rates and status"""
    try:
        import sys, os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.shared.adaptive_filter import AdaptiveFilter

        af = AdaptiveFilter()
        return {
            'setup_types': af.get_state(),
            'config': af.get_config(),
        }
    except Exception as e:
        return {'setup_types': {}, 'config': {}, 'error': str(e)}


@router.post("/adaptive-filter/config")
async def update_adaptive_filter_config(config: dict):
    """Update adaptive filter thresholds"""
    try:
        import sys, os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.shared.adaptive_filter import AdaptiveFilter

        af = AdaptiveFilter()
        af.update_config(
            window_size=config.get('window_size'),
            min_trades=config.get('min_trades'),
            disable_threshold=config.get('disable_threshold'),
            enable_threshold=config.get('enable_threshold'),
        )
        return {'status': 'updated', 'config': af.get_config()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/adaptive-filter/reset")
async def reset_adaptive_filter(data: dict = None):
    """Reset adaptive filter state (one or all setup types)"""
    try:
        import sys, os
        project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
        if project_root not in sys.path:
            sys.path.insert(0, project_root)
        from Strategies.shared.adaptive_filter import AdaptiveFilter

        af = AdaptiveFilter()
        setup_type = data.get('setup_type') if data else None
        af.reset(setup_type)
        return {'status': 'reset', 'setup_type': setup_type or 'all'}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ========================== Live Execution Quality ==========================

@router.get("/live/execution-quality")
async def get_execution_quality(
    days: int = Query(30, ge=1, le=365),
    strategy_id: Optional[str] = None,
):
    """Get aggregated execution quality stats"""
    import sys
    import os
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
    if project_root not in sys.path:
        sys.path.insert(0, project_root)
    from Strategies.shared.trade_journal import TradeJournal

    journal = TradeJournal()
    return journal.get_execution_summary(strategy_id=strategy_id, days=days)


@router.get("/live/execution-quality/trades")
async def get_execution_quality_trades(
    days: int = Query(30, ge=1, le=365),
    limit: int = Query(50, ge=1, le=200),
):
    """Get per-trade execution cost breakdown"""
    import sys
    import os
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
    if project_root not in sys.path:
        sys.path.insert(0, project_root)
    from Strategies.shared.trade_journal import TradeJournal

    journal = TradeJournal()
    return journal.get_trade_costs(limit=limit, days=days)


@router.get("/live/cost-comparison")
async def get_cost_comparison(
    days: int = Query(30, ge=1, le=365),
    db: Session = Depends(get_db),
):
    """Compare backtest cost assumptions vs live actual costs"""
    import sys
    import os
    project_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__))))
    if project_root not in sys.path:
        sys.path.insert(0, project_root)
    from Strategies.shared.trade_journal import TradeJournal

    journal = TradeJournal()
    live_stats = journal.get_execution_summary(days=days)

    # Get most recent backtest config's cost assumptions
    config = db.query(BacktestConfigModel).order_by(
        BacktestConfigModel.id.desc()
    ).first()

    backtest_costs = {
        "commission_per_lot": config.commission_per_lot if config else 3.50,
        "avg_slippage": config.avg_slippage_usd if config else 0.05,
        "avg_spread": config.max_spread_usd if config else 0.40,
        "swap_long_per_lot": config.swap_long_per_lot if config else -8.50,
        "swap_short_per_lot": config.swap_short_per_lot if config else -3.20,
    }

    # Compute deltas
    spread_delta = live_stats["avg_spread"] - backtest_costs["avg_spread"]
    slippage_delta = live_stats["avg_slippage"] - backtest_costs["avg_slippage"]
    commission_delta = live_stats["avg_commission"] - backtest_costs["commission_per_lot"]
    swap_delta = live_stats["avg_swap"] - (
        (backtest_costs["swap_long_per_lot"] + backtest_costs["swap_short_per_lot"]) / 2
    )

    return {
        "backtest": backtest_costs,
        "live": {
            "avg_spread": live_stats["avg_spread"],
            "avg_slippage": live_stats["avg_slippage"],
            "avg_commission": live_stats["avg_commission"],
            "avg_swap": live_stats["avg_swap"],
            "cost_per_trade": live_stats["cost_per_trade"],
        },
        "delta": {
            "spread": round(spread_delta, 4),
            "slippage": round(slippage_delta, 4),
            "commission": round(commission_delta, 2),
            "swap": round(swap_delta, 2),
            "total_impact": round(spread_delta + slippage_delta + commission_delta + swap_delta, 2),
        },
        "total_live_trades": live_stats["total_trades"],
        "period_days": days,
    }


# ============================================================================
# Data Management Endpoints
# ============================================================================

@router.get("/data/files")
async def list_data_files():
    """List available CSV data files with their date ranges"""
    from ..core.data_provider import HistoricalDataProvider
    provider = HistoricalDataProvider()
    files = provider.get_csv_data_info()
    return files


@router.post("/data/download-mt5")
async def download_mt5_data(request_data: dict):
    """
    Download all available data from MT5 using copy_rates_from_pos
    and save as CSV in data/historical/.

    This fetches data by position (most recent first) which can
    sometimes access more history than copy_rates_range.
    """
    import MetaTrader5 as mt5_lib
    import pandas as pd
    from pathlib import Path
    from datetime import datetime as dt

    symbol = request_data.get('symbol', 'XAUUSD')
    timeframe = request_data.get('timeframe', 'M1')

    # MT5 timeframe mapping
    tf_map = {
        "M1": mt5_lib.TIMEFRAME_M1, "M5": mt5_lib.TIMEFRAME_M5,
        "M15": mt5_lib.TIMEFRAME_M15, "M30": mt5_lib.TIMEFRAME_M30,
        "H1": mt5_lib.TIMEFRAME_H1, "H4": mt5_lib.TIMEFRAME_H4,
        "D1": mt5_lib.TIMEFRAME_D1,
    }

    mt5_tf = tf_map.get(timeframe)
    if mt5_tf is None:
        raise HTTPException(status_code=400, detail=f"Invalid timeframe: {timeframe}")

    # Initialize MT5
    if not mt5_lib.initialize():
        raise HTTPException(status_code=500, detail=f"MT5 initialization failed: {mt5_lib.last_error()}")

    try:
        if not mt5_lib.symbol_select(symbol, True):
            raise HTTPException(status_code=400, detail=f"Symbol {symbol} not available")

        # Fetch maximum available data using copy_rates_from_pos
        # Start from position 0 (most recent) and go back in chunks
        all_rates = []
        chunk_size = 50000  # MT5 max per request
        pos = 0
        max_iterations = 20  # Safety limit

        for i in range(max_iterations):
            rates = mt5_lib.copy_rates_from_pos(symbol, mt5_tf, pos, chunk_size)
            if rates is None or len(rates) == 0:
                break

            all_rates.append(pd.DataFrame(rates))
            pos += len(rates)

            # If we got fewer than requested, we've reached the end
            if len(rates) < chunk_size:
                break

        if not all_rates:
            raise HTTPException(status_code=404, detail="No data available from MT5")

        # Combine all chunks
        df = pd.concat(all_rates, ignore_index=True)
        df = df.drop_duplicates(subset=['time'])
        df = df.sort_values('time')

        # Convert timestamps
        df['datetime'] = pd.to_datetime(df['time'], unit='s')

        # Save as CSV
        data_dir = Path(__file__).parent.parent.parent / "data" / "historical"
        data_dir.mkdir(parents=True, exist_ok=True)

        start_date = df['datetime'].min().strftime('%Y%m%d')
        end_date = df['datetime'].max().strftime('%Y%m%d')
        filename = f"{symbol}_{timeframe}_{start_date}_{end_date}_mt5.csv"

        csv_path = data_dir / filename

        # Save in standard format with headers
        csv_df = pd.DataFrame({
            'Date': df['datetime'].dt.strftime('%Y.%m.%d'),
            'Time': df['datetime'].dt.strftime('%H:%M'),
            'Open': df['open'],
            'High': df['high'],
            'Low': df['low'],
            'Close': df['close'],
            'Tickvolume': df['tick_volume'],
            'Volume': df['real_volume'],
            'Spread': df['spread'],
        })

        csv_df.to_csv(str(csv_path), sep='\t', index=False)

        return {
            "status": "success",
            "filename": filename,
            "bars": len(df),
            "start_date": df['datetime'].min().strftime('%Y-%m-%d'),
            "end_date": df['datetime'].max().strftime('%Y-%m-%d'),
            "trading_days": df['datetime'].dt.date.nunique(),
        }

    finally:
        mt5_lib.shutdown()


@router.post("/data/download-ibkr")
async def download_ibkr_data(request_data: dict):
    """
    Start a background IBKR data download task.
    Returns task_id for progress polling.
    """
    try:
        from ..services.ibkr_service import IBKRDataService
    except ImportError:
        raise HTTPException(status_code=500, detail="ib_async not installed. Run: pip install ib_async")

    symbol = request_data.get('symbol', 'XAUUSD')
    timeframe = request_data.get('timeframe', 'M1')
    start_date = request_data.get('start_date')
    end_date = request_data.get('end_date')
    port = int(request_data.get('port', 7497))

    if not start_date or not end_date:
        raise HTTPException(status_code=400, detail="start_date and end_date are required (YYYY-MM-DD)")

    task_id = IBKRDataService.start_download(
        symbol=symbol,
        timeframe=timeframe,
        start_date=start_date,
        end_date=end_date,
        port=port,
    )

    return {"status": "started", "task_id": task_id}


@router.get("/data/ibkr-status/{task_id}")
async def get_ibkr_status(task_id: str):
    """Poll IBKR download task progress."""
    try:
        from ..services.ibkr_service import IBKRDataService
    except ImportError:
        raise HTTPException(status_code=500, detail="ib_async not installed")

    status = IBKRDataService.get_task_status(task_id)
    if not status:
        raise HTTPException(status_code=404, detail="Task not found")
    return status


@router.get("/data/ibkr-connection-test")
async def test_ibkr_connection(port: int = Query(7497, description="TWS port")):
    """Test IBKR TWS connectivity."""
    try:
        from ..services.ibkr_service import IBKRDataService
    except ImportError:
        raise HTTPException(status_code=500, detail="ib_async not installed. Run: pip install ib_async")

    result = IBKRDataService.test_connection(port=port)
    return result


@router.post("/data/download-dukascopy")
async def download_dukascopy_data(request_data: dict):
    """
    Start a background Dukascopy data download task.
    Downloads tick data from Dukascopy's free binary feed and aggregates to M1 candles.
    Returns task_id for progress polling.
    """
    from ..services.dukascopy_service import DukascopyDataService

    symbol = request_data.get('symbol', 'XAUUSD').upper()
    start_date = request_data.get('start_date')
    end_date = request_data.get('end_date')

    if not start_date or not end_date:
        raise HTTPException(status_code=400, detail="start_date and end_date are required (YYYY-MM-DD)")

    task_id = DukascopyDataService.start_download(
        symbol=symbol,
        start_date=start_date,
        end_date=end_date,
    )

    return {"status": "started", "task_id": task_id}


@router.get("/data/dukascopy-status/{task_id}")
async def get_dukascopy_status(task_id: str):
    """Poll Dukascopy download task progress."""
    from ..services.dukascopy_service import DukascopyDataService

    status = DukascopyDataService.get_task_status(task_id)
    if not status:
        raise HTTPException(status_code=404, detail="Task not found")
    return status


@router.get("/data/dukascopy-connection-test")
async def test_dukascopy_connection(symbol: str = Query("XAUUSD", description="Symbol to test")):
    """Test Dukascopy data feed connectivity."""
    from ..services.dukascopy_service import DukascopyDataService

    result = DukascopyDataService.test_connection(symbol=symbol)
    return result


@router.delete("/data/files/{filename}")
async def delete_data_file(filename: str):
    """Delete a CSV data file"""
    from ..core.data_provider import HistoricalDataProvider
    provider = HistoricalDataProvider()

    # Security: only allow .csv files, no path traversal
    if '..' in filename or '/' in filename or '\\' in filename:
        raise HTTPException(status_code=400, detail="Invalid filename")
    if not filename.endswith('.csv'):
        raise HTTPException(status_code=400, detail="Only CSV files can be deleted")

    success = provider.delete_csv_file(filename)
    if not success:
        raise HTTPException(status_code=404, detail="File not found")
    return {"status": "deleted", "filename": filename}
