import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { csvRows, checkRow, checkMetric, strategyCoverage } from '../scripts/report_strategy_window_campaign.mjs';

const job = { id: 'orb_test', symbol: 'USDJPYm', name: 'test', chartTf: 5, windows: [2, 260] };
const row = { catalog_id: job.id, native_id: 'user_a', name: job.name, symbol: job.symbol,
  chart_tf: '5', weeks: '260', total: '10', wins: '7', losses: '2', open: '1', flat: '0', data: '0',
  net_r: '0.75', min_cum_r: '-1', as_of: '1791490000', status: 'AUDITED_OPEN', metrics_saved: '1', elapsed_ms: '10', order_attempts: '0' };
test('CSV parser preserves quotes, commas, UTF-8, newlines and CRLF', () => {
  assert.deepEqual(csvRows('\uFEFFid,name\r\n"a","x,""y""\nz"\r\n'), [{ id: 'a', name: 'x,"y"\nz' }]);
  assert.deepEqual(csvRows('id,name\na,JP225 Türkçe'), [{ id: 'a', name: 'JP225 Türkçe' }]);
  assert.throws(() => csvRows('id,name\na,"broken'), /UNTERMINATED/);
});
test('valid open and closed outcomes reconcile exactly', () => {
  assert.deepEqual(checkRow(row, job), []);
  assert.deepEqual(checkRow({ ...row, total: '9', open: '0', status: 'AUDITED' }, job), []);
  assert.ok(checkRow({ ...row, total: '30' }, job).includes('COUNTS'));
});
test('DATA and research orders can never be ready metrics', () => {
  assert.ok(checkRow({ ...row, data: '1' }, job).includes('UNSAFE_READY'));
  assert.ok(checkRow({ ...row, order_attempts: '1' }, job).includes('UNSAFE_READY'));
  assert.ok(checkRow({ ...row, status: 'DATA_INCOMPLETE' }, job).includes('INCOMPLETE_PUBLISHED'));
});
test('identity and requested window cannot be silently changed', () => {
  assert.ok(checkRow({ ...row, symbol: 'XAUUSDm' }, job).includes('IDENTITY'));
  assert.ok(checkRow({ ...row, chart_tf: '1' }, job).includes('TIMEFRAME'));
  assert.ok(checkRow({ ...row, weeks: '51' }, job).includes('WINDOW'));
});
test('native metric checksum and numeric readback independently verified', () => {
  const body = ['SW_METRICS_1', row.native_id, 'a'.repeat(64), row.weeks,
    ...['as_of', 'total', 'wins', 'losses', 'open', 'flat', 'net_r', 'min_cum_r'].map(key => Number(row[key]).toFixed(12))].join('\n');
  const metric = body + '\nSHA256=' + createHash('sha256').update(body).digest('hex');
  assert.deepEqual(checkMetric(metric, row), []);
  assert.ok(checkMetric(metric.replace('0.750000000000', '0.850000000000'), row).includes('CHECKSUM'));
  assert.ok(checkMetric(metric, { ...row, net_r: '0.5' }).includes('net_r'));
});

test('missing 5Y never suppresses independently valid shorter-window results', () => {
  const limited = { ...job, family: 'entrylab', windows: [260, 52, 20, 10, 5, 2] };
  const failed = { ...row, status: 'HISTORY_UNAVAILABLE', metrics_saved: '0' };
  const valid = [20, 10, 5, 2].map(weeks => ({ ...row, weeks: String(weeks) }));
  const coverage = strategyCoverage(limited, [failed, { ...failed, weeks: '52' }, ...valid]);
  assert.deepEqual(coverage.availableWeeks, [2, 5, 10, 20]);
  assert.deepEqual(coverage.unavailableWeeks, [52, 260]);
  assert.deepEqual(coverage.pendingWeeks, []);
  assert.equal(coverage.maxAvailableWeeks, 20);
});

test('not attempted and DATA windows are not fabricated as available audits', () => {
  const limited = { ...job, family: 'entrylab' };
  const failed = { ...row, status: 'DATA_INCOMPLETE', metrics_saved: '0', data: '1' };
  assert.deepEqual(strategyCoverage(limited, [failed]).availableWeeks, []);
  assert.deepEqual(strategyCoverage(limited, [failed]).unavailableWeeks, [260]);
  assert.deepEqual(strategyCoverage(limited, [failed]).pendingWeeks, [2]);
  assert.equal(strategyCoverage(limited, [failed]).maxAvailableWeeks, 0);
  assert.deepEqual(strategyCoverage(limited, [{ ...row, weeks: '2', total: '999' }]).availableWeeks, []);
});
