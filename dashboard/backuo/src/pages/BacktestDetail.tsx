import { useEffect, useMemo } from 'react';
import { useParams, Link, useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import {
  ArrowLeft,
  Download,
  TrendingUp,
  TrendingDown,
  Target,
  AlertTriangle,
  Clock,
  DollarSign,
  BarChart3,
  Activity,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { getBacktestResult, getBacktestTrades, exportBacktest, downloadFile } from '@/services/api';
import { wsService, onBacktestProgress, onBacktestCompleted } from '@/services/websocket';
import { useDashboardStore } from '@/store';
import {
  formatCurrency,
  formatPercent,
  formatDateTime,
  formatDuration,
  classifyWinRate,
  classifyProfitFactor,
  classifyDrawdown,
} from '@/lib/utils';
import EquityChart from '@/components/charts/EquityChart';
import TradesTable from '@/components/TradesTable';

export default function BacktestDetail() {
  const { resultId } = useParams<{ resultId: string }>();
  const navigate = useNavigate();
  const { setBacktestProgress, runningBacktests, clearBacktestProgress } = useDashboardStore();

  const { data: result, isLoading, refetch } = useQuery({
    queryKey: ['backtest-result', resultId],
    queryFn: () => getBacktestResult(parseInt(resultId!)),
    enabled: !!resultId,
    refetchInterval: (query) => {
      // Poll while running
      return query.state.data?.status === 'RUNNING' ? 2000 : false;
    },
  });

  const { data: trades } = useQuery({
    queryKey: ['backtest-trades', resultId],
    queryFn: () => getBacktestTrades(parseInt(resultId!)),
    enabled: !!resultId && result?.status === 'COMPLETED',
  });

  // WebSocket subscription for real-time updates
  useEffect(() => {
    if (!resultId) return;

    wsService.connect().then(() => {
      wsService.subscribeToBacktest(parseInt(resultId));
    });

    const unsubProgress = onBacktestProgress((msg) => {
      if (msg.result_id === parseInt(resultId)) {
        setBacktestProgress(msg.result_id, msg.progress, msg.message);
      }
    });

    const unsubCompleted = onBacktestCompleted((msg) => {
      if (msg.result_id === parseInt(resultId)) {
        clearBacktestProgress(msg.result_id);
        refetch();
        toast.success('Backtest completed!');
      }
    });

    return () => {
      unsubProgress();
      unsubCompleted();
      wsService.unsubscribeFromBacktest(parseInt(resultId));
    };
  }, [resultId, setBacktestProgress, clearBacktestProgress, refetch]);

  const progress = runningBacktests.get(parseInt(resultId!));

  const handleExport = async (format: 'csv' | 'json') => {
    try {
      const blob = await exportBacktest(parseInt(resultId!), format);
      downloadFile(blob, `backtest_${resultId}.${format}`);
      toast.success('Export downloaded');
    } catch {
      toast.error('Failed to export');
    }
  };

  if (isLoading) {
    return (
      <div className="space-y-6">
        <div className="h-8 w-48 skeleton rounded" />
        <div className="grid grid-cols-4 gap-4">
          {Array.from({ length: 8 }).map((_, i) => (
            <div key={i} className="h-24 skeleton rounded-lg" />
          ))}
        </div>
        <div className="h-96 skeleton rounded-lg" />
      </div>
    );
  }

  if (!result) {
    return (
      <div className="text-center py-12">
        <p className="text-dark-400">Backtest not found</p>
        <Link to="/backtests" className="text-primary-500 hover:underline mt-2">
          Back to backtests
        </Link>
      </div>
    );
  }

  const metrics = result.metrics;
  const winRateClass = classifyWinRate(metrics.win_rate);
  const pfClass = classifyProfitFactor(metrics.profit_factor);
  const ddClass = classifyDrawdown(metrics.max_drawdown_percent);

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <button
            onClick={() => navigate('/backtests')}
            className="p-2 text-dark-400 hover:text-white hover:bg-dark-800 rounded-lg"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <div>
            <h1 className="text-2xl font-bold text-white">
              {result.config?.name || `Backtest #${resultId}`}
            </h1>
            <div className="flex items-center gap-3 mt-1">
              <StatusBadge status={result.status} />
              {result.started_at && (
                <span className="text-dark-400 text-sm">
                  Started {formatDateTime(result.started_at)}
                </span>
              )}
            </div>
          </div>
        </div>
        {result.status === 'COMPLETED' && (
          <div className="flex items-center gap-2">
            <button
              onClick={() => handleExport('csv')}
              className="btn btn-secondary btn-sm"
            >
              <Download className="w-4 h-4" />
              CSV
            </button>
            <button
              onClick={() => handleExport('json')}
              className="btn btn-secondary btn-sm"
            >
              <Download className="w-4 h-4" />
              JSON
            </button>
          </div>
        )}
      </div>

      {/* Progress Bar (while running) */}
      {(result.status === 'RUNNING' || result.status === 'PENDING') && (
        <div className="card p-4">
          <div className="flex items-center justify-between mb-2">
            <span className="text-white font-medium">
              {progress?.message || 'Processing...'}
            </span>
            <span className="text-dark-400">{(progress?.progress || 0).toFixed(0)}%</span>
          </div>
          <div className="h-2 bg-dark-700 rounded-full overflow-hidden">
            <div
              className="h-full bg-primary-500 transition-all duration-300"
              style={{ width: `${progress?.progress || 0}%` }}
            />
          </div>
        </div>
      )}

      {/* Error Message */}
      {result.status === 'FAILED' && result.error_message && (
        <div className="card bg-danger-500/10 border-danger-500/50 p-4">
          <div className="flex items-center gap-2 text-danger-500">
            <AlertTriangle className="w-5 h-5" />
            <span className="font-medium">Backtest Failed</span>
          </div>
          <p className="text-dark-300 mt-2">{result.error_message}</p>
        </div>
      )}

      {/* Metrics Grid */}
      {result.status === 'COMPLETED' && (
        <>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <MetricCard
              icon={BarChart3}
              label="Total Trades"
              value={metrics.total_trades.toString()}
              subtext={`${metrics.winning_trades}W / ${metrics.losing_trades}L`}
            />
            <MetricCard
              icon={Target}
              label="Win Rate"
              value={formatPercent(metrics.win_rate)}
              valueColor={winRateClass.color}
              subtext={winRateClass.label}
            />
            <MetricCard
              icon={metrics.net_profit >= 0 ? TrendingUp : TrendingDown}
              label="Net Profit"
              value={formatCurrency(metrics.net_profit)}
              valueColor={metrics.net_profit >= 0 ? 'text-success-500' : 'text-danger-500'}
              subtext={`${((metrics.net_profit / metrics.initial_balance) * 100).toFixed(1)}% return`}
            />
            <MetricCard
              icon={Activity}
              label="Profit Factor"
              value={metrics.profit_factor.toFixed(2)}
              valueColor={pfClass.color}
              subtext={pfClass.label}
            />
          </div>

          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <MetricCard
              icon={AlertTriangle}
              label="Max Drawdown"
              value={formatPercent(metrics.max_drawdown_percent)}
              valueColor={ddClass.color}
              subtext={`${formatCurrency(metrics.max_drawdown)} ${ddClass.label}`}
            />
            <MetricCard
              icon={DollarSign}
              label="Avg Win / Loss"
              value={`$${metrics.avg_win.toFixed(0)} / $${metrics.avg_loss.toFixed(0)}`}
              subtext={`R:R ${metrics.avg_rr_ratio.toFixed(2)}`}
            />
            <MetricCard
              icon={Clock}
              label="Avg Trade Duration"
              value={formatDuration(metrics.avg_trade_duration)}
            />
            <MetricCard
              icon={Target}
              label="Expectancy"
              value={formatCurrency(metrics.expectancy)}
              valueColor={metrics.expectancy >= 0 ? 'text-success-500' : 'text-danger-500'}
              subtext="Per trade"
            />
          </div>

          {/* Risk Metrics */}
          <div className="card p-4">
            <h3 className="font-semibold text-white mb-4">Risk Metrics</h3>
            <div className="grid grid-cols-3 md:grid-cols-6 gap-4">
              <div>
                <div className="text-dark-400 text-sm">Sharpe Ratio</div>
                <div className="text-lg font-mono text-white">
                  {metrics.sharpe_ratio.toFixed(2)}
                </div>
              </div>
              <div>
                <div className="text-dark-400 text-sm">Sortino Ratio</div>
                <div className="text-lg font-mono text-white">
                  {metrics.sortino_ratio.toFixed(2)}
                </div>
              </div>
              <div>
                <div className="text-dark-400 text-sm">Calmar Ratio</div>
                <div className="text-lg font-mono text-white">
                  {metrics.calmar_ratio.toFixed(2)}
                </div>
              </div>
              <div>
                <div className="text-dark-400 text-sm">Largest Win</div>
                <div className="text-lg font-mono text-success-500">
                  {formatCurrency(metrics.largest_win)}
                </div>
              </div>
              <div>
                <div className="text-dark-400 text-sm">Largest Loss</div>
                <div className="text-lg font-mono text-danger-500">
                  {formatCurrency(metrics.largest_loss)}
                </div>
              </div>
              <div>
                <div className="text-dark-400 text-sm">Final Balance</div>
                <div className="text-lg font-mono text-white">
                  {formatCurrency(metrics.final_balance)}
                </div>
              </div>
            </div>
          </div>

          {/* Equity Chart */}
          {result.equity_curve && result.equity_curve.length > 0 && (
            <div className="card p-4">
              <h3 className="font-semibold text-white mb-4">Equity Curve</h3>
              <div className="h-80">
                <EquityChart data={result.equity_curve} />
              </div>
            </div>
          )}

          {/* Monthly Returns */}
          {result.monthly_returns && Object.keys(result.monthly_returns).length > 0 && (
            <div className="card p-4">
              <h3 className="font-semibold text-white mb-4">Monthly Returns</h3>
              <div className="grid grid-cols-6 md:grid-cols-12 gap-2">
                {Object.entries(result.monthly_returns).map(([month, ret]) => (
                  <div
                    key={month}
                    className={`p-2 rounded text-center ${
                      ret >= 0 ? 'bg-success-500/10' : 'bg-danger-500/10'
                    }`}
                  >
                    <div className="text-xs text-dark-400">{month}</div>
                    <div
                      className={`text-sm font-mono ${
                        ret >= 0 ? 'text-success-500' : 'text-danger-500'
                      }`}
                    >
                      {ret >= 0 ? '+' : ''}{ret.toFixed(1)}%
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Trades Table */}
          {trades && trades.length > 0 && (
            <div className="card">
              <div className="card-header">
                <h3 className="font-semibold text-white">Trade History</h3>
              </div>
              <TradesTable trades={trades} />
            </div>
          )}
        </>
      )}
    </div>
  );
}

function StatusBadge({ status }: { status: string }) {
  const styles = {
    COMPLETED: 'badge-success',
    RUNNING: 'badge-info',
    PENDING: 'badge-warning',
    FAILED: 'badge-danger',
  };

  return (
    <span className={`badge ${styles[status as keyof typeof styles]}`}>
      {status}
    </span>
  );
}

interface MetricCardProps {
  icon: React.ElementType;
  label: string;
  value: string;
  valueColor?: string;
  subtext?: string;
}

function MetricCard({ icon: Icon, label, value, valueColor, subtext }: MetricCardProps) {
  return (
    <div className="card p-4">
      <div className="flex items-center gap-2 mb-2">
        <Icon className="w-4 h-4 text-dark-400" />
        <span className="text-sm text-dark-400">{label}</span>
      </div>
      <div className={`text-xl font-bold ${valueColor || 'text-white'}`}>
        {value}
      </div>
      {subtext && <div className="text-xs text-dark-500 mt-1">{subtext}</div>}
    </div>
  );
}
