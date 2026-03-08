"""
Enterprise Monitoring Service - Aggregated snapshot for the monitoring dashboard.

Combines data from StrategyManager, TradeJournal, PortfolioGovernor, and DB
into a single JSON response to minimize frontend API calls.
"""

import sys
import os
import logging
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

from sqlalchemy.orm import Session

logger = logging.getLogger(__name__)

# Startup timestamp for uptime tracking
_startup_time = datetime.now(timezone.utc)


def _ensure_project_root():
    """Add project root to sys.path if needed."""
    project_root = os.path.dirname(
        os.path.dirname(os.path.dirname(os.path.dirname(__file__)))
    )
    if project_root not in sys.path:
        sys.path.insert(0, project_root)
    return project_root


class MonitoringService:
    """Aggregates all monitoring data into a single snapshot."""

    def get_snapshot(self, db: Session) -> Dict[str, Any]:
        """Build a complete monitoring snapshot for the dashboard."""
        _ensure_project_root()
        now = datetime.now(timezone.utc)

        # Single StrategyManager instance reused across all helpers
        mgr = self._get_manager()

        # -- Gather raw data from subsystems (each wrapped for resilience) --
        capital = self._get_capital(mgr)
        governor = self._get_governor(mgr)
        running_ids = self._get_running_ids(mgr)
        all_strategies = self._get_all_strategies()
        strategy_states = self._get_strategy_states(
            mgr, all_strategies, running_ids, capital.get("allocations", {})
        )
        execution = self._get_execution_quality()
        recent_trades = self._get_recent_trades(db)

        # -- Derive computed sections --
        governor_snapshot = governor.get("snapshot", {})
        governor_config = governor.get("config", {})
        governor_state = governor.get("state", {})

        system = {
            "mt5_connected": capital.get("mt5_connected", False),
            "active_strategies": len(running_ids),
            "total_strategies": len(all_strategies),
            "backend_uptime_seconds": round(
                (now - _startup_time).total_seconds()
            ),
        }

        portfolio = {
            "account_balance": capital.get("account_balance"),
            "account_equity": governor_snapshot.get("account_equity"),
            "total_allocated": capital.get("total_allocated", 0),
            "available_capital": capital.get("available"),
            "net_daily_pnl": sum(
                s.get("daily_pnl") or 0 for s in strategy_states
            ),
            "total_open_positions": sum(
                s.get("open_positions") or 0 for s in strategy_states
            ),
            "portfolio_heat_pct": governor_snapshot.get(
                "portfolio_heat_pct", 0
            ),
            "daily_drawdown_pct": governor_snapshot.get(
                "daily_drawdown_pct", 0
            ),
            "long_lots": governor_snapshot.get("long_lots", 0),
            "short_lots": governor_snapshot.get("short_lots", 0),
        }

        risk = {
            "governor_status": governor.get("status", "unknown"),
            "allow_new_starts": governor.get("allow_new_starts", True),
            "breaches": governor.get("breaches", []),
            "cooldown_until": governor_state.get("cooldown_until"),
            "heat_limit_pct": governor_config.get(
                "max_portfolio_heat_pct", 10
            ),
            "dd_kill_pct": governor_config.get(
                "daily_drawdown_kill_pct", 5
            ),
            "exposure_limit_lots": governor_config.get(
                "max_directional_exposure_lots", 5
            ),
        }

        # Build alerts from current state
        alerts = self._build_alerts(system, risk, strategy_states)

        return {
            "timestamp": now.isoformat(),
            "system": system,
            "portfolio": portfolio,
            "strategies": strategy_states,
            "risk": risk,
            "execution": execution,
            "recent_trades": recent_trades,
            "alerts": alerts,
        }

    # ------------------------------------------------------------------
    # Private data-gathering helpers (each catches its own exceptions)
    # ------------------------------------------------------------------

    def _get_manager(self) -> Optional[object]:
        """Create a single StrategyManager instance for the request."""
        try:
            from Strategies.strategy_manager import StrategyManager
            return StrategyManager()
        except Exception as e:
            logger.warning("Monitoring: StrategyManager unavailable: %s", e)
            return None

    def _get_capital(self, mgr) -> Dict[str, Any]:
        try:
            if mgr is None:
                raise RuntimeError("No StrategyManager")
            account_balance = mgr.get_account_balance()
            allocations = mgr.get_allocated_capital()
            total_allocated = sum(allocations.values()) if allocations else 0
            available = (
                (account_balance - total_allocated)
                if account_balance is not None
                else None
            )
            return {
                "mt5_connected": account_balance is not None,
                "account_balance": account_balance,
                "total_allocated": total_allocated,
                "available": available,
                "allocations": allocations or {},
            }
        except Exception as e:
            logger.warning("Monitoring: capital allocation unavailable: %s", e)
            return {
                "mt5_connected": False,
                "account_balance": None,
                "total_allocated": 0,
                "available": None,
                "allocations": {},
            }

    def _get_governor(self, mgr) -> Dict[str, Any]:
        try:
            if mgr is None:
                raise RuntimeError("No StrategyManager")
            return mgr.evaluate_portfolio_governor(enforce=False)
        except Exception as e:
            logger.warning("Monitoring: governor unavailable: %s", e)
            return {
                "status": "unknown",
                "allow_new_starts": True,
                "breaches": [],
                "snapshot": {},
                "config": {},
                "state": {},
            }

    def _get_running_ids(self, mgr) -> List[str]:
        try:
            if mgr is None:
                raise RuntimeError("No StrategyManager")
            return mgr.get_all_running()
        except Exception as e:
            logger.warning("Monitoring: running list unavailable: %s", e)
            return []

    def _get_all_strategies(self) -> list:
        try:
            from dashboard.backend.core.strategy_registry import (
                StrategyRegistry,
            )
            return list(StrategyRegistry.get_all_strategies())
        except Exception as e:
            logger.warning("Monitoring: strategy registry unavailable: %s", e)
            return []

    def _get_strategy_states(
        self,
        mgr,
        all_strategies: list,
        running_ids: List[str],
        allocations: Dict[str, float],
    ) -> List[Dict[str, Any]]:
        """Build per-strategy state dicts for every registered strategy."""
        result = []

        for s in all_strategies:
            sid = s.id
            is_running = sid in running_ids
            state = {}

            if mgr and is_running:
                try:
                    state = mgr.get_strategy_state(sid) or {}
                except Exception:
                    state = {}

            # Determine status
            if is_running:
                if state.get("error_message"):
                    status = "error"
                else:
                    status = "running"
            else:
                status = "stopped"

            symbols = s.optimal_parameters.get("symbols", [])
            timeframes = s.optimal_parameters.get("timeframes", [])

            result.append({
                "id": sid,
                "name": s.name,
                "status": status,
                "symbol": state.get("symbol") or (symbols[0] if symbols else ""),
                "timeframe": state.get("timeframe") or (timeframes[0] if timeframes else ""),
                "current_price": state.get("current_price"),
                "spread": state.get("spread"),
                "daily_pnl": state.get("daily_pnl", 0) if is_running else 0,
                "daily_trades": state.get("daily_trades", 0) if is_running else 0,
                "balance": state.get("balance"),
                "open_positions": state.get("open_positions", 0) if is_running else 0,
                "session_bias": state.get("session_bias"),
                "can_trade": state.get("can_trade", True),
                "last_signal": state.get("last_signal"),
                "last_update": state.get("last_update"),
                "error_message": state.get("error_message"),
                "allocation": allocations.get(sid, 0),
            })

        return result

    def _get_execution_quality(self) -> Dict[str, Any]:
        try:
            from Strategies.shared.trade_journal import TradeJournal
            journal = TradeJournal()
            eq = journal.get_execution_summary(days=30)
            return {
                "avg_spread": eq.get("avg_spread", 0),
                "avg_slippage": eq.get("avg_slippage", 0),
                "cost_per_trade": eq.get("cost_per_trade", 0),
                "total_live_trades": eq.get("total_trades", 0),
            }
        except Exception as e:
            logger.warning("Monitoring: execution quality unavailable: %s", e)
            return {
                "avg_spread": 0,
                "avg_slippage": 0,
                "cost_per_trade": 0,
                "total_live_trades": 0,
            }

    def _get_recent_trades(self, db: Session) -> List[Dict[str, Any]]:
        try:
            from ..models.database import LiveTradeModel, TradeStatus

            trades = (
                db.query(LiveTradeModel)
                .filter(LiveTradeModel.status == TradeStatus.CLOSED)
                .order_by(LiveTradeModel.exit_time.desc())
                .limit(10)
                .all()
            )
            result = []
            for t in trades:
                result.append({
                    "ticket": t.ticket,
                    "symbol": t.symbol,
                    "direction": t.direction.value if t.direction else None,
                    "entry_time": t.entry_time.isoformat() if t.entry_time else None,
                    "exit_time": t.exit_time.isoformat() if t.exit_time else None,
                    "pnl": t.profit_loss,
                    "setup_type": t.setup_type,
                    "lot_size": t.lot_size,
                })
            return result
        except Exception as e:
            logger.warning("Monitoring: recent trades unavailable: %s", e)
            return []

    def _build_alerts(
        self,
        system: Dict[str, Any],
        risk: Dict[str, Any],
        strategy_states: List[Dict[str, Any]],
    ) -> List[Dict[str, Any]]:
        alerts = []

        # System-level alerts
        if not system.get("mt5_connected"):
            alerts.append({
                "level": "warning",
                "message": "MT5 Disconnected — capital data unavailable",
                "source": "system",
            })

        # Governor breaches
        if risk.get("governor_status") == "breached":
            for breach in risk.get("breaches", []):
                alerts.append({
                    "level": "danger",
                    "message": breach,
                    "source": "governor",
                })

        if not risk.get("allow_new_starts") and risk.get("governor_status") != "breached":
            alerts.append({
                "level": "warning",
                "message": "New strategy starts blocked (cooldown active)",
                "source": "governor",
            })

        # Strategy errors
        for s in strategy_states:
            if s.get("status") == "error" and s.get("error_message"):
                alerts.append({
                    "level": "warning",
                    "message": f"{s['name']}: {s['error_message']}",
                    "source": "strategy",
                })

        return alerts
