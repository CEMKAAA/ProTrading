import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate } from 'react-router-dom';
import {
  Plus,
  Trash2,
  Eye,
  Download,
  RefreshCw,
  Search,
} from 'lucide-react';
import toast from 'react-hot-toast';
import {
  getBacktestResults,
  getConfigs,
  runBacktest,
  deleteBacktestResult,
  exportBacktest,
  downloadFile,
} from '@/services/api';
import { formatCurrency, formatPercent, formatDateTime } from '@/lib/utils';
import type { BacktestResultSummary } from '@/types';

export default function Backtests() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [statusFilter, setStatusFilter] = useState<string>('');
  const [searchQuery, setSearchQuery] = useState('');

  const { data: results, isLoading, refetch } = useQuery({
    queryKey: ['backtest-results', statusFilter],
    queryFn: () => getBacktestResults(0, 100, statusFilter || undefined),
    refetchInterval: 5000, // Poll for updates
  });

  const { data: configs } = useQuery({
    queryKey: ['configs'],
    queryFn: () => getConfigs(0, 100),
  });

  const runMutation = useMutation({
    mutationFn: runBacktest,
    onSuccess: (data) => {
      toast.success('Backtest started');
      queryClient.invalidateQueries({ queryKey: ['backtest-results'] });
      navigate(`/backtests/${data.result_id}`);
    },
    onError: (error) => {
      toast.error('Failed to start backtest');
      console.error(error);
    },
  });

  const deleteMutation = useMutation({
    mutationFn: deleteBacktestResult,
    onSuccess: () => {
      toast.success('Backtest deleted');
      queryClient.invalidateQueries({ queryKey: ['backtest-results'] });
    },
    onError: () => {
      toast.error('Failed to delete backtest');
    },
  });

  const handleExport = async (resultId: number, format: 'csv' | 'json') => {
    try {
      const blob = await exportBacktest(resultId, format);
      downloadFile(blob, `backtest_${resultId}.${format}`);
      toast.success('Export downloaded');
    } catch {
      toast.error('Failed to export backtest');
    }
  };

  const filteredResults = results?.filter((r) =>
    r.config_name.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Backtests</h1>
          <p className="text-dark-400 mt-1">
            Run and analyze strategy backtests
          </p>
        </div>
        <Link to="/configurations/new" className="btn btn-primary">
          <Plus className="w-4 h-4" />
          New Configuration
        </Link>
      </div>

      {/* Quick Run Section */}
      {configs && configs.length > 0 && (
        <div className="card p-4">
          <div className="flex items-center gap-4">
            <span className="text-dark-400">Quick run:</span>
            <select
              className="select w-64"
              onChange={(e) => {
                if (e.target.value) {
                  runMutation.mutate(parseInt(e.target.value));
                }
              }}
              disabled={runMutation.isPending}
            >
              <option value="">Select a configuration...</option>
              {configs.map((config) => (
                <option key={config.id} value={config.id}>
                  {config.name}
                </option>
              ))}
            </select>
            {runMutation.isPending && (
              <RefreshCw className="w-4 h-4 animate-spin text-primary-500" />
            )}
          </div>
        </div>
      )}

      {/* Filters */}
      <div className="flex items-center gap-4">
        <div className="relative flex-1 max-w-md">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-dark-400" />
          <input
            type="text"
            placeholder="Search backtests..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="input pl-10"
          />
        </div>
        <select
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value)}
          className="select w-40"
        >
          <option value="">All Status</option>
          <option value="COMPLETED">Completed</option>
          <option value="RUNNING">Running</option>
          <option value="PENDING">Pending</option>
          <option value="FAILED">Failed</option>
        </select>
        <button onClick={() => refetch()} className="btn btn-secondary">
          <RefreshCw className="w-4 h-4" />
          Refresh
        </button>
      </div>

      {/* Results Table */}
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="table">
            <thead>
              <tr>
                <th>Configuration</th>
                <th>Status</th>
                <th>Trades</th>
                <th>Win Rate</th>
                <th>Net P&L</th>
                <th>Max DD</th>
                <th>Started</th>
                <th className="text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {isLoading ? (
                Array.from({ length: 5 }).map((_, i) => (
                  <tr key={i}>
                    <td colSpan={8}>
                      <div className="h-12 skeleton rounded" />
                    </td>
                  </tr>
                ))
              ) : filteredResults && filteredResults.length > 0 ? (
                filteredResults.map((result) => (
                  <ResultRow
                    key={result.id}
                    result={result}
                    onView={() => navigate(`/backtests/${result.id}`)}
                    onDelete={() => deleteMutation.mutate(result.id)}
                    onExport={(format) => handleExport(result.id, format)}
                  />
                ))
              ) : (
                <tr>
                  <td colSpan={8} className="text-center text-dark-400 py-12">
                    No backtests found.{' '}
                    <Link
                      to="/configurations/new"
                      className="text-primary-500 hover:underline"
                    >
                      Create a configuration
                    </Link>{' '}
                    to get started.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

interface ResultRowProps {
  result: BacktestResultSummary;
  onView: () => void;
  onDelete: () => void;
  onExport: (format: 'csv' | 'json') => void;
}

function ResultRow({ result, onView, onDelete, onExport }: ResultRowProps) {
  const [showExportMenu, setShowExportMenu] = useState(false);

  const statusStyles = {
    COMPLETED: 'badge-success',
    RUNNING: 'badge-info',
    PENDING: 'badge-warning',
    FAILED: 'badge-danger',
  };

  return (
    <tr className="group">
      <td>
        <button
          onClick={onView}
          className="font-medium text-white hover:text-primary-400 transition-colors"
        >
          {result.config_name}
        </button>
      </td>
      <td>
        <span
          className={`badge ${statusStyles[result.status as keyof typeof statusStyles]}`}
        >
          {result.status === 'RUNNING' && (
            <RefreshCw className="w-3 h-3 animate-spin mr-1" />
          )}
          {result.status}
        </span>
      </td>
      <td>{result.total_trades}</td>
      <td>
        <span
          className={result.win_rate >= 50 ? 'text-success-500' : 'text-danger-500'}
        >
          {formatPercent(result.win_rate)}
        </span>
      </td>
      <td>
        <span
          className={result.net_profit >= 0 ? 'text-success-500' : 'text-danger-500'}
        >
          {formatCurrency(result.net_profit)}
        </span>
      </td>
      <td className="text-danger-500">{formatPercent(result.max_drawdown_percent)}</td>
      <td className="text-dark-400">
        {result.started_at ? formatDateTime(result.started_at) : '-'}
      </td>
      <td>
        <div className="flex items-center justify-end gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
          <button
            onClick={onView}
            className="p-2 text-dark-400 hover:text-white hover:bg-dark-700 rounded"
            title="View details"
          >
            <Eye className="w-4 h-4" />
          </button>
          <div className="relative">
            <button
              onClick={() => setShowExportMenu(!showExportMenu)}
              className="p-2 text-dark-400 hover:text-white hover:bg-dark-700 rounded"
              title="Export"
            >
              <Download className="w-4 h-4" />
            </button>
            {showExportMenu && (
              <div className="absolute right-0 mt-1 w-32 bg-dark-800 border border-dark-700 rounded-lg shadow-xl z-10">
                <button
                  onClick={() => {
                    onExport('csv');
                    setShowExportMenu(false);
                  }}
                  className="w-full px-3 py-2 text-left text-sm text-dark-300 hover:bg-dark-700 hover:text-white"
                >
                  Export CSV
                </button>
                <button
                  onClick={() => {
                    onExport('json');
                    setShowExportMenu(false);
                  }}
                  className="w-full px-3 py-2 text-left text-sm text-dark-300 hover:bg-dark-700 hover:text-white"
                >
                  Export JSON
                </button>
              </div>
            )}
          </div>
          <button
            onClick={onDelete}
            className="p-2 text-dark-400 hover:text-danger-500 hover:bg-dark-700 rounded"
            title="Delete"
          >
            <Trash2 className="w-4 h-4" />
          </button>
        </div>
      </td>
    </tr>
  );
}
