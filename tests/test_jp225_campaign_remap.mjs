import { test } from 'node:test';
import assert from 'node:assert/strict';
import { jp225Names, remapJp225Manifest } from '../scripts/prepare_jp225_campaign_remap.mjs';
import { checkRow } from '../scripts/report_strategy_window_campaign.mjs';

const manifest = { sourceHash: 'immutable', jobs: [
  ...jp225Names.map((name, index) => ({ id: 'sol_' + index, name, family: 'sol', origin: 'image:' + name,
    symbol: 'JP225s', inputs: { pipStop: 7000 + index, target: 3 }, chartTf: 5, windows: [2, 260] })),
  { id: 'untouched', symbol: 'EURUSDm', inputs: { target: 0.5 } },
] };

test('only two explicitly authorized image symbols change, never strategy inputs or source hash', () => {
  const before = structuredClone(manifest);
  const result = remapJp225Manifest(manifest);
  assert.deepEqual(manifest, before);
  assert.deepEqual(result.jobs[2], before.jobs[2]);
  assert.equal(result.sourceHash, before.sourceHash);
  for (let i = 0; i < 2; i++) {
    assert.deepEqual(result.jobs[i].inputs, before.jobs[i].inputs);
    assert.deepEqual(result.jobs[i].windows, before.jobs[i].windows);
    assert.equal(result.jobs[i].symbol, 'JP225m');
    assert.equal(result.jobs[i].sourceSymbol, 'JP225s');
    assert.equal(result.jobs[i].id, before.jobs[i].id);
  }
  assert.deepEqual(remapJp225Manifest(result), result);
});
test('a different symbol, saved record or duplicate identity cannot be silently remapped', () => {
  for (const patch of [{ symbol: 'USDJPYm' }, { origin: 'saved:record' }, { family: 'orb' }]) {
    const invalid = structuredClone(manifest);Object.assign(invalid.jobs[0], patch);
    assert.throws(() => remapJp225Manifest(invalid), /MISMATCH/);
  }
  const duplicate = structuredClone(manifest);duplicate.jobs.push(duplicate.jobs[0]);
  assert.throws(() => remapJp225Manifest(duplicate), /NOT_UNIQUE/);
});
test('native results must carry the actual audited broker symbol, not the archived symbol', () => {
  const job = remapJp225Manifest(manifest).jobs[0];
  const row = { catalog_id: job.id, name: job.name, symbol: 'JP225m', chart_tf: '5', weeks: '2',
    total: '1', wins: '1', losses: '0', open: '0', flat: '0', data: '0', order_attempts: '0',
    status: 'AUDITED', metrics_saved: '1', net_r: '2', min_cum_r: '0', as_of: '1791490000', elapsed_ms: '10' };
  assert.deepEqual(checkRow(row, job), []);
  assert.ok(checkRow({ ...row, symbol: 'JP225s' }, job).includes('IDENTITY'));
});
