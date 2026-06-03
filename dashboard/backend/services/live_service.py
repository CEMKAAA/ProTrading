"""
Live Trading Service - Interface with the running bot and MT5
"""

import MetaTrader5 as mt5
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List, Set
from pathlib import Path
import json
import re
import time
import pytz
import logging

logger = logging.getLogger(__name__)


def _to_float_or_none(v: Any) -> Optional[float]:
    try:
        if v is None:
            return None
        x = float(v)
        if x != x:
            return None
        return x
    except Exception:
        return None

# Bot state file locations for all strategies
BOT_STATE_FILES = {
    "orb_strategy": Path(__file__).parent.parent.parent / "data" / "bot_state.json",
    "advanced_orb_strategy": Path(__file__).parent.parent.parent / "data" / "advanced_orb_state.json",
    "orb_ml_strategy": Path(__file__).parent.parent.parent / "data" / "orb_ml_state.json",
    "advanced_orb_ml_strategy": Path(__file__).parent.parent.parent / "data" / "advanced_orb_ml_state.json",
    "liquidity_sweep_strategy": Path(__file__).parent.parent.parent / "data" / "liquidity_sweep_state.json",
    "keltner_breakout_strategy": Path(__file__).parent.parent.parent / "data" / "keltner_breakout_state.json",
    "htf_fvg_liquidity_reclaim_strategy": Path(__file__).parent.parent.parent / "data" / "htf_fvg_liquidity_reclaim_strategy_state.json",
    "trendilo_strategy": Path(__file__).parent.parent.parent / "data" / "trendilo_strategy_state.json",
}


class LiveTradingService:
    """Service for interacting with live trading and MT5"""

    _GLOBAL_SYMBOL_FILLING_MODE_CACHE: Dict[str, int] = {}
    _GLOBAL_SYMBOL_INVALID_FILLING_MODES: Dict[str, Set[int]] = {}

    def __init__(self):
        self.ny_tz = pytz.timezone('America/New_York')
        self._mt5_initialized = False
        self._symbols_cache: List[Dict[str, Any]] = []
        self._symbols_cache_ts: float = 0.0
        self._resolved_symbol_cache: Dict[str, Dict[str, Any]] = {}
        self._resolved_symbol_cache_ttl_sec: float = 30.0
        self._last_symbols_error: str = ""
        self._last_mt5_warn_msg: str = ""
        self._last_mt5_warn_ts: float = 0.0
        # Shared across service instances in the same backend process. MT5 symbols often
        # reject some filling modes; retrying known-bad modes on every order is noisy and slow.
        self._symbol_filling_mode_cache = LiveTradingService._GLOBAL_SYMBOL_FILLING_MODE_CACHE
        self._symbol_invalid_filling_modes = LiveTradingService._GLOBAL_SYMBOL_INVALID_FILLING_MODES

    def _warn_mt5_unavailable(self, err: Any) -> None:
        msg = str(err)
        now_ts = time.time()
        if msg != self._last_mt5_warn_msg or (now_ts - float(self._last_mt5_warn_ts)) >= 30.0:
            logger.warning("MT5 not available: %s", msg)
            self._last_mt5_warn_msg = msg
            self._last_mt5_warn_ts = now_ts

    @staticmethod
    def _extract_strategy_diagnostics(state: Optional[Dict[str, Any]]) -> Dict[str, Any]:
        if not isinstance(state, dict):
            return {}
        keys = [
            "strategy_preset",
            "base_symbol",
            "timeframe",
            "bias",
            "bias_strength",
            "setup_detected",
            "fvg_detected",
            "fvg_quality",
            "sweep_detected",
            "sweep_quality",
            "rejection_confirmed",
            "entry_price",
            "stop_loss",
            "take_profit",
            "rr",
            "invalidation_reason",
            "last_signal",
        ]
        out: Dict[str, Any] = {}
        for key in keys:
            if key in state and state.get(key) is not None:
                out[str(key)] = state.get(key)
        return out

    def _reset_mt5(self) -> None:
        try:
            mt5.shutdown()
        except Exception:
            pass
        self._mt5_initialized = False

    def _ensure_mt5(self, *, force_reconnect: bool = False) -> bool:
        """Ensure MT5 is initialized"""
        if force_reconnect:
            self._reset_mt5()

        if self._mt5_initialized:
            try:
                terminal_info = mt5.terminal_info()
                if terminal_info is not None and bool(getattr(terminal_info, "connected", True)):
                    return True
            except Exception:
                pass
            self._reset_mt5()

        if not mt5.initialize():
            self._warn_mt5_unavailable(mt5.last_error())
            return False

        self._mt5_initialized = True
        return True

    @staticmethod
    def _symbol_token(v: Any) -> str:
        return re.sub(r"[^A-Za-z0-9]", "", str(v or "")).upper()

    def list_symbols(
        self,
        search: str = "",
        limit: int = 500,
        include_hidden: bool = True,
        refresh: bool = False,
    ) -> List[Dict[str, Any]]:
        """List broker symbols from currently connected MT5 terminal."""
        self._last_symbols_error = ""
        if not self._ensure_mt5():
            self._last_symbols_error = f"MT5 initialize failed: {mt5.last_error()}"
            return []
        now = time.time()
        if (not refresh) and self._symbols_cache and (now - self._symbols_cache_ts) < 10.0:
            rows = list(self._symbols_cache)
        else:
            raw = mt5.symbols_get()
            if not raw:
                logger.warning("MT5 symbols_get returned no symbols; retrying after fresh initialize")
                if self._ensure_mt5(force_reconnect=True):
                    raw = mt5.symbols_get()
            if not raw:
                terminal_info = None
                try:
                    terminal_info = mt5.terminal_info()
                except Exception:
                    terminal_info = None
                connected = bool(getattr(terminal_info, "connected", False)) if terminal_info is not None else False
                self._last_symbols_error = (
                    f"MT5 symbol catalog unavailable (connected={connected}, last_error={mt5.last_error()})"
                )
                logger.warning(self._last_symbols_error)
                self._symbols_cache = []
                self._symbols_cache_ts = 0.0
                self._resolved_symbol_cache = {}
                return []
            rows = []
            for s in raw:
                name = str(getattr(s, "name", "") or "").strip()
                if not name:
                    continue
                visible = bool(getattr(s, "visible", False))
                if (not include_hidden) and (not visible):
                    continue
                rows.append(
                    {
                        "name": name,
                        "description": str(getattr(s, "description", "") or "").strip(),
                        "path": str(getattr(s, "path", "") or "").strip(),
                        "visible": visible,
                        "digits": int(getattr(s, "digits", 0) or 0),
                        "point": float(getattr(s, "point", 0.0) or 0.0),
                        "trade_mode": int(getattr(s, "trade_mode", 0) or 0),
                        "spread": int(getattr(s, "spread", 0) or 0),
                    }
                )
            rows.sort(key=lambda r: (0 if bool(r.get("visible")) else 1, str(r.get("name") or "")))
            self._symbols_cache = list(rows)
            self._symbols_cache_ts = now
            # Symbol universe changed; reset alias-resolution cache.
            self._resolved_symbol_cache = {}
        q = str(search or "").strip().upper()
        if q:
            rows = [
                r
                for r in rows
                if q in str(r.get("name") or "").upper()
                or q in str(r.get("description") or "").upper()
            ]
        lim = max(1, min(int(limit or 500), 5000))
        return rows[:lim]

    def resolve_symbol_name(self, symbol: str) -> Optional[str]:
        """
        Resolve user symbol to an actual broker symbol.

        Handles common broker suffix/prefix variants like XAUUSDm, XAUUSD.r, etc.
        """
        req_raw = str(symbol or "").strip()
        if not req_raw:
            return None
        req_u = req_raw.upper()
        req_tok = self._symbol_token(req_u)
        if not req_tok:
            return None

        now = time.time()
        cached = self._resolved_symbol_cache.get(req_tok)
        if isinstance(cached, dict):
            age = float(now - float(cached.get("ts") or 0.0))
            cached_name = str(cached.get("name") or "").strip()
            if cached_name and age <= float(self._resolved_symbol_cache_ttl_sec):
                return cached_name

        rows = self.list_symbols(limit=5000, include_hidden=True, refresh=False)
        if not rows:
            return req_u

        # Exact name match first.
        for r in rows:
            n = str(r.get("name") or "").strip()
            if n.upper() == req_u:
                if not bool(r.get("visible", False)):
                    try:
                        mt5.symbol_select(n, True)
                    except Exception:
                        pass
                self._resolved_symbol_cache[req_tok] = {"name": n, "ts": now}
                return n

        best_name: Optional[str] = None
        best_score: Optional[tuple] = None
        for r in rows:
            n = str(r.get("name") or "").strip()
            if not n:
                continue
            nu = n.upper()
            nt = self._symbol_token(nu)
            if not nt:
                continue
            score = None
            if nt == req_tok:
                score = (0, 0, len(n))
            elif nu.startswith(req_u):
                # e.g. XAUUSDm for XAUUSD
                score = (1, len(nu) - len(req_u), len(n))
            elif nt.startswith(req_tok):
                # e.g. XAUUSD.r where token still starts with XAUUSD
                score = (2, len(nt) - len(req_tok), len(n))
            elif req_tok in nt:
                score = (3, nt.find(req_tok), len(n))
            if score is None:
                continue
            visibility_penalty = 0 if bool(r.get("visible", False)) else 1
            score_full = (score[0], visibility_penalty, score[1], score[2])
            if best_score is None or score_full < best_score:
                best_score = score_full
                best_name = n

        if best_name:
            try:
                mt5.symbol_select(best_name, True)
            except Exception:
                pass
            self._resolved_symbol_cache[req_tok] = {"name": best_name, "ts": now}
            return best_name
        return None

    def _read_single_bot_state(self, state_file: Path) -> Dict[str, Any]:
        """Read a single bot state file"""
        try:
            if state_file.exists():
                with open(state_file, 'r') as f:
                    state = json.load(f)

                # Check if state is stale (more than 15 seconds old)
                if state.get("last_update"):
                    last_update = datetime.fromisoformat(state["last_update"])
                    age = (datetime.now() - last_update).total_seconds()
                    if age > 15:
                        state["is_connected"] = False
                        state["is_running"] = False
                        state["error_message"] = f"Bot state stale ({int(age)}s old)"

                return state
        except Exception as e:
            logger.debug(f"Could not read bot state from {state_file}: {e}")

        return None

    def _read_bot_state(self) -> Dict[str, Any]:
        """Read bot state from all strategy files, return first running one"""
        for strategy_id, state_file in BOT_STATE_FILES.items():
            state = self._read_single_bot_state(state_file)
            if state and state.get("is_running") and state.get("is_connected"):
                state["active_strategy"] = strategy_id
                return state

        # No running strategy found, return None
        return None

    def get_all_running_strategies(self) -> List[Dict[str, Any]]:
        """Get state of all running strategies"""
        running = []
        for strategy_id, state_file in BOT_STATE_FILES.items():
            state = self._read_single_bot_state(state_file)
            if state and state.get("is_running") and state.get("is_connected"):
                state["strategy_id"] = strategy_id
                running.append(state)
        return running

    def get_status(self, symbol: str = "XAUUSD") -> Dict[str, Any]:
        """Get current live trading status"""
        symbol_req = str(symbol or "XAUUSD").upper()
        default_status = {
            "is_connected": False,  # True only when a bot is running
            "is_trading": False,
            "is_running": False,
            "mt5_available": False,  # True when MT5 terminal is connected
            "symbol_requested": symbol_req,
            "symbol_resolved": None,
            "active_strategy": None,
            "current_time_ny": None,
            "current_price": None,
            "spread": None,
            "session_bias": None,
            "is_trending": False,
            "orb_high": None,
            "orb_low": None,
            "asian_high": None,
            "asian_low": None,
            "daily_trades": 0,
            "daily_pnl": 0.0,
            "can_trade": False,
            "balance": 0.0,
            "equity": 0.0,
            "margin_level": None,
            "strategy_diagnostics": {},
            "running_strategies": [],
        }

        # Check all running strategies
        running_strategies = self.get_all_running_strategies()
        default_status["running_strategies"] = running_strategies

        # First try to read from bot state file (preferred - has full bot context)
        bot_state = self._read_bot_state()
        if bot_state and bot_state.get("is_connected") and bot_state.get("is_running"):
            # Use bot state - it has session data, bias, etc.
            return {
                "is_connected": True,
                "is_running": True,
                "mt5_available": True,
                "is_trading": bot_state.get("is_trading", False),
                "symbol_requested": symbol_req,
                "symbol_resolved": bot_state.get("symbol") or bot_state.get("base_symbol") or symbol_req,
                "active_strategy": bot_state.get("active_strategy"),
                "current_time_ny": bot_state.get("current_time_ny"),
                "current_price": bot_state.get("current_price"),
                "spread": bot_state.get("spread"),
                "session_bias": bot_state.get("session_bias"),
                "is_trending": bot_state.get("is_trending", False),
                "orb_high": bot_state.get("orb_high"),
                "orb_low": bot_state.get("orb_low"),
                "asian_high": bot_state.get("asian_high"),
                "asian_low": bot_state.get("asian_low"),
                "daily_trades": bot_state.get("daily_trades", 0),
                "daily_pnl": bot_state.get("daily_pnl", 0.0),
                "can_trade": bot_state.get("can_trade", False),
                "balance": bot_state.get("balance", 0.0),
                "equity": bot_state.get("equity", 0.0),
                "margin_level": bot_state.get("margin_level"),
                "strategy_diagnostics": self._extract_strategy_diagnostics(bot_state),
                "running_strategies": running_strategies,
            }

        # Fallback: try direct MT5 connection (for when bot is not running)
        # Note: is_connected stays False because no bot is running
        if not self._ensure_mt5():
            return default_status

        try:
            resolved_symbol = self.resolve_symbol_name(symbol_req)
            default_status["symbol_resolved"] = resolved_symbol
            if not resolved_symbol:
                return default_status

            # Connection status - MT5 terminal is available but no bot running
            terminal_info = mt5.terminal_info()
            if terminal_info is None:
                return default_status

            # Only set mt5_available, NOT is_connected (that's for when bot is running)
            default_status["mt5_available"] = terminal_info.connected

            if not terminal_info.connected:
                return default_status

            # Get tick data
            tick = mt5.symbol_info_tick(resolved_symbol)
            if tick:
                default_status["current_price"] = tick.bid
                default_status["spread"] = round(tick.ask - tick.bid, 3)

                # Convert broker time to NY
                broker_time = datetime.fromtimestamp(tick.time, tz=timezone.utc)
                default_status["current_time_ny"] = broker_time.isoformat()

            # Account info
            account = mt5.account_info()
            if account:
                default_status["balance"] = round(account.balance, 2)
                default_status["equity"] = round(account.equity, 2)
                if account.margin > 0:
                    default_status["margin_level"] = round(account.equity / account.margin * 100, 2)

            # Check open positions
            positions = mt5.positions_get(symbol=resolved_symbol)
            if positions:
                default_status["is_trading"] = True

            return default_status

        except Exception as e:
            logger.error(f"Error getting live status: {e}")
            return default_status

    def get_open_positions(self, symbol: Optional[str] = "XAUUSD") -> List[Dict[str, Any]]:
        """Get open positions (symbol-filtered when symbol is provided)."""
        if not self._ensure_mt5():
            return []

        try:
            symbol_raw = str(symbol or "").strip()
            symbol_resolved: Optional[str] = None
            if symbol_raw:
                symbol_req = symbol_raw.upper()
                symbol_resolved = self.resolve_symbol_name(symbol_req)
                if not symbol_resolved:
                    return []
                positions = mt5.positions_get(symbol=symbol_resolved)
            else:
                positions = mt5.positions_get()
            if not positions:
                return []

            result = []
            tick_cache: Dict[str, Any] = {}
            for pos in positions:
                pos_symbol = str(getattr(pos, "symbol", "") or "").strip() or str(symbol_resolved or "")
                tick = None
                if pos_symbol:
                    if pos_symbol not in tick_cache:
                        tick_cache[pos_symbol] = mt5.symbol_info_tick(pos_symbol)
                    tick = tick_cache.get(pos_symbol)
                if tick:
                    current_price = tick.bid if pos.type == 0 else tick.ask
                else:
                    current_price = pos.price_current

                result.append({
                    "ticket": pos.ticket,
                    "direction": "BUY" if pos.type == 0 else "SELL",
                    "symbol": pos_symbol,
                    "entry_time": datetime.fromtimestamp(pos.time, tz=timezone.utc).isoformat(),
                    "entry_price": pos.price_open,
                    "current_price": current_price,
                    "stop_loss": pos.sl,
                    "take_profit": pos.tp,
                    "lot_size": pos.volume,
                    "profit_loss": pos.profit,
                    "swap": pos.swap,
                    "magic": pos.magic,
                    "comment": pos.comment,
                })

            return result

        except Exception as e:
            logger.error(f"Error getting positions: {e}")
            return []

    def get_account_info(self) -> Dict[str, Any]:
        """Get detailed account information"""
        if not self._ensure_mt5():
            return {"error": "MT5 not connected"}

        try:
            account = mt5.account_info()
            if not account:
                return {"error": "Could not get account info"}

            return {
                "login": account.login,
                "server": account.server,
                "name": account.name,
                "currency": account.currency,
                "balance": account.balance,
                "equity": account.equity,
                "margin": account.margin,
                "margin_free": account.margin_free,
                "margin_level": account.margin_level if account.margin > 0 else None,
                "profit": account.profit,
                "trade_allowed": account.trade_allowed,
                "leverage": account.leverage,
            }

        except Exception as e:
            logger.error(f"Error getting account info: {e}")
            return {"error": str(e)}

    def get_recent_deals(
        self,
        days: int = 1,
        symbol: Optional[str] = "XAUUSD",
        position_ticket: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        """
        Get recent deals.

        - When `symbol` is provided, results are filtered to resolved symbol.
        - When `symbol` is None/empty, returns deals across all symbols.
        - When `position_ticket` is provided, results are additionally filtered
          to matching MT5 position id.
        """
        if not self._ensure_mt5():
            return []

        try:
            from datetime import timedelta
            symbol_raw = str(symbol or "").strip()
            symbol_req = str(symbol_raw).upper() if symbol_raw else ""
            symbol_resolved = self.resolve_symbol_name(symbol_req) if symbol_req else None
            if symbol_req and (not symbol_resolved):
                return []
            wanted_pos = int(position_ticket) if position_ticket is not None else 0

            # Get deals from last N days
            to_time = datetime.now()
            from_time = to_time - timedelta(days=days)

            deals = mt5.history_deals_get(from_time, to_time)
            if not deals:
                return []

            result = []
            for deal in deals:
                d_symbol = str(deal.symbol or "").upper()
                if symbol_resolved and d_symbol != str(symbol_resolved).upper():
                    continue
                pos_id = int(getattr(deal, "position_id", 0) or 0)
                if wanted_pos > 0 and pos_id != wanted_pos:
                    continue
                entry_code = int(getattr(deal, "entry", 0) or 0)
                # MT5 deal.entry map: 0=IN, 1=OUT, 2=INOUT, 3=OUT_BY
                if entry_code == 0:
                    entry_name = "IN"
                elif entry_code == 1:
                    entry_name = "OUT"
                elif entry_code == 2:
                    entry_name = "INOUT"
                elif entry_code == 3:
                    entry_name = "OUT_BY"
                else:
                    entry_name = str(entry_code)

                result.append({
                    "ticket": deal.ticket,
                    "order": deal.order,
                    "position_id": pos_id,
                    "requested_symbol": symbol_req or d_symbol,
                    "symbol": d_symbol,
                    "time": datetime.fromtimestamp(deal.time, tz=timezone.utc).isoformat(),
                    "type": "BUY" if deal.type in [0, 2] else "SELL",
                    "entry": entry_name,
                    "entry_code": entry_code,
                    "price": deal.price,
                    "volume": deal.volume,
                    "profit": deal.profit,
                    "commission": deal.commission,
                    "swap": deal.swap,
                    "magic": deal.magic,
                    "comment": deal.comment,
                })

            return result

        except Exception as e:
            logger.error(f"Error getting deals: {e}")
            return []

    def get_position_deals(
        self,
        *,
        position_ticket: int,
        days: int = 14,
        symbol: Optional[str] = None,
    ) -> List[Dict[str, Any]]:
        """Convenience wrapper for position-id scoped deal history."""
        try:
            pos = int(position_ticket)
        except Exception:
            pos = 0
        if pos <= 0:
            return []
        return self.get_recent_deals(days=int(max(1, min(60, int(days or 14)))), symbol=symbol, position_ticket=pos)

    def get_symbol_info(self, symbol: str = "XAUUSD") -> Dict[str, Any]:
        """Get symbol information"""
        if not self._ensure_mt5():
            return {"error": "MT5 not connected"}

        try:
            symbol_req = str(symbol or "XAUUSD").upper()
            symbol_resolved = self.resolve_symbol_name(symbol_req)
            if not symbol_resolved:
                return {"error": f"Symbol {symbol_req} not found in broker symbol list"}
            info = mt5.symbol_info(symbol_resolved)
            if not info:
                return {"error": f"Symbol {symbol_resolved} not found"}

            return {
                "name": info.name,
                "requested_symbol": symbol_req,
                "resolved_symbol": symbol_resolved,
                "description": info.description,
                "point": info.point,
                "digits": info.digits,
                "spread": info.spread,
                "trade_tick_value": info.trade_tick_value,
                "trade_tick_value_profit": getattr(info, "trade_tick_value_profit", None),
                "trade_tick_value_loss": getattr(info, "trade_tick_value_loss", None),
                "trade_tick_size": getattr(info, "trade_tick_size", None),
                "trade_contract_size": getattr(info, "trade_contract_size", None),
                "volume_min": info.volume_min,
                "volume_max": info.volume_max,
                "volume_step": info.volume_step,
                "trade_stops_level": info.trade_stops_level,
                "trade_freeze_level": info.trade_freeze_level,
                "trade_calc_mode": getattr(info, "trade_calc_mode", None),
                "currency_base": getattr(info, "currency_base", None),
                "currency_profit": getattr(info, "currency_profit", None),
                "currency_margin": getattr(info, "currency_margin", None),
            }

        except Exception as e:
            logger.error(f"Error getting symbol info: {e}")
            return {"error": str(e)}

    def get_live_spread(self, symbol: str = "XAUUSD") -> Optional[float]:
        """Get current live spread in price units (ask - bid)."""
        if not self._ensure_mt5():
            return None
        try:
            symbol_req = str(symbol or "XAUUSD").upper()
            symbol_resolved = self.resolve_symbol_name(symbol_req)
            if not symbol_resolved:
                return None
            tick = mt5.symbol_info_tick(symbol_resolved)
            if tick and tick.ask is not None and tick.bid is not None:
                spread = float(tick.ask) - float(tick.bid)
                if spread >= 0:
                    if spread == 0:
                        logger.debug(f"MT5 returned zero spread from tick for {symbol_resolved}")
                    return float(spread)

            info = mt5.symbol_info(symbol_resolved)
            if info and info.spread is not None and info.point is not None:
                spread = float(info.spread) * float(info.point)
                if spread >= 0:
                    if spread == 0:
                        logger.debug(f"MT5 returned zero spread from symbol_info for {symbol_resolved}")
                    return float(spread)
        except Exception as e:
            logger.debug(f"Error getting live spread for {symbol}: {e}")
        return None

    def get_current_candle(self, symbol: str = "XAUUSD", timeframe: str = "M1") -> Dict[str, Any]:
        """Get current candle data"""
        if not self._ensure_mt5():
            return {"error": "MT5 not connected"}

        try:
            symbol_req = str(symbol or "XAUUSD").upper()
            symbol_resolved = self.resolve_symbol_name(symbol_req)
            if not symbol_resolved:
                return {"error": f"Symbol {symbol_req} not found in broker symbol list"}
            timeframe_map = {
                "M1": mt5.TIMEFRAME_M1,
                "M5": mt5.TIMEFRAME_M5,
                "M15": mt5.TIMEFRAME_M15,
                "M30": mt5.TIMEFRAME_M30,
                "H1": mt5.TIMEFRAME_H1,
                "H4": mt5.TIMEFRAME_H4,
                "D1": mt5.TIMEFRAME_D1,
            }

            mt5_tf = timeframe_map.get(timeframe, mt5.TIMEFRAME_M1)
            rates = mt5.copy_rates_from_pos(symbol_resolved, mt5_tf, 0, 1)

            if rates is None or len(rates) == 0:
                return {"error": "No data"}

            candle = rates[0]
            return {
                "requested_symbol": symbol_req,
                "resolved_symbol": symbol_resolved,
                "time": datetime.fromtimestamp(candle['time'], tz=timezone.utc).isoformat(),
                "open": candle['open'],
                "high": candle['high'],
                "low": candle['low'],
                "close": candle['close'],
                "volume": int(candle['tick_volume']),
            }

        except Exception as e:
            logger.error(f"Error getting candle: {e}")
            return {"error": str(e)}

    def get_symbol_tick(self, symbol: str = "XAUUSD", resolve_symbol: bool = True) -> Dict[str, Any]:
        """Get latest MT5 tick for symbol."""
        if not self._ensure_mt5():
            return {"error": "MT5 not connected"}
        try:
            symbol_raw = str(symbol or "XAUUSD").strip()
            symbol_req = symbol_raw.upper()
            symbol_resolved = self.resolve_symbol_name(symbol_req) if bool(resolve_symbol) else symbol_raw
            if not symbol_resolved:
                return {"error": f"Symbol {symbol_req} not found in broker symbol list"}
            tick = mt5.symbol_info_tick(symbol_resolved)
            if tick is None:
                return {"error": f"No tick data for {symbol_resolved}"}
            ts = int(getattr(tick, "time", 0) or 0)
            return {
                "requested_symbol": symbol_req,
                "resolved_symbol": symbol_resolved,
                "time_unix": ts,
                "time": datetime.fromtimestamp(ts, tz=timezone.utc).isoformat() if ts > 0 else None,
                "bid": _to_float_or_none(getattr(tick, "bid", None)),
                "ask": _to_float_or_none(getattr(tick, "ask", None)),
                "last": _to_float_or_none(getattr(tick, "last", None)),
                "volume": _to_float_or_none(getattr(tick, "volume", None)),
            }
        except Exception as e:
            logger.error(f"Error getting symbol tick: {e}")
            return {"error": str(e)}

    def get_recent_candles(
        self,
        symbol: str = "XAUUSD",
        timeframe: str = "M1",
        count: int = 300,
        resolve_symbol: bool = True,
    ) -> List[Dict[str, Any]]:
        """Get recent candles ordered oldest -> newest for chart streaming."""
        if not self._ensure_mt5():
            return []

        try:
            symbol_raw = str(symbol or "XAUUSD").strip()
            symbol_req = symbol_raw.upper()
            # When resolve_symbol=False (hot WS path), keep broker-native casing exactly as passed.
            symbol_resolved = self.resolve_symbol_name(symbol_req) if bool(resolve_symbol) else symbol_raw
            if not symbol_resolved:
                return []
            timeframe_map = {
                "M1": mt5.TIMEFRAME_M1,
                "M5": mt5.TIMEFRAME_M5,
                "M15": mt5.TIMEFRAME_M15,
                "M30": mt5.TIMEFRAME_M30,
                "H1": mt5.TIMEFRAME_H1,
                "H4": mt5.TIMEFRAME_H4,
                "D1": mt5.TIMEFRAME_D1,
            }

            tfu = str(timeframe or "M1").upper()
            mt5_tf = timeframe_map.get(tfu, mt5.TIMEFRAME_M1)
            n = max(1, min(int(count), 10000))
            rates = mt5.copy_rates_from_pos(symbol_resolved, mt5_tf, 0, n)
            if rates is None or len(rates) == 0:
                return []

            bars: List[Dict[str, Any]] = []
            for r in rates:
                ts = int(r["time"])
                bars.append(
                    {
                        "time_unix": ts,
                        "time": datetime.fromtimestamp(ts, tz=timezone.utc).isoformat(),
                        "symbol": symbol_resolved,
                        "requested_symbol": symbol_req,
                        "open": float(r["open"]),
                        "high": float(r["high"]),
                        "low": float(r["low"]),
                        "close": float(r["close"]),
                        "volume": int(r["tick_volume"]),
                    }
                )
            bars.sort(key=lambda x: int(x.get("time_unix") or 0))
            return bars
        except Exception as e:
            logger.error(f"Error getting recent candles: {e}")
            return []

    @staticmethod
    def _retcode_name(retcode: Any) -> str:
        try:
            code = int(retcode)
        except Exception:
            return ""
        for name in dir(mt5):
            if not name.startswith("TRADE_RETCODE_"):
                continue
            try:
                if int(getattr(mt5, name)) == code:
                    return str(name)
            except Exception:
                continue
        return ""

    @staticmethod
    def _filling_symbol_key(symbol: Any) -> str:
        return str(symbol or "").strip().upper()

    def _ordered_filling_candidates(
        self,
        *,
        symbol: str,
        info: Any,
        fallback_modes: List[Any],
    ) -> List[int]:
        symbol_key = self._filling_symbol_key(symbol)
        candidates: List[int] = []

        cached = self._symbol_filling_mode_cache.get(symbol_key)
        if cached is not None:
            candidates.append(int(cached))

        if info is not None:
            try:
                fm = int(getattr(info, "filling_mode", 0) or 0)
                if fm not in candidates:
                    candidates.append(fm)
            except Exception:
                pass

        for c in fallback_modes:
            try:
                cv = int(c)
            except Exception:
                continue
            if cv not in candidates:
                candidates.append(cv)

        invalid_modes = self._symbol_invalid_filling_modes.get(symbol_key, set())
        filtered = [mode for mode in candidates if mode not in invalid_modes]
        return filtered or candidates or [int(getattr(mt5, "ORDER_FILLING_RETURN", 0) or 0)]

    def _remember_filling_success(self, *, symbol: str, fill_mode: int) -> None:
        symbol_key = self._filling_symbol_key(symbol)
        if not symbol_key:
            return
        mode = int(fill_mode)
        self._symbol_filling_mode_cache[symbol_key] = mode
        invalid_modes = self._symbol_invalid_filling_modes.get(symbol_key)
        if invalid_modes is not None:
            invalid_modes.discard(mode)

    def _remember_filling_failure(self, *, symbol: str, fill_mode: int, retcode_name: str) -> None:
        if str(retcode_name or "") != "TRADE_RETCODE_INVALID_FILL":
            return
        symbol_key = self._filling_symbol_key(symbol)
        if not symbol_key:
            return
        self._symbol_invalid_filling_modes.setdefault(symbol_key, set()).add(int(fill_mode))

    def place_market_order(
        self,
        *,
        symbol: str,
        direction: str,
        lot_size: float,
        stop_loss: Optional[float] = None,
        take_profit: Optional[float] = None,
        comment: str = "",
        magic: Optional[int] = None,
        deviation_points: int = 20,
    ) -> Dict[str, Any]:
        """Place a live MT5 market order."""
        if not self._ensure_mt5():
            return {"ok": False, "error": "MT5 not connected"}
        try:
            symbol_req = str(symbol or "").strip().upper()
            if not symbol_req:
                return {"ok": False, "error": "symbol is required"}
            direction_u = str(direction or "").strip().upper()
            if direction_u not in {"BUY", "SELL"}:
                return {"ok": False, "error": "direction must be BUY or SELL"}
            vol = float(lot_size or 0.0)
            if (not vol) or vol <= 0.0:
                return {"ok": False, "error": "lot_size must be > 0"}
            sl_raw = _to_float_or_none(stop_loss)
            sl = None if sl_raw is None or float(sl_raw) <= 0.0 else float(sl_raw)
            tp = None if take_profit is None else float(take_profit)
            if tp is not None and tp <= 0.0:
                return {"ok": False, "error": "take_profit must be > 0"}
            try:
                magic_value = int(magic) if magic is not None else 970001
            except Exception:
                magic_value = 970001

            symbol_resolved = self.resolve_symbol_name(symbol_req)
            if not symbol_resolved:
                return {"ok": False, "error": f"symbol_not_found:{symbol_req}"}
            try:
                mt5.symbol_select(symbol_resolved, True)
            except Exception:
                pass
            info = mt5.symbol_info(symbol_resolved)
            if info is None:
                return {"ok": False, "error": f"symbol_info_unavailable:{symbol_resolved}"}
            tick = mt5.symbol_info_tick(symbol_resolved)
            if tick is None:
                return {"ok": False, "error": f"symbol_tick_unavailable:{symbol_resolved}"}

            order_type = mt5.ORDER_TYPE_BUY if direction_u == "BUY" else mt5.ORDER_TYPE_SELL
            requested_price = float(tick.ask) if direction_u == "BUY" else float(tick.bid)
            if requested_price <= 0.0:
                return {"ok": False, "error": f"invalid_market_price:{symbol_resolved}"}
            point = _to_float_or_none(getattr(info, "point", None)) or 0.0
            stops_level = _to_float_or_none(getattr(info, "trade_stops_level", None)) or 0.0
            min_dist = max(0.0, float(point) * float(stops_level), float(point) * 2.0)
            if direction_u == "BUY":
                if sl is not None and float(sl) >= float(requested_price) - float(min_dist):
                    return {
                        "ok": False,
                        "error": "invalid_order_geometry:buy_sl_not_below_market",
                        "requested_price": float(requested_price),
                        "sl": float(sl),
                        "tp": (float(tp) if tp is not None else None),
                        "min_distance": float(min_dist),
                    }
                if tp is not None and float(tp) <= float(requested_price) + float(min_dist):
                    return {
                        "ok": False,
                        "error": "invalid_order_geometry:buy_tp_not_above_market",
                        "requested_price": float(requested_price),
                        "sl": (float(sl) if sl is not None else None),
                        "tp": float(tp),
                        "min_distance": float(min_dist),
                    }
            else:
                if sl is not None and float(sl) <= float(requested_price) + float(min_dist):
                    return {
                        "ok": False,
                        "error": "invalid_order_geometry:sell_sl_not_above_market",
                        "requested_price": float(requested_price),
                        "sl": float(sl),
                        "tp": (float(tp) if tp is not None else None),
                        "min_distance": float(min_dist),
                    }
                if tp is not None and float(tp) >= float(requested_price) - float(min_dist):
                    return {
                        "ok": False,
                        "error": "invalid_order_geometry:sell_tp_not_below_market",
                        "requested_price": float(requested_price),
                        "sl": (float(sl) if sl is not None else None),
                        "tp": float(tp),
                        "min_distance": float(min_dist),
                    }

            filling_candidates = self._ordered_filling_candidates(
                symbol=symbol_resolved,
                info=info,
                fallback_modes=[
                    getattr(mt5, "ORDER_FILLING_RETURN", 0),
                    getattr(mt5, "ORDER_FILLING_IOC", 0),
                    getattr(mt5, "ORDER_FILLING_FOK", 0),
                ],
            )

            last_err = ""
            for fill_mode in filling_candidates:
                request = {
                    "action": mt5.TRADE_ACTION_DEAL,
                    "symbol": symbol_resolved,
                    "volume": float(vol),
                    "type": int(order_type),
                    "price": float(requested_price),
                    "sl": float(sl) if sl is not None else 0.0,
                    "tp": float(tp) if tp is not None else 0.0,
                    "deviation": int(max(1, min(5000, int(deviation_points or 20)))),
                    "magic": int(magic_value),
                    "comment": str(comment or "")[:31],
                    "type_time": mt5.ORDER_TIME_GTC,
                    "type_filling": int(fill_mode),
                }
                try:
                    result = mt5.order_send(request)
                except Exception as exc:
                    last_err = f"{type(exc).__name__}:{str(exc)}"
                    continue
                if result is None:
                    last_err = f"order_send_none:last_error={mt5.last_error()}"
                    continue
                retcode = int(getattr(result, "retcode", 0) or 0)
                retcode_name = self._retcode_name(retcode)
                ok = retcode in {
                    int(getattr(mt5, "TRADE_RETCODE_DONE", 10009)),
                    int(getattr(mt5, "TRADE_RETCODE_PLACED", 10008)),
                    int(getattr(mt5, "TRADE_RETCODE_DONE_PARTIAL", 10010)),
                }
                payload = {
                    "ok": bool(ok),
                    "requested_symbol": symbol_req,
                    "symbol": symbol_resolved,
                    "direction": direction_u,
                    "lot_size": float(vol),
                    "requested_price": float(requested_price),
                    "price": float(getattr(result, "price", requested_price) or requested_price),
                    "sl": float(sl) if sl is not None else None,
                    "tp": float(tp) if tp is not None else None,
                    "retcode": int(retcode),
                    "retcode_name": str(retcode_name),
                    "comment": str(getattr(result, "comment", "") or ""),
                    "order": int(getattr(result, "order", 0) or 0),
                    "deal": int(getattr(result, "deal", 0) or 0),
                    # MT5 result.position is the true position ticket when available.
                    "position": int(getattr(result, "position", 0) or 0),
                    "request": request,
                }
                if ok:
                    self._remember_filling_success(symbol=symbol_resolved, fill_mode=int(fill_mode))
                    logger.info(
                        "mt5_market_order_sent symbol=%s direction=%s lot=%.4f magic=%s order=%s deal=%s position=%s comment=%s retcode=%s filling=%s",
                        str(symbol_resolved),
                        str(direction_u),
                        float(vol),
                        int(magic_value),
                        int(payload.get("order") or 0),
                        int(payload.get("deal") or 0),
                        int(payload.get("position") or 0),
                        str(request.get("comment") or ""),
                        str(retcode_name),
                        int(fill_mode),
                    )
                    return payload
                last_err = f"{retcode}:{retcode_name}:{payload.get('comment')}"
                self._remember_filling_failure(symbol=symbol_resolved, fill_mode=int(fill_mode), retcode_name=str(retcode_name))
                log_fn = logger.info if str(retcode_name) == "TRADE_RETCODE_INVALID_FILL" else logger.warning
                log_fn(
                    "mt5_market_order_failed symbol=%s direction=%s lot=%.4f magic=%s retcode=%s comment=%s request_comment=%s filling=%s",
                    str(symbol_resolved),
                    str(direction_u),
                    float(vol),
                    int(magic_value),
                    str(retcode_name),
                    str(payload.get("comment") or ""),
                    str(request.get("comment") or ""),
                    int(fill_mode),
                )
            return {"ok": False, "error": f"order_send_failed:{last_err or mt5.last_error()}"}
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}:{str(exc)}"}

    def close_position(
        self,
        *,
        symbol: str,
        position_ticket: Optional[int] = None,
        lot_size: Optional[float] = None,
        deviation_points: int = 20,
        comment: str = "",
    ) -> Dict[str, Any]:
        """Close an open MT5 position by ticket (or first symbol position)."""
        if not self._ensure_mt5():
            return {"ok": False, "error": "MT5 not connected"}
        try:
            symbol_req = str(symbol or "").strip().upper()
            symbol_resolved = self.resolve_symbol_name(symbol_req) if symbol_req else None
            if not symbol_resolved:
                return {"ok": False, "error": f"symbol_not_found:{symbol_req}"}
            try:
                mt5.symbol_select(symbol_resolved, True)
            except Exception:
                pass
            if position_ticket is not None:
                try:
                    rows = mt5.positions_get(ticket=int(position_ticket))
                except Exception:
                    rows = None
                positions = list(rows or [])
            else:
                positions = list(mt5.positions_get(symbol=symbol_resolved) or [])
            if not positions:
                return {"ok": False, "error": "position_not_found"}
            pos = positions[0]
            pos_type = int(getattr(pos, "type", 0) or 0)
            close_type = mt5.ORDER_TYPE_SELL if pos_type == mt5.POSITION_TYPE_BUY else mt5.ORDER_TYPE_BUY
            tick = mt5.symbol_info_tick(symbol_resolved)
            if tick is None:
                return {"ok": False, "error": f"symbol_tick_unavailable:{symbol_resolved}"}
            close_price = float(tick.bid) if close_type == mt5.ORDER_TYPE_SELL else float(tick.ask)
            volume = float(lot_size if lot_size is not None else getattr(pos, "volume", 0.0) or 0.0)
            if volume <= 0.0:
                return {"ok": False, "error": "invalid_close_volume"}
            info = mt5.symbol_info(symbol_resolved)
            filling_candidates: List[int] = self._ordered_filling_candidates(
                symbol=symbol_resolved,
                info=info,
                fallback_modes=[
                    getattr(mt5, "ORDER_FILLING_IOC", 0),
                    getattr(mt5, "ORDER_FILLING_FOK", 0),
                    getattr(mt5, "ORDER_FILLING_RETURN", 0),
                ],
            )

            last_err = ""
            for fill_mode in filling_candidates:
                req = {
                    "action": mt5.TRADE_ACTION_DEAL,
                    "symbol": symbol_resolved,
                    "position": int(getattr(pos, "ticket", 0) or 0),
                    "volume": float(volume),
                    "type": int(close_type),
                    "price": float(close_price),
                    "deviation": int(max(1, min(5000, int(deviation_points or 20)))),
                    "magic": 970001,
                    "comment": str(comment or "")[:31],
                    "type_time": mt5.ORDER_TIME_GTC,
                    "type_filling": int(fill_mode),
                }
                result = mt5.order_send(req)
                if result is None:
                    last_err = f"order_send_none:last_error={mt5.last_error()}"
                    continue
                retcode = int(getattr(result, "retcode", 0) or 0)
                retcode_name = self._retcode_name(retcode)
                ok = retcode in {
                    int(getattr(mt5, "TRADE_RETCODE_DONE", 10009)),
                    int(getattr(mt5, "TRADE_RETCODE_PLACED", 10008)),
                    int(getattr(mt5, "TRADE_RETCODE_DONE_PARTIAL", 10010)),
                }
                payload = {
                    "ok": bool(ok),
                    "requested_symbol": symbol_req,
                    "symbol": symbol_resolved,
                    "position_ticket": int(getattr(pos, "ticket", 0) or 0),
                    "price": float(getattr(result, "price", close_price) or close_price),
                    "retcode": int(retcode),
                    "retcode_name": str(retcode_name),
                    "comment": str(getattr(result, "comment", "") or ""),
                    "order": int(getattr(result, "order", 0) or 0),
                    "deal": int(getattr(result, "deal", 0) or 0),
                    "request": req,
                    "error": None if ok else f"{retcode}:{retcode_name}:{getattr(result, 'comment', '')}",
                }
                if ok:
                    self._remember_filling_success(symbol=symbol_resolved, fill_mode=int(fill_mode))
                    return payload
                self._remember_filling_failure(symbol=symbol_resolved, fill_mode=int(fill_mode), retcode_name=str(retcode_name))
                last_err = str(payload.get("error") or "")
            return {"ok": False, "error": last_err or "close_order_send_failed"}
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}:{str(exc)}"}

    def modify_position_sl_tp(
        self,
        *,
        symbol: str,
        position_ticket: int,
        stop_loss: Optional[float] = None,
        take_profit: Optional[float] = None,
        comment: str = "",
    ) -> Dict[str, Any]:
        """Modify broker-side SL/TP for an existing MT5 position."""
        if not self._ensure_mt5():
            return {"ok": False, "error": "MT5 not connected"}
        try:
            symbol_req = str(symbol or "").strip().upper()
            if not symbol_req:
                return {"ok": False, "error": "symbol is required"}
            try:
                pos_ticket = int(position_ticket or 0)
            except Exception:
                pos_ticket = 0
            if pos_ticket <= 0:
                return {"ok": False, "error": "position_ticket must be > 0"}

            symbol_resolved = self.resolve_symbol_name(symbol_req)
            if not symbol_resolved:
                return {"ok": False, "error": f"symbol_not_found:{symbol_req}"}
            try:
                mt5.symbol_select(symbol_resolved, True)
            except Exception:
                pass

            try:
                rows = mt5.positions_get(ticket=int(pos_ticket))
            except Exception:
                rows = None
            positions = list(rows or [])
            if not positions:
                return {"ok": False, "error": "position_not_found"}
            pos = positions[0]

            sl_in = _to_float_or_none(stop_loss)
            tp_in = _to_float_or_none(take_profit)
            cur_sl = _to_float_or_none(getattr(pos, "sl", None))
            cur_tp = _to_float_or_none(getattr(pos, "tp", None))
            sl = float(sl_in) if sl_in is not None and float(sl_in) > 0.0 else (float(cur_sl) if cur_sl is not None and float(cur_sl) > 0.0 else 0.0)
            tp = float(tp_in) if tp_in is not None and float(tp_in) > 0.0 else (float(cur_tp) if cur_tp is not None and float(cur_tp) > 0.0 else 0.0)

            req = {
                "action": int(getattr(mt5, "TRADE_ACTION_SLTP", 6)),
                "symbol": symbol_resolved,
                "position": int(getattr(pos, "ticket", 0) or pos_ticket),
                "sl": float(sl),
                "tp": float(tp),
                "magic": 970001,
                "comment": str(comment or "")[:31],
            }
            result = mt5.order_send(req)
            if result is None:
                return {"ok": False, "error": f"order_send_none:last_error={mt5.last_error()}"}
            retcode = int(getattr(result, "retcode", 0) or 0)
            retcode_name = self._retcode_name(retcode)
            ok = retcode in {
                int(getattr(mt5, "TRADE_RETCODE_DONE", 10009)),
                int(getattr(mt5, "TRADE_RETCODE_PLACED", 10008)),
                int(getattr(mt5, "TRADE_RETCODE_DONE_PARTIAL", 10010)),
            }
            payload = {
                "ok": bool(ok),
                "requested_symbol": symbol_req,
                "symbol": symbol_resolved,
                "position_ticket": int(getattr(pos, "ticket", 0) or pos_ticket),
                "sl": (float(sl) if float(sl) > 0.0 else None),
                "tp": (float(tp) if float(tp) > 0.0 else None),
                "retcode": int(retcode),
                "retcode_name": str(retcode_name),
                "comment": str(getattr(result, "comment", "") or ""),
                "request": req,
            }
            if not ok:
                payload["error"] = f"{retcode}:{retcode_name}:{payload.get('comment')}"
            return payload
        except Exception as exc:
            return {"ok": False, "error": f"{type(exc).__name__}:{str(exc)}"}

    def close(self):
        """Cleanup MT5 connection"""
        if self._mt5_initialized:
            mt5.shutdown()
            self._mt5_initialized = False
