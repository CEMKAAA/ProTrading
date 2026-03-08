"""
Strategy Manager - Manages running strategies from dashboard
"""

import subprocess
import sys
import os
import json
import sqlite3
import logging
import threading
import time
from pathlib import Path
from typing import Dict, Any, Optional, List
from datetime import datetime, timedelta, timezone

from .base import StrategyRegistry, StrategyStatus

# Try to import MT5 for account balance checking
try:
    import MetaTrader5 as mt5
    HAS_MT5 = True
except ImportError:
    HAS_MT5 = False
    mt5 = None


# State file location
MANAGER_STATE_FILE = Path(__file__).parent.parent / "dashboard" / "data" / "strategy_manager_state.json"
PORTFOLIO_GOVERNOR_CONFIG_FILE = Path(__file__).parent.parent / "dashboard" / "data" / "portfolio_risk_governor_config.json"
PORTFOLIO_GOVERNOR_STATE_FILE = Path(__file__).parent.parent / "dashboard" / "data" / "portfolio_risk_governor_state.json"

# Centralized strategy registry: maps strategy_id -> {main, state}
# Adding a new strategy only requires one entry here.
_STRATEGIES_DIR = Path(__file__).parent
_DATA_DIR = Path(__file__).parent.parent / "dashboard" / "data"
_DASHBOARD_DB_PATH = _DATA_DIR / "trading.db"

STRATEGY_PATHS = {
    # === Base strategies ===
    "orb_strategy": {
        "main": _STRATEGIES_DIR / "ORBStrategy" / "main.py",
        "state": _DATA_DIR / "bot_state.json",
    },
    "advanced_orb_strategy": {
        "main": _STRATEGIES_DIR / "AdvancedORBStrategy" / "main.py",
        "state": _DATA_DIR / "advanced_orb_state.json",
    },
    "liquidity_sweep_strategy": {
        "main": _STRATEGIES_DIR / "LiquiditySweepStrategy" / "main.py",
        "state": _DATA_DIR / "liquidity_sweep_state.json",
    },
    "keltner_breakout_strategy": {
        "main": _STRATEGIES_DIR / "KeltnerBreakoutStrategy" / "main.py",
        "state": _DATA_DIR / "keltner_breakout_state.json",
    },
    # === ML wrapper strategies (each needs its OWN state file) ===
    "orb_ml_strategy": {
        "main": _STRATEGIES_DIR / "MLWrapper" / "orb_ml_main.py",
        "state": _DATA_DIR / "orb_ml_state.json",
    },
    "advanced_orb_ml_strategy": {
        "main": _STRATEGIES_DIR / "MLWrapper" / "advanced_orb_ml_main.py",
        "state": _DATA_DIR / "advanced_orb_ml_state.json",
    },
    "liquidity_sweep_ml_strategy": {
        "main": _STRATEGIES_DIR / "MLWrapper" / "liquidity_sweep_ml_main.py",
        "state": _DATA_DIR / "liquidity_sweep_ml_state.json",
    },
    "keltner_breakout_ml_strategy": {
        "main": _STRATEGIES_DIR / "MLWrapper" / "keltner_breakout_ml_main.py",
        "state": _DATA_DIR / "keltner_breakout_ml_state.json",
    },
}


class StrategyManager:
    """
    Manages strategy processes from the dashboard.
    Each strategy runs as a separate process.
    """

    def __init__(self):
        self.state_file = MANAGER_STATE_FILE
        self._ensure_directory()
        self._running_processes: Dict[str, subprocess.Popen] = {}
        self._process_threads: Dict[str, threading.Thread] = {}
        self._mt5_initialized = False
        # Thread safety: protects _running_processes, _process_threads, state file I/O
        # RLock allows nested acquisition (e.g., start_strategy -> _update_strategy_state)
        self._lock = threading.RLock()

    @staticmethod
    def _default_governor_config() -> Dict[str, Any]:
        return {
            "enabled": True,
            "check_interval_seconds": 15,
            "max_portfolio_heat_pct": 6.0,
            "max_directional_exposure_lots": 0.30,
            "daily_drawdown_kill_pct": 3.0,
            "auto_stop_all_on_breach": True,
            "cooldown_minutes": 60,
            "block_new_starts_when_breached": True,
        }

    @staticmethod
    def _default_governor_state() -> Dict[str, Any]:
        return {
            "status": "ok",
            "allow_new_starts": True,
            "baseline_date": None,
            "baseline_equity": None,
            "cooldown_until": None,
            "last_breach_time": None,
            "last_breach_reasons": [],
            "last_snapshot": None,
            "updated_at": datetime.now(timezone.utc).isoformat(),
        }

    def get_portfolio_governor_config(self) -> Dict[str, Any]:
        cfg = self._default_governor_config()
        try:
            if PORTFOLIO_GOVERNOR_CONFIG_FILE.exists():
                with open(PORTFOLIO_GOVERNOR_CONFIG_FILE, "r") as f:
                    raw = json.load(f)
                    if isinstance(raw, dict):
                        cfg.update(raw)
        except Exception:
            pass
        return cfg

    def save_portfolio_governor_config(self, config: Dict[str, Any]) -> Dict[str, Any]:
        current = self.get_portfolio_governor_config()
        current.update(config or {})
        PORTFOLIO_GOVERNOR_CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(PORTFOLIO_GOVERNOR_CONFIG_FILE, "w") as f:
            json.dump(current, f, indent=2)
        return current

    def _get_portfolio_governor_state(self) -> Dict[str, Any]:
        with self._lock:
            state = self._default_governor_state()
            try:
                if PORTFOLIO_GOVERNOR_STATE_FILE.exists():
                    with open(PORTFOLIO_GOVERNOR_STATE_FILE, "r") as f:
                        raw = json.load(f)
                        if isinstance(raw, dict):
                            state.update(raw)
            except Exception:
                pass
            return state

    def _save_portfolio_governor_state(self, state: Dict[str, Any]):
        with self._lock:
            state["updated_at"] = datetime.now(timezone.utc).isoformat()
            PORTFOLIO_GOVERNOR_STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
            with open(PORTFOLIO_GOVERNOR_STATE_FILE, "w") as f:
                json.dump(state, f, indent=2)

    def evaluate_portfolio_governor(self, enforce: bool = False) -> Dict[str, Any]:
        cfg = self.get_portfolio_governor_config()
        state = self._get_portfolio_governor_state()

        result = {
            "config": cfg,
            "state": state,
            "snapshot": {},
            "breaches": [],
            "status": "ok",
            "allow_new_starts": True,
            "enforced_actions": [],
        }

        if not cfg.get("enabled", True):
            result["status"] = "disabled"
            result["allow_new_starts"] = True
            state["status"] = "disabled"
            state["allow_new_starts"] = True
            self._save_portfolio_governor_state(state)
            result["state"] = state
            return result

        if not self._ensure_mt5():
            result["status"] = "degraded_mt5_disconnected"
            result["allow_new_starts"] = False  # Fail-safe: block new starts when MT5 is down
            state["status"] = result["status"]
            state["allow_new_starts"] = False
            self._save_portfolio_governor_state(state)
            result["state"] = state
            return result

        account = mt5.account_info()
        if account is None:
            result["status"] = "degraded_no_account_info"
            result["allow_new_starts"] = False  # Fail-safe: block without account verification
            state["status"] = result["status"]
            state["allow_new_starts"] = False
            self._save_portfolio_governor_state(state)
            result["state"] = state
            return result

        running = self.get_all_running()
        alloc = self.get_allocated_capital()
        total_alloc = float(sum(alloc.values()))

        heat_usd = 0.0
        for sid in running:
            scfg = self.get_strategy_config(sid) or {}
            try:
                heat_usd += float(scfg.get("max_total_risk_usd", scfg.get("max_total_risk", 0.0)) or 0.0)
            except Exception:
                continue
        # Cross-system guard: include open Options Edge journal risk
        # so MT5 strategy starts are aware of options exposure too.
        options_open_risk_usd = self._get_options_journal_open_risk_usd()
        heat_usd += float(options_open_risk_usd)

        positions = mt5.positions_get() or []
        long_lots = 0.0
        short_lots = 0.0
        for p in positions:
            if int(getattr(p, "type", 0)) == 0:
                long_lots += float(getattr(p, "volume", 0.0))
            else:
                short_lots += float(getattr(p, "volume", 0.0))
        directional_exposure_lots = max(long_lots, short_lots)

        now = datetime.now(timezone.utc)
        today = now.date().isoformat()
        baseline_date = state.get("baseline_date")
        baseline_equity = state.get("baseline_equity")
        baseline_balance = state.get("baseline_balance")
        if baseline_date != today or baseline_equity is None:
            # Use balance (not equity) as basis to avoid unrealized P&L skewing the baseline
            baseline_equity = float(account.balance)
            baseline_balance = float(account.balance)
            state["baseline_date"] = today
            state["baseline_equity"] = baseline_equity
            state["baseline_balance"] = baseline_balance
        else:
            # Detect mid-day deposits/withdrawals by tracking balance changes
            # Balance changes only from deposits/withdrawals/closed trades.
            # If balance jumped by more than closed P&L could explain,
            # adjust baseline to account for the deposit/withdrawal.
            if baseline_balance is not None:
                current_balance = float(account.balance)
                balance_change = current_balance - float(baseline_balance)
                # Threshold: if balance changed by more than 5% of baseline,
                # it's likely a deposit/withdrawal, not just trade P&L
                if abs(balance_change) > float(baseline_equity) * 0.05:
                    baseline_equity = float(baseline_equity) + balance_change
                    state["baseline_equity"] = baseline_equity
                    state["baseline_balance"] = current_balance
                    logging.getLogger(__name__).info(
                        f"Portfolio governor: baseline adjusted by ${balance_change:.2f} "
                        f"(deposit/withdrawal detected). New baseline: ${baseline_equity:.2f}"
                    )

        if baseline_equity and baseline_equity > 0:
            daily_dd_pct = max(0.0, (float(baseline_equity) - float(account.equity)) / float(baseline_equity) * 100.0)
        else:
            daily_dd_pct = 0.0

        balance = float(account.balance)
        heat_pct = (heat_usd / balance * 100.0) if balance > 0 else 0.0

        cooldown_until = state.get("cooldown_until")
        cooldown_active = False
        if cooldown_until:
            try:
                cooldown_active = now < datetime.fromisoformat(cooldown_until)
            except Exception:
                cooldown_active = False

        breaches = []
        if heat_pct > float(cfg.get("max_portfolio_heat_pct", 6.0)):
            breaches.append(f"portfolio_heat_exceeded:{heat_pct:.2f}%")
        if directional_exposure_lots > float(cfg.get("max_directional_exposure_lots", 0.30)):
            breaches.append(f"directional_exposure_exceeded:{directional_exposure_lots:.2f} lots")
        if daily_dd_pct > float(cfg.get("daily_drawdown_kill_pct", 3.0)):
            breaches.append(f"daily_drawdown_exceeded:{daily_dd_pct:.2f}%")
        if cooldown_active:
            breaches.append("cooldown_active")

        block_new = bool(cfg.get("block_new_starts_when_breached", True))
        allow_new_starts = not (block_new and len(breaches) > 0)

        result["snapshot"] = {
            "running_strategies": running,
            "account_balance": balance,
            "account_equity": float(account.equity),
            "allocated_capital": total_alloc,
            "portfolio_heat_usd": heat_usd,
            "portfolio_heat_pct": heat_pct,
            "options_open_risk_usd": float(options_open_risk_usd),
            "long_lots": long_lots,
            "short_lots": short_lots,
            "directional_exposure_lots": directional_exposure_lots,
            "daily_drawdown_pct": daily_dd_pct,
        }
        result["breaches"] = breaches
        result["allow_new_starts"] = allow_new_starts

        if breaches:
            result["status"] = "breached"
            state["status"] = "breached"
            state["last_breach_time"] = now.isoformat()
            state["last_breach_reasons"] = breaches
            cooldown_minutes = int(cfg.get("cooldown_minutes", 60))
            state["cooldown_until"] = (now + timedelta(minutes=max(1, cooldown_minutes))).isoformat()
            if enforce and bool(cfg.get("auto_stop_all_on_breach", True)):
                for sid in running:
                    stop_res = self.stop_strategy(sid)
                    result["enforced_actions"].append({
                        "strategy_id": sid,
                        "action": "stop",
                        "result": stop_res,
                    })
        else:
            result["status"] = "ok"
            state["status"] = "ok"
            state["last_breach_reasons"] = []
            state["cooldown_until"] = None

        state["allow_new_starts"] = allow_new_starts
        state["last_snapshot"] = result["snapshot"]
        self._save_portfolio_governor_state(state)
        result["state"] = state
        return result

    def clear_portfolio_governor_cooldown(self) -> Dict[str, Any]:
        state = self._get_portfolio_governor_state()
        state["cooldown_until"] = None
        state["status"] = "ok"
        state["allow_new_starts"] = True
        self._save_portfolio_governor_state(state)
        return state

    def _ensure_directory(self):
        """Ensure state directory exists"""
        self.state_file.parent.mkdir(parents=True, exist_ok=True)

    def _ensure_mt5(self) -> bool:
        """Initialize MT5 connection if not already done (thread-safe)"""
        if not HAS_MT5:
            return False

        if self._mt5_initialized:
            return True

        with self._lock:
            # Double-check after acquiring lock
            if self._mt5_initialized:
                return True

            if not mt5.initialize():
                return False

            self._mt5_initialized = True
            return True

    def get_account_balance(self) -> Optional[float]:
        """Get current MT5 account balance"""
        if not self._ensure_mt5():
            return None

        account = mt5.account_info()
        if account is None:
            return None

        return account.balance

    def get_allocated_capital(self) -> Dict[str, float]:
        """
        Get capital allocated to each running strategy.

        Returns:
            Dict mapping strategy_id to allocated capital
        """
        allocations = {}

        for strategy_id in STRATEGY_PATHS:
            if self._is_process_running(strategy_id):
                config = self.get_strategy_config(strategy_id)
                if config:
                    allocations[strategy_id] = config.get("initial_balance", 0)

        # Cross-system conservative proxy:
        # map open options journal risk into allocation ledger so new starts
        # cannot silently exceed combined account risk.
        options_open_risk_usd = self._get_options_journal_open_risk_usd()
        if options_open_risk_usd > 0:
            allocations["options_edge_manual"] = float(options_open_risk_usd)

        return allocations

    def _get_options_journal_open_risk_usd(self) -> float:
        """
        Sum open options-edge journal risk as a conservative risk proxy.

        Uses:
            max_loss * contracts for rows with status='OPEN'
        """
        try:
            if not _DASHBOARD_DB_PATH.exists():
                return 0.0
            conn = sqlite3.connect(str(_DASHBOARD_DB_PATH))
            cur = conn.cursor()
            cur.execute(
                """
                SELECT COALESCE(SUM(COALESCE(max_loss, 0) * COALESCE(contracts, 1)), 0)
                FROM options_trade_journal
                WHERE UPPER(COALESCE(status, '')) = 'OPEN'
                """
            )
            row = cur.fetchone()
            conn.close()
            if not row:
                return 0.0
            return max(0.0, float(row[0] or 0.0))
        except Exception:
            return 0.0

    def get_total_allocated_capital(self) -> float:
        """Get total capital allocated to all running strategies"""
        allocations = self.get_allocated_capital()
        return sum(allocations.values())

    def get_available_capital(self) -> Optional[float]:
        """
        Get capital available for new strategy allocation.

        Returns:
            Available capital or None if MT5 not connected
        """
        account_balance = self.get_account_balance()
        if account_balance is None:
            return None

        allocated = self.get_total_allocated_capital()
        return account_balance - allocated

    def validate_capital_allocation(self, strategy_id: str, requested_capital: float) -> Dict[str, Any]:
        """
        Validate if requested capital can be allocated.

        Args:
            strategy_id: Strategy requesting capital
            requested_capital: Amount of capital requested

        Returns:
            Dict with 'valid' bool and 'message' str
        """
        account_balance = self.get_account_balance()

        if account_balance is None:
            # Can't validate without MT5, allow but warn
            return {
                "valid": True,
                "warning": "Could not verify account balance (MT5 not connected). Proceeding without validation."
            }

        # Get capital already allocated to OTHER running strategies
        allocations = self.get_allocated_capital()

        # Remove current strategy from allocations (in case of restart)
        other_allocated = sum(
            capital for sid, capital in allocations.items()
            if sid != strategy_id
        )

        total_if_allocated = other_allocated + requested_capital
        available = account_balance - other_allocated

        if total_if_allocated > account_balance:
            return {
                "valid": False,
                "message": (
                    f"Insufficient capital! "
                    f"Account balance: ${account_balance:.2f}, "
                    f"Already allocated: ${other_allocated:.2f}, "
                    f"Available: ${available:.2f}, "
                    f"Requested: ${requested_capital:.2f}. "
                    f"Maximum you can allocate: ${available:.2f}"
                ),
                "account_balance": account_balance,
                "already_allocated": other_allocated,
                "available": available,
                "requested": requested_capital
            }

        return {
            "valid": True,
            "message": f"Capital allocation valid. Using ${requested_capital:.2f} of ${available:.2f} available.",
            "account_balance": account_balance,
            "already_allocated": other_allocated,
            "available": available,
            "remaining_after": available - requested_capital
        }

    def get_available_strategies(self) -> List[Dict[str, Any]]:
        """
        Get list of all available strategies with their info.

        Returns:
            List of strategy info dicts
        """
        # Import strategies to register them
        self._import_strategies()

        strategies = []
        for info in StrategyRegistry.list_all():
            strategies.append({
                "id": info.id,
                "name": info.name,
                "description": info.description,
                "version": info.version,
                "author": info.author,
                "timeframes": info.timeframes,
                "symbols": info.symbols,
                "parameters": info.parameters,
                "status": self.get_strategy_status(info.id),
            })

        return strategies

    def _import_strategies(self):
        """Import all strategy modules to register them"""
        strategy_imports = [
            ("Strategies.ORBStrategy", "GoldORBStrategy"),
            ("Strategies.AdvancedORBStrategy", "AdvancedGoldORBStrategy"),
            ("Strategies.MACDEMAStrategy", "MACDEMALiveStrategy"),
            ("Strategies.BassoStrategy", "BassoLiveStrategy"),
            ("Strategies.ConfluenceZoneStrategy", "ConfluenceZoneLiveStrategy"),
            ("Strategies.LiquiditySweepStrategy", "LiquiditySweepLiveStrategy"),
            ("Strategies.VWAPReversionStrategy", "VWAPReversionLiveStrategy"),
            ("Strategies.KeltnerBreakoutStrategy", "KeltnerBreakoutLiveStrategy"),
            ("Strategies.BBSqueezeStrategy", "BBSqueezeLiveStrategy"),
        ]

        for module_path, class_name in strategy_imports:
            try:
                __import__(module_path, fromlist=[class_name])
            except ImportError:
                pass

    def start_strategy(self, strategy_id: str, config: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        """
        Start a strategy in a new process.

        Args:
            strategy_id: ID of the strategy to start
            config: Optional runtime configuration

        Returns:
            dict with status and message
        """
        # Check if already running
        if self._is_process_running(strategy_id):
            return {
                "success": False,
                "message": f"Strategy {strategy_id} is already running"
            }

        # Portfolio-level governor check
        try:
            gov = self.evaluate_portfolio_governor(enforce=False)
            if not gov.get("allow_new_starts", True):
                return {
                    "success": False,
                    "message": "Portfolio risk governor blocked new strategy start",
                    "governor": gov,
                }
        except Exception:
            pass

        # Validate capital allocation if config specifies initial_balance
        if config and "initial_balance" in config:
            requested_capital = config["initial_balance"]
            validation = self.validate_capital_allocation(strategy_id, requested_capital)

            if not validation.get("valid"):
                return {
                    "success": False,
                    "message": validation.get("message", "Capital allocation validation failed"),
                    "validation": validation
                }

            # Log warning if validation couldn't be performed
            if validation.get("warning"):
                print(f"[WARNING] {validation['warning']}")

        # Save config if provided
        if config:
            self.save_strategy_config(strategy_id, config)

        # Clear any stale state
        self._update_strategy_state(strategy_id, {
            "status": "starting",
            "pid": None,
            "error": None
        })

        # Get strategy entry point
        strategy_path = self._get_strategy_main_path(strategy_id)

        if not strategy_path or not os.path.exists(strategy_path):
            return {
                "success": False,
                "message": f"Strategy {strategy_id} not found"
            }

        try:
            # Get project root for proper imports
            project_root = Path(__file__).parent.parent

            # Prepare environment with PYTHONPATH
            env = os.environ.copy()
            env['PYTHONPATH'] = str(project_root) + os.pathsep + env.get('PYTHONPATH', '')

            if sys.platform == 'win32':
                # On Windows, use CREATE_NEW_CONSOLE without stdout capture
                # This allows the console to show output properly
                process = subprocess.Popen(
                    [sys.executable, strategy_path],
                    cwd=str(project_root),  # Run from project root for imports
                    env=env,
                    creationflags=subprocess.CREATE_NEW_CONSOLE,
                )
            else:
                # On Unix, run in background
                process = subprocess.Popen(
                    [sys.executable, strategy_path],
                    cwd=str(project_root),
                    env=env,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                )

            with self._lock:
                self._running_processes[strategy_id] = process

            # Update state
            self._update_strategy_state(strategy_id, {
                "status": "running",
                "pid": process.pid,
                "started_at": datetime.now().isoformat(),
            })

            return {
                "success": True,
                "message": f"Strategy {strategy_id} started",
                "pid": process.pid
            }

        except Exception as e:
            import traceback
            return {
                "success": False,
                "message": f"Failed to start strategy: {str(e)}\n{traceback.format_exc()}"
            }

    def stop_strategy(self, strategy_id: str) -> Dict[str, Any]:
        """
        Stop a running strategy.

        Args:
            strategy_id: ID of the strategy to stop

        Returns:
            dict with status and message
        """
        with self._lock:
            process = self._running_processes.get(strategy_id)

        if not process:
            # Try to find by reading state file
            state = self._read_strategy_state(strategy_id)
            candidate_pids = []
            if state and state.get("pid"):
                try:
                    candidate_pids.append(int(state["pid"]))
                except Exception:
                    pass

            # Recovery path: if pid is missing/stale, scan processes by command line.
            if not candidate_pids:
                candidate_pids = self._find_strategy_pids(strategy_id)

            if candidate_pids:
                alive_before = [pid for pid in candidate_pids if self._is_pid_running(pid)]
                if not alive_before:
                    self._update_strategy_state(strategy_id, {
                        "status": "stopped",
                        "pid": None
                    })
                    self._clear_bot_state(strategy_id)
                    return {
                        "success": True,
                        "message": f"Strategy {strategy_id} was not running"
                    }

                for pid in alive_before:
                    self._kill_pid(pid)

                # Verify termination before reporting success
                still_alive = [pid for pid in alive_before if self._is_pid_running(pid)]
                if still_alive:
                    return {
                        "success": False,
                        "message": f"Failed to stop strategy {strategy_id}; still running PIDs: {still_alive}"
                    }

                self._update_strategy_state(strategy_id, {
                    "status": "stopped",
                    "stopped_at": datetime.now().isoformat(),
                    "pid": None
                })
                self._clear_bot_state(strategy_id)
                return {
                    "success": True,
                    "message": f"Strategy {strategy_id} stopped"
                }

            # Not running
            self._update_strategy_state(strategy_id, {"status": "stopped", "pid": None})
            self._clear_bot_state(strategy_id)
            return {
                "success": True,
                "message": f"Strategy {strategy_id} is not running"
            }

        try:
            process.terminate()
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
        except Exception as e:
            return {
                "success": False,
                "message": f"Failed to stop strategy: {str(e)}"
            }

        with self._lock:
            if strategy_id in self._running_processes:
                del self._running_processes[strategy_id]

        state = self._read_strategy_state(strategy_id) or {}
        pid = state.get("pid")
        if pid and self._is_pid_running(int(pid)):
            return {
                "success": False,
                "message": f"Failed to stop strategy {strategy_id}; PID {pid} is still running"
            }

        self._update_strategy_state(strategy_id, {
            "status": "stopped",
            "stopped_at": datetime.now().isoformat(),
            "pid": None
        })

        # Clear bot state file to prevent stale status
        self._clear_bot_state(strategy_id)

        return {
            "success": True,
            "message": f"Strategy {strategy_id} stopped"
        }

    def get_strategy_status(self, strategy_id: str) -> str:
        """Get status of a strategy"""
        # First check process running status
        if self._is_process_running(strategy_id):
            return "running"

        # Check bot state file (written by the strategy itself)
        bot_state = self._read_bot_state(strategy_id)
        if bot_state and bot_state.get("is_running"):
            # Verify the bot state is fresh (within 30 seconds)
            last_update = bot_state.get("last_update")
            if last_update:
                try:
                    last_update_dt = datetime.fromisoformat(last_update)
                    age = (datetime.now() - last_update_dt).total_seconds()
                    if age < 30:
                        return "running"
                except:
                    pass

        # Fall back to manager state
        state = self._read_strategy_state(strategy_id)
        if state:
            return state.get("status", "stopped")

        return "stopped"

    def get_strategy_state(self, strategy_id: str) -> Dict[str, Any]:
        """Get full state of a strategy"""
        # First check bot state file (written by strategy itself)
        bot_state = self._read_bot_state(strategy_id)
        if bot_state:
            return bot_state

        # Fall back to manager state
        return self._read_strategy_state(strategy_id) or {
            "status": "stopped",
            "strategy_id": strategy_id,
        }

    def _is_process_running(self, strategy_id: str) -> bool:
        """Check if a strategy process is running"""
        # First check in-memory process
        process = self._running_processes.get(strategy_id)
        if process:
            if process.poll() is None:
                return True
            else:
                # Process ended, clean up
                del self._running_processes[strategy_id]

        # Check by PID from state file (handles restarts and different instances)
        state = self._read_strategy_state(strategy_id)
        if state and state.get("pid") and state.get("status") == "running":
            try:
                pid = state["pid"]
                # On Windows, os.kill(pid, 0) checks if process exists
                if sys.platform == 'win32':
                    import ctypes
                    kernel32 = ctypes.windll.kernel32
                    PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
                    handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
                    if handle:
                        kernel32.CloseHandle(handle)
                        return True
                    return False
                else:
                    os.kill(pid, 0)
                    return True
            except (ProcessLookupError, PermissionError, OSError):
                # Process not running, update state
                self._update_strategy_state(strategy_id, {"status": "stopped"})
                return False

        return False

    def _is_pid_running(self, pid: int) -> bool:
        """Check whether a PID exists."""
        try:
            pid = int(pid)
        except Exception:
            return False

        if pid <= 0:
            return False

        try:
            if sys.platform == 'win32':
                import ctypes
                kernel32 = ctypes.windll.kernel32
                PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
                handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, pid)
                if handle:
                    kernel32.CloseHandle(handle)
                    return True
                return False
            os.kill(pid, 0)
            return True
        except Exception:
            return False

    def _kill_pid(self, pid: int) -> bool:
        """Terminate PID and return True if process is no longer alive."""
        try:
            pid = int(pid)
        except Exception:
            return True

        if not self._is_pid_running(pid):
            return True

        try:
            if sys.platform == 'win32':
                # /T kills child process tree as well.
                result = subprocess.run(
                    ['taskkill', '/PID', str(pid), '/T', '/F'],
                    capture_output=True,
                    text=True,
                    timeout=8
                )
                if result.returncode != 0:
                    return not self._is_pid_running(pid)
                return True
            import signal
            os.kill(pid, signal.SIGTERM)
            return not self._is_pid_running(pid)
        except Exception:
            return not self._is_pid_running(pid)

    def _find_strategy_pids(self, strategy_id: str) -> List[int]:
        """
        Find running strategy process PIDs by matching strategy main.py in command line.
        Useful when manager state lost PID.
        """
        strategy_main = self._get_strategy_main_path(strategy_id)
        if not strategy_main or sys.platform != 'win32':
            return []

        needle = str(strategy_main).replace("'", "''")
        ps_cmd = (
            f"$needle='{needle}'; "
            "Get-CimInstance Win32_Process | "
            "Where-Object { $_.CommandLine -and $_.CommandLine.Contains($needle) } | "
            "Select-Object -ExpandProperty ProcessId"
        )
        try:
            result = subprocess.run(
                ["powershell", "-NoProfile", "-Command", ps_cmd],
                capture_output=True,
                text=True,
                timeout=8,
            )
            if result.returncode != 0:
                return []
            pids = []
            for line in (result.stdout or "").splitlines():
                line = line.strip()
                if line.isdigit():
                    pids.append(int(line))
            return pids
        except Exception:
            return []

    def _get_strategy_main_path(self, strategy_id: str) -> Optional[str]:
        """Get path to strategy's main.py"""
        entry = STRATEGY_PATHS.get(strategy_id)
        if entry:
            return str(entry["main"])
        return ""

    def _read_strategy_state(self, strategy_id: str) -> Optional[Dict[str, Any]]:
        """Read strategy state from manager state file (thread-safe)"""
        with self._lock:
            try:
                if self.state_file.exists():
                    with open(self.state_file, 'r') as f:
                        all_states = json.load(f)
                        return all_states.get(strategy_id)
            except Exception:
                pass
            return None

    def _update_strategy_state(self, strategy_id: str, state: Dict[str, Any]):
        """Update strategy state in manager state file (thread-safe)"""
        with self._lock:
            try:
                all_states = {}
                if self.state_file.exists():
                    with open(self.state_file, 'r') as f:
                        all_states = json.load(f)

                if strategy_id not in all_states:
                    all_states[strategy_id] = {}

                all_states[strategy_id].update(state)
                all_states[strategy_id]["last_update"] = datetime.now().isoformat()

                with open(self.state_file, 'w') as f:
                    json.dump(all_states, f, indent=2)
            except Exception:
                pass

    def _read_bot_state(self, strategy_id: str) -> Optional[Dict[str, Any]]:
        """Read bot state file written by the strategy itself"""
        entry = STRATEGY_PATHS.get(strategy_id)
        if not entry:
            return None

        state_file = entry["state"]
        if state_file and state_file.exists():
            try:
                with open(state_file, 'r') as f:
                    state = json.load(f)
                    state["strategy_id"] = strategy_id
                    return state
            except Exception:
                pass

        return None

    def _clear_bot_state(self, strategy_id: str):
        """Clear bot state file to mark strategy as stopped"""
        entry = STRATEGY_PATHS.get(strategy_id)
        if not entry:
            return

        state_file = entry["state"]
        if state_file and state_file.exists():
            try:
                with open(state_file, 'r') as f:
                    state = json.load(f)

                # Mark as not running
                state["is_running"] = False
                state["is_connected"] = False
                state["status"] = "stopped"
                state["last_update"] = datetime.now().isoformat()

                with open(state_file, 'w') as f:
                    json.dump(state, f, indent=2)
            except Exception:
                pass

    def save_strategy_config(self, strategy_id: str, config: Dict[str, Any]):
        """Save runtime configuration for a strategy"""
        config_file = Path(__file__).parent.parent / "dashboard" / "data" / f"{strategy_id}_config.json"

        try:
            config_file.parent.mkdir(parents=True, exist_ok=True)
            with open(config_file, 'w') as f:
                json.dump(config, f, indent=2)
        except Exception as e:
            print(f"Error saving config: {e}")

    def get_strategy_config(self, strategy_id: str) -> Optional[Dict[str, Any]]:
        """Get saved runtime configuration for a strategy"""
        config_file = Path(__file__).parent.parent / "dashboard" / "data" / f"{strategy_id}_config.json"

        if config_file.exists():
            try:
                with open(config_file, 'r') as f:
                    return json.load(f)
            except Exception:
                pass

        return None

    def get_all_running(self) -> List[str]:
        """Get list of all running strategy IDs"""
        running = []
        for strategy_id in STRATEGY_PATHS:
            if self._is_process_running(strategy_id):
                running.append(strategy_id)
        return running
