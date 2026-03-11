"""
Live Trading Service - Interface with the running bot and MT5
"""

import MetaTrader5 as mt5
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List
from pathlib import Path
import json
import re
import time
import pytz
import logging

logger = logging.getLogger(__name__)

# Bot state file locations for all strategies
BOT_STATE_FILES = {
    "orb_strategy": Path(__file__).parent.parent.parent / "data" / "bot_state.json",
    "advanced_orb_strategy": Path(__file__).parent.parent.parent / "data" / "advanced_orb_state.json",
    "orb_ml_strategy": Path(__file__).parent.parent.parent / "data" / "orb_ml_state.json",
    "advanced_orb_ml_strategy": Path(__file__).parent.parent.parent / "data" / "advanced_orb_ml_state.json",
    "liquidity_sweep_strategy": Path(__file__).parent.parent.parent / "data" / "liquidity_sweep_state.json",
    "keltner_breakout_strategy": Path(__file__).parent.parent.parent / "data" / "keltner_breakout_state.json",
}


class LiveTradingService:
    """Service for interacting with live trading and MT5"""

    def __init__(self):
        self.ny_tz = pytz.timezone('America/New_York')
        self._mt5_initialized = False
        self._symbols_cache: List[Dict[str, Any]] = []
        self._symbols_cache_ts: float = 0.0
        self._resolved_symbol_cache: Dict[str, Dict[str, Any]] = {}
        self._resolved_symbol_cache_ttl_sec: float = 30.0

    def _ensure_mt5(self) -> bool:
        """Ensure MT5 is initialized"""
        if self._mt5_initialized:
            return True

        if not mt5.initialize():
            logger.warning(f"MT5 not available: {mt5.last_error()}")
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
        if not self._ensure_mt5():
            return []
        now = time.time()
        if (not refresh) and self._symbols_cache and (now - self._symbols_cache_ts) < 10.0:
            rows = list(self._symbols_cache)
        else:
            raw = mt5.symbols_get()
            rows = []
            if raw:
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

    def get_open_positions(self, symbol: str = "XAUUSD") -> List[Dict[str, Any]]:
        """Get all open positions for given symbol"""
        if not self._ensure_mt5():
            return []

        try:
            symbol_req = str(symbol or "XAUUSD").upper()
            symbol_resolved = self.resolve_symbol_name(symbol_req)
            if not symbol_resolved:
                return []
            positions = mt5.positions_get(symbol=symbol_resolved)
            if not positions:
                return []

            result = []
            for pos in positions:
                tick = mt5.symbol_info_tick(symbol_resolved)
                current_price = tick.bid if pos.type == 0 else tick.ask if tick else pos.price_current

                result.append({
                    "ticket": pos.ticket,
                    "direction": "BUY" if pos.type == 0 else "SELL",
                    "symbol": symbol_resolved,
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

    def get_recent_deals(self, days: int = 1, symbol: str = "XAUUSD") -> List[Dict[str, Any]]:
        """Get recent closed deals for given symbol"""
        if not self._ensure_mt5():
            return []

        try:
            from datetime import timedelta
            symbol_req = str(symbol or "XAUUSD").upper()
            symbol_resolved = self.resolve_symbol_name(symbol_req)
            if not symbol_resolved:
                return []

            # Get deals from last N days
            to_time = datetime.now()
            from_time = to_time - timedelta(days=days)

            deals = mt5.history_deals_get(from_time, to_time)
            if not deals:
                return []

            result = []
            for deal in deals:
                if str(deal.symbol or "").upper() != str(symbol_resolved).upper():
                    continue

                result.append({
                    "ticket": deal.ticket,
                    "order": deal.order,
                    "requested_symbol": symbol_req,
                    "symbol": symbol_resolved,
                    "time": datetime.fromtimestamp(deal.time, tz=timezone.utc).isoformat(),
                    "type": "BUY" if deal.type in [0, 2] else "SELL",
                    "entry": "IN" if deal.entry == 0 else "OUT",
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
                "volume_min": info.volume_min,
                "volume_max": info.volume_max,
                "volume_step": info.volume_step,
                "trade_stops_level": info.trade_stops_level,
                "trade_freeze_level": info.trade_freeze_level,
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
            symbol_req = str(symbol or "XAUUSD").upper()
            symbol_resolved = self.resolve_symbol_name(symbol_req) if bool(resolve_symbol) else symbol_req
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

    def close(self):
        """Cleanup MT5 connection"""
        if self._mt5_initialized:
            mt5.shutdown()
            self._mt5_initialized = False
