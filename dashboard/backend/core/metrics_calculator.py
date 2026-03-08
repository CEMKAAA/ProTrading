"""
Performance Metrics Calculator
Calculates comprehensive trading statistics and risk metrics
"""

import numpy as np
import pandas as pd
from typing import List, Dict, Any, Optional, Tuple
from datetime import datetime, timedelta
from dataclasses import dataclass
import logging

logger = logging.getLogger(__name__)


@dataclass
class TradeRecord:
    """Data class for individual trade records with full cost tracking"""
    trade_number: int
    direction: str  # "BUY" or "SELL"
    entry_time: datetime
    exit_time: Optional[datetime]
    entry_price: float
    exit_price: Optional[float]
    stop_loss: float
    take_profit: Optional[float]
    lot_size: float
    profit_loss: float  # Net P&L (after all costs)
    balance_before: float
    balance_after: float
    setup_type: Optional[str] = None
    exit_reason: Optional[str] = None
    r_multiple: float = 0.0
    # Cost breakdown for realistic simulation
    gross_pnl: float = 0.0      # P&L before costs (price movement only)
    spread_cost: float = 0.0    # Entry + exit spread cost in USD
    slippage_cost: float = 0.0  # Entry slippage cost in USD
    commission_cost: float = 0.0  # Round-trip commission in USD
    swap_cost: float = 0.0      # Overnight swap costs in USD
    # Strategy diagnostics: why the trade was entered
    entry_reason: Optional[Dict[str, Any]] = None
    # ML features captured at entry time (for training data)
    ml_features: Optional[Dict[str, float]] = None
    # Maximum Favorable/Adverse Excursion (for R:R predictor training)
    max_favorable_excursion: float = 0.0  # Best price movement in trade direction
    max_adverse_excursion: float = 0.0    # Worst price movement against trade


class MetricsCalculator:
    """
    Comprehensive performance metrics calculator for backtesting results.
    Calculates financial, risk, and statistical metrics.
    """

    def __init__(self, initial_balance: float = 10000.0):
        self.initial_balance = initial_balance
        self.risk_free_rate = 0.02  # 2% annual risk-free rate

    def calculate_all_metrics(
        self,
        trades: List[TradeRecord],
        equity_curve: List[Tuple[datetime, float]]
    ) -> Dict[str, Any]:
        """
        Calculate all performance metrics.

        Args:
            trades: List of completed trades
            equity_curve: List of (timestamp, equity) tuples

        Returns:
            Dictionary containing all metrics
        """
        if not trades:
            return self._empty_metrics()

        # Basic metrics
        basic = self._calculate_basic_metrics(trades)

        # Financial metrics
        financial = self._calculate_financial_metrics(trades)

        # Risk metrics
        risk = self._calculate_risk_metrics(trades, equity_curve)

        # Trade statistics
        stats = self._calculate_trade_statistics(trades)

        # Time-based analysis
        time_metrics = self._calculate_time_metrics(trades)

        # Cost summary
        cost_summary = self._calculate_cost_summary(trades)

        # Combine all metrics
        return {
            **basic,
            **financial,
            **risk,
            **stats,
            **time_metrics,
            **cost_summary
        }

    def _calculate_cost_summary(self, trades: List[TradeRecord]) -> Dict[str, Any]:
        """Calculate summary of all trading costs"""
        if not trades:
            return {
                'total_gross_pnl': 0.0,
                'total_spread_cost': 0.0,
                'total_slippage_cost': 0.0,
                'total_commission': 0.0,
                'total_swap_cost': 0.0,
                'total_costs': 0.0,
                'avg_cost_per_trade': 0.0,
                'cost_impact_percent': 0.0,
            }

        total_gross_pnl = sum(t.gross_pnl for t in trades)
        total_spread = sum(t.spread_cost for t in trades)
        total_slippage = sum(t.slippage_cost for t in trades)
        total_commission = sum(t.commission_cost for t in trades)
        total_swap = sum(t.swap_cost for t in trades)
        total_costs = total_spread + total_slippage + total_commission + total_swap

        avg_cost = total_costs / len(trades) if trades else 0

        # Cost impact: how much did costs reduce gross P&L (as percentage)
        cost_impact = (total_costs / total_gross_pnl * 100) if total_gross_pnl > 0 else 0

        return {
            'total_gross_pnl': round(total_gross_pnl, 2),
            'total_spread_cost': round(total_spread, 2),
            'total_slippage_cost': round(total_slippage, 2),
            'total_commission': round(total_commission, 2),
            'total_swap_cost': round(total_swap, 2),
            'total_costs': round(total_costs, 2),
            'avg_cost_per_trade': round(avg_cost, 2),
            'cost_impact_percent': round(cost_impact, 2),
        }

    def _empty_metrics(self) -> Dict[str, Any]:
        """Return empty metrics structure"""
        return {
            'total_trades': 0,
            'winning_trades': 0,
            'losing_trades': 0,
            'win_rate': 0.0,
            'initial_balance': self.initial_balance,
            'final_balance': self.initial_balance,
            'total_profit': 0.0,
            'total_loss': 0.0,
            'net_profit': 0.0,
            'profit_factor': 0.0,
            'max_drawdown': 0.0,
            'max_drawdown_percent': 0.0,
            'sharpe_ratio': 0.0,
            'sortino_ratio': 0.0,
            'calmar_ratio': 0.0,
            'avg_win': 0.0,
            'avg_loss': 0.0,
            'largest_win': 0.0,
            'largest_loss': 0.0,
            'avg_trade_duration': 0.0,
            'avg_rr_ratio': 0.0,
            'expectancy': 0.0,
        }

    def _calculate_basic_metrics(self, trades: List[TradeRecord]) -> Dict[str, Any]:
        """Calculate basic trade metrics"""
        total_trades = len(trades)
        winning_trades = sum(1 for t in trades if t.profit_loss > 0)
        losing_trades = sum(1 for t in trades if t.profit_loss < 0)
        breakeven_trades = sum(1 for t in trades if t.profit_loss == 0)

        win_rate = (winning_trades / total_trades * 100) if total_trades > 0 else 0.0

        return {
            'total_trades': total_trades,
            'winning_trades': winning_trades,
            'losing_trades': losing_trades,
            'breakeven_trades': breakeven_trades,
            'win_rate': round(win_rate, 2),
        }

    def _calculate_financial_metrics(self, trades: List[TradeRecord]) -> Dict[str, Any]:
        """Calculate financial performance metrics"""
        if not trades:
            return {}

        profits = [t.profit_loss for t in trades if t.profit_loss > 0]
        losses = [abs(t.profit_loss) for t in trades if t.profit_loss < 0]

        total_profit = sum(profits)
        total_loss = sum(losses)
        net_profit = total_profit - total_loss

        final_balance = trades[-1].balance_after if trades else self.initial_balance

        # Profit Factor
        profit_factor = (total_profit / total_loss) if total_loss > 0 else float('inf')
        if profit_factor == float('inf'):
            profit_factor = total_profit if total_profit > 0 else 0.0

        # Return percentage
        return_percent = ((final_balance - self.initial_balance) / self.initial_balance * 100)

        return {
            'initial_balance': round(self.initial_balance, 2),
            'final_balance': round(final_balance, 2),
            'total_profit': round(total_profit, 2),
            'total_loss': round(total_loss, 2),
            'net_profit': round(net_profit, 2),
            'profit_factor': round(profit_factor, 2),
            'return_percent': round(return_percent, 2),
        }

    def _calculate_risk_metrics(
        self,
        trades: List[TradeRecord],
        equity_curve: List[Tuple[datetime, float]]
    ) -> Dict[str, Any]:
        """Calculate risk-adjusted performance metrics"""

        # Max Drawdown
        max_dd, max_dd_pct, dd_curve = self._calculate_max_drawdown(equity_curve)

        # Sharpe/Sortino using daily equity returns (not per-trade returns)
        sharpe = self._calculate_sharpe_ratio(trades)
        sortino = self._calculate_sortino_ratio(trades)

        # Calmar Ratio
        calmar = self._calculate_calmar_ratio(trades, max_dd_pct)

        # Recovery Factor
        recovery = self._calculate_recovery_factor(trades, max_dd)

        return {
            'max_drawdown': round(max_dd, 2),
            'max_drawdown_percent': round(max_dd_pct, 2),
            'sharpe_ratio': sharpe,
            'sortino_ratio': sortino,
            'calmar_ratio': round(calmar, 3),
            'recovery_factor': round(recovery, 2),
            'drawdown_curve': dd_curve,
        }

    def _calculate_max_drawdown(
        self,
        equity_curve: List[Tuple[datetime, float]]
    ) -> Tuple[float, float, List[Dict[str, Any]]]:
        """
        Calculate maximum drawdown from equity curve.

        Returns:
            Tuple of (max_dd_amount, max_dd_percent, drawdown_curve)
        """
        if not equity_curve:
            return 0.0, 0.0, []

        equities = [e[1] for e in equity_curve]
        timestamps = [e[0] for e in equity_curve]

        peak = equities[0]
        max_dd = 0.0
        max_dd_pct = 0.0
        dd_curve = []

        for i, equity in enumerate(equities):
            if equity > peak:
                peak = equity

            drawdown = peak - equity
            drawdown_pct = (drawdown / peak * 100) if peak > 0 else 0

            if drawdown > max_dd:
                max_dd = drawdown
                max_dd_pct = drawdown_pct

            dd_curve.append({
                'timestamp': timestamps[i].isoformat() if hasattr(timestamps[i], 'isoformat') else str(timestamps[i]),
                'drawdown': round(drawdown, 2),
                'drawdown_pct': round(drawdown_pct, 2),
                'equity': round(equity, 2),
                'peak': round(peak, 2),
            })

        return max_dd, max_dd_pct, dd_curve

    def _calculate_returns(self, trades: List[TradeRecord]) -> np.ndarray:
        """Calculate trade returns as percentages"""
        if not trades:
            return np.array([])

        returns = []
        for trade in trades:
            if trade.balance_before > 0:
                ret = (trade.profit_loss / trade.balance_before) * 100
                returns.append(ret)

        return np.array(returns)

    def _build_daily_equity(self, trades: List[TradeRecord]) -> np.ndarray:
        """Build daily equity curve from trade records."""
        if not trades:
            return np.array([self.initial_balance])

        # Group P&L by exit date
        daily_pnl = {}
        for trade in trades:
            if trade.exit_time:
                date_key = trade.exit_time.date()
                daily_pnl[date_key] = daily_pnl.get(date_key, 0) + trade.profit_loss

        if not daily_pnl:
            return np.array([self.initial_balance])

        # Build cumulative equity
        sorted_dates = sorted(daily_pnl.keys())
        equity = [self.initial_balance]
        for date in sorted_dates:
            equity.append(equity[-1] + daily_pnl[date])

        return np.array(equity)

    def _calculate_sharpe_ratio(self, trades: List[TradeRecord]) -> float:
        """
        Calculate annualized Sharpe Ratio from daily equity returns.
        Sharpe = (Mean Daily Return - Daily Risk Free Rate) / Std Dev of Daily Returns
        Annualized by multiplying by sqrt(252).
        """
        if len(trades) < 2:
            return 0.0

        daily_equity = self._build_daily_equity(trades)
        if len(daily_equity) < 5:
            return 0.0

        # Calculate daily returns
        returns = np.diff(daily_equity) / daily_equity[:-1]

        mean_return = np.mean(returns)
        std_return = np.std(returns, ddof=1)

        if std_return == 0:
            return 0.0

        daily_rf = self.risk_free_rate / 252
        sharpe = (mean_return - daily_rf) / std_return
        return round(sharpe * np.sqrt(252), 4)

    def _calculate_sortino_ratio(self, trades: List[TradeRecord]) -> float:
        """
        Calculate annualized Sortino Ratio from daily equity returns.
        Sortino = (Mean Daily Return - Daily Risk Free Rate) / Downside Deviation
        Annualized by multiplying by sqrt(252).
        """
        if len(trades) < 2:
            return 0.0

        daily_equity = self._build_daily_equity(trades)
        if len(daily_equity) < 5:
            return 0.0

        returns = np.diff(daily_equity) / daily_equity[:-1]
        mean_return = np.mean(returns)

        # Downside deviation: only negative returns
        negative_returns = returns[returns < 0]
        if len(negative_returns) == 0:
            return 0.0  # No losing days, can't compute downside deviation

        downside_std = np.std(negative_returns, ddof=1)
        if downside_std == 0:
            return 0.0

        daily_rf = self.risk_free_rate / 252
        sortino = (mean_return - daily_rf) / downside_std
        return round(sortino * np.sqrt(252), 4)

    def _calculate_calmar_ratio(
        self,
        trades: List[TradeRecord],
        max_dd_pct: float
    ) -> float:
        """
        Calculate Calmar Ratio.
        Calmar = Annual Return / Max Drawdown
        """
        if max_dd_pct == 0 or not trades:
            return 0.0

        # Calculate annualized return
        total_days = (trades[-1].exit_time - trades[0].entry_time).days
        if total_days < 1:
            total_days = 1

        total_return = (trades[-1].balance_after - self.initial_balance) / self.initial_balance
        annual_return = total_return * (365 / total_days) * 100

        return annual_return / max_dd_pct

    def _calculate_recovery_factor(
        self,
        trades: List[TradeRecord],
        max_dd: float
    ) -> float:
        """
        Calculate Recovery Factor.
        Recovery = Net Profit / Max Drawdown
        """
        if max_dd == 0:
            return 0.0

        net_profit = trades[-1].balance_after - self.initial_balance if trades else 0
        return net_profit / max_dd

    def _calculate_trade_statistics(self, trades: List[TradeRecord]) -> Dict[str, Any]:
        """Calculate detailed trade statistics"""
        if not trades:
            return {}

        profits = [t.profit_loss for t in trades if t.profit_loss > 0]
        losses = [t.profit_loss for t in trades if t.profit_loss < 0]

        # Average win/loss
        avg_win = np.mean(profits) if profits else 0.0
        avg_loss = abs(np.mean(losses)) if losses else 0.0

        # Largest win/loss
        largest_win = max(profits) if profits else 0.0
        largest_loss = min(losses) if losses else 0.0

        # R-multiples
        r_multiples = [t.r_multiple for t in trades if t.r_multiple != 0]
        avg_r = np.mean(r_multiples) if r_multiples else 0.0

        # Expectancy
        win_rate = len(profits) / len(trades) if trades else 0
        expectancy = (win_rate * avg_win) - ((1 - win_rate) * avg_loss)

        # Consecutive wins/losses
        max_consec_wins, max_consec_losses = self._calculate_consecutive_trades(trades)

        # Win/Loss ratio
        win_loss_ratio = (avg_win / avg_loss) if avg_loss > 0 else 0.0

        return {
            'avg_win': round(avg_win, 2),
            'avg_loss': round(avg_loss, 2),
            'largest_win': round(largest_win, 2),
            'largest_loss': round(largest_loss, 2),
            # Backwards compatibility: avg_rr_ratio historically stores avg win / avg loss.
            'avg_rr_ratio': round(win_loss_ratio, 2),
            'avg_win_loss_ratio': round(win_loss_ratio, 2),
            'avg_r_multiple': round(avg_r, 2),
            'expectancy': round(expectancy, 2),
            'max_consecutive_wins': max_consec_wins,
            'max_consecutive_losses': max_consec_losses,
        }

    def _calculate_consecutive_trades(
        self,
        trades: List[TradeRecord]
    ) -> Tuple[int, int]:
        """Calculate maximum consecutive wins and losses"""
        if not trades:
            return 0, 0

        max_wins = 0
        max_losses = 0
        current_wins = 0
        current_losses = 0

        for trade in trades:
            if trade.profit_loss > 0:
                current_wins += 1
                current_losses = 0
                max_wins = max(max_wins, current_wins)
            elif trade.profit_loss < 0:
                current_losses += 1
                current_wins = 0
                max_losses = max(max_losses, current_losses)
            else:
                current_wins = 0
                current_losses = 0

        return max_wins, max_losses

    def _calculate_time_metrics(self, trades: List[TradeRecord]) -> Dict[str, Any]:
        """Calculate time-based metrics"""
        if not trades:
            return {}

        # Trade durations
        durations = []
        for trade in trades:
            if trade.exit_time and trade.entry_time:
                duration = (trade.exit_time - trade.entry_time).total_seconds() / 60
                durations.append(duration)

        avg_duration = np.mean(durations) if durations else 0.0
        max_duration = max(durations) if durations else 0.0
        min_duration = min(durations) if durations else 0.0

        return {
            'avg_trade_duration': round(avg_duration, 1),
            'max_trade_duration': round(max_duration, 1),
            'min_trade_duration': round(min_duration, 1),
        }

    def calculate_daily_pnl(
        self,
        trades: List[TradeRecord]
    ) -> List[Dict[str, Any]]:
        """Calculate daily P&L breakdown"""
        if not trades:
            return []

        daily_pnl = {}

        for trade in trades:
            if not trade.exit_time:
                continue

            date_key = trade.exit_time.date()

            if date_key not in daily_pnl:
                daily_pnl[date_key] = {
                    'date': date_key.isoformat(),
                    'trades': 0,
                    'wins': 0,
                    'losses': 0,
                    'pnl': 0.0,
                    'gross_profit': 0.0,
                    'gross_loss': 0.0,
                }

            daily_pnl[date_key]['trades'] += 1
            daily_pnl[date_key]['pnl'] += trade.profit_loss

            if trade.profit_loss > 0:
                daily_pnl[date_key]['wins'] += 1
                daily_pnl[date_key]['gross_profit'] += trade.profit_loss
            elif trade.profit_loss < 0:
                daily_pnl[date_key]['losses'] += 1
                daily_pnl[date_key]['gross_loss'] += abs(trade.profit_loss)

        # Sort by date and convert to list
        sorted_dates = sorted(daily_pnl.keys())
        return [daily_pnl[d] for d in sorted_dates]

    def calculate_monthly_returns(
        self,
        trades: List[TradeRecord]
    ) -> Dict[str, float]:
        """Calculate monthly return percentages"""
        if not trades:
            return {}

        monthly_pnl = {}
        monthly_start_balance = {}

        for trade in trades:
            if not trade.exit_time:
                continue

            month_key = trade.exit_time.strftime('%Y-%m')

            if month_key not in monthly_pnl:
                monthly_pnl[month_key] = 0.0
                monthly_start_balance[month_key] = trade.balance_before

            monthly_pnl[month_key] += trade.profit_loss

        # Convert to percentages
        monthly_returns = {}
        for month, pnl in monthly_pnl.items():
            start_balance = monthly_start_balance.get(month, self.initial_balance)
            if start_balance > 0:
                monthly_returns[month] = round((pnl / start_balance) * 100, 2)

        return monthly_returns

    def generate_equity_curve(
        self,
        trades: List[TradeRecord]
    ) -> List[Dict[str, Any]]:
        """Generate equity curve data points"""
        if not trades:
            return []

        curve = []

        # Start point
        curve.append({
            'timestamp': trades[0].entry_time.isoformat(),
            'equity': self.initial_balance,
            'trade_number': 0,
        })

        for trade in trades:
            if trade.exit_time:
                curve.append({
                    'timestamp': trade.exit_time.isoformat(),
                    'equity': trade.balance_after,
                    'trade_number': trade.trade_number,
                    'pnl': trade.profit_loss,
                })

        return curve

    def calculate_setup_analysis(
        self,
        trades: List[TradeRecord]
    ) -> Dict[str, Dict[str, Any]]:
        """Analyze performance by setup type"""
        setup_stats = {}

        for trade in trades:
            setup = trade.setup_type or 'Unknown'

            if setup not in setup_stats:
                setup_stats[setup] = {
                    'count': 0,
                    'wins': 0,
                    'losses': 0,
                    'total_pnl': 0.0,
                    'avg_pnl': 0.0,
                    'win_rate': 0.0,
                }

            setup_stats[setup]['count'] += 1
            setup_stats[setup]['total_pnl'] += trade.profit_loss

            if trade.profit_loss > 0:
                setup_stats[setup]['wins'] += 1
            elif trade.profit_loss < 0:
                setup_stats[setup]['losses'] += 1

        # Calculate averages and win rates
        for setup in setup_stats:
            count = setup_stats[setup]['count']
            if count > 0:
                setup_stats[setup]['avg_pnl'] = round(
                    setup_stats[setup]['total_pnl'] / count, 2
                )
                setup_stats[setup]['win_rate'] = round(
                    setup_stats[setup]['wins'] / count * 100, 2
                )

        return setup_stats
