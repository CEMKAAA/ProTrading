// Trading Dashboard Types

export type TimeframeEnum = 'M1' | 'M5' | 'M15' | 'M30' | 'H1' | 'H4' | 'D1';
export type TradeDirection = 'BUY' | 'SELL';
export type BacktestStatus = 'PENDING' | 'RUNNING' | 'COMPLETED' | 'FAILED';

export interface BacktestConfig {
  id?: number;
  name: string;
  description?: string;
  created_at?: string;

  // Symbol & Timeframe
  symbol: string;
  timeframe: TimeframeEnum;

  // Date Range
  start_date: string;
  end_date: string;

  // Risk Management
  initial_balance: number;
  risk_percent: number;
  max_spread_usd: number;
  max_daily_loss_usd: number;
  max_total_risk_usd: number;

  // Stop Loss Parameters
  min_sl_usd: number;
  max_sl_usd: number;
  gold_rr_threshold: number;

  // ICT Parameters - FVG
  min_fvg_gap: number;
  fvg_lookback: number;

  // ICT Parameters - Displacement
  displacement_percentile: number;
  displacement_lookback: number;
  max_opposing_wick_ratio: number;

  // ICT Parameters - Order Blocks
  ob_lookback: number;
  ob_min_body_percent: number;
  ob_validation_bars: number;

  // ICT Parameters - Liquidity
  liquidity_wick_ratio: number;
  sweep_tolerance_usd: number;

  // Session Times
  orb_start_time: string;
  orb_end_time: string;
  trade_start_time: string;
  trade_end_time: string;
  asian_start: string;
  asian_end: string;
  london_start: string;
  london_end: string;

  // Trailing Stop
  use_trailing: boolean;
  trailing_atr_period: number;
  trailing_atr_multiplier: number;

  // Trend Filter
  min_adr_for_trend: number;
  adr_period: number;
}

export interface PerformanceMetrics {
  total_trades: number;
  winning_trades: number;
  losing_trades: number;
  win_rate: number;

  initial_balance: number;
  final_balance: number;
  total_profit: number;
  total_loss: number;
  net_profit: number;
  profit_factor: number;

  max_drawdown: number;
  max_drawdown_percent: number;
  sharpe_ratio: number;
  sortino_ratio: number;
  calmar_ratio: number;

  avg_win: number;
  avg_loss: number;
  largest_win: number;
  largest_loss: number;
  avg_trade_duration: number;

  avg_rr_ratio: number;
  expectancy: number;
}

export interface Trade {
  id?: number;
  trade_number: number;
  direction: TradeDirection;
  status: string;

  entry_time: string;
  exit_time?: string;

  entry_price: number;
  exit_price?: number;
  stop_loss: number;
  take_profit?: number;
  lot_size: number;

  profit_loss: number;
  profit_loss_pips?: number;
  profit_loss_percent?: number;
  r_multiple: number;

  setup_type?: string;
  bias?: string;
  exit_reason?: string;

  orb_high?: number;
  orb_low?: number;
  asian_high?: number;
  asian_low?: number;

  fvg_size?: number;
  ob_high?: number;
  ob_low?: number;

  balance_before?: number;
  balance_after?: number;
}

export interface BacktestResult {
  id: number;
  config_id: number;
  status: BacktestStatus;
  started_at?: string;
  completed_at?: string;
  error_message?: string;

  metrics: PerformanceMetrics;

  equity_curve?: EquityPoint[];
  drawdown_curve?: DrawdownPoint[];
  daily_pnl?: DailyPnL[];
  monthly_returns?: Record<string, number>;

  config?: BacktestConfig;
}

export interface BacktestResultSummary {
  id: number;
  config_id: number;
  config_name: string;
  status: BacktestStatus;
  started_at?: string;
  completed_at?: string;
  total_trades: number;
  win_rate: number;
  net_profit: number;
  max_drawdown_percent: number;
}

export interface EquityPoint {
  timestamp: string;
  equity: number;
  trade_number?: number;
  pnl?: number;
}

export interface DrawdownPoint {
  timestamp: string;
  drawdown: number;
  drawdown_pct: number;
  equity: number;
  peak: number;
}

export interface DailyPnL {
  date: string;
  trades: number;
  wins: number;
  losses: number;
  pnl: number;
  gross_profit: number;
  gross_loss: number;
}

export interface DashboardStats {
  total_backtests: number;
  successful_backtests: number;
  total_live_trades: number;
  current_balance: number;
  daily_pnl: number;
  weekly_pnl: number;
  monthly_pnl: number;
  best_win_rate: number;
  best_profit_factor: number;
  lowest_drawdown: number;
  open_positions: number;
  total_exposure: number;
}

export interface LiveStatus {
  is_connected: boolean;
  is_trading: boolean;
  current_time_ny?: string;
  current_price?: number;
  spread?: number;
  session_bias?: string;
  is_trending: boolean;
  orb_high?: number;
  orb_low?: number;
  asian_high?: number;
  asian_low?: number;
  daily_trades: number;
  daily_pnl: number;
  can_trade: boolean;
  balance: number;
  equity: number;
  margin_level?: number;
}

export interface CandleData {
  time: number;
  open: number;
  high: number;
  low: number;
  close: number;
  volume?: number;
}

export interface ChartAnnotation {
  type: string;
  time: number;
  price?: number;
  price_high?: number;
  price_low?: number;
  color?: string;
  label?: string;
}

// WebSocket Message Types
export interface WSMessage {
  type: string;
  timestamp: string;
  [key: string]: unknown;
}

export interface BacktestProgressMessage extends WSMessage {
  type: 'backtest_progress';
  result_id: number;
  progress: number;
  message: string;
}

export interface BacktestCompletedMessage extends WSMessage {
  type: 'backtest_completed';
  result_id: number;
  status: string;
  summary: {
    total_trades: number;
    win_rate: number;
    net_profit: number;
    max_drawdown_percent: number;
  };
}

// Form Types
export interface BacktestConfigForm extends Omit<BacktestConfig, 'id' | 'created_at'> {}
