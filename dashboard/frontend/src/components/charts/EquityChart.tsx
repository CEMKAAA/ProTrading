import { useMemo } from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Area,
  AreaChart,
  ReferenceLine,
} from 'recharts';
import { formatCurrency, formatDateTime } from '@/lib/utils';
import type { EquityPoint } from '@/types';

interface EquityChartProps {
  data: EquityPoint[];
  height?: number;
  showArea?: boolean;
}

export default function EquityChart({ data, height = 300, showArea = true }: EquityChartProps) {
  const chartData = useMemo(() => {
    return data.map((point) => ({
      ...point,
      time: new Date(point.timestamp).getTime(),
      displayTime: formatDateTime(point.timestamp),
    }));
  }, [data]);

  const minEquity = useMemo(() => {
    return Math.min(...chartData.map((d) => d.equity));
  }, [chartData]);

  const maxEquity = useMemo(() => {
    return Math.max(...chartData.map((d) => d.equity));
  }, [chartData]);

  const startEquity = chartData[0]?.equity || 0;

  const CustomTooltip = ({ active, payload }: any) => {
    if (active && payload && payload.length) {
      const data = payload[0].payload;
      return (
        <div className="bg-dark-800 border border-dark-700 rounded-lg p-3 shadow-xl">
          <div className="text-dark-400 text-xs mb-1">{data.displayTime}</div>
          <div className="text-white font-bold">
            {formatCurrency(data.equity)}
          </div>
          {data.pnl !== undefined && (
            <div
              className={`text-sm ${
                data.pnl >= 0 ? 'text-success-500' : 'text-danger-500'
              }`}
            >
              Trade P&L: {data.pnl >= 0 ? '+' : ''}{formatCurrency(data.pnl)}
            </div>
          )}
        </div>
      );
    }
    return null;
  };

  if (showArea) {
    return (
      <ResponsiveContainer width="100%" height={height}>
        <AreaChart data={chartData}>
          <defs>
            <linearGradient id="equityGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor="#0ea5e9" stopOpacity={0.3} />
              <stop offset="95%" stopColor="#0ea5e9" stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
          <XAxis
            dataKey="time"
            type="number"
            domain={['dataMin', 'dataMax']}
            tickFormatter={(value) => {
              const date = new Date(value);
              return `${date.getMonth() + 1}/${date.getDate()}`;
            }}
            stroke="#64748b"
            tick={{ fill: '#64748b', fontSize: 11 }}
          />
          <YAxis
            domain={[minEquity * 0.98, maxEquity * 1.02]}
            tickFormatter={(value) => `$${(value / 1000).toFixed(1)}k`}
            stroke="#64748b"
            tick={{ fill: '#64748b', fontSize: 11 }}
          />
          <Tooltip content={<CustomTooltip />} />
          <ReferenceLine
            y={startEquity}
            stroke="#475569"
            strokeDasharray="5 5"
            label={{
              value: 'Start',
              fill: '#64748b',
              fontSize: 10,
              position: 'insideTopRight',
            }}
          />
          <Area
            type="monotone"
            dataKey="equity"
            stroke="#0ea5e9"
            strokeWidth={2}
            fill="url(#equityGradient)"
            dot={false}
            activeDot={{ r: 4, fill: '#0ea5e9', stroke: '#0f172a', strokeWidth: 2 }}
          />
        </AreaChart>
      </ResponsiveContainer>
    );
  }

  return (
    <ResponsiveContainer width="100%" height={height}>
      <LineChart data={chartData}>
        <CartesianGrid strokeDasharray="3 3" stroke="#334155" />
        <XAxis
          dataKey="time"
          type="number"
          domain={['dataMin', 'dataMax']}
          tickFormatter={(value) => {
            const date = new Date(value);
            return `${date.getMonth() + 1}/${date.getDate()}`;
          }}
          stroke="#64748b"
          tick={{ fill: '#64748b', fontSize: 11 }}
        />
        <YAxis
          domain={[minEquity * 0.98, maxEquity * 1.02]}
          tickFormatter={(value) => `$${(value / 1000).toFixed(1)}k`}
          stroke="#64748b"
          tick={{ fill: '#64748b', fontSize: 11 }}
        />
        <Tooltip content={<CustomTooltip />} />
        <ReferenceLine y={startEquity} stroke="#475569" strokeDasharray="5 5" />
        <Line
          type="monotone"
          dataKey="equity"
          stroke="#0ea5e9"
          strokeWidth={2}
          dot={false}
          activeDot={{ r: 4, fill: '#0ea5e9' }}
        />
      </LineChart>
    </ResponsiveContainer>
  );
}
