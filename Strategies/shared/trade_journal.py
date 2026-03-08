"""
Trade Journal - Records intended vs actual execution for cost analysis.

Uses direct SQLite (not SQLAlchemy) since it runs in strategy subprocesses,
not the FastAPI process. All operations are fail-safe - if recording fails,
trading continues unaffected.
"""

import sqlite3
import logging
from pathlib import Path
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)

# Default DB path relative to project root
DEFAULT_DB_PATH = Path(__file__).parent.parent.parent / "dashboard" / "data" / "trading.db"


class TradeJournal:
    """Records intended vs actual execution for cost analysis."""

    def __init__(self, db_path=None):
        self.db_path = str(db_path or DEFAULT_DB_PATH)

    def _get_conn(self):
        """Get a SQLite connection."""
        return sqlite3.connect(self.db_path)

    def record_entry(self, ticket, intended_price, actual_price,
                     spread, lot_size, direction, symbol):
        """
        Record entry execution quality. Called after MT5 fill.

        Args:
            ticket: MT5 position ticket
            intended_price: Strategy's ideal entry price
            actual_price: What MT5 actually filled at
            spread: ask - bid at entry time
            lot_size: Position size
            direction: 'BUY' or 'SELL'
            symbol: Trading symbol
        """
        try:
            slippage = abs(actual_price - intended_price) if intended_price and actual_price else 0

            conn = self._get_conn()
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE live_trades SET
                    intended_entry_price = ?,
                    actual_entry_price = ?,
                    spread_at_entry = ?,
                    slippage_entry = ?
                WHERE ticket = ?
            """, (intended_price, actual_price, spread, slippage, ticket))
            conn.commit()
            conn.close()

            logger.debug(
                f"Journal: entry recorded ticket={ticket}, "
                f"intended={intended_price:.2f}, actual={actual_price:.2f}, "
                f"slip={slippage:.2f}, spread={spread:.2f}"
            )
        except Exception as e:
            logger.warning(f"TradeJournal.record_entry failed: {e}")

    def record_exit(self, ticket, intended_price, actual_price, spread):
        """
        Record exit execution quality. Called after position close.

        Args:
            ticket: MT5 position ticket
            intended_price: TP/SL price (intended exit)
            actual_price: What MT5 actually filled at
            spread: ask - bid at exit time
        """
        try:
            slippage = abs(actual_price - intended_price) if intended_price and actual_price else 0

            conn = self._get_conn()
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE live_trades SET
                    intended_exit_price = ?,
                    actual_exit_price = ?,
                    spread_at_exit = ?,
                    slippage_exit = ?
                WHERE ticket = ?
            """, (intended_price, actual_price, spread, slippage, ticket))
            conn.commit()
            conn.close()

            logger.debug(
                f"Journal: exit recorded ticket={ticket}, "
                f"slip={slippage:.2f}, spread={spread:.2f}"
            )
        except Exception as e:
            logger.warning(f"TradeJournal.record_exit failed: {e}")

    def get_execution_summary(self, strategy_id=None, days=30):
        """
        Aggregate execution quality stats for dashboard.

        Returns dict with avg_spread, avg_slippage, total_commission, etc.
        """
        try:
            conn = self._get_conn()
            cursor = conn.cursor()

            cutoff = (datetime.utcnow() - timedelta(days=days)).isoformat()

            where_clause = "WHERE entry_time > ?"
            params = [cutoff]

            if strategy_id:
                where_clause += " AND setup_type LIKE ?"
                params.append(f"%{strategy_id}%")

            cursor.execute(f"""
                SELECT
                    COUNT(*) as total_trades,
                    AVG(spread_at_entry) as avg_spread_entry,
                    AVG(spread_at_exit) as avg_spread_exit,
                    AVG(slippage_entry) as avg_slippage_entry,
                    AVG(slippage_exit) as avg_slippage_exit,
                    SUM(commission) as total_commission,
                    SUM(swap) as total_swap,
                    AVG(commission) as avg_commission,
                    AVG(swap) as avg_swap,
                    AVG(ABS(actual_entry_price - intended_entry_price)) as avg_fill_deviation
                FROM live_trades
                {where_clause}
                AND intended_entry_price IS NOT NULL
            """, params)

            row = cursor.fetchone()
            conn.close()

            if not row or row[0] == 0:
                return {
                    "total_trades": 0,
                    "avg_spread": 0,
                    "avg_slippage": 0,
                    "total_commission": 0,
                    "total_swap": 0,
                    "avg_commission": 0,
                    "avg_swap": 0,
                    "avg_fill_deviation": 0,
                    "cost_per_trade": 0,
                }

            avg_spread = ((row[1] or 0) + (row[2] or 0)) / 2
            avg_slippage = ((row[3] or 0) + (row[4] or 0)) / 2
            avg_comm = row[7] or 0
            avg_swap_val = row[8] or 0

            return {
                "total_trades": row[0],
                "avg_spread": round(avg_spread, 4),
                "avg_slippage": round(avg_slippage, 4),
                "total_commission": round(row[5] or 0, 2),
                "total_swap": round(row[6] or 0, 2),
                "avg_commission": round(avg_comm, 2),
                "avg_swap": round(avg_swap_val, 2),
                "avg_fill_deviation": round(row[9] or 0, 4),
                "cost_per_trade": round(avg_comm + avg_swap_val + avg_spread + avg_slippage, 2),
            }
        except Exception as e:
            logger.warning(f"TradeJournal.get_execution_summary failed: {e}")
            return {
                "total_trades": 0,
                "avg_spread": 0,
                "avg_slippage": 0,
                "total_commission": 0,
                "total_swap": 0,
                "avg_commission": 0,
                "avg_swap": 0,
                "avg_fill_deviation": 0,
                "cost_per_trade": 0,
            }

    def record_mfe_mae(self, ticket, mfe_r, mae_r):
        """
        Update MFE/MAE values for a live trade (in R-multiples).

        Args:
            ticket: MT5 position ticket
            mfe_r: Maximum favorable excursion in R-multiples
            mae_r: Maximum adverse excursion in R-multiples
        """
        try:
            conn = self._get_conn()
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE live_trades SET
                    max_favorable_excursion = ?,
                    max_adverse_excursion = ?
                WHERE ticket = ?
            """, (mfe_r, mae_r, ticket))
            conn.commit()
            conn.close()

            logger.debug(
                f"Journal: MFE/MAE recorded ticket={ticket}, "
                f"MFE={mfe_r:.2f}R, MAE={mae_r:.2f}R"
            )
        except Exception as e:
            logger.warning(f"TradeJournal.record_mfe_mae failed: {e}")

    def record_ml_data(self, ticket, ml_features, ml_win_probability):
        """
        Save ML feature vector and win probability for a live trade.

        Args:
            ticket: MT5 position ticket
            ml_features: Dict of ML features
            ml_win_probability: Predicted win probability
        """
        try:
            import json
            features_json = json.dumps(ml_features) if ml_features else None

            conn = self._get_conn()
            cursor = conn.cursor()
            cursor.execute("""
                UPDATE live_trades SET
                    ml_features = ?,
                    ml_win_probability = ?
                WHERE ticket = ?
            """, (features_json, ml_win_probability, ticket))
            conn.commit()
            conn.close()

            logger.debug(
                f"Journal: ML data recorded ticket={ticket}, "
                f"prob={ml_win_probability:.3f}"
            )
        except Exception as e:
            logger.warning(f"TradeJournal.record_ml_data failed: {e}")

    def get_trade_costs(self, limit=50, days=30):
        """Get per-trade cost breakdown."""
        try:
            conn = self._get_conn()
            cursor = conn.cursor()

            cutoff = (datetime.utcnow() - timedelta(days=days)).isoformat()

            cursor.execute("""
                SELECT
                    ticket,
                    symbol,
                    direction,
                    entry_time,
                    intended_entry_price,
                    actual_entry_price,
                    intended_exit_price,
                    actual_exit_price,
                    spread_at_entry,
                    spread_at_exit,
                    slippage_entry,
                    slippage_exit,
                    commission,
                    swap,
                    profit_loss
                FROM live_trades
                WHERE entry_time > ?
                AND intended_entry_price IS NOT NULL
                ORDER BY entry_time DESC
                LIMIT ?
            """, (cutoff, limit))

            rows = cursor.fetchall()
            conn.close()

            return [
                {
                    "ticket": r[0],
                    "symbol": r[1],
                    "direction": r[2],
                    "entry_time": r[3],
                    "intended_entry": r[4],
                    "actual_entry": r[5],
                    "intended_exit": r[6],
                    "actual_exit": r[7],
                    "spread_entry": r[8],
                    "spread_exit": r[9],
                    "slippage_entry": r[10],
                    "slippage_exit": r[11],
                    "commission": r[12],
                    "swap": r[13],
                    "pnl": r[14],
                }
                for r in rows
            ]
        except Exception as e:
            logger.warning(f"TradeJournal.get_trade_costs failed: {e}")
            return []
