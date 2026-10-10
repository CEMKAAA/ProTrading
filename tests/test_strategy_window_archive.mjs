import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { frozenMetric, baselineIssues } from '../scripts/seal_strategy_window_campaign.mjs';
import { verifyWindowPair } from '../scripts/verify_strategy_window_pair.mjs';
const sha = v => createHash('sha256').update(v).digest('hex');
const manifest = { sourceHash: 'a', templateHash: 'b', generatorHash: 'c' };
const job = { id: 'a', name: 'pilot', symbol: 'JP225m', chartTf: 1, windows: [2] };
const row = { catalog_id: 'a', native_id: 'user_a', name: 'pilot', symbol: 'JP225m', chart_tf: '1', weeks: '2',
  total: '1', wins: '1', losses: '0', open: '0', flat: '0', data: '0', net_r: '0.01', min_cum_r: '0',
  as_of: '1791504000', independent: '1', settings_key: 'a'.repeat(64), calendar: '', status: 'AUDITED',
  settings_verified: '1', order_attempts: '0', elapsed_ms: '1', load_mode: 'campaign',
  engine_hash: 'a', template_hash: 'b', generator_hash: 'c' };
test('frozen archive is checksummed and distinctly marked legacy or verified', () => {
  for (const legacy of [true, false]) {
    const text = frozenMetric(row, legacy), at = text.indexOf('\nSHA256=');
    assert.equal(text.slice(at + 8), sha(text.slice(0, at)));
    assert.equal(text.split('\n')[0], legacy ? 'SW_FROZEN_LEGACY_1' : 'SW_FROZEN_VERIFIED_1');
    assert.equal(text.slice(0, at).split('\n').length, 13);
  }
});
test('every current publication compares native trades, counts, geometry, R, MC and source identity', () => {
  const b = { ...row, load_mode: 'dashboard' }, trace = [{ entry_time: '1', tp: '150', net_r: '0.01' }];
  assert.deepEqual(verifyWindowPair(row, b, trace, trace, job, manifest), []);
  assert.ok(verifyWindowPair(row, { ...b, net_r: '0.02' }, trace, trace, job, manifest).includes('net_r'));
  assert.ok(verifyWindowPair(row, b, trace, [{ ...trace[0], tp: '151' }], job, manifest).length);
  assert.ok(verifyWindowPair(row, b, trace, trace, job, { ...manifest, sourceHash: 'wrong' }).length);
});
test('all four strategy screens have source selection but native metric writers never use archive paths', () => {
  for (const folder of ['orb', 'macrossover_orb', 'entry_engine_lab', 'SolAdvanced']) {
    const code = readFileSync(new URL(`../IndicatorCodeExamples/${folder}/StrategyWindowMetrics.mqh`, import.meta.url), 'utf8');
    const writer = code.slice(code.indexOf('bool SwWrite('), code.indexOf('bool SwReadView('));
    assert.doesNotMatch(writer, /SwFrozenPath|StrategyWindowArchive/);
    assert.match(code, /if\(!g_swFrozen\)return SwRead/);
    assert.match(code, /existing.asOf>asOf/);
  }
});
test('three saved strategy NAS clocks remain stable across display chart changes and re-save', () => {
  for (const folder of ['orb', 'macrossover_orb', 'entry_engine_lab']) {
    const code = readFileSync(new URL(`../IndicatorCodeExamples/${folder}/OrbStrategyUserLibrary.mqh`, import.meta.url), 'utf8');
    assert.match(code, /g_rtNasTf=\(ENUM_TIMEFRAMES\)g_userStrategies\[i\].chartTf/);
    assert.match(code, /if\(\(int\)NasConfirmationTf\(\)!=g_userStrategies\[i\].chartTf\)return false/);
    assert.match(code, /\(string\)\(int\)NasConfirmationTf\(\)\+"\\n"\+signature/);
  }
});

test('baseline permits genuine unavailable data, never parity or engineering failures', () => {
  const verified = { ...row, native_parity_verified: '1', trade_trace_hash: 'd'.repeat(64) };
  assert.deepEqual(baselineIssues([verified], manifest), []);
  assert.deepEqual(baselineIssues([{ ...row, status: 'HISTORY_UNAVAILABLE', unavailable_parity_verified: '1' }], manifest), []);
  assert.ok(baselineIssues([{ ...row, status: 'HISTORY_UNAVAILABLE' }], manifest).length);
  for (const status of ['PARITY_MISMATCH', 'SETTINGS_MISMATCH', 'METRIC_WRITE_FAILED',
    'AUDIT_TIMEOUT', 'SAFETY_GUARD_TRIGGERED', 'NEWER_NATIVE_RESULT_RETAINED', 'UNKNOWN']) {
    assert.ok(baselineIssues([{ ...row, status }], manifest).length, status);
  }
  assert.ok(baselineIssues([{ ...verified, trade_trace_hash: '' }], manifest).length);
});
