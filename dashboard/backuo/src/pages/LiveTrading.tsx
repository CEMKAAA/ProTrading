import { useQuery } from '@tanstack/react-query';
import {
  Activity,
  TrendingUp,
  TrendingDown,
  AlertCircle,
  Clock,
  DollarSign,
  Zap,
  Target,
} from 'lucide-react';
import { getLiveStatus } from '@/services/api';
import { formatCurrency } from '@/lib/utils';

export default function LiveTrading() {
  const { data: status, isLoading, refetch } = useQuery({
    queryKey: ['live-status'],
    queryFn: getLiveStatus,
    refetchInterval: 2000, // Update every 2 seconds
  });

  if (isLoading) {
    return (
      <div className="space-y-6">
        <div className="h-8 w-48 skeleton rounded" />
        <div className="grid grid-cols-4 gap-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <div key={i} className="h-32 skeleton rounded-lg" />
          ))}
        </div>
      </div>
    );
  }

  const isConnected = status?.is_connected ?? false;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Live Trading</h1>
          <p className="text-dark-400 mt-1">
            Monitor your live trading bot
          </p>
        </div>
        <div className="flex items-center gap-3">
          <div
            className={`flex items-center gap-2 px-3 py-2 rounded-lg ${
              isConnected ? 'bg-success-500/10' : 'bg-danger-500/10'
            }`}
          >
            <span
              className={`w-2 h-2 rounded-full ${
                isConnected ? 'bg-success-500 animate-pulse' : 'bg-danger-500'
              }`}
            />
            <span
              className={isConnected ? 'text-success-500' : 'text-danger-500'}
            >
              {isConnected ? 'MT5 Connected' : 'MT5 Disconnected'}
            </span>
          </div>
        </div>
      </div>

      {!isConnected ? (
        <div className="card p-8 text-center">
          <AlertCircle className="w-16 h-16 text-danger-500 mx-auto mb-4" />
          <h2 className="text-xl font-bold text-white mb-2">
            MetaTrader 5 Not Connected
          </h2>
          <p className="text-dark-400 max-w-md mx-auto">
            Make sure MetaTrader 5 is running and the trading bot is started.
            The dashboard will automatically update when connected.
          </p>
        </div>
      ) : (
        <>
          {/* Main Stats */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            <StatCard
              icon={DollarSign}
              label="Balance"
              value={formatCurrency(status?.balance || 0)}
            />
            <StatCard
              icon={Activity}
              label="Equity"
              value={formatCurrency(status?.equity || 0)}
            />
            <StatCard
              icon={status?.daily_pnl && status.daily_pnl >= 0 ? TrendingUp : TrendingDown}
              label="Daily P&L"
              value={formatCurrency(status?.daily_pnl || 0)}
              trend={status?.daily_pnl && status.daily_pnl >= 0 ? 'up' : 'down'}
            />
            <StatCard
              icon={Target}
              label="Daily Trades"
              value={status?.daily_trades?.toString() || '0'}
              subtext="/2 max"
            />
          </div>

          {/* Price & Trading Status */}
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
            {/* Current Price Panel */}
            <div className="card p-6">
              <h2 className="text-lg font-semibold text-white mb-4">XAUUSD</h2>
              <div className="flex items-center gap-8">
                <div>
                  <div className="text-4xl font-bold text-white font-mono">
                    {status?.current_price?.toFixed(2) || '---'}
                  </div>
                  <div className="text-dark-400 text-sm mt-1">
                    Spread: ${status?.spread?.toFixed(3) || '---'}
                  </div>
                </div>
                <div className="flex-1 grid grid-cols-2 gap-4">
                  <div className="text-center">
                    <div className="text-dark-400 text-sm">Can Trade</div>
                    <div
                      className={`text-lg font-bold ${
                        status?.can_trade ? 'text-success-500' : 'text-danger-500'
                      }`}
                    >
                      {status?.can_trade ? 'Yes' : 'No'}
                    </div>
                  </div>
                  <div className="text-center">
                    <div className="text-dark-400 text-sm">Trading</div>
                    <div
                      className={`text-lg font-bold ${
                        status?.is_trading ? 'text-success-500' : 'text-dark-400'
                      }`}
                    >
                      {status?.is_trading ? 'Active' : 'Idle'}
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* Session Analysis */}
            <div className="card p-6">
              <h2 className="text-lg font-semibold text-white mb-4">
                Session Analysis
              </h2>
              <div className="space-y-4">
                <div className="flex items-center justify-between">
                  <span className="text-dark-400">Session Bias</span>
                  <span
                    className={`font-bold text-lg ${
                      status?.session_bias === 'bullish'
                        ? 'text-success-500'
                        : status?.session_bias === 'bearish'
                        ? 'text-danger-500'
                        : 'text-dark-400'
                    }`}
                  >
                    {status?.session_bias?.toUpperCase() || 'NEUTRAL'}
                  </span>
                </div>
                <div className="flex items-center justify-between">
                  <span className="text-dark-400">Is Trending</span>
                  <span
                    className={`font-medium ${
                      status?.is_trending ? 'text-success-500' : 'text-warning-500'
                    }`}
                  >
                    {status?.is_trending ? 'Yes (ADR > $20)' : 'No (Ranging)'}
                  </span>
                </div>
                {status?.margin_level && (
                  <div className="flex items-center justify-between">
                    <span className="text-dark-400">Margin Level</span>
                    <span className="text-white font-mono">
                      {status.margin_level.toFixed(0)}%
                    </span>
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Session Levels */}
          <div className="card">
            <div className="card-header">
              <h2 className="font-semibold text-white">Session Levels</h2>
            </div>
            <div className="card-body">
              <div className="grid grid-cols-2 md:grid-cols-4 gap-6">
                <LevelDisplay
                  label="ORB High"
                  value={status?.orb_high}
                  color="text-success-500"
                />
                <LevelDisplay
                  label="ORB Low"
                  value={status?.orb_low}
                  color="text-danger-500"
                />
                <LevelDisplay
                  label="Asian High"
                  value={status?.asian_high}
                  color="text-primary-500"
                />
                <LevelDisplay
                  label="Asian Low"
                  value={status?.asian_low}
                  color="text-warning-500"
                />
              </div>
            </div>
          </div>

          {/* Trading Rules */}
          <div className="card">
            <div className="card-header">
              <h2 className="font-semibold text-white">Trading Rules Status</h2>
            </div>
            <div className="card-body">
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <RuleCard
                  label="Daily Loss Limit"
                  passed={(status?.daily_pnl || 0) > -150}
                  detail="Max -$150/day"
                />
                <RuleCard
                  label="Trade Count"
                  passed={(status?.daily_trades || 0) < 2}
                  detail={`${status?.daily_trades || 0}/2 trades`}
                />
                <RuleCard
                  label="Trending Market"
                  passed={status?.is_trending || false}
                  detail="ADR > $20"
                />
                <RuleCard
                  label="Spread Check"
                  passed={(status?.spread || 1) < 0.40}
                  detail="Max $0.40"
                />
              </div>
            </div>
          </div>

          {/* Time Info */}
          <div className="text-center text-dark-500 text-sm">
            <Clock className="w-4 h-4 inline mr-1" />
            {status?.current_time_ny
              ? `NY Time: ${new Date(status.current_time_ny).toLocaleTimeString()}`
              : 'Time unavailable'}
            <span className="mx-2">|</span>
            Auto-refreshing every 2 seconds
          </div>
        </>
      )}
    </div>
  );
}

interface StatCardProps {
  icon: React.ElementType;
  label: string;
  value: string;
  subtext?: string;
  trend?: 'up' | 'down';
}

function StatCard({ icon: Icon, label, value, subtext, trend }: StatCardProps) {
  return (
    <div className="card p-4">
      <div className="flex items-start justify-between">
        <div>
          <div className="text-dark-400 text-sm">{label}</div>
          <div
            className={`text-2xl font-bold mt-1 ${
              trend === 'up'
                ? 'text-success-500'
                : trend === 'down'
                ? 'text-danger-500'
                : 'text-white'
            }`}
          >
            {value}
            {subtext && (
              <span className="text-dark-500 text-sm font-normal ml-1">
                {subtext}
              </span>
            )}
          </div>
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

function LevelDisplay({
  label,
  value,
  color,
}: {
  label: string;
  value?: number;
  color: string;
}) {
  return (
    <div>
      <div className="text-dark-400 text-sm">{label}</div>
      <div className={`text-xl font-mono font-bold ${value ? color : 'text-dark-600'}`}>
        {value?.toFixed(2) || '---'}
      </div>
    </div>
  );
}

function RuleCard({
  label,
  passed,
  detail,
}: {
  label: string;
  passed: boolean;
  detail: string;
}) {
  return (
    <div
      className={`p-3 rounded-lg border ${
        passed
          ? 'bg-success-500/5 border-success-500/20'
          : 'bg-danger-500/5 border-danger-500/20'
      }`}
    >
      <div className="flex items-center gap-2">
        <span
          className={`w-2 h-2 rounded-full ${
            passed ? 'bg-success-500' : 'bg-danger-500'
          }`}
        />
        <span className="text-white text-sm font-medium">{label}</span>
      </div>
      <div className="text-dark-400 text-xs mt-1">{detail}</div>
    </div>
  );
}
