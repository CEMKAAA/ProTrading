import { useQuery } from '@tanstack/react-query';
import {
  TrendingUp,
  TrendingDown,
  Activity,
  BarChart3,
  Target,
  AlertTriangle,
  DollarSign,
  Percent,
} from 'lucide-react';
import { getDashboardStats, getLiveStatus, getBacktestResults } from '@/services/api';
import { formatCurrency, formatPercent } from '@/lib/utils';

export default function Dashboard() {
  const { data: stats, isLoading: statsLoading } = useQuery({
    queryKey: ['dashboard-stats'],
    queryFn: getDashboardStats,
    refetchInterval: 30000,
  });

  const { data: liveStatus, isLoading: liveLoading } = useQuery({
    queryKey: ['live-status'],
    queryFn: getLiveStatus,
    refetchInterval: 5000,
  });

  const { data: recentResults } = useQuery({
    queryKey: ['recent-results'],
    queryFn: () => getBacktestResults(0, 5),
  });

  return (
    <div className="space-y-6">
      {/* Page header */}
      <div>
        <h1 className="text-2xl font-bold text-white">Dashboard</h1>
        <p className="text-dark-400 mt-1">
          Overview of your trading system performance
        </p>
      </div>

      {/* Stats grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Account Balance"
          value={formatCurrency(liveStatus?.balance || 0)}
          icon={DollarSign}
          loading={liveLoading}
        />
        <StatCard
          title="Daily P&L"
          value={formatCurrency(liveStatus?.daily_pnl || 0)}
          icon={liveStatus?.daily_pnl && liveStatus.daily_pnl >= 0 ? TrendingUp : TrendingDown}
          trend={liveStatus?.daily_pnl && liveStatus.daily_pnl >= 0 ? 'up' : 'down'}
          loading={liveLoading}
        />
        <StatCard
          title="Best Win Rate"
          value={formatPercent(stats?.best_win_rate || 0)}
          icon={Target}
          loading={statsLoading}
        />
        <StatCard
          title="Total Backtests"
          value={stats?.successful_backtests?.toString() || '0'}
          subtitle={`of ${stats?.total_backtests || 0} total`}
          icon={BarChart3}
          loading={statsLoading}
        />
      </div>

      {/* Live Status Panel */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Live Trading Status */}
        <div className="lg:col-span-1 card">
          <div className="card-header flex items-center justify-between">
            <h2 className="font-semibold text-white">Live Status</h2>
            <div className="flex items-center gap-2">
              <span
                className={`w-2 h-2 rounded-full ${
                  liveStatus?.is_connected ? 'bg-success-500' : 'bg-danger-500'
                }`}
              />
              <span className="text-sm text-dark-400">
                {liveStatus?.is_connected ? 'Connected' : 'Disconnected'}
              </span>
            </div>
          </div>
          <div className="card-body space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <div>
                <div className="text-dark-400 text-sm">Current Price</div>
                <div className="text-xl font-mono text-white">
                  {liveStatus?.current_price?.toFixed(2) || '---'}
                </div>
              </div>
              <div>
                <div className="text-dark-400 text-sm">Spread</div>
                <div className="text-xl font-mono text-white">
                  ${liveStatus?.spread?.toFixed(3) || '---'}
                </div>
              </div>
            </div>

            <div className="border-t border-dark-700 pt-4">
              <div className="flex items-center justify-between text-sm">
                <span className="text-dark-400">Session Bias</span>
                <span
                  className={`font-medium ${
                    liveStatus?.session_bias === 'bullish'
                      ? 'text-success-500'
                      : liveStatus?.session_bias === 'bearish'
                      ? 'text-danger-500'
                      : 'text-dark-400'
                  }`}
                >
                  {liveStatus?.session_bias?.toUpperCase() || 'N/A'}
                </span>
              </div>
              <div className="flex items-center justify-between text-sm mt-2">
                <span className="text-dark-400">Is Trending</span>
                <span
                  className={
                    liveStatus?.is_trending ? 'text-success-500' : 'text-warning-500'
                  }
                >
                  {liveStatus?.is_trending ? 'Yes' : 'No'}
                </span>
              </div>
              <div className="flex items-center justify-between text-sm mt-2">
                <span className="text-dark-400">Can Trade</span>
                <span
                  className={
                    liveStatus?.can_trade ? 'text-success-500' : 'text-danger-500'
                  }
                >
                  {liveStatus?.can_trade ? 'Yes' : 'No'}
                </span>
              </div>
            </div>

            <div className="border-t border-dark-700 pt-4">
              <div className="text-dark-400 text-sm mb-2">Session Levels</div>
              <div className="grid grid-cols-2 gap-2 text-sm font-mono">
                <div>
                  <span className="text-dark-500">ORB H:</span>{' '}
                  <span className="text-white">
                    {liveStatus?.orb_high?.toFixed(2) || '---'}
                  </span>
                </div>
                <div>
                  <span className="text-dark-500">ORB L:</span>{' '}
                  <span className="text-white">
                    {liveStatus?.orb_low?.toFixed(2) || '---'}
                  </span>
                </div>
                <div>
                  <span className="text-dark-500">Asian H:</span>{' '}
                  <span className="text-white">
                    {liveStatus?.asian_high?.toFixed(2) || '---'}
                  </span>
                </div>
                <div>
                  <span className="text-dark-500">Asian L:</span>{' '}
                  <span className="text-white">
                    {liveStatus?.asian_low?.toFixed(2) || '---'}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* Recent Backtests */}
        <div className="lg:col-span-2 card">
          <div className="card-header">
            <h2 className="font-semibold text-white">Recent Backtests</h2>
          </div>
          <div className="overflow-x-auto">
            <table className="table">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Status</th>
                  <th>Trades</th>
                  <th>Win Rate</th>
                  <th>Net P&L</th>
                  <th>Max DD</th>
                </tr>
              </thead>
              <tbody>
                {recentResults?.map((result) => (
                  <tr key={result.id}>
                    <td className="font-medium text-white">
                      {result.config_name}
                    </td>
                    <td>
                      <StatusBadge status={result.status} />
                    </td>
                    <td>{result.total_trades}</td>
                    <td
                      className={
                        result.win_rate >= 50 ? 'text-success-500' : 'text-danger-500'
                      }
                    >
                      {result.win_rate.toFixed(1)}%
                    </td>
                    <td
                      className={
                        result.net_profit >= 0 ? 'text-success-500' : 'text-danger-500'
                      }
                    >
                      {formatCurrency(result.net_profit)}
                    </td>
                    <td className="text-danger-500">
                      {result.max_drawdown_percent.toFixed(1)}%
                    </td>
                  </tr>
                ))}
                {(!recentResults || recentResults.length === 0) && (
                  <tr>
                    <td colSpan={6} className="text-center text-dark-400 py-8">
                      No backtests yet. Create a configuration to get started.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {/* Performance Highlights */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div className="card p-4">
          <div className="flex items-center gap-3">
            <div className="p-3 bg-primary-500/10 rounded-lg">
              <Percent className="w-6 h-6 text-primary-500" />
            </div>
            <div>
              <div className="text-dark-400 text-sm">Best Profit Factor</div>
              <div className="text-xl font-bold text-white">
                {stats?.best_profit_factor?.toFixed(2) || '---'}
              </div>
            </div>
          </div>
        </div>

        <div className="card p-4">
          <div className="flex items-center gap-3">
            <div className="p-3 bg-success-500/10 rounded-lg">
              <Target className="w-6 h-6 text-success-500" />
            </div>
            <div>
              <div className="text-dark-400 text-sm">Lowest Drawdown</div>
              <div className="text-xl font-bold text-white">
                {stats?.lowest_drawdown?.toFixed(1) || '---'}%
              </div>
            </div>
          </div>
        </div>

        <div className="card p-4">
          <div className="flex items-center gap-3">
            <div className="p-3 bg-warning-500/10 rounded-lg">
              <Activity className="w-6 h-6 text-warning-500" />
            </div>
            <div>
              <div className="text-dark-400 text-sm">Today's Trades</div>
              <div className="text-xl font-bold text-white">
                {liveStatus?.daily_trades || 0}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

interface StatCardProps {
  title: string;
  value: string;
  subtitle?: string;
  icon: React.ElementType;
  trend?: 'up' | 'down';
  loading?: boolean;
}

function StatCard({
  title,
  value,
  subtitle,
  icon: Icon,
  trend,
  loading,
}: StatCardProps) {
  return (
    <div className="stat-card">
      <div className="flex items-start justify-between">
        <div>
          <div className="text-dark-400 text-sm">{title}</div>
          {loading ? (
            <div className="h-8 w-24 skeleton rounded mt-1" />
          ) : (
            <div
              className={`stat-value ${
                trend === 'up'
                  ? 'text-success-500'
                  : trend === 'down'
                  ? 'text-danger-500'
                  : ''
              }`}
            >
              {value}
            </div>
          )}
          {subtitle && <div className="text-dark-500 text-sm mt-1">{subtitle}</div>}
        </div>
        <div
          className={`p-2 rounded-lg ${
            trend === 'up'
              ? 'bg-success-500/10'
              : trend === 'down'
              ? 'bg-danger-500/10'
              : 'bg-dark-700'
          }`}
        >
          <Icon
            className={`w-5 h-5 ${
              trend === 'up'
                ? 'text-success-500'
                : trend === 'down'
                ? 'text-danger-500'
                : 'text-dark-400'
            }`}
          />
        </div>
      </div>
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
    <span className={`badge ${styles[status as keyof typeof styles] || 'badge-info'}`}>
      {status}
    </span>
  );
}
