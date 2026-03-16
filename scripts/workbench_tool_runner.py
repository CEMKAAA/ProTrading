#!/usr/bin/env python
"""Deterministic runner for Workbench agent tools.

Usage examples:
  python scripts/workbench_tool_runner.py --session 25 --strategy strategy1
  python scripts/workbench_tool_runner.py --session 25 --strategy strategy2 --preset xauusd_m15
  python scripts/workbench_tool_runner.py --session 25 --strategy strategy3 --preset xauusd_m1

This script executes the same backend tools used by the Workbench agent path,
without relying on LLM prompt parsing.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from dashboard.backend.api import simulation_routes as sim_routes
from dashboard.backend.models.database import SessionLocal, SimulationSession


def _parse_bool(value: str) -> bool:
    v = str(value or "").strip().lower()
    if v in {"1", "true", "t", "yes", "y", "on"}:
        return True
    if v in {"0", "false", "f", "no", "n", "off"}:
        return False
    raise argparse.ArgumentTypeError(f"Invalid bool value: {value}")


def _default_permissions() -> Dict[str, Any]:
    return {
        "can_chat": True,
        "can_scan_tools": True,
        "can_manage_indicators": True,
        "can_use_research": True,
        "can_place_trades": False,
        "can_close_trades": False,
        "requires_user_confirm_for_trade": True,
    }


def _run_tool(
    *,
    session: SimulationSession,
    db,
    context_snapshot: Dict[str, Any],
    permissions: Dict[str, Any],
    tool_config: Dict[str, Any],
    tool_name: str,
    args: Dict[str, Any],
) -> Dict[str, Any]:
    out = sim_routes._agent_execute_tool(
        session=session,
        db=db,
        permissions=permissions,
        context_snapshot=context_snapshot,
        tool_name=tool_name,
        args=args,
        tool_config=tool_config,
        atomic=False,
    )
    return out if isinstance(out, dict) else {"ok": False, "error": "invalid_tool_response"}


def _build_analysis_tool(strategy: str, args: argparse.Namespace) -> Dict[str, Any]:
    s = str(strategy or "").strip().lower()
    if s == "strategy2":
        return {
            "tool_name": "run_htf_fvg_liquidity_reclaim_analysis",
            "tool_args": {
                "symbol": args.symbol,
                "execution_timeframe": args.execution_timeframe,
                "preset": args.preset,
                "include_news": bool(args.include_news),
            },
        }
    if s == "strategy3":
        return {
            "tool_name": "run_orb_analysis",
            "tool_args": {
                "symbol": args.symbol,
                "source": args.source,
                "preset": args.preset,
                "history_days": float(args.history_days),
                "risk_percent": float(args.risk_percent),
                "rr_target": float(args.rr_target),
                "include_news": bool(args.include_news),
            },
        }

    return {
        "tool_name": "run_mtf_analysis",
        "tool_args": {
            "symbol": args.symbol,
            "source": args.source,
            "htf_timeframes": args.htf_timeframes,
            "execution_timeframe": args.execution_timeframe,
            "risk_percent": float(args.risk_percent),
            "rr_target": float(args.rr_target),
            "include_news": bool(args.include_news),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Run Workbench tool chain deterministically.")
    parser.add_argument("--session", type=int, required=True, help="Workbench simulation session id")
    parser.add_argument("--strategy", choices=["strategy1", "strategy2", "strategy3"], default="strategy1")
    parser.add_argument("--symbol", default="XAUUSD", help="Symbol for analysis tool")
    parser.add_argument("--execution-timeframe", default="M15", help="Execution timeframe")
    parser.add_argument("--source", default="mt5", help="Data source for strategy1")
    parser.add_argument("--htf-timeframes", nargs="+", default=["D1", "H4"], help="HTF list for strategy1")
    parser.add_argument("--risk-percent", type=float, default=0.5, help="Risk percent for strategy1")
    parser.add_argument("--rr-target", type=float, default=2.0, help="RR target for strategy1")
    parser.add_argument("--history-days", type=float, default=2.5, help="History window in days for strategy3")
    parser.add_argument("--preset", default="xauusd_m15", help="Preset for strategy2")
    parser.add_argument(
        "--respect-session-profile",
        action="store_true",
        help="Do not auto-override agent strategy profile/preset from CLI strategy choice",
    )
    parser.add_argument("--include-news", type=_parse_bool, default=False, help="Include news context")
    parser.add_argument("--pretty", action="store_true", help="Pretty-print JSON output")
    args = parser.parse_args()

    db = SessionLocal()
    try:
        row = db.query(SimulationSession).get(int(args.session))
        if row is None:
            print(json.dumps({"ok": False, "error": f"session_not_found:{args.session}"}))
            return 2
        if str(row.strategy_id or "") != str(sim_routes.WORKBENCH_ID):
            print(
                json.dumps(
                    {
                        "ok": False,
                        "error": "not_workbench_session",
                        "session_id": int(args.session),
                        "strategy_id": str(row.strategy_id or ""),
                    }
                )
            )
            return 2

        context_snapshot = sim_routes._agent_default_context(session=row, db=db)
        permissions = _default_permissions()
        override_cfg: Dict[str, Any] = {}
        if not bool(args.respect_session_profile):
            if str(args.strategy) == "strategy2":
                override_cfg["agent_strategy_profile"] = "htf_fvg_liquidity_reclaim_v2"
                override_cfg["agent_strategy_preset"] = str(args.preset)
            elif str(args.strategy) == "strategy3":
                override_cfg["agent_strategy_profile"] = "orb_ny_15m_imbalance"
                override_cfg["agent_strategy_preset"] = str(args.preset)
            else:
                override_cfg["agent_strategy_profile"] = "classic_htf_fvg"
                override_cfg["agent_strategy_preset"] = "default"
        tool_config = sim_routes._agent_effective_tool_config(
            session=row,
            db=db,
            override=(override_cfg if override_cfg else None),
        )

        positions = _run_tool(
            session=row,
            db=db,
            context_snapshot=context_snapshot,
            permissions=permissions,
            tool_config=tool_config,
            tool_name="get_positions_detail",
            args={"open_limit": 20, "recent_limit": 20},
        )

        triggers = _run_tool(
            session=row,
            db=db,
            context_snapshot=context_snapshot,
            permissions=permissions,
            tool_config=tool_config,
            tool_name="get_scheduled_triggers",
            args={"limit": 200, "include_non_pending": True},
        )

        analysis_spec = _build_analysis_tool(args.strategy, args)
        analysis = _run_tool(
            session=row,
            db=db,
            context_snapshot=context_snapshot,
            permissions=permissions,
            tool_config=tool_config,
            tool_name=str(analysis_spec["tool_name"]),
            args=dict(analysis_spec["tool_args"]),
        )

        out = {
            "ok": bool(positions.get("ok")) and bool(triggers.get("ok")) and bool(analysis.get("ok")),
            "session_id": int(args.session),
            "strategy": str(args.strategy),
            "effective_tool_config": {
                "agent_strategy_profile": tool_config.get("agent_strategy_profile"),
                "agent_strategy_preset": tool_config.get("agent_strategy_preset"),
            },
            "tools": {
                "get_positions_detail": positions,
                "get_scheduled_triggers": triggers,
                str(analysis_spec["tool_name"]): analysis,
            },
        }
        if args.pretty:
            print(json.dumps(out, indent=2, ensure_ascii=False))
        else:
            print(json.dumps(out, ensure_ascii=False))
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
