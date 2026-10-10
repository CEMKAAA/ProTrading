import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { pathToFileURL } from 'node:url';
import { csvRows, checkRow } from './report_strategy_window_campaign.mjs';
import { verifiedSnapshot } from './watch_strategy_window_refresh.mjs';
const sha = value => createHash('sha256').update(value).digest('hex');
export function frozenMetric(row, legacy) {
  const body = [legacy ? 'SW_FROZEN_LEGACY_1' : 'SW_FROZEN_VERIFIED_1', row.native_id,
    row.settings_key || 'original-campaign', row.weeks,
    ...['as_of','total','wins','losses','open','flat','net_r','min_cum_r'].map(k => Number(row[k]).toFixed(12)),
    row.independent].join('\n');
  return body + '\nSHA256=' + sha(body);
}
export function metricFolder(row, family) {
  return family === 'sol' ? dirname(row.native_id).replaceAll('/', '\\') + '\\WindowMetrics'
    : { orb: 'OrbStrategyUserLibrary', macross: 'MaCrossOrbStrategyLibrary', entrylab: 'EntryEngineLabStrategyLibrary' }[family] + '\\WindowMetrics';
}
export function baselineIssues(rows, manifest) {
  const available = new Set(['AUDITED', 'AUDITED_OPEN']);
  const unavailable = new Set(['HISTORY_UNAVAILABLE', 'REGIME_HISTORY_UNAVAILABLE',
    'REGIME_DATA_PENDING', 'WINDOW_INCOMPLETE', 'ORDERFLOW_DATA_INCOMPLETE',
    'COVERAGE_SHORT', 'DATA_INCOMPLETE']);
  return rows.flatMap(row => {
    if (!available.has(row.status)) {
      const confirmed = unavailable.has(row.status) && row.unavailable_parity_verified === '1'
        && row.settings_verified === '1' && row.order_attempts === '0'
        && row.engine_hash === manifest.sourceHash && row.template_hash === manifest.templateHash
        && row.generator_hash === manifest.generatorHash;
      return confirmed ? [] : [`${row.catalog_id}:${row.weeks}:UNCONFIRMED_${row.status}`];
    }
    const verified = row.settings_verified === '1' && row.native_parity_verified === '1'
      && /^[a-f0-9]{64}$/.test(row.trade_trace_hash ?? '')
      && row.engine_hash === manifest.sourceHash && row.template_hash === manifest.templateHash
      && row.generator_hash === manifest.generatorHash;
    return verified ? [] : [`${row.catalog_id}:${row.weeks}:UNVERIFIED_BASELINE`];
  });
}
export function sealCampaign(out, common, legacy = false) {
  const manifest = JSON.parse(readFileSync(join(out, 'manifest.private.json'), 'utf8'));
  const jobs = new Map(manifest.jobs.map(j => [j.id, j]));
  const inputs = readdirSync(join(out, 'results')).filter(n => n.endsWith('.csv')).sort();
  const rows = inputs.flatMap(n => csvRows(readFileSync(join(out, 'results', n), 'utf8')));
  const seen = new Set();
  for (const row of rows) {
    const key = `${row.catalog_id}:${row.weeks}`;
    if (seen.has(key) || checkRow(row, jobs.get(row.catalog_id)).length) throw Error('INVALID_ARCHIVE_ROW:' + key);
    seen.add(key);
  }
  if (!legacy && manifest.jobs.some(j => j.windows.some(w => !seen.has(`${j.id}:${w}`)))) throw Error('CAMPAIGN_NOT_FINISHED');
  if (!legacy && baselineIssues(rows, manifest).length) throw Error('BASELINE_REJECTED:' + baselineIssues(rows, manifest).join(';'));
  const valid = rows.filter(r => ['AUDITED','AUDITED_OPEN'].includes(r.status));
  if (!legacy && valid.some(r => r.native_parity_verified !== '1' || r.engine_hash !== manifest.sourceHash
      || r.template_hash !== manifest.templateHash || r.generator_hash !== manifest.generatorHash)) throw Error('UNVERIFIED_BASELINE');
  const epoch = legacy ? '20261008' : '20261009', folder = join(common, 'StrategyWindowArchive', epoch);
  mkdirSync(folder, { recursive: true });
  const files = [];
  for (const row of valid) {
    const text = frozenMetric(row, legacy);
    const name = sha(metricFolder(row, jobs.get(row.catalog_id).family) + '|' + row.native_id) + '.' + row.weeks + '.swm';
    const path = join(folder, name);
    if (existsSync(path)) { if (readFileSync(path, 'utf8') !== text) throw Error('IMMUTABLE_ARCHIVE_CHANGED:' + name); }
    else writeFileSync(path, text, { flag: 'wx' });
    files.push({ name, sha256: sha(text) });
  }
  const seal = JSON.stringify({ epoch, legacy, sourceHash: manifest.sourceHash,
    results: inputs.map(name => ({ name, sha256: sha(readFileSync(join(out, 'results', name))) })), files }, null, 2);
  const path = join(folder, 'seal.json');
  if (existsSync(path)) { if (readFileSync(path, 'utf8') !== seal) throw Error('IMMUTABLE_SEAL_CHANGED'); }
  else writeFileSync(path, seal, { flag: 'wx' });
  return { epoch, archivedWindows: valid.length, folder };
}
if (import.meta.url === pathToFileURL(resolve(process.argv[1] ?? '')).href) {
  // A running frozen campaign may finish its evidence, but cannot seal an
  // obsolete engine as the current verified baseline after a production fix.
  if (!process.argv.includes('--legacy')) verifiedSnapshot(resolve(import.meta.dirname, '..'), resolve(process.argv[2]));
  const common = join(process.env.APPDATA, 'MetaQuotes/Terminal/Common/Files');
  console.log(JSON.stringify(sealCampaign(resolve(process.argv[2]), common, process.argv.includes('--legacy')), null, 2));
}
