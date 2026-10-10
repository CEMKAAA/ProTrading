import { test } from 'node:test';
import assert from 'node:assert/strict';
import { verifyUnavailablePair } from '../scripts/verify_strategy_window_pair.mjs';
const manifest = { sourceHash: 'a', templateHash: 'b', generatorHash: 'c' };
const job = { id: 'x', name: 'pilot', symbol: 'BTCUSDm', chartTf: 1, windows: [52] };
const row = { catalog_id: 'x', native_id: 'user_x', name: 'pilot', symbol: 'BTCUSDm', chart_tf: '1', weeks: '52',
  as_of: '1791575217', total: '0', wins: '0', losses: '0', open: '0', flat: '0', data: '0',
  net_r: '0', min_cum_r: '0', elapsed_ms: '1', metrics_saved: '0', independent: '0',
  status: 'HISTORY_UNAVAILABLE', settings_verified: '1', order_attempts: '0',
  settings_key: 'd'.repeat(64), calendar: 'TCAL1=0', load_mode: 'campaign',
  engine_hash: 'a', template_hash: 'b', generator_hash: 'c' };
const direct = { ...row, load_mode: 'dashboard' };

test('matching unavailable native paths confirm a gap, not wins or losses', () => {
  assert.deepEqual(verifyUnavailablePair(row, direct, job, manifest), []);
});
test('a first download failure cannot hide a successful second path', () => {
  assert.ok(verifyUnavailablePair(row, { ...direct, status: 'AUDITED' }, job, manifest).includes('AVAILABILITY_CHANGED'));
});
test('missing unavailable counterpart cannot be called verified', () => {
  assert.deepEqual(verifyUnavailablePair(row, undefined, job, manifest), ['MISSING_UNAVAILABLE_PAIR']);
});
test('unavailable comparisons bind the endpoint, settings, mode, counts and data', () => {
  for (const field of ['as_of','settings_key','calendar','independent','total','wins','losses','data','net_r'])
    assert.ok(verifyUnavailablePair(row, { ...direct, [field]: '2' }, job, manifest).length, field);
});
test('engineering failures are never relabeled as genuine data gaps', () => {
  for (const status of ['AUDIT_TIMEOUT','SETTINGS_MISMATCH','APPLY_FAILED','SAFETY_GUARD_TRIGGERED'])
    assert.ok(verifyUnavailablePair({ ...row, status }, { ...direct, status }, job, manifest).length, status);
});
test('unavailable audit still rejects stale sources and attempted orders', () => {
  assert.ok(verifyUnavailablePair(row, direct, job, { ...manifest, sourceHash: 'wrong' }).length);
  assert.ok(verifyUnavailablePair(row, { ...direct, order_attempts: '1' }, job, manifest).length);
  assert.ok(verifyUnavailablePair(row, { ...direct, settings_verified: '0' }, job, manifest).length);
});
