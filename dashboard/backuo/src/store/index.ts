import { create } from 'zustand';
import type {
  BacktestConfig,
  BacktestResult,
  BacktestResultSummary,
  DashboardStats,
  LiveStatus,
} from '@/types';

interface DashboardStore {
  // Dashboard State
  stats: DashboardStats | null;
  liveStatus: LiveStatus | null;
  isLoading: boolean;
  error: string | null;

  // Backtest State
  configs: BacktestConfig[];
  results: BacktestResultSummary[];
  selectedConfig: BacktestConfig | null;
  selectedResult: BacktestResult | null;
  runningBacktests: Map<number, { progress: number; message: string }>;

  // Actions
  setStats: (stats: DashboardStats) => void;
  setLiveStatus: (status: LiveStatus) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;

  setConfigs: (configs: BacktestConfig[]) => void;
  addConfig: (config: BacktestConfig) => void;
  updateConfig: (config: BacktestConfig) => void;
  removeConfig: (configId: number) => void;
  selectConfig: (config: BacktestConfig | null) => void;

  setResults: (results: BacktestResultSummary[]) => void;
  addResult: (result: BacktestResultSummary) => void;
  updateResult: (result: BacktestResultSummary) => void;
  removeResult: (resultId: number) => void;
  selectResult: (result: BacktestResult | null) => void;

  setBacktestProgress: (resultId: number, progress: number, message: string) => void;
  clearBacktestProgress: (resultId: number) => void;
}

export const useDashboardStore = create<DashboardStore>((set) => ({
  // Initial State
  stats: null,
  liveStatus: null,
  isLoading: false,
  error: null,
  configs: [],
  results: [],
  selectedConfig: null,
  selectedResult: null,
  runningBacktests: new Map(),

  // Dashboard Actions
  setStats: (stats) => set({ stats }),
  setLiveStatus: (liveStatus) => set({ liveStatus }),
  setLoading: (isLoading) => set({ isLoading }),
  setError: (error) => set({ error }),

  // Config Actions
  setConfigs: (configs) => set({ configs }),
  addConfig: (config) =>
    set((state) => ({ configs: [config, ...state.configs] })),
  updateConfig: (config) =>
    set((state) => ({
      configs: state.configs.map((c) => (c.id === config.id ? config : c)),
    })),
  removeConfig: (configId) =>
    set((state) => ({
      configs: state.configs.filter((c) => c.id !== configId),
      selectedConfig: state.selectedConfig?.id === configId ? null : state.selectedConfig,
    })),
  selectConfig: (selectedConfig) => set({ selectedConfig }),

  // Result Actions
  setResults: (results) => set({ results }),
  addResult: (result) =>
    set((state) => ({ results: [result, ...state.results] })),
  updateResult: (result) =>
    set((state) => ({
      results: state.results.map((r) => (r.id === result.id ? result : r)),
    })),
  removeResult: (resultId) =>
    set((state) => ({
      results: state.results.filter((r) => r.id !== resultId),
      selectedResult: state.selectedResult?.id === resultId ? null : state.selectedResult,
    })),
  selectResult: (selectedResult) => set({ selectedResult }),

  // Backtest Progress
  setBacktestProgress: (resultId, progress, message) =>
    set((state) => {
      const newMap = new Map(state.runningBacktests);
      newMap.set(resultId, { progress, message });
      return { runningBacktests: newMap };
    }),
  clearBacktestProgress: (resultId) =>
    set((state) => {
      const newMap = new Map(state.runningBacktests);
      newMap.delete(resultId);
      return { runningBacktests: newMap };
    }),
}));
