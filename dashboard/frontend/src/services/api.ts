import axios from 'axios';
import type {
  BacktestConfig,
  BacktestResult,
  BacktestResultSummary,
  Trade,
  DashboardStats,
  LiveStatus,
  StrategyDefinition,
  StrategyListItem,
} from '@/types';

const API_BASE = '/api/v1';

const api = axios.create({
  baseURL: API_BASE,
  headers: {
    'Content-Type': 'application/json',
  },
});

// ========================== Dashboard ==========================

export const getDashboardStats = async (): Promise<DashboardStats> => {
  const response = await api.get('/dashboard/stats');
  return response.data;
};

export const getLiveStatus = async (): Promise<LiveStatus> => {
  const response = await api.get('/dashboard/live-status');
  return response.data;
};

// ========================== Configurations ==========================

export const getConfigs = async (skip = 0, limit = 50): Promise<BacktestConfig[]> => {
  const response = await api.get('/configs', { params: { skip, limit } });
  return response.data;
};

export const getConfig = async (configId: number): Promise<BacktestConfig> => {
  const response = await api.get(`/configs/${configId}`);
  return response.data;
};

export const createConfig = async (config: Omit<BacktestConfig, 'id' | 'created_at'>): Promise<BacktestConfig> => {
  const response = await api.post('/configs', config);
  return response.data;
};

export const updateConfig = async (configId: number, config: Partial<BacktestConfig>): Promise<BacktestConfig> => {
  const response = await api.put(`/configs/${configId}`, config);
  return response.data;
};

export const deleteConfig = async (configId: number): Promise<void> => {
  await api.delete(`/configs/${configId}`);
};

export const duplicateConfig = async (configId: number, newName: string): Promise<BacktestConfig> => {
  const response = await api.post(`/configs/${configId}/duplicate`, null, {
    params: { new_name: newName },
  });
  return response.data;
};

// ========================== Backtests ==========================

export const runBacktest = async (configId: number): Promise<{ result_id: number }> => {
  const response = await api.post(`/backtests/run/${configId}`);
  return response.data;
};

export const getBacktestStatus = async (resultId: number): Promise<{
  result_id: number;
  status: string;
  started_at?: string;
  completed_at?: string;
  error_message?: string;
}> => {
  const response = await api.get(`/backtests/status/${resultId}`);
  return response.data;
};

export const getBacktestResults = async (
  skip = 0,
  limit = 50,
  status?: string
): Promise<BacktestResultSummary[]> => {
  const response = await api.get('/backtests/results', {
    params: { skip, limit, status },
  });
  return response.data;
};

export const getBacktestResult = async (resultId: number): Promise<BacktestResult> => {
  const response = await api.get(`/backtests/results/${resultId}`);
  return response.data;
};

export const getBacktestTrades = async (
  resultId: number,
  skip = 0,
  limit = 100
): Promise<Trade[]> => {
  const response = await api.get(`/backtests/results/${resultId}/trades`, {
    params: { skip, limit },
  });
  return response.data;
};

export const deleteBacktestResult = async (resultId: number): Promise<void> => {
  await api.delete(`/backtests/results/${resultId}`);
};

export const compareBacktests = async (resultIds: number[]): Promise<{
  comparison: Array<{
    result_id: number;
    config_name: string;
    metrics: Record<string, number>;
  }>;
  equity_curves: Record<number, Array<{ timestamp: string; equity: number }>>;
}> => {
  const response = await api.post('/backtests/compare', resultIds);
  return response.data;
};

// ========================== Export ==========================

export const exportBacktest = async (
  resultId: number,
  format: 'csv' | 'json' = 'csv'
): Promise<Blob> => {
  const response = await api.post(
    `/backtests/export/${resultId}`,
    null,
    {
      params: { format },
      responseType: 'blob',
    }
  );
  return response.data;
};

// ========================== Strategy Definitions ==========================

export const getStrategyDefinitions = async (): Promise<StrategyDefinition[]> => {
  const response = await api.get('/strategy-definitions');
  return response.data;
};

export const getStrategyList = async (): Promise<StrategyListItem[]> => {
  const response = await api.get('/strategy-definitions/list');
  return response.data;
};

export const getStrategyDefinition = async (strategyId: string): Promise<StrategyDefinition> => {
  const response = await api.get(`/strategy-definitions/${strategyId}`);
  return response.data;
};

export const getStrategyDefaults = async (strategyId: string): Promise<Record<string, unknown>> => {
  const response = await api.get(`/strategy-definitions/${strategyId}/defaults`);
  return response.data;
};

// ========================== Presets ==========================

export const getDefaultConfig = async (): Promise<Omit<BacktestConfig, 'id' | 'created_at' | 'name' | 'description' | 'start_date' | 'end_date'>> => {
  const response = await api.get('/presets/default-config');
  return response.data;
};

export const getAggressivePreset = async (): Promise<Omit<BacktestConfig, 'id' | 'created_at' | 'name' | 'description' | 'start_date' | 'end_date'>> => {
  const response = await api.get('/presets/aggressive');
  return response.data;
};

export const getConservativePreset = async (): Promise<Omit<BacktestConfig, 'id' | 'created_at' | 'name' | 'description' | 'start_date' | 'end_date'>> => {
  const response = await api.get('/presets/conservative');
  return response.data;
};

// ========================== Utilities ==========================

export const downloadFile = (blob: Blob, filename: string) => {
  const url = window.URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  window.URL.revokeObjectURL(url);
};

export default api;
