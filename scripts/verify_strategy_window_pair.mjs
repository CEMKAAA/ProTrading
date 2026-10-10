import { readFileSync, writeFileSync, renameSync, existsSync, unlinkSync, mkdirSync, copyFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawnSync } from 'node:child_process';
import { csvRows, checkRow } from './report_strategy_window_campaign.mjs';
import { compareAudits, compareTrades } from './verify_strategy_campaign_parity.mjs';
const sha = text => createHash('sha256').update(text).digest('hex');
const unavailableStatuses = new Set(['HISTORY_UNAVAILABLE', 'REGIME_HISTORY_UNAVAILABLE',
  'REGIME_DATA_PENDING', 'WINDOW_INCOMPLETE', 'ORDERFLOW_DATA_INCOMPLETE', 'COVERAGE_SHORT', 'DATA_INCOMPLETE']);
export function verifyUnavailablePair(a, b, job, manifest) {
  if (!a || !b) return ['MISSING_UNAVAILABLE_PAIR'];
  const issues = [];
  if (!unavailableStatuses.has(a.status) || a.status !== b.status) issues.push('AVAILABILITY_CHANGED');
  for (const row of [a, b]) {
    issues.push(...checkRow({ ...row, metrics_saved: '0' }, job));
    if (row.settings_verified !== '1' || row.order_attempts !== '0' || Number(row.as_of) <= 0)
      issues.push('UNVERIFIED_UNAVAILABLE');
    for (const [field, expected] of [['engine_hash', manifest.sourceHash], ['template_hash', manifest.templateHash], ['generator_hash', manifest.generatorHash]])
      if (row[field] !== expected) issues.push('SOURCE_CHANGED:' + field);
  }
  for (const key of ['catalog_id','native_id','symbol','chart_tf','weeks','as_of','settings_key','calendar','independent',
    'total','wins','losses','open','flat','data','net_r','min_cum_r'])
    if (a[key] !== b[key]) issues.push('UNAVAILABLE:' + key);
  if (a.load_mode !== 'campaign' || b.load_mode !== 'dashboard') issues.push('LOAD_PATH');
  return [...new Set(issues)];
}
export function verifyWindowPair(a, b, ta, tb, job, manifest) {
  const issues = [...compareAudits(a, b), ...compareTrades(ta, tb)];
  for (const row of [a, b]) {
    if (!row) continue;
    issues.push(...checkRow({ ...row, metrics_saved: '1' }, job));
    for (const [field, value] of [['engine_hash', manifest.sourceHash], ['template_hash', manifest.templateHash], ['generator_hash', manifest.generatorHash]])
      if (row[field] !== value) issues.push('SOURCE_CHANGED:' + field);
    if (ta?.length !== +a?.total || tb?.length !== +b?.total) issues.push('TRACE_TOTAL');
  }
  return [...new Set(issues)];
}
if (import.meta.url === pathToFileURL(resolve(process.argv[1] ?? '')).href) {
  const [out, worker, id] = process.argv.slice(2).map(String);
  const manifest = JSON.parse(readFileSync(join(out, 'manifest.private.json'), 'utf8'));
  const job = manifest.jobs.find(j => j.id === id); if (!job) throw Error('UNKNOWN_STRATEGY');
  let a = csvRows(readFileSync(join(out, 'publication-check/campaign.csv'), 'utf8'));
  let b = csvRows(readFileSync(join(worker, 'MQL5/Files/Campaign_' + id + '.csv'), 'utf8'));
  const inspect = row => {
    const direct = b.find(r => r.weeks === row.weeks);
    const paths = ['campaign','dashboard'].map(mode => join(worker, 'MQL5/Files', `Trace_${id}_${row.weeks}_${mode}.csv`));
    const traces = paths.map(p => existsSync(p) ? csvRows(readFileSync(p, 'utf8')) : undefined);
    const ready = ['AUDITED','AUDITED_OPEN'].includes(row.status);
    const issues = ready ? verifyWindowPair(row, direct, ...traces, job, manifest)
      : verifyUnavailablePair(row, direct, job, manifest);
    return { paths, ready, issues };
  };
  const retry = a.filter(row => inspect(row).issues.length).map(row => Number(row.weeks));
  if (retry.length) {
    // A first run can be incomplete while the second finishes a download.
    // Re-run only mismatched windows once, through both native paths. Never
    // turn the second run's success alone into campaign/dashboard proof.
    if (retry.some(w => !job.windows.includes(w))) throw Error('INVALID_RETRY_WINDOW');
    const root = resolve(import.meta.dirname, '..');
    const asOf = new Date(Number(a[0].as_of) * 1000).toISOString().slice(0,19).replace('T',' ').replaceAll('-','.');
    const quote = text => "'" + text.replaceAll("'", "''") + "'";
    const bars = Number(readFileSync(join(out, 'worker.ini'), 'utf8').match(/MaxBars=(\d+)/)?.[1]);
    if (!Number.isInteger(bars) || bars < 1000 || bars > 100000000) throw Error('INVALID_HISTORY_LIMIT');
    for (const mode of ['campaign','dashboard']) {
      const command = `& ${quote(join(root,'scripts/run_strategy_window_campaign.ps1'))} -Mode Run -ReportDir ${quote(out)}`
        + ` -StrategyIds @(${quote(id)}) -Weeks @(${retry.join(',')}) -ResultSet publication-retry-${mode}`
        + ` -AsOf ${quote(asOf)} -TraceTrades -PairTraceOnly -Force -HistoryMaxBars ${bars} -TimeoutSeconds 1800`
        + (mode === 'dashboard' ? ' -DashboardLoad' : '');
      console.log(`RETRY NATIVE PAIR ${id} ${retry.join(',')} ${mode}`);
      const run = spawnSync('powershell.exe', ['-NoProfile','-ExecutionPolicy','Bypass','-Command',command],
        { cwd: root, windowsHide: true, stdio: 'inherit' });
      if (run.status !== 0) throw Error('NATIVE_PAIR_RETRY_FAILED');
      const fresh = csvRows(readFileSync(join(worker,'MQL5/Files/Campaign_' + id + '.csv'),'utf8'));
      if (fresh.length !== retry.length || fresh.some(r => r.catalog_id !== id || !retry.includes(Number(r.weeks))))
        throw Error('RETRY_OUTPUT_IDENTITY');
      if (mode === 'campaign') a = [...a.filter(r => !retry.includes(Number(r.weeks))), ...fresh];
      else b = [...b.filter(r => !retry.includes(Number(r.weeks))), ...fresh];
    }
  }
  const result = a.map(row => {
    const { paths, ready, issues } = inspect(row);
    const verified = ready && issues.length === 0;
    if (issues.length || !ready) {
      mkdirSync(join(out, 'publication-check/last-failure'), { recursive: true });
      paths.forEach((p, i) => { if (existsSync(p)) copyFileSync(p, join(out, 'publication-check/last-failure', ['campaign','dashboard'][i] + '.' + row.weeks + '.csv')); });
    }
    const result = { ...row, metrics_saved: '0', native_parity_verified: verified ? '1' : '0',
      unavailable_parity_verified: !ready && !issues.length ? '1' : '0',
      trade_trace_hash: verified ? sha(readFileSync(paths[0])) : '',
      status: issues.length ? 'PARITY_MISMATCH' : row.status, detail: issues.length ? issues.join(';') : row.detail };
    // Disposable full traces are not retained for every strategy/refresh.
    for (const p of paths) if (existsSync(p)) unlinkSync(p);
    return result;
  });
  const headers = [...new Set(result.flatMap(Object.keys))];
  const cell = value => '"' + String(value ?? '').replaceAll('"', '""') + '"';
  const destination = join(out, 'publication-check/verified.csv');
  writeFileSync(destination + '.pending', [headers.map(cell).join(','), ...result.map(r => headers.map(k => cell(r[k])).join(','))].join('\n') + '\n');
  renameSync(destination + '.pending', destination);
}
