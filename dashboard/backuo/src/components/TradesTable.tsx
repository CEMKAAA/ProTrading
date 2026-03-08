import { useState, useMemo } from 'react';
import {
  ChevronUp,
  ChevronDown,
  ChevronsUpDown,
  TrendingUp,
  TrendingDown,
} from 'lucide-react';
import { formatCurrency, formatDateTime, formatDuration } from '@/lib/utils';
import type { Trade } from '@/types';

interface TradesTableProps {
  trades: Trade[];
  pageSize?: number;
}

type SortField = 'trade_number' | 'entry_time' | 'profit_loss' | 'r_multiple';
type SortOrder = 'asc' | 'desc';

export default function TradesTable({ trades, pageSize = 20 }: TradesTableProps) {
  const [sortField, setSortField] = useState<SortField>('trade_number');
  const [sortOrder, setSortOrder] = useState<SortOrder>('desc');
  const [currentPage, setCurrentPage] = useState(0);
  const [expandedTrade, setExpandedTrade] = useState<number | null>(null);

  const sortedTrades = useMemo(() => {
    const sorted = [...trades].sort((a, b) => {
      let aVal: number | string = 0;
      let bVal: number | string = 0;

      switch (sortField) {
        case 'trade_number':
          aVal = a.trade_number;
          bVal = b.trade_number;
          break;
        case 'entry_time':
          aVal = new Date(a.entry_time).getTime();
          bVal = new Date(b.entry_time).getTime();
          break;
        case 'profit_loss':
          aVal = a.profit_loss;
          bVal = b.profit_loss;
          break;
        case 'r_multiple':
          aVal = a.r_multiple;
          bVal = b.r_multiple;
          break;
      }

      if (sortOrder === 'asc') {
        return aVal > bVal ? 1 : -1;
      }
      return aVal < bVal ? 1 : -1;
    });

    return sorted;
  }, [trades, sortField, sortOrder]);

  const paginatedTrades = useMemo(() => {
    const start = currentPage * pageSize;
    return sortedTrades.slice(start, start + pageSize);
  }, [sortedTrades, currentPage, pageSize]);

  const totalPages = Math.ceil(trades.length / pageSize);

  const handleSort = (field: SortField) => {
    if (sortField === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortField(field);
      setSortOrder('desc');
    }
  };

  const SortIcon = ({ field }: { field: SortField }) => {
    if (sortField !== field) {
      return <ChevronsUpDown className="w-4 h-4 text-dark-500" />;
    }
    return sortOrder === 'asc' ? (
      <ChevronUp className="w-4 h-4 text-primary-500" />
    ) : (
      <ChevronDown className="w-4 h-4 text-primary-500" />
    );
  };

  return (
    <div>
      <div className="overflow-x-auto">
        <table className="table">
          <thead>
            <tr>
              <th>
                <button
                  onClick={() => handleSort('trade_number')}
                  className="flex items-center gap-1 hover:text-white"
                >
                  # <SortIcon field="trade_number" />
                </button>
              </th>
              <th>Direction</th>
              <th>
                <button
                  onClick={() => handleSort('entry_time')}
                  className="flex items-center gap-1 hover:text-white"
                >
                  Entry Time <SortIcon field="entry_time" />
                </button>
              </th>
              <th>Entry</th>
              <th>Exit</th>
              <th>SL</th>
              <th>
                <button
                  onClick={() => handleSort('profit_loss')}
                  className="flex items-center gap-1 hover:text-white"
                >
                  P&L <SortIcon field="profit_loss" />
                </button>
              </th>
              <th>
                <button
                  onClick={() => handleSort('r_multiple')}
                  className="flex items-center gap-1 hover:text-white"
                >
                  R <SortIcon field="r_multiple" />
                </button>
              </th>
              <th>Setup</th>
            </tr>
          </thead>
          <tbody>
            {paginatedTrades.map((trade) => (
              <>
                <tr
                  key={trade.id || trade.trade_number}
                  className="cursor-pointer hover:bg-dark-800/50"
                  onClick={() =>
                    setExpandedTrade(
                      expandedTrade === trade.trade_number ? null : trade.trade_number
                    )
                  }
                >
                  <td className="font-mono">{trade.trade_number}</td>
                  <td>
                    <span
                      className={`flex items-center gap-1 ${
                        trade.direction === 'BUY'
                          ? 'text-success-500'
                          : 'text-danger-500'
                      }`}
                    >
                      {trade.direction === 'BUY' ? (
                        <TrendingUp className="w-4 h-4" />
                      ) : (
                        <TrendingDown className="w-4 h-4" />
                      )}
                      {trade.direction}
                    </span>
                  </td>
                  <td className="text-dark-300 text-sm">
                    {formatDateTime(trade.entry_time)}
                  </td>
                  <td className="font-mono">{trade.entry_price.toFixed(2)}</td>
                  <td className="font-mono">
                    {trade.exit_price?.toFixed(2) || '-'}
                  </td>
                  <td className="font-mono text-dark-400">
                    {trade.stop_loss.toFixed(2)}
                  </td>
                  <td>
                    <span
                      className={`font-mono font-medium ${
                        trade.profit_loss >= 0
                          ? 'text-success-500'
                          : 'text-danger-500'
                      }`}
                    >
                      {trade.profit_loss >= 0 ? '+' : ''}
                      {formatCurrency(trade.profit_loss)}
                    </span>
                  </td>
                  <td>
                    <span
                      className={`font-mono ${
                        trade.r_multiple >= 0
                          ? 'text-success-500'
                          : 'text-danger-500'
                      }`}
                    >
                      {trade.r_multiple >= 0 ? '+' : ''}
                      {trade.r_multiple.toFixed(2)}R
                    </span>
                  </td>
                  <td className="text-dark-400 text-sm max-w-[200px] truncate">
                    {trade.setup_type || '-'}
                  </td>
                </tr>
                {expandedTrade === trade.trade_number && (
                  <tr key={`${trade.trade_number}-expanded`}>
                    <td colSpan={9} className="bg-dark-800/30 p-4">
                      <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                        <div>
                          <div className="text-dark-400">Exit Time</div>
                          <div className="text-white">
                            {trade.exit_time
                              ? formatDateTime(trade.exit_time)
                              : '-'}
                          </div>
                        </div>
                        <div>
                          <div className="text-dark-400">Exit Reason</div>
                          <div className="text-white">
                            {trade.exit_reason || '-'}
                          </div>
                        </div>
                        <div>
                          <div className="text-dark-400">Take Profit</div>
                          <div className="text-white font-mono">
                            {trade.take_profit?.toFixed(2) || '-'}
                          </div>
                        </div>
                        <div>
                          <div className="text-dark-400">Lot Size</div>
                          <div className="text-white font-mono">
                            {trade.lot_size.toFixed(2)}
                          </div>
                        </div>
                        <div>
                          <div className="text-dark-400">Bias</div>
                          <div
                            className={
                              trade.bias === 'bullish'
                                ? 'text-success-500'
                                : trade.bias === 'bearish'
                                ? 'text-danger-500'
                                : 'text-dark-400'
                            }
                          >
                            {trade.bias?.toUpperCase() || '-'}
                          </div>
                        </div>
                        <div>
                          <div className="text-dark-400">ORB Range</div>
                          <div className="text-white font-mono">
                            {trade.orb_high && trade.orb_low
                              ? `${trade.orb_high.toFixed(2)} - ${trade.orb_low.toFixed(2)}`
                              : '-'}
                          </div>
                        </div>
                        <div>
                          <div className="text-dark-400">Balance Before</div>
                          <div className="text-white">
                            {trade.balance_before
                              ? formatCurrency(trade.balance_before)
                              : '-'}
                          </div>
                        </div>
                        <div>
                          <div className="text-dark-400">Balance After</div>
                          <div className="text-white">
                            {trade.balance_after
                              ? formatCurrency(trade.balance_after)
                              : '-'}
                          </div>
                        </div>
                      </div>
                    </td>
                  </tr>
                )}
              </>
            ))}
          </tbody>
        </table>
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between px-4 py-3 border-t border-dark-700">
          <div className="text-sm text-dark-400">
            Showing {currentPage * pageSize + 1} to{' '}
            {Math.min((currentPage + 1) * pageSize, trades.length)} of{' '}
            {trades.length} trades
          </div>
          <div className="flex items-center gap-2">
            <button
              onClick={() => setCurrentPage((p) => Math.max(0, p - 1))}
              disabled={currentPage === 0}
              className="btn btn-secondary btn-sm"
            >
              Previous
            </button>
            <span className="text-dark-400 text-sm">
              Page {currentPage + 1} of {totalPages}
            </span>
            <button
              onClick={() =>
                setCurrentPage((p) => Math.min(totalPages - 1, p + 1))
              }
              disabled={currentPage >= totalPages - 1}
              className="btn btn-secondary btn-sm"
            >
              Next
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
