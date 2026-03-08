import { useEffect, useState } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import {
  ArrowLeft,
  Save,
  Play,
  RefreshCw,
  Settings,
  Clock,
  Shield,
  TrendingUp,
  Zap,
} from 'lucide-react';
import toast from 'react-hot-toast';
import {
  getConfig,
  createConfig,
  updateConfig,
  runBacktest,
  getDefaultConfig,
  getAggressivePreset,
  getConservativePreset,
} from '@/services/api';
import type { BacktestConfig, BacktestConfigForm } from '@/types';

const configSchema = z.object({
  name: z.string().min(1, 'Name is required').max(255),
  description: z.string().optional(),
  symbol: z.string().default('XAUUSD'),
  timeframe: z.enum(['M1', 'M5', 'M15', 'M30', 'H1', 'H4', 'D1']).default('M1'),
  start_date: z.string().min(1, 'Start date is required'),
  end_date: z.string().min(1, 'End date is required'),
  initial_balance: z.coerce.number().min(100, 'Minimum $100'),
  risk_percent: z.coerce.number().min(0.1).max(10),
  max_spread_usd: z.coerce.number().min(0.01).max(5),
  max_daily_loss_usd: z.coerce.number().max(0),
  max_total_risk_usd: z.coerce.number().min(10),
  min_sl_usd: z.coerce.number().min(0.1).max(50),
  max_sl_usd: z.coerce.number().min(0.5).max(100),
  gold_rr_threshold: z.coerce.number().min(0.5).max(20),
  min_fvg_gap: z.coerce.number().min(0.05).max(5),
  fvg_lookback: z.coerce.number().min(10).max(500),
  displacement_percentile: z.coerce.number().min(50).max(99),
  displacement_lookback: z.coerce.number().min(5).max(100),
  max_opposing_wick_ratio: z.coerce.number().min(0.1).max(1),
  ob_lookback: z.coerce.number().min(20).max(500),
  ob_min_body_percent: z.coerce.number().min(30).max(90),
  ob_validation_bars: z.coerce.number().min(1).max(10),
  liquidity_wick_ratio: z.coerce.number().min(0.2).max(1),
  sweep_tolerance_usd: z.coerce.number().min(0.05).max(2),
  orb_start_time: z.string().regex(/^\d{2}:\d{2}$/),
  orb_end_time: z.string().regex(/^\d{2}:\d{2}$/),
  trade_start_time: z.string().regex(/^\d{2}:\d{2}$/),
  trade_end_time: z.string().regex(/^\d{2}:\d{2}$/),
  asian_start: z.string().regex(/^\d{2}:\d{2}$/),
  asian_end: z.string().regex(/^\d{2}:\d{2}$/),
  london_start: z.string().regex(/^\d{2}:\d{2}$/),
  london_end: z.string().regex(/^\d{2}:\d{2}$/),
  use_trailing: z.boolean().default(true),
  trailing_atr_period: z.coerce.number().min(5).max(50),
  trailing_atr_multiplier: z.coerce.number().min(0.5).max(5),
  min_adr_for_trend: z.coerce.number().min(5).max(100),
  adr_period: z.coerce.number().min(1).max(20),
});

type ConfigFormData = z.infer<typeof configSchema>;

export default function NewConfiguration() {
  const { configId } = useParams<{ configId: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const isEditing = !!configId;
  const [activeTab, setActiveTab] = useState('general');

  const { data: existingConfig, isLoading: loadingConfig } = useQuery({
    queryKey: ['config', configId],
    queryFn: () => getConfig(parseInt(configId!)),
    enabled: isEditing,
  });

  const { data: defaultConfig } = useQuery({
    queryKey: ['default-config'],
    queryFn: getDefaultConfig,
    enabled: !isEditing,
  });

  const {
    register,
    handleSubmit,
    reset,
    setValue,
    watch,
    formState: { errors, isDirty },
  } = useForm<ConfigFormData>({
    resolver: zodResolver(configSchema),
    defaultValues: {
      symbol: 'XAUUSD',
      timeframe: 'M1',
      initial_balance: 10000,
      risk_percent: 1.0,
      use_trailing: true,
    },
  });

  // Load existing config or defaults
  useEffect(() => {
    if (existingConfig) {
      const formData = {
        ...existingConfig,
        start_date: existingConfig.start_date?.split('T')[0] || '',
        end_date: existingConfig.end_date?.split('T')[0] || '',
      };
      reset(formData as ConfigFormData);
    } else if (defaultConfig && !isEditing) {
      reset({
        ...defaultConfig,
        name: '',
        description: '',
        start_date: '',
        end_date: '',
      } as ConfigFormData);
    }
  }, [existingConfig, defaultConfig, isEditing, reset]);

  const saveMutation = useMutation({
    mutationFn: async (data: ConfigFormData) => {
      const payload = {
        ...data,
        start_date: new Date(data.start_date).toISOString(),
        end_date: new Date(data.end_date).toISOString(),
      };

      if (isEditing) {
        return updateConfig(parseInt(configId!), payload);
      }
      return createConfig(payload as Omit<BacktestConfig, 'id' | 'created_at'>);
    },
    onSuccess: (config) => {
      toast.success(isEditing ? 'Configuration updated' : 'Configuration created');
      queryClient.invalidateQueries({ queryKey: ['configs'] });
      navigate('/configurations');
    },
    onError: (error) => {
      toast.error('Failed to save configuration');
      console.error(error);
    },
  });

  const runMutation = useMutation({
    mutationFn: async (data: ConfigFormData) => {
      // Save first if needed
      let savedConfig: BacktestConfig;
      if (isDirty || !isEditing) {
        const payload = {
          ...data,
          start_date: new Date(data.start_date).toISOString(),
          end_date: new Date(data.end_date).toISOString(),
        };

        if (isEditing) {
          savedConfig = await updateConfig(parseInt(configId!), payload);
        } else {
          savedConfig = await createConfig(payload as Omit<BacktestConfig, 'id' | 'created_at'>);
        }
      } else {
        savedConfig = existingConfig!;
      }

      // Run backtest
      return runBacktest(savedConfig.id!);
    },
    onSuccess: (data) => {
      toast.success('Backtest started');
      navigate(`/backtests/${data.result_id}`);
    },
    onError: () => {
      toast.error('Failed to start backtest');
    },
  });

  const loadPreset = async (preset: 'default' | 'aggressive' | 'conservative') => {
    try {
      let config;
      switch (preset) {
        case 'aggressive':
          config = await getAggressivePreset();
          break;
        case 'conservative':
          config = await getConservativePreset();
          break;
        default:
          config = await getDefaultConfig();
      }

      Object.entries(config).forEach(([key, value]) => {
        setValue(key as keyof ConfigFormData, value as never, { shouldDirty: true });
      });

      toast.success(`Loaded ${preset} preset`);
    } catch {
      toast.error('Failed to load preset');
    }
  };

  const onSubmit = (data: ConfigFormData) => {
    saveMutation.mutate(data);
  };

  const onRunBacktest = () => {
    handleSubmit((data) => runMutation.mutate(data))();
  };

  if (loadingConfig) {
    return (
      <div className="space-y-6">
        <div className="h-8 w-48 skeleton rounded" />
        <div className="h-96 skeleton rounded-lg" />
      </div>
    );
  }

  const tabs = [
    { id: 'general', label: 'General', icon: Settings },
    { id: 'risk', label: 'Risk', icon: Shield },
    { id: 'ict', label: 'ICT Parameters', icon: TrendingUp },
    { id: 'sessions', label: 'Sessions', icon: Clock },
    { id: 'trailing', label: 'Trailing', icon: Zap },
  ];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-4">
          <button
            onClick={() => navigate('/configurations')}
            className="p-2 text-dark-400 hover:text-white hover:bg-dark-800 rounded-lg"
          >
            <ArrowLeft className="w-5 h-5" />
          </button>
          <div>
            <h1 className="text-2xl font-bold text-white">
              {isEditing ? 'Edit Configuration' : 'New Configuration'}
            </h1>
            <p className="text-dark-400 mt-1">
              Configure your backtest parameters
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={handleSubmit(onSubmit)}
            disabled={saveMutation.isPending}
            className="btn btn-secondary"
          >
            <Save className="w-4 h-4" />
            {saveMutation.isPending ? 'Saving...' : 'Save'}
          </button>
          <button
            onClick={onRunBacktest}
            disabled={runMutation.isPending}
            className="btn btn-success"
          >
            <Play className="w-4 h-4" />
            {runMutation.isPending ? 'Starting...' : 'Save & Run'}
          </button>
        </div>
      </div>

      {/* Presets */}
      <div className="flex items-center gap-2">
        <span className="text-dark-400 text-sm">Presets:</span>
        <button
          onClick={() => loadPreset('default')}
          className="btn btn-ghost btn-sm"
        >
          Default
        </button>
        <button
          onClick={() => loadPreset('conservative')}
          className="btn btn-ghost btn-sm"
        >
          Conservative
        </button>
        <button
          onClick={() => loadPreset('aggressive')}
          className="btn btn-ghost btn-sm"
        >
          Aggressive
        </button>
      </div>

      {/* Tabs */}
      <div className="flex border-b border-dark-700">
        {tabs.map((tab) => (
          <button
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            className={`flex items-center gap-2 px-4 py-3 border-b-2 transition-colors ${
              activeTab === tab.id
                ? 'border-primary-500 text-white'
                : 'border-transparent text-dark-400 hover:text-white'
            }`}
          >
            <tab.icon className="w-4 h-4" />
            {tab.label}
          </button>
        ))}
      </div>

      {/* Form */}
      <form onSubmit={handleSubmit(onSubmit)} className="card">
        <div className="card-body space-y-6">
          {/* General Tab */}
          {activeTab === 'general' && (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
              <div className="md:col-span-2">
                <label className="label">Configuration Name *</label>
                <input
                  {...register('name')}
                  className="input"
                  placeholder="My Backtest Configuration"
                />
                {errors.name && (
                  <p className="text-danger-500 text-sm mt-1">{errors.name.message}</p>
                )}
              </div>

              <div className="md:col-span-2">
                <label className="label">Description</label>
                <textarea
                  {...register('description')}
                  className="input min-h-[80px]"
                  placeholder="Optional description..."
                />
              </div>

              <div>
                <label className="label">Symbol</label>
                <input
                  {...register('symbol')}
                  className="input"
                  placeholder="XAUUSD"
                />
              </div>

              <div>
                <label className="label">Timeframe</label>
                <select {...register('timeframe')} className="select">
                  <option value="M1">M1 (1 Minute)</option>
                  <option value="M5">M5 (5 Minutes)</option>
                  <option value="M15">M15 (15 Minutes)</option>
                  <option value="M30">M30 (30 Minutes)</option>
                  <option value="H1">H1 (1 Hour)</option>
                  <option value="H4">H4 (4 Hours)</option>
                  <option value="D1">D1 (Daily)</option>
                </select>
              </div>

              <div>
                <label className="label">Start Date *</label>
                <input
                  {...register('start_date')}
                  type="date"
                  className="input"
                />
                {errors.start_date && (
                  <p className="text-danger-500 text-sm mt-1">{errors.start_date.message}</p>
                )}
              </div>

              <div>
                <label className="label">End Date *</label>
                <input
                  {...register('end_date')}
                  type="date"
                  className="input"
                />
                {errors.end_date && (
                  <p className="text-danger-500 text-sm mt-1">{errors.end_date.message}</p>
                )}
              </div>

              <div>
                <label className="label">Initial Balance ($)</label>
                <input
                  {...register('initial_balance')}
                  type="number"
                  step="100"
                  className="input"
                />
              </div>
            </div>
          )}

          {/* Risk Tab */}
          {activeTab === 'risk' && (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
              <div>
                <label className="label">Risk Per Trade (%)</label>
                <input
                  {...register('risk_percent')}
                  type="number"
                  step="0.1"
                  className="input"
                />
                <p className="text-dark-500 text-xs mt-1">Percentage of balance risked per trade</p>
              </div>

              <div>
                <label className="label">Max Spread ($)</label>
                <input
                  {...register('max_spread_usd')}
                  type="number"
                  step="0.01"
                  className="input"
                />
              </div>

              <div>
                <label className="label">Max Daily Loss ($)</label>
                <input
                  {...register('max_daily_loss_usd')}
                  type="number"
                  step="10"
                  className="input"
                />
                <p className="text-dark-500 text-xs mt-1">Must be negative</p>
              </div>

              <div>
                <label className="label">Max Total Risk ($)</label>
                <input
                  {...register('max_total_risk_usd')}
                  type="number"
                  step="10"
                  className="input"
                />
              </div>

              <div>
                <label className="label">Min Stop Loss ($)</label>
                <input
                  {...register('min_sl_usd')}
                  type="number"
                  step="0.1"
                  className="input"
                />
              </div>

              <div>
                <label className="label">Max Stop Loss ($)</label>
                <input
                  {...register('max_sl_usd')}
                  type="number"
                  step="0.1"
                  className="input"
                />
              </div>

              <div>
                <label className="label">Gold R:R Threshold ($)</label>
                <input
                  {...register('gold_rr_threshold')}
                  type="number"
                  step="0.5"
                  className="input"
                />
                <p className="text-dark-500 text-xs mt-1">SL below this = 2R target, else 1R</p>
              </div>
            </div>
          )}

          {/* ICT Tab */}
          {activeTab === 'ict' && (
            <div className="space-y-8">
              {/* FVG Parameters */}
              <div>
                <h3 className="text-white font-medium mb-4">Fair Value Gap (FVG)</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                  <div>
                    <label className="label">Min FVG Gap ($)</label>
                    <input
                      {...register('min_fvg_gap')}
                      type="number"
                      step="0.05"
                      className="input"
                    />
                  </div>
                  <div>
                    <label className="label">FVG Lookback (bars)</label>
                    <input
                      {...register('fvg_lookback')}
                      type="number"
                      className="input"
                    />
                  </div>
                </div>
              </div>

              {/* Displacement Parameters */}
              <div>
                <h3 className="text-white font-medium mb-4">Displacement</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                  <div>
                    <label className="label">Percentile (%)</label>
                    <input
                      {...register('displacement_percentile')}
                      type="number"
                      className="input"
                    />
                  </div>
                  <div>
                    <label className="label">Lookback (bars)</label>
                    <input
                      {...register('displacement_lookback')}
                      type="number"
                      className="input"
                    />
                  </div>
                  <div>
                    <label className="label">Max Opposing Wick Ratio</label>
                    <input
                      {...register('max_opposing_wick_ratio')}
                      type="number"
                      step="0.1"
                      className="input"
                    />
                  </div>
                </div>
              </div>

              {/* Order Block Parameters */}
              <div>
                <h3 className="text-white font-medium mb-4">Order Blocks</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                  <div>
                    <label className="label">OB Lookback (bars)</label>
                    <input
                      {...register('ob_lookback')}
                      type="number"
                      className="input"
                    />
                  </div>
                  <div>
                    <label className="label">Min Body %</label>
                    <input
                      {...register('ob_min_body_percent')}
                      type="number"
                      className="input"
                    />
                  </div>
                  <div>
                    <label className="label">Validation Bars</label>
                    <input
                      {...register('ob_validation_bars')}
                      type="number"
                      className="input"
                    />
                  </div>
                </div>
              </div>

              {/* Liquidity Parameters */}
              <div>
                <h3 className="text-white font-medium mb-4">Liquidity</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                  <div>
                    <label className="label">Wick Ratio</label>
                    <input
                      {...register('liquidity_wick_ratio')}
                      type="number"
                      step="0.1"
                      className="input"
                    />
                  </div>
                  <div>
                    <label className="label">Sweep Tolerance ($)</label>
                    <input
                      {...register('sweep_tolerance_usd')}
                      type="number"
                      step="0.05"
                      className="input"
                    />
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Sessions Tab */}
          {activeTab === 'sessions' && (
            <div className="space-y-8">
              {/* ORB Times */}
              <div>
                <h3 className="text-white font-medium mb-4">Opening Range (NY Time)</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="label">ORB Start</label>
                    <input
                      {...register('orb_start_time')}
                      type="time"
                      className="input"
                    />
                  </div>
                  <div>
                    <label className="label">ORB End</label>
                    <input
                      {...register('orb_end_time')}
                      type="time"
                      className="input"
                    />
                  </div>
                </div>
              </div>

              {/* Trading Hours */}
              <div>
                <h3 className="text-white font-medium mb-4">Trading Hours (NY Time)</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="label">Trade Start</label>
                    <input
                      {...register('trade_start_time')}
                      type="time"
                      className="input"
                    />
                  </div>
                  <div>
                    <label className="label">Trade End</label>
                    <input
                      {...register('trade_end_time')}
                      type="time"
                      className="input"
                    />
                  </div>
                </div>
              </div>

              {/* Asian Session */}
              <div>
                <h3 className="text-white font-medium mb-4">Asian Session (NY Time)</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="label">Asian Start</label>
                    <input
                      {...register('asian_start')}
                      type="time"
                      className="input"
                    />
                  </div>
                  <div>
                    <label className="label">Asian End</label>
                    <input
                      {...register('asian_end')}
                      type="time"
                      className="input"
                    />
                  </div>
                </div>
              </div>

              {/* London Session */}
              <div>
                <h3 className="text-white font-medium mb-4">London Session (NY Time)</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="label">London Start</label>
                    <input
                      {...register('london_start')}
                      type="time"
                      className="input"
                    />
                  </div>
                  <div>
                    <label className="label">London End</label>
                    <input
                      {...register('london_end')}
                      type="time"
                      className="input"
                    />
                  </div>
                </div>
              </div>
            </div>
          )}

          {/* Trailing Tab */}
          {activeTab === 'trailing' && (
            <div className="space-y-6">
              <div className="flex items-center gap-3">
                <input
                  type="checkbox"
                  {...register('use_trailing')}
                  id="use_trailing"
                  className="w-5 h-5 rounded border-dark-600 bg-dark-800 text-primary-500 focus:ring-primary-500"
                />
                <label htmlFor="use_trailing" className="text-white font-medium">
                  Enable Trailing Stop
                </label>
              </div>

              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                <div>
                  <label className="label">ATR Period</label>
                  <input
                    {...register('trailing_atr_period')}
                    type="number"
                    className="input"
                    disabled={!watch('use_trailing')}
                  />
                </div>
                <div>
                  <label className="label">ATR Multiplier</label>
                  <input
                    {...register('trailing_atr_multiplier')}
                    type="number"
                    step="0.1"
                    className="input"
                    disabled={!watch('use_trailing')}
                  />
                </div>
              </div>

              <div className="border-t border-dark-700 pt-6">
                <h3 className="text-white font-medium mb-4">Trend Filter</h3>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div>
                    <label className="label">Min ADR for Trend ($)</label>
                    <input
                      {...register('min_adr_for_trend')}
                      type="number"
                      step="1"
                      className="input"
                    />
                  </div>
                  <div>
                    <label className="label">ADR Period (days)</label>
                    <input
                      {...register('adr_period')}
                      type="number"
                      className="input"
                    />
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      </form>
    </div>
  );
}
