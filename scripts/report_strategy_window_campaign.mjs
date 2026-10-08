import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const sha = value => createHash('sha256').update(value).digest('hex');
export function csvRows(text) {
  const rows = [], cells = [];
  let value = '', quoted = false;
  text = text.replace(/^\uFEFF/, '');
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (c === '"') {
      if (quoted && text[i + 1] === '"') { value += '"'; i++; }
      else quoted = !quoted;
    } else if (!quoted && (c === ',' || c === '\n')) {
      cells.push(value.replace(/\r$/, '')); value = '';
      if (c === '\n') { rows.push(cells.splice(0)); }
    } else value += c;
  }
  if (quoted) throw Error('CSV_UNTERMINATED_QUOTE');
  if (value || cells.length) { cells.push(value.replace(/\r$/, '')); rows.push(cells); }
  const headers = rows.shift() ?? [];
  return rows.filter(row => row.some(Boolean)).map(row => {
    if (row.length !== headers.length) throw Error('CSV_COLUMN_COUNT');
    return Object.fromEntries(headers.map((key, i) => [key, row[i]]));
  });
}

export function checkRow(row, job) {
  const issues = [];
  if (!job || row.catalog_id !== job.id || row.symbol !== job.symbol || row.name !== job.name)
    issues.push('IDENTITY');
  if (job && !job.windows.includes(Number(row.weeks)) && row.status !== 'APPLY_FAILED')
    issues.push('WINDOW');
  if (job && Number(row.chart_tf) !== job.chartTf) issues.push('TIMEFRAME');
  const keys = ['total', 'wins', 'losses', 'open', 'flat', 'data', 'order_attempts'];
  for (const key of keys) if (!/^\d+$/.test(row[key] ?? '') || !Number.isSafeInteger(Number(row[key]))) issues.push(key);
  for (const key of ['net_r', 'min_cum_r', 'as_of', 'elapsed_ms'])
    if (row[key] === '' || !Number.isFinite(Number(row[key]))) issues.push(key);
  const ready = ['AUDITED', 'AUDITED_OPEN'].includes(row.status);
  if (ready) {
    if (Number(row.data) !== 0 || Number(row.order_attempts) !== 0 || row.metrics_saved !== '1') issues.push('UNSAFE_READY');
    if (Number(row.as_of) <= 0 || Number(row.min_cum_r) > 1e-8) issues.push('METRIC_DOMAIN');
    if (['wins', 'losses', 'open', 'flat'].reduce((n, key) => n + Number(row[key]), 0) !== Number(row.total)) issues.push('COUNTS');
    if ((row.status === 'AUDITED_OPEN') !== (Number(row.open) > 0)) issues.push('OPEN_STATUS');
  } else if (row.metrics_saved !== '0') issues.push('INCOMPLETE_PUBLISHED');
  return issues;
}

export function checkMetric(text, row) {
  const at = text.indexOf('\nSHA256=');
  if (at < 0 || sha(text.slice(0, at)) !== text.slice(at + 8)) return ['CHECKSUM'];
  const values = text.slice(0, at).split('\n');
  if (values.length !== 12 || values[0] !== 'SW_METRICS_1' || values[1] !== row.native_id || values[3] !== row.weeks)
    return ['METRIC_IDENTITY'];
  if (!/^[a-f0-9]{64}$/.test(values[2])) return ['SETTINGS_KEY'];
  const columns = ['as_of', 'total', 'wins', 'losses', 'open', 'flat', 'net_r', 'min_cum_r'];
  return columns.filter((key, i) => !Number.isFinite(Number(values[i + 4])) || Math.abs(Number(values[i + 4]) - Number(row[key])) > 1e-8);
}

function metricPath(common, row, family) {
  const folder = family === 'sol' ? join(dirname(row.native_id), 'WindowMetrics')
    : join({ orb: 'OrbStrategyUserLibrary', macross: 'MaCrossOrbStrategyLibrary', entrylab: 'EntryEngineLabStrategyLibrary' }[family], 'WindowMetrics');
  return join(common, folder, `${sha(row.native_id)}.${row.weeks}.swm`);
}

export function strategyCoverage(job, rows) {
  const own = rows.filter(row => row.catalog_id === job.id);
  const available = new Set(own.filter(row => ['AUDITED', 'AUDITED_OPEN'].includes(row.status)
    && checkRow(row, job).length === 0).map(row => Number(row.weeks)));
  const attempted = new Set(own.map(row => Number(row.weeks)));
  const windows = [...job.windows].sort((a, b) => a - b);
  const availableWeeks = windows.filter(weeks => available.has(weeks));
  return {
    id: job.id, family: job.family, name: job.name,
    availableWeeks,
    unavailableWeeks: windows.filter(weeks => attempted.has(weeks) && !available.has(weeks)),
    pendingWeeks: windows.filter(weeks => !attempted.has(weeks)),
    maxAvailableWeeks: availableWeeks.at(-1) ?? 0,
  };
}

export function reportCampaign(root, verifyCommon = false) {
  const out = join(root, 'reports/strategy_audit_20261008');
  const manifest = JSON.parse(readFileSync(join(out, 'manifest.private.json'), 'utf8'));
  const jobs = new Map(manifest.jobs.map(job => [job.id, job]));
  const rows = readdirSync(join(out, 'results')).filter(name => name.endsWith('.csv'))
    .flatMap(name => csvRows(readFileSync(join(out, 'results', name), 'utf8')));
  const errors = [], seen = new Set();
  const common = join(process.env.APPDATA ?? '', 'MetaQuotes/Terminal/Common/Files');
  const ready = row => ['AUDITED', 'AUDITED_OPEN'].includes(row.status);
  for (const row of rows) {
    const job = jobs.get(row.catalog_id), key = `${row.catalog_id}:${row.weeks}`;
    const issues = checkRow(row, job);
    if (seen.has(key)) issues.push('DUPLICATE_WINDOW');
    seen.add(key);
    if (verifyCommon && ready(row) && job) {
      const path = metricPath(common, row, job.family);
      if (!existsSync(path)) issues.push('METRIC_MISSING');
      else issues.push(...checkMetric(readFileSync(path, 'utf8'), row));
    }
    if (issues.length) errors.push({ id: row.catalog_id, weeks: Number(row.weeks), issues });
  }
  const coverage = manifest.jobs.map(job => strategyCoverage(job, rows));
  const byFamily = Object.fromEntries(Object.keys(manifest.families).map(family => {
    const records = manifest.jobs.filter(job => job.family === family), ids = new Set(records.map(job => job.id));
    const results = rows.filter(row => ids.has(row.catalog_id));
    const familyCoverage = coverage.filter(record => record.family === family);
    return [family, {
      strategies: records.length, strategiesAttempted: new Set(results.map(row => row.catalog_id)).size,
      strategiesWithResults: familyCoverage.filter(record => record.availableWeeks.length > 0).length,
      partialStrategies: familyCoverage.filter(record => record.availableWeeks.length > 0 && record.unavailableWeeks.length > 0).length,
      strategiesWithoutResults: familyCoverage.filter(record => record.availableWeeks.length === 0 && record.unavailableWeeks.length > 0).length,
      completeStrategies: records.filter(job => job.windows.every(weeks => results.some(row => row.catalog_id === job.id && Number(row.weeks) === weeks && ready(row)))).length,
      validWindows: results.filter(ready).length,
      validFiveYear: results.filter(row => ready(row) && Number(row.weeks) === 260).length,
      incompleteWindows: results.filter(row => !ready(row)).length,
    }];
  }));
  return {
    generatedAt: new Date().toISOString(), sourceHash: manifest.sourceHash,
    requestedStrategies: manifest.strategies, requestedWindows: manifest.strategies * manifest.windows.length,
    strategiesAttempted: new Set(rows.map(row => row.catalog_id)).size,
    strategiesWithResults: Object.values(byFamily).reduce((n, f) => n + f.strategiesWithResults, 0),
    partialStrategies: Object.values(byFamily).reduce((n, f) => n + f.partialStrategies, 0),
    strategiesWithoutResults: Object.values(byFamily).reduce((n, f) => n + f.strategiesWithoutResults, 0),
    completeStrategies: Object.values(byFamily).reduce((n, f) => n + f.completeStrategies, 0),
    validWindows: rows.filter(ready).length,
    validFiveYear: rows.filter(row => ready(row) && Number(row.weeks) === 260).length,
    profitableFiveYear: rows.filter(row => ready(row) && Number(row.weeks) === 260 && Number(row.net_r) > 0).length,
    incompleteWindows: rows.filter(row => !ready(row)).length,
    notAttemptedWindows: manifest.jobs.reduce((n, job) => n + job.windows.filter(weeks => !seen.has(`${job.id}:${weeks}`)).length, 0),
    statuses: Object.fromEntries([...new Set(rows.map(row => row.status))].map(status => [status, rows.filter(row => row.status === status).length])),
    byFamily, commonFilesVerified: verifyCommon, integrityErrors: errors, coverage,
  };
}

if (resolve(process.argv[1] ?? '') === fileURLToPath(import.meta.url)) {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  const watch = process.argv.includes('--watch');
  do {
    const report = reportCampaign(root, process.argv.includes('--verify-common'));
    if (process.argv.includes('--write')) {
      writeFileSync(join(root, 'reports/strategy_audit_20261008/verification.json'), JSON.stringify(report, null, 2));
      writeFileSync(join(root, 'reports/strategy_audit_20261008/coverage.json'), JSON.stringify({ generatedAt: report.generatedAt, strategies: report.coverage }, null, 2));
    }
    const { coverage, ...summary } = report;
    console.log(JSON.stringify(watch ? {
      at: report.generatedAt, attempted: report.strategiesAttempted, complete: report.completeStrategies,
      validWindows: report.validWindows, validFiveYear: report.validFiveYear, integrityErrors: report.integrityErrors,
    } : process.argv.includes('--coverage') ? report : summary, null, watch ? 0 : 2));
    if (report.integrityErrors.length) { process.exitCode = 1; break; }
    if (!watch) break;
    // Retry a partially written progress JSON without confusing it with completion.
    let progress;
    try { progress = JSON.parse(readFileSync(join(root, 'reports/strategy_audit_20261008/progress.json'), 'utf8').replace(/^\uFEFF/, '')); }
    catch { progress = { state: 'running' }; }
    if (progress.state === 'finished') break;
    await new Promise(resolve => setTimeout(resolve, 30000));
  } while (watch);
}
