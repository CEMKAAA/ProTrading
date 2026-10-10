import { readFileSync, writeFileSync, existsSync, mkdirSync, renameSync, copyFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { csvRows } from './report_strategy_window_campaign.mjs';
import { verifyUnavailablePair } from './verify_strategy_window_pair.mjs';
import { verifiedSnapshot } from './watch_strategy_window_refresh.mjs';

export function recoverUnavailableFlags(rows, dashboard, job, manifest, asOf) {
  const recovered = [], rejected = [];
  const updated = rows.map(row => {
    if (['AUDITED', 'AUDITED_OPEN'].includes(row.status) || row.unavailable_parity_verified === '1') return row;
    const direct = dashboard.find(r => r.weeks === row.weeks);
    const issues = verifyUnavailablePair(row, direct, job, manifest);
    if (Number(row.as_of) !== asOf || !/^[a-f0-9]{64}$/.test(row.settings_key ?? '')) issues.push('EPOCH_OR_SETTINGS_INVALID');
    if (issues.length) { rejected.push({ weeks: Number(row.weeks), issues }); return row; }
    recovered.push(Number(row.weeks));
    return { ...row, unavailable_parity_verified: '1', unavailable_verification_mode: 'RECOVERED_NATIVE_PAIR' };
  });
  return { rows: updated, recovered, rejected };
}

function saveRows(path, rows) {
  const keys = [...new Set(rows.flatMap(Object.keys))];
  const cell = value => '"' + String(value ?? '').replaceAll('"', '""') + '"';
  const text = [keys.map(cell).join(','), ...rows.map(row => keys.map(k => cell(row[k])).join(','))].join('\n') + '\n';
  writeFileSync(path + '.pending', text); renameSync(path + '.pending', path);
}

if (import.meta.url === pathToFileURL(resolve(process.argv[1] ?? '')).href) {
  const root = resolve(import.meta.dirname, '..');
  const out = join(root, 'reports/verification_build/audit_failures');
  const manifest = verifiedSnapshot(root, out);
  const epoch = JSON.parse(readFileSync(join(out, 'campaign-epoch.json'), 'utf8'));
  const asOf = Date.parse(epoch.asOf.replaceAll('.', '-').replace(' ', 'T') + 'Z') / 1000;
  if (!Number.isSafeInteger(asOf) || asOf <= 0) throw Error('INVALID_EPOCH');
  const apply = process.argv.includes('--apply'), evidence = [];
  const sha = value => createHash('sha256').update(value).digest('hex');
  for (const job of manifest.jobs) {
    const path = join(out, 'results', job.id + '.csv');
    if (!existsSync(path)) continue;
    const bytes = readFileSync(path);
    const rows = csvRows(bytes.toString('utf8'));
    if (!rows.some(r => !['AUDITED', 'AUDITED_OPEN'].includes(r.status) && r.unavailable_parity_verified !== '1')) continue;
    const directPath = join(out, 'publication-dashboard/results', job.id + '.csv');
    const directBytes = existsSync(directPath) ? readFileSync(directPath) : undefined;
    const result = recoverUnavailableFlags(rows, directBytes ? csvRows(directBytes.toString('utf8')) : [], job, manifest, asOf);
    evidence.push({ id: job.id, name: job.name, family: job.family, campaignSha256: sha(bytes),
      dashboardSha256: directBytes ? sha(directBytes) : null, recovered: result.recovered, rejected: result.rejected });
    if (apply && result.recovered.length) {
      const backup = join(out, 'closure-before', job.id + '.csv');
      mkdirSync(resolve(backup, '..'), { recursive: true });
      if (!existsSync(backup)) copyFileSync(path, backup);
      saveRows(path, result.rows);
    }
  }
  const report = { applied: apply, sourceHash: manifest.sourceHash, asOf,
    recoveredWindows: evidence.reduce((n, e) => n + e.recovered.length, 0), evidence };
  if (apply) {
    const path = join(out, 'unavailable-proof-recovery.json');
    writeFileSync(path + '.pending', JSON.stringify(report, null, 2)); renameSync(path + '.pending', path);
  }
  console.log(JSON.stringify(report, null, 2));
}
