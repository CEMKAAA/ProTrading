import { useEffect, useState, useMemo } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm, Controller } from 'react-hook-form';
import {
  ArrowLeft,
  Save,
  Play,
  Settings,
  Clock,
  Shield,
  TrendingUp,
  Zap,
  FlaskConical,
  Layers,
  ChevronDown,
} from 'lucide-react';
import toast from 'react-hot-toast';
import {
  getConfig,
  createConfig,
  updateConfig,
  runBacktest,
  getStrategyList,
  getStrategyDefinition,
  getStrategyDefaults,
} from '@/services/api';
import type { StrategyDefinition, StrategyListItem, ParameterDefinition } from '@/types';

// Icon mapping for parameter groups
const iconMap: Record<string, React.ElementType> = {
  Settings,
  Clock,
  Shield,
  TrendingUp,
  Zap,
  FlaskConical,
  Layers,
};

export default function NewConfiguration() {
  const { configId } = useParams<{ configId: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const isEditing = !!configId;

  const [selectedStrategyId, setSelectedStrategyId] = useState<string>('');
  const [activeTab, setActiveTab] = useState<string>('_meta');
  const [formValues, setFormValues] = useState<Record<string, unknown>>({});

  // Fetch strategy list
  const { data: strategyList, isLoading: loadingStrategies } = useQuery({
    queryKey: ['strategy-list'],
    queryFn: getStrategyList,
  });

  // Fetch selected strategy definition
  const { data: strategyDef, isLoading: loadingStrategy } = useQuery({
    queryKey: ['strategy-definition', selectedStrategyId],
    queryFn: () => getStrategyDefinition(selectedStrategyId),
    enabled: !!selectedStrategyId,
  });

  // Fetch strategy defaults
  const { data: strategyDefaults } = useQuery({
    queryKey: ['strategy-defaults', selectedStrategyId],
    queryFn: () => getStrategyDefaults(selectedStrategyId),
    enabled: !!selectedStrategyId && !isEditing,
  });

  // Fetch existing config when editing
  const { data: existingConfig, isLoading: loadingConfig } = useQuery({
    queryKey: ['config', configId],
    queryFn: () => getConfig(parseInt(configId!)),
    enabled: isEditing,
  });

  // Form setup
  const { register, handleSubmit, control, reset, setValue, watch, formState: { errors, isDirty } } = useForm({
    defaultValues: formValues,
  });

  // When editing, set strategy from existing config
  useEffect(() => {
    if (existingConfig && existingConfig.strategy_id) {
      setSelectedStrategyId(existingConfig.strategy_id);
    } else if (!isEditing && strategyList?.length && !selectedStrategyId) {
      // Default to first strategy when creating new
      setSelectedStrategyId(strategyList[0].id);
    }
  }, [existingConfig, strategyList, isEditing, selectedStrategyId]);

  // Load defaults or existing config into form
  useEffect(() => {
    if (isEditing && existingConfig && strategyDef) {
      // Convert dates for form
      const formData: Record<string, unknown> = { ...existingConfig };
      if (existingConfig.start_date) {
        formData.start_date = existingConfig.start_date.split('T')[0];
      }
      if (existingConfig.end_date) {
        formData.end_date = existingConfig.end_date.split('T')[0];
      }
      reset(formData);
    } else if (!isEditing && strategyDefaults && strategyDef) {
      reset({
        ...strategyDefaults,
        name: '',
        description: '',
        start_date: '',
        end_date: '',
        strategy_id: selectedStrategyId,
      });
    }
  }, [existingConfig, strategyDefaults, strategyDef, isEditing, reset, selectedStrategyId]);

  // Handle strategy change
  const handleStrategyChange = async (newStrategyId: string) => {
    if (newStrategyId === selectedStrategyId) return;

    setSelectedStrategyId(newStrategyId);
    setActiveTab('general');

    // Load new defaults
    try {
      const defaults = await getStrategyDefaults(newStrategyId);
      const currentName = watch('name');
      const currentDesc = watch('description');
      const currentStart = watch('start_date');
      const currentEnd = watch('end_date');

      reset({
        ...defaults,
        name: currentName || '',
        description: currentDesc || '',
        start_date: currentStart || '',
        end_date: currentEnd || '',
        strategy_id: newStrategyId,
      });
    } catch (err) {
      toast.error('Failed to load strategy defaults');
    }
  };

  // Save mutation
  const saveMutation = useMutation({
    mutationFn: async (data: Record<string, unknown>) => {
      const payload = {
        ...data,
        strategy_id: selectedStrategyId,
        start_date: new Date(data.start_date as string).toISOString(),
        end_date: new Date(data.end_date as string).toISOString(),
      };

      if (isEditing) {
        return updateConfig(parseInt(configId!), payload);
      }
      return createConfig(payload as never);
    },
    onSuccess: () => {
      toast.success(isEditing ? 'Configuration updated' : 'Configuration created');
      queryClient.invalidateQueries({ queryKey: ['configs'] });
      navigate('/configurations');
    },
    onError: (error) => {
      toast.error('Failed to save configuration');
      console.error(error);
    },
  });

  // Run backtest mutation
  const runMutation = useMutation({
    mutationFn: async (data: Record<string, unknown>) => {
      const payload = {
        ...data,
        strategy_id: selectedStrategyId,
        start_date: new Date(data.start_date as string).toISOString(),
        end_date: new Date(data.end_date as string).toISOString(),
      };

      let savedConfig;
      if (isDirty || !isEditing) {
        if (isEditing) {
          savedConfig = await updateConfig(parseInt(configId!), payload);
        } else {
          savedConfig = await createConfig(payload as never);
        }
      } else {
        savedConfig = existingConfig!;
      }

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

  const onSubmit = (data: Record<string, unknown>) => {
    saveMutation.mutate(data);
  };

  const onRunBacktest = () => {
    handleSubmit((data) => runMutation.mutate(data))();
  };

  // Group parameters by their group
  const parametersByGroup = useMemo(() => {
    if (!strategyDef) return {};

    const grouped: Record<string, ParameterDefinition[]> = {};
    for (const param of strategyDef.parameters) {
      if (!grouped[param.group]) {
        grouped[param.group] = [];
      }
      grouped[param.group].push(param);
    }
    return grouped;
  }, [strategyDef]);

  // Loading state
  if (loadingStrategies || loadingConfig) {
    return (
      <div className="space-y-6">
        <div className="h-8 w-48 skeleton rounded" />
        <div className="h-96 skeleton rounded-lg" />
      </div>
    );
  }

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
            disabled={saveMutation.isPending || !selectedStrategyId}
            className="btn btn-secondary"
          >
            <Save className="w-4 h-4" />
            {saveMutation.isPending ? 'Saving...' : 'Save'}
          </button>
          <button
            onClick={onRunBacktest}
            disabled={runMutation.isPending || !selectedStrategyId}
            className="btn btn-success"
          >
            <Play className="w-4 h-4" />
            {runMutation.isPending ? 'Starting...' : 'Save & Run'}
          </button>
        </div>
      </div>

      {/* Strategy Selector */}
      <div className="card p-6">
        <h2 className="text-lg font-semibold text-white mb-4">Select Strategy</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {strategyList?.map((strategy: StrategyListItem) => (
            <button
              key={strategy.id}
              onClick={() => handleStrategyChange(strategy.id)}
              className={`p-4 rounded-lg border-2 text-left transition-all ${
                selectedStrategyId === strategy.id
                  ? 'border-primary-500 bg-primary-500/10'
                  : 'border-dark-700 bg-dark-800 hover:border-dark-600'
              }`}
            >
              <h3 className="font-medium text-white">{strategy.name}</h3>
              <p className="text-sm text-dark-400 mt-1 line-clamp-2">
                {strategy.description}
              </p>
            </button>
          ))}
        </div>
      </div>

      {/* Strategy Configuration */}
      {selectedStrategyId && strategyDef && (
        <>
          {/* Strategy Info */}
          <div className="card p-4 bg-dark-800/50">
            <div className="flex items-center justify-between">
              <div>
                <h3 className="font-medium text-white">{strategyDef.name}</h3>
                <p className="text-sm text-dark-400">{strategyDef.description}</p>
              </div>
              <span className="text-xs text-dark-500">v{strategyDef.version}</span>
            </div>
          </div>

          {/* Tabs */}
          <div className="flex border-b border-dark-700 overflow-x-auto">
            {/* Always show General first for name/description/dates */}
            <button
              onClick={() => setActiveTab('_meta')}
              className={`flex items-center gap-2 px-4 py-3 border-b-2 transition-colors whitespace-nowrap ${
                activeTab === '_meta'
                  ? 'border-primary-500 text-white'
                  : 'border-transparent text-dark-400 hover:text-white'
              }`}
            >
              <Settings className="w-4 h-4" />
              Basic Info
            </button>
            {strategyDef.parameter_groups.map((group) => {
              const Icon = iconMap[group.icon] || Settings;
              return (
                <button
                  key={group.id}
                  onClick={() => setActiveTab(group.id)}
                  className={`flex items-center gap-2 px-4 py-3 border-b-2 transition-colors whitespace-nowrap ${
                    activeTab === group.id
                      ? 'border-primary-500 text-white'
                      : 'border-transparent text-dark-400 hover:text-white'
                  }`}
                >
                  <Icon className="w-4 h-4" />
                  {group.label}
                </button>
              );
            })}
          </div>

          {/* Form */}
          <form onSubmit={handleSubmit(onSubmit)} className="card">
            <div className="card-body space-y-6">
              {/* Meta Tab (Name, Description, Dates) */}
              {activeTab === '_meta' && (
                <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div className="md:col-span-2">
                    <label className="label">Configuration Name *</label>
                    <input
                      {...register('name', { required: 'Name is required' })}
                      className="input"
                      placeholder="My Backtest Configuration"
                    />
                    {errors.name && (
                      <p className="text-danger-500 text-sm mt-1">
                        {errors.name.message as string}
                      </p>
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
                    <label className="label">Start Date *</label>
                    <input
                      {...register('start_date', { required: 'Start date is required' })}
                      type="date"
                      className="input"
                    />
                    {errors.start_date && (
                      <p className="text-danger-500 text-sm mt-1">
                        {errors.start_date.message as string}
                      </p>
                    )}
                  </div>

                  <div>
                    <label className="label">End Date *</label>
                    <input
                      {...register('end_date', { required: 'End date is required' })}
                      type="date"
                      className="input"
                    />
                    {errors.end_date && (
                      <p className="text-danger-500 text-sm mt-1">
                        {errors.end_date.message as string}
                      </p>
                    )}
                  </div>
                </div>
              )}

              {/* Dynamic Parameter Groups */}
              {strategyDef.parameter_groups.map((group) => (
                activeTab === group.id && (
                  <div key={group.id} className="space-y-6">
                    {group.description && (
                      <p className="text-dark-400 text-sm">{group.description}</p>
                    )}
                    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                      {parametersByGroup[group.id]?.map((param) => (
                        <ParameterInput
                          key={param.name}
                          param={param}
                          register={register}
                          control={control}
                          errors={errors}
                        />
                      ))}
                    </div>
                  </div>
                )
              ))}
            </div>
          </form>
        </>
      )}
    </div>
  );
}

// Component for rendering different parameter types
interface ParameterInputProps {
  param: ParameterDefinition;
  register: ReturnType<typeof useForm>['register'];
  control: ReturnType<typeof useForm>['control'];
  errors: Record<string, unknown>;
}

function ParameterInput({ param, register, control, errors }: ParameterInputProps) {
  const error = errors[param.name];

  switch (param.type) {
    case 'boolean':
      return (
        <div className="flex items-center gap-3">
          <input
            type="checkbox"
            {...register(param.name)}
            id={param.name}
            className="w-5 h-5 rounded border-dark-600 bg-dark-800 text-primary-500 focus:ring-primary-500"
          />
          <div>
            <label htmlFor={param.name} className="text-white font-medium">
              {param.label}
            </label>
            {param.description && (
              <p className="text-dark-500 text-xs">{param.description}</p>
            )}
          </div>
        </div>
      );

    case 'select':
      return (
        <div>
          <label className="label">{param.label}</label>
          <select {...register(param.name)} className="select">
            {param.options?.map((opt) => (
              <option key={opt.value} value={opt.value}>
                {opt.label}
              </option>
            ))}
          </select>
          {param.description && (
            <p className="text-dark-500 text-xs mt-1">{param.description}</p>
          )}
        </div>
      );

    case 'time':
      return (
        <div>
          <label className="label">{param.label}</label>
          <input
            {...register(param.name)}
            type="time"
            className="input"
          />
          {param.description && (
            <p className="text-dark-500 text-xs mt-1">{param.description}</p>
          )}
        </div>
      );

    case 'integer':
    case 'number':
      return (
        <div>
          <label className="label">{param.label}</label>
          <input
            {...register(param.name, {
              valueAsNumber: true,
              min: param.min_value !== undefined ? {
                value: param.min_value,
                message: `Minimum value is ${param.min_value}`
              } : undefined,
              max: param.max_value !== undefined ? {
                value: param.max_value,
                message: `Maximum value is ${param.max_value}`
              } : undefined,
            })}
            type="number"
            step={param.step || (param.type === 'integer' ? 1 : 0.01)}
            min={param.min_value}
            max={param.max_value}
            className="input"
          />
          {param.description && (
            <p className="text-dark-500 text-xs mt-1">{param.description}</p>
          )}
          {error && (
            <p className="text-danger-500 text-sm mt-1">
              {(error as { message?: string }).message}
            </p>
          )}
        </div>
      );

    case 'string':
    default:
      return (
        <div>
          <label className="label">{param.label}</label>
          <input
            {...register(param.name)}
            type="text"
            className="input"
          />
          {param.description && (
            <p className="text-dark-500 text-xs mt-1">{param.description}</p>
          )}
        </div>
      );
  }
}
