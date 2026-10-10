import { readFileSync, writeFileSync, existsSync, mkdirSync, renameSync, unlinkSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { createHash } from 'node:crypto';
import { pathToFileURL } from 'node:url';
import { csvRows, checkRow, reportCampaign } from './report_strategy_window_campaign.mjs';
import { compareAudits } from './verify_strategy_campaign_parity.mjs';
import { verifyWindowPair } from './verify_strategy_window_pair.mjs';
import { verifiedSnapshot } from './watch_strategy_window_refresh.mjs';

const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const ready = r => r && ['AUDITED', 'AUDITED_OPEN'].includes(r.status);
const json = p => JSON.parse(readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
function atomic(path, text) {
  mkdirSync(resolve(path, '..'), { recursive: true });
  writeFileSync(path + '.pending', text); renameSync(path + '.pending', path);
}
function saveRows(path, rows) {
  const keys = [...new Set(rows.flatMap(Object.keys))];
  const cell = v => '"' + String(v ?? '').replaceAll('"', '""') + '"';
  atomic(path, [keys.map(cell).join(','), ...rows.map(r => keys.map(k => cell(r[k])).join(','))].join('\n') + '\n');
}
const rowsAt = path => existsSync(path) ? csvRows(readFileSync(path, 'utf8')) : [];

export function priorVerified(row, job, manifest) {
  return ready(row) && row.native_parity_verified === '1'
    && /^[a-f0-9]{64}$/.test(row.trade_trace_hash ?? '')
    && checkRow(row, job).length === 0
    && ['sourceHash', 'templateHash', 'generatorHash'].every((k, i) =>
      row[['engine_hash', 'template_hash', 'generator_hash'][i]] === manifest[k]);
}

// This is a new native dashboard execution, not a source-hash migration of old
// totals. The old campaign/dashboard trace hash witnesses identical mathematics.
export function equivalentAudit(old, current, traceBytes, job, oldManifest, manifest) {
  if (!priorVerified(old, job, oldManifest)) return ['OLD_NATIVE_PROOF_REQUIRED'];
  if (!ready(current) || !traceBytes) return ['CURRENT_NATIVE_PROOF_REQUIRED'];
  const issues = checkRow({ ...current, metrics_saved: '1' }, job);
  for (const [k, field] of [['sourceHash','engine_hash'], ['templateHash','template_hash'], ['generatorHash','generator_hash']])
    if (current[field] !== manifest[k]) issues.push('CURRENT_SOURCE:' + field);
  if (oldManifest.templateHash !== manifest.templateHash || oldManifest.generatorHash !== manifest.generatorHash)
    issues.push('LOAD_PATH_CHANGED');
  // Versioned settings keys are intentionally different after the audit fix.
  // The caller separately checks the complete, immutable job/input inventory.
  issues.push(...compareAudits({ ...old, engine_hash: current.engine_hash, settings_key: current.settings_key }, current));
  const trace = csvRows(traceBytes.toString('utf8'));
  if (trace.length !== Number(current.total)) issues.push('TRACE_TOTAL');
  if (sha(traceBytes) !== old.trade_trace_hash) issues.push('OLD_TRACE_CHANGED');
  return [...new Set(issues)];
}

function context(root) {
  const out = join(root, 'reports/verification_build/audit_failures');
  const oldOut = join(root, 'reports/strategy_audit_20261009_rolling');
  const manifest = verifiedSnapshot(root, out), oldManifest = json(join(oldOut, 'manifest.private.json'));
  if (JSON.stringify(manifest.jobs) !== JSON.stringify(oldManifest.jobs)) throw Error('INVENTORY_CHANGED');
  const epoch = json(join(oldOut, 'campaign-epoch.json'));
  const asOf = Date.parse(epoch.asOf.replaceAll('.', '-').replace(' ', 'T') + 'Z') / 1000;
  if (!Number.isSafeInteger(asOf) || asOf <= 0) throw Error('INVALID_EPOCH');
  return { root, out, oldOut, manifest, oldManifest, epoch, asOf };
}
function currentRows(c, job) { return rowsAt(join(c.out, 'results', job.id + '.csv')); }
function commit(c, job, additions) {
  const updated = new Set(additions.map(r => r.weeks));
  saveRows(join(c.out, 'results', job.id + '.csv'),
    [...currentRows(c, job).filter(r => !updated.has(r.weeks)), ...additions]);
}
function currentVerified(row, c, job) {
  return ready(row) && row.native_parity_verified === '1' && row.settings_verified === '1'
    && row.engine_hash === c.manifest.sourceHash && row.template_hash === c.manifest.templateHash
    && row.generator_hash === c.manifest.generatorHash && Number(row.as_of) === c.asOf
    && /^[a-f0-9]{64}$/.test(row.trade_trace_hash ?? '')
    && checkRow({ ...row, metrics_saved: '1' }, job).length === 0;
}
function knownUnavailable(row, c) {
  return row?.unavailable_parity_verified === '1' && Number(row.as_of) === c.asOf
    && row.engine_hash === c.manifest.sourceHash && row.metrics_saved === '0';
}

function seed(c) {
  let seeded = 0;
  for (const job of c.manifest.jobs) {
    const a = rowsAt(join(c.out, 'campaign-proof/results', job.id + '.csv'));
    const b = rowsAt(join(c.out, 'dashboard-proof/results', job.id + '.csv'));
    const existing = currentRows(c, job), additions = [];
    for (const row of a) {
      if (existing.some(r => r.weeks === row.weeks && currentVerified(r, c, job))) continue;
      const direct = b.find(r => r.weeks === row.weeks);
      const paths = ['campaign', 'dashboard'].map(mode => join(c.out, mode + '-proof/trades', `Trace_${job.id}_${row.weeks}_${mode}.csv`));
      if (!direct || paths.some(p => !existsSync(p)) || Number(row.as_of) !== c.asOf) continue;
      const traces = paths.map(p => csvRows(readFileSync(p, 'utf8')));
      if (verifyWindowPair(row, direct, ...traces, job, c.manifest).length) continue;
      additions.push({ ...row, metrics_saved: '0', native_parity_verified: '1',
        trade_trace_hash: sha(readFileSync(paths[0])), verification_mode: 'CURRENT_CACHED_NATIVE_PAIR' });
      seeded++;
    }
    if (additions.length) commit(c, job, additions);
  }
  atomic(join(c.out, 'campaign-epoch.json'), JSON.stringify({ ...c.epoch, sourceHash: c.manifest.sourceHash }, null, 2));
  return { seededWindows: seeded };
}
function plan(c) {
  const entries = c.manifest.jobs.map(job => {
    const current = currentRows(c, job), old = rowsAt(join(c.oldOut, 'results', job.id + '.csv'));
    const settled = current.filter(r => currentVerified(r, c, job) || knownUnavailable(r, c));
    const unresolved = job.windows.filter(w => !settled.some(r => Number(r.weeks) === w));
    const equivalence = unresolved.filter(w => old.some(r => Number(r.weeks) === w
      && Number(r.as_of) === c.asOf && priorVerified(r, job, c.oldManifest)));
    return { id: job.id, family: job.family, name: job.name,
      publishWeeks: current.filter(r => currentVerified(r, c, job) && r.metrics_saved !== '1').map(r => Number(r.weeks)),
      equivalenceWeeks: equivalence, pairedWeeks: unresolved.filter(w => !equivalence.includes(w)) };
  });
  const result = { createdUtc: new Date().toISOString(), sourceHash: c.manifest.sourceHash,
    asOf: c.epoch.asOf, strategies: entries.length,
    windowsAlreadyVerified: entries.reduce((n, e) => n + c.manifest.windows.length - e.equivalenceWeeks.length - e.pairedWeeks.length, 0),
    singleReplayWindows: entries.reduce((n, e) => n + e.equivalenceWeeks.length, 0),
    pairedWindows: entries.reduce((n, e) => n + e.pairedWeeks.length, 0), entries };
  atomic(join(c.out, 'targeted-plan.json'), JSON.stringify(result, null, 2));
  return { ...result, entries: undefined };
}
function review(c, id) {
  const job = c.manifest.jobs.find(j => j.id === id); if (!job) throw Error('UNKNOWN_STRATEGY');
  const old = rowsAt(join(c.oldOut, 'results', id + '.csv'));
  const fresh = rowsAt(join(c.out, 'equivalence-dashboard/results', id + '.csv'));
  const selection = json(join(c.out, 'targeted-plan.json')).entries.find(e => e.id === id);
  const additions = [], fallback = [];
  for (const weeks of selection.equivalenceWeeks) {
    const row = fresh.find(r => Number(r.weeks) === weeks), prior = old.find(r => Number(r.weeks) === weeks);
    const path = join(c.root, '.tmp/orb_jp225_full_worker/MQL5/Files', `Trace_${id}_${weeks}_dashboard.csv`);
    const bytes = existsSync(path) ? readFileSync(path) : undefined;
    const issues = equivalentAudit(prior, row, bytes, job, c.oldManifest, c.manifest);
    if (issues.length) fallback.push({ weeks, issues });
    else additions.push({ ...row, metrics_saved: '0', native_parity_verified: '1',
      trade_trace_hash: sha(bytes), verification_mode: 'CROSS_REVISION_EXACT_TRACE',
      reused_from_engine_hash: prior.engine_hash, previous_settings_key: prior.settings_key });
    // Delete only the bounded trace produced by this requested replay, not histories.
    const traceRoot = resolve(c.root, '.tmp/orb_jp225_full_worker/MQL5/Files') + '\\';
    if (existsSync(path) && resolve(path).startsWith(traceRoot)) unlinkSync(path);
  }
  if (additions.length) commit(c, job, additions);
  const result = { id, verifiedWeeks: additions.map(r => Number(r.weeks)), fallback };
  atomic(join(c.out, 'equivalence-review.json'), JSON.stringify(result, null, 2));
  return result;
}
function summarize(c) {
  const report = reportCampaign(c.root, true, 'reports/verification_build/audit_failures');
  const all = c.manifest.jobs.flatMap(j => currentRows(c, j));
  const unconfirmed = all.filter(r => !ready(r) && !knownUnavailable(r, c));
  const result = { ...report, targeted: true,
    exactTraceReuseWindows: all.filter(r => r.verification_mode === 'CROSS_REVISION_EXACT_TRACE').length,
    cachedPairWindows: all.filter(r => r.verification_mode === 'CURRENT_CACHED_NATIVE_PAIR').length,
    confirmedUnavailableWindows: all.filter(r => knownUnavailable(r, c)).length,
    unconfirmedWindows: unconfirmed.map(r => ({ id: r.catalog_id, weeks: +r.weeks, status: r.status, detail: r.detail })),
    completed: report.notAttemptedWindows === 0 && report.integrityErrors.length === 0 && unconfirmed.length === 0 };
  atomic(join(c.out, 'targeted-verification.json'), JSON.stringify(result, null, 2));
  const { coverage, ...brief } = result;
  return brief;
}

if (import.meta.url === pathToFileURL(resolve(process.argv[1] ?? '')).href) {
  const c = context(resolve(import.meta.dirname, '..')), action = process.argv[2];
  const result = action === 'seed' ? seed(c) : action === 'plan' ? plan(c)
    : action === 'review' ? review(c, process.argv[3]) : action === 'summary' ? summarize(c) : null;
  if (!result) throw Error('Expected seed, plan, review or summary');
  console.log(JSON.stringify(result, null, 2));
}
