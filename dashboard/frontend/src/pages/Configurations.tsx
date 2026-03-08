import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Link, useNavigate } from 'react-router-dom';
import {
  Plus,
  Play,
  Edit2,
  Trash2,
  Copy,
  Settings2,
  Calendar,
  DollarSign,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { getConfigs, deleteConfig, duplicateConfig, runBacktest } from '@/services/api';
import { formatDate, formatCurrency } from '@/lib/utils';
import type { BacktestConfig } from '@/types';

export default function Configurations() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [duplicateName, setDuplicateName] = useState('');
  const [showDuplicateModal, setShowDuplicateModal] = useState<number | null>(null);

  const { data: configs, isLoading } = useQuery({
    queryKey: ['configs'],
    queryFn: () => getConfigs(0, 100),
  });

  const deleteMutation = useMutation({
    mutationFn: deleteConfig,
    onSuccess: () => {
      toast.success('Configuration deleted');
      queryClient.invalidateQueries({ queryKey: ['configs'] });
    },
    onError: () => {
      toast.error('Failed to delete configuration');
    },
  });

  const duplicateMutation = useMutation({
    mutationFn: ({ configId, name }: { configId: number; name: string }) =>
      duplicateConfig(configId, name),
    onSuccess: (newConfig) => {
      toast.success('Configuration duplicated');
      queryClient.invalidateQueries({ queryKey: ['configs'] });
      setShowDuplicateModal(null);
      setDuplicateName('');
      navigate(`/configurations/${newConfig.id}/edit`);
    },
    onError: () => {
      toast.error('Failed to duplicate configuration');
    },
  });

  const runMutation = useMutation({
    mutationFn: runBacktest,
    onSuccess: (data) => {
      toast.success('Backtest started');
      navigate(`/backtests/${data.result_id}`);
    },
    onError: () => {
      toast.error('Failed to start backtest');
    },
  });

  const handleDuplicate = (configId: number) => {
    if (!duplicateName.trim()) {
      toast.error('Please enter a name');
      return;
    }
    duplicateMutation.mutate({ configId, name: duplicateName });
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-white">Configurations</h1>
          <p className="text-dark-400 mt-1">
            Manage your backtest configurations
          </p>
        </div>
        <Link to="/configurations/new" className="btn btn-primary">
          <Plus className="w-4 h-4" />
          New Configuration
        </Link>
      </div>

      {/* Configurations Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {isLoading ? (
          Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="card h-48 skeleton" />
          ))
        ) : configs && configs.length > 0 ? (
          configs.map((config) => (
            <ConfigCard
              key={config.id}
              config={config}
              onEdit={() => navigate(`/configurations/${config.id}/edit`)}
              onDelete={() => {
                if (window.confirm('Are you sure you want to delete this configuration?')) {
                  deleteMutation.mutate(config.id!);
                }
              }}
              onDuplicate={() => {
                setDuplicateName(`${config.name} (Copy)`);
                setShowDuplicateModal(config.id!);
              }}
              onRun={() => runMutation.mutate(config.id!)}
              isRunning={runMutation.isPending && runMutation.variables === config.id}
            />
          ))
        ) : (
          <div className="col-span-full text-center py-12">
            <Settings2 className="w-12 h-12 text-dark-600 mx-auto mb-4" />
            <h3 className="text-lg font-medium text-white mb-2">
              No configurations yet
            </h3>
            <p className="text-dark-400 mb-4">
              Create your first backtest configuration to get started
            </p>
            <Link to="/configurations/new" className="btn btn-primary">
              <Plus className="w-4 h-4" />
              Create Configuration
            </Link>
          </div>
        )}
      </div>

      {/* Duplicate Modal */}
      {showDuplicateModal !== null && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-dark-800 border border-dark-700 rounded-lg p-6 w-full max-w-md">
            <h3 className="text-lg font-semibold text-white mb-4">
              Duplicate Configuration
            </h3>
            <div className="mb-4">
              <label className="label">New Configuration Name</label>
              <input
                type="text"
                className="input"
                value={duplicateName}
                onChange={(e) => setDuplicateName(e.target.value)}
                placeholder="Enter name..."
              />
            </div>
            <div className="flex justify-end gap-3">
              <button
                onClick={() => {
                  setShowDuplicateModal(null);
                  setDuplicateName('');
                }}
                className="btn btn-secondary"
              >
                Cancel
              </button>
              <button
                onClick={() => handleDuplicate(showDuplicateModal)}
                disabled={duplicateMutation.isPending}
                className="btn btn-primary"
              >
                {duplicateMutation.isPending ? 'Duplicating...' : 'Duplicate'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

interface ConfigCardProps {
  config: BacktestConfig;
  onEdit: () => void;
  onDelete: () => void;
  onDuplicate: () => void;
  onRun: () => void;
  isRunning: boolean;
}

// Strategy name mapping for display
const strategyNames: Record<string, string> = {
  orb_strategy: 'ORB Strategy',
  advanced_orb_strategy: 'Advanced ORB',
};

function ConfigCard({
  config,
  onEdit,
  onDelete,
  onDuplicate,
  onRun,
  isRunning,
}: ConfigCardProps) {
  const strategyName = config.strategy_id
    ? strategyNames[config.strategy_id] || config.strategy_id
    : 'ORB Strategy';

  return (
    <div className="card hover:border-dark-600 transition-colors group">
      <div className="card-header flex items-start justify-between">
        <div>
          <h3 className="font-semibold text-white">{config.name}</h3>
          <p className="text-primary-400 text-xs mt-0.5">{strategyName}</p>
          {config.description && (
            <p className="text-dark-400 text-sm mt-1 line-clamp-2">
              {config.description}
            </p>
          )}
        </div>
        <span className="badge badge-info">{config.symbol}</span>
      </div>

      <div className="card-body space-y-3">
        {/* Date Range */}
        <div className="flex items-center gap-2 text-sm">
          <Calendar className="w-4 h-4 text-dark-400" />
          <span className="text-dark-300">
            {formatDate(config.start_date)} - {formatDate(config.end_date)}
          </span>
        </div>

        {/* Initial Balance */}
        <div className="flex items-center gap-2 text-sm">
          <DollarSign className="w-4 h-4 text-dark-400" />
          <span className="text-dark-300">
            Initial: {formatCurrency(config.initial_balance)}
          </span>
        </div>

        {/* Key Settings */}
        <div className="flex flex-wrap gap-2 text-xs">
          <span className="px-2 py-1 bg-dark-700 rounded text-dark-300">
            Risk: {config.risk_percent}%
          </span>
          <span className="px-2 py-1 bg-dark-700 rounded text-dark-300">
            FVG: ${config.min_fvg_gap}
          </span>
          <span className="px-2 py-1 bg-dark-700 rounded text-dark-300">
            {config.timeframe}
          </span>
        </div>

        {/* Actions */}
        <div className="flex items-center justify-between pt-2 border-t border-dark-700">
          <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
            <button
              onClick={onEdit}
              className="p-2 text-dark-400 hover:text-white hover:bg-dark-700 rounded"
              title="Edit"
            >
              <Edit2 className="w-4 h-4" />
            </button>
            <button
              onClick={onDuplicate}
              className="p-2 text-dark-400 hover:text-white hover:bg-dark-700 rounded"
              title="Duplicate"
            >
              <Copy className="w-4 h-4" />
            </button>
            <button
              onClick={onDelete}
              className="p-2 text-dark-400 hover:text-danger-500 hover:bg-dark-700 rounded"
              title="Delete"
            >
              <Trash2 className="w-4 h-4" />
            </button>
          </div>

          <button
            onClick={onRun}
            disabled={isRunning}
            className="btn btn-success btn-sm"
          >
            <Play className="w-4 h-4" />
            {isRunning ? 'Starting...' : 'Run'}
          </button>
        </div>
      </div>
    </div>
  );
}
