import { test } from 'node:test';
import assert from 'node:assert/strict';
import { recoverUnavailableFlags } from '../scripts/repair_strategy_campaign_records.mjs';

const manifest = { sourceHash: 'a', templateHash: 'b', generatorHash: 'c' };
const job = { id: 'x', name: 'pilot', symbol: 'BTCUSDm', chartTf: 1, windows: [52] };
const row = { catalog_id: 'x', native_id: 'user_x', name: 'pilot', symbol: 'BTCUSDm', chart_tf: '1', weeks: '52',
  as_of: '1791575217', total: '0', wins: '0', losses: '0', open: '0', flat: '0', data: '0',
  net_r: '0', min_cum_r: '0', elapsed_ms: '1', metrics_saved: '0', independent: '0',
  status: 'HISTORY_UNAVAILABLE', settings_verified: '1', order_attempts: '0',
  settings_key: 'd'.repeat(64), calendar: 'TCAL1=0', load_mode: 'campaign',
  engine_hash: 'a', template_hash: 'b', generator_hash: 'c' };
const direct = { ...row, load_mode: 'dashboard' };

test('recover a lost column only from identical native paths; leave audit mathematics unchanged', () => {
  const result = recoverUnavailableFlags([row], [direct], job, manifest, +row.as_of);
  assert.deepEqual(result.recovered, [52]);
  assert.deepEqual(result.rejected, []);
  const { unavailable_parity_verified, unavailable_verification_mode, ...original } = result.rows[0];
  assert.equal(unavailable_parity_verified, '1');
  assert.equal(unavailable_verification_mode, 'RECOVERED_NATIVE_PAIR');
  assert.deepEqual(original, row);
});
test('never turn an engineering error, missing counterpart or stale endpoint into a data gap', () => {
  for (const [a, b, epoch] of [
    [row, undefined, +row.as_of], [row, direct, +row.as_of + 1],
    [{ ...row, status: 'AUDIT_TIMEOUT' }, { ...direct, status: 'AUDIT_TIMEOUT' }, +row.as_of],
    [row, { ...direct, settings_key: 'e'.repeat(64) }, +row.as_of],
    [row, { ...direct, engine_hash: 'changed' }, +row.as_of],
  ]) {
    const result = recoverUnavailableFlags([a], b ? [b] : [], job, manifest, epoch);
    assert.equal(result.recovered.length, 0);
    assert.deepEqual(result.rows[0], a);
    assert.equal(result.rejected.length, 1);
  }
});
test('already verified outcomes are idempotent and cannot be relabeled as unavailable', () => {
  for (const status of ['AUDITED', 'AUDITED_OPEN', 'HISTORY_UNAVAILABLE']) {
    const existing = { ...row, status, unavailable_parity_verified: '1' };
    assert.deepEqual(recoverUnavailableFlags([existing], [], job, manifest, +row.as_of).rows, [existing]);
  }
});
