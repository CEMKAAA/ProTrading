import { createHash } from 'node:crypto';
import { existsSync, readFileSync, writeFileSync, renameSync, mkdirSync, copyFileSync, unlinkSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { csvRows, checkRow, checkMetric } from './report_strategy_window_campaign.mjs';
import { verifiedSnapshot } from './watch_strategy_window_refresh.mjs';

export const WINDOWS = [260, 208, 156, 104, 52, 20, 10, 5, 2];
const families = ['orb', 'macross', 'entrylab', 'sol'];
const unavailable = new Set(['HISTORY_UNAVAILABLE', 'REGIME_HISTORY_UNAVAILABLE', 'REGIME_DATA_PENDING',
  'WINDOW_INCOMPLETE', 'ORDERFLOW_DATA_INCOMPLETE', 'COVERAGE_SHORT', 'DATA_INCOMPLETE']);
const sha = text => createHash('sha256').update(text).digest('hex');
const json = file => JSON.parse(readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
const readJson = file => { try { return json(file); } catch { return null; } };
const atomic = (file, value) => {
  mkdirSync(dirname(file), { recursive: true });
  writeFileSync(file + '.pending', JSON.stringify(value, null, 2)); renameSync(file + '.pending', file);
};

export function discoverJobs(records, profiles, previousJobs = []) {
  const ids = new Set(), origins = new Set();
  // Only symbol substitutions already approved in a verified campaign are retained.
  const aliases = new Map();
  for (const old of previousJobs) {
    const r = records.find(r => r.id === old.id);
    if (r && r.symbol !== old.symbol) {
      if (aliases.has(r.symbol) && aliases.get(r.symbol) !== old.symbol) throw Error('AMBIGUOUS_SYMBOL_ALIAS');
      aliases.set(r.symbol, old.symbol);
    }
  }
  return records.filter(r => r.active !== false).map(r => {
    if (!families.includes(r.family) || !/^[\w-]+$/.test(r.id) || ids.has(r.id)) throw Error('INVALID_OR_DUPLICATE_STRATEGY:' + r.id);
    ids.add(r.id);
    const snap = r.native_snapshot, origin = snap?.origin;
    if (!origin || origins.has(r.family + '|' + origin)) throw Error('INVALID_OR_DUPLICATE_ORIGIN:' + r.id);
    origins.add(r.family + '|' + origin);
    if (!/^(builtin|image):/.test(origin) && (origin.includes('..') || /^[\\/]|^[A-Za-z]:/.test(origin))) throw Error('UNSAFE_STRATEGY_PATH');
    const signature = snap.lines ? (r.family === 'sol' ? snap.lines[4] : snap.inputSignature) : '';
    const base = signature ? profiles[r.family]?.[signature] : Object.values(profiles[r.family] ?? {})[0];
    if (!base || !r.configuration) throw Error('UNVERIFIED_BASE_INPUTS:' + r.id);
    const symbol = aliases.get(r.symbol) ?? r.symbol;
    if (!/^\w+$/.test(symbol) || symbol === 'ANY') throw Error('UNRESOLVED_SYMBOL:' + r.id);
    const tf = snap.chartTimeframe ?? (r.family === 'sol' ? 5 : r.configuration.inputs.InpSignalTimeframe ?? 5);
    const period = tf === 0 ? 'M5' : tf < 60 ? 'M' + tf : tf === 16385 ? 'H1' : tf === 16388 ? 'H4' : tf === 16408 ? 'D1' : 'M' + tf;
    return { id: r.id, family: r.family, name: r.name, symbol, origin, chartTf: tf, period,
      nativeSourceHash: r.source_hash, profileSignature: signature, inputs: base, windows: [...WINDOWS] };
  });
}

function rowState(row, job, manifest, stamp, common) {
  if (!row || +row.as_of !== stamp || row.engine_hash !== manifest.sourceHash
    || row.template_hash !== manifest.templateHash || row.generator_hash !== manifest.generatorHash) return 'pending';
  if (unavailable.has(row.status) && row.unavailable_parity_verified === '1'
      && row.settings_verified === '1' && row.order_attempts === '0' && checkRow(row, job).length === 0) return 'unavailable';
  if (!['AUDITED', 'AUDITED_OPEN'].includes(row.status) || row.native_parity_verified !== '1'
      || row.settings_verified !== '1' || !/^[a-f0-9]{64}$/.test(row.trade_trace_hash ?? '')
      || checkRow(row, job).length) return 'failed';
  if (common) {
    const folder = job.family === 'sol' ? join(dirname(row.native_id.replaceAll('\\', '/')), 'WindowMetrics')
      : join({ orb: 'OrbStrategyUserLibrary', macross: 'MaCrossOrbStrategyLibrary', entrylab: 'EntryEngineLabStrategyLibrary' }[job.family], 'WindowMetrics');
    const file = join(common, folder, `${sha(row.native_id)}.${row.weeks}.swm`);
    try {
      const text = readFileSync(file, 'utf8');
      if (!text.startsWith('SW_METRICS_2\n') || checkMetric(text, row).length) return 'failed';
    } catch { return 'failed'; }
  }
  return 'verified';
}

export function summarize(manifest, rowsById, stamp, common) {
  const totals = { strategies: manifest.jobs.length, windows: 0, processed: 0, complete: 0,
    partial: 0, settled: 0, verifiedWindows: 0, unavailableWindows: 0, failedWindows: 0, pendingWindows: 0 };
  const details = manifest.jobs.map(job => {
    const rows = rowsById.get(job.id) ?? [], duplicates = new Set();
    for (const w of job.windows) if (rows.filter(r => +r.weeks === w && +r.as_of === stamp).length > 1) duplicates.add(w);
    const states = job.windows.map(w => ({ weeks: w, state: duplicates.has(w) ? 'failed'
      : rowState(rows.find(r => +r.weeks === w && +r.as_of === stamp), job, manifest, stamp, common) }));
    const count = state => states.filter(s => s.state === state).length;
    totals.windows += states.length;
    totals.verifiedWindows += count('verified'); totals.unavailableWindows += count('unavailable');
    totals.failedWindows += count('failed'); totals.pendingWindows += count('pending');
    if (!count('pending')) totals.processed++;
    if (count('verified') === states.length) totals.complete++;
    else if (count('verified')) totals.partial++;
    if (!count('pending') && !count('failed')) totals.settled++;
    return { id: job.id, family: job.family, name: job.name, states };
  });
  const percent = n => totals.windows ? +(n * 100 / totals.windows).toFixed(2) : 0;
  return { ...totals, progressPercent: percent(totals.windows - totals.pendingWindows),
    verifiedPercent: percent(totals.verifiedWindows), details };
}

export function campaignStatus(out, common = join(process.env.APPDATA ?? '', 'MetaQuotes/Terminal/Common/Files')) {
  const manifest = json(join(out, 'manifest.private.json')), epoch = readJson(join(out, 'campaign-epoch.json'));
  const stamp = Date.parse(epoch?.asOf?.replaceAll('.', '-').replace(' ', 'T') + 'Z') / 1000;
  if (!Number.isSafeInteger(stamp)) throw Error('CAMPAIGN_EPOCH_MISSING');
  const rows = new Map(manifest.jobs.map(j => {
    try { return [j.id, csvRows(readFileSync(join(out, 'results', j.id + '.csv'), 'utf8'))]; }
    catch { return [j.id, []]; }
  }));
  const summary = summarize(manifest, rows, stamp, common), progress = readJson(join(out, 'progress.json'));
  const runner = readJson(join(out, 'manual-state.json')) ?? readJson(join(out, 'finish-state.json'));
  return { generatedAt: new Date().toISOString(), asOf: epoch.asOf, sourceHash: manifest.sourceHash,
    families: manifest.families, current: progress?.state === 'running' ? progress.name : '',
    phase: runner?.state === 'WAITING_FOR_NATIVE_CAMPAIGN' && progress?.state === 'running'
      ? 'AUDITING_NATIVE_PAIRS' : runner?.state ?? progress?.state ?? 'READY', ...summary };
}

async function child(program, args, cwd, quiet = false) {
  await new Promise((done, fail) => {
    const p = spawn(program, args, { cwd, windowsHide: true, stdio: quiet ? ['ignore', 'ignore', 'pipe'] : 'inherit' });
    let error = ''; if (quiet) p.stderr.on('data', d => { error += d; });
    p.on('error', fail); p.on('close', code => code === 0 ? done() : fail(Error('COMMAND_FAILED:' + program + ':' + code + ':' + error.slice(-1000))));
  });
}

export async function prepare(root, out, verifiedOut) {
  const engine = verifiedSnapshot(root, verifiedOut);
  const inventory = join(out, 'inventory');
  await child(process.execPath, [join(root, 'web-mvp/scripts/import-native-strategy-catalog.mjs'), '--output', inventory], root, true);
  const importReport = json(join(inventory, 'import-report.json'));
  if (importReport.failures.length) throw Error('STRATEGY_IMPORT_FAILED: see inventory/import-report.json');
  const jobs = discoverJobs(json(join(inventory, 'catalog.private.json')),
    json(join(inventory, 'audit-input-profiles.private.json')), engine.jobs);
  if (!jobs.length) throw Error('EMPTY_STRATEGY_INVENTORY');
  // Reuse the verified binaries/staged sources: no terminal, history or source-tree copies.
  const manifest = { ...engine, preparedAt: new Date().toISOString(), jobs, strategies: jobs.length,
    windows: [...WINDOWS], families: Object.fromEntries(families.map(f => [f, jobs.filter(j => j.family === f).length])),
    inventoryHash: sha(JSON.stringify(jobs)), verifiedBuild: verifiedOut };
  for (const c of engine.compiles) {
    const log = join(verifiedOut, c.script + '.compile.log');
    const bytes = readFileSync(log), text = bytes.toString(bytes[0] === 0xff && bytes[1] === 0xfe ? 'utf16le' : 'utf8');
    if (!/Result: 0 errors, 0 warnings/.test(text) || !existsSync(c.source.replace(/\.mq5$/, '.ex5'))) throw Error('VERIFIED_COMPILE_MISSING:' + c.family);
    copyFileSync(log, join(out, c.script + '.compile.log'));
  }
  atomic(join(out, 'parity_verified.json'), json(join(verifiedOut, 'parity_verified.json')));
  atomic(join(out, 'manifest.private.json'), manifest);
  return manifest;
}

const sleep = ms => new Promise(r => setTimeout(r, ms));
async function acquireWorker(root, state) {
  const request = join(root, 'reports/verification_build/mega_campaign/manual-request.json');
  const nonce = sha(process.pid + ':' + Date.now());
  const heartbeat = () => atomic(request, { pid: process.pid, nonce, at: Date.now() });
  heartbeat(); const timer = setInterval(heartbeat, 10000);
  let server;
  try {
    for (;;) {
      server = createServer(socket => socket.end());
      const acquired = await new Promise((done, fail) => {
        server.once('error', e => e.code === 'EADDRINUSE' ? done(false) : fail(e));
        server.listen(47937, '127.0.0.1', () => done(true));
      });
      if (acquired) break;
      state('WAITING_FOR_ROLLING_AUDIT', 'Existing automatic audit will finish naturally; no terminal is stopped.');
      await sleep(10000);
    }
    return { server, timer, request, nonce };
  } catch (error) { clearInterval(timer); throw error; }
}

async function run(root, out, verifiedOut) {
  const state = (state, detail = '') => atomic(join(out, 'manual-state.json'), { state, detail, pid: process.pid, updatedUtc: new Date().toISOString() });
  let lease;
  try {
    state('CAPTURING_CURRENT_STRATEGIES');
    const manifest = await prepare(root, out, verifiedOut);
    const oldEpoch = readJson(join(out, 'campaign-epoch.json'));
    const stamp = Math.max(Math.floor(Date.now() / 1000), (Date.parse(oldEpoch?.asOf?.replaceAll('.', '-').replace(' ', 'T') + 'Z') / 1000 || 0) + 1);
    const asOf = new Date(stamp * 1000).toISOString().slice(0, 19).replaceAll('-', '.').replace('T', ' ');
    atomic(join(out, 'campaign-epoch.json'), { asOf, sourceHash: manifest.sourceHash, inventoryHash: manifest.inventoryHash, createdUtc: new Date().toISOString() });
    // Old result files are retained; only rows at this run's endpoint count.
    state('WAITING_FOR_AUDIT_WORKER', `${manifest.jobs.length} strategies / ${manifest.jobs.length * WINDOWS.length} windows`);
    lease = await acquireWorker(root, state);
    const base = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', join(root, 'scripts/run_strategy_window_campaign.ps1'),
      '-Mode', 'Run', '-ReportDir', out, '-AsOf', asOf, '-PublishMetrics', '-HistoryMaxBars', '5000000'];
    state('AUDITING_NATIVE_PAIRS');
    await child('powershell.exe', base, root);
    // Retry only unresolved windows; confirmed broker gaps are not profitability failures.
    for (let pass = 1; pass <= 2; pass++) {
      const summary = campaignStatus(out);
      const pending = summary.details.filter(j => j.states.some(s => ['pending', 'failed'].includes(s.state)));
      if (!pending.length) break;
      state('RETRYING_UNRESOLVED_WINDOWS', `Pass ${pass}; ${pending.length} strategies`);
      for (const job of pending) {
        const weeks = job.states.filter(s => ['pending', 'failed'].includes(s.state)).map(s => s.weeks);
        // PowerShell -File does not bind multiple array values reliably.
        const q = s => "'" + s.replaceAll("'", "''") + "'";
        const command = `& ${q(join(root, 'scripts/run_strategy_window_campaign.ps1'))} -Mode Run -ReportDir ${q(out)}`
          + ` -AsOf ${q(asOf)} -PublishMetrics -HistoryMaxBars 5000000 -StrategyIds @(${q(job.id)}) -Weeks @(${weeks.join(',')})`;
        await child('powershell.exe', ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', command], root);
      }
    }
    const result = campaignStatus(out);
    atomic(join(out, 'manual-verification.json'), result);
    if (result.failedWindows || result.pendingWindows) { state('INCOMPLETE', `${result.failedWindows} failed / ${result.pendingWindows} pending windows`); process.exitCode = 1; }
    else state('VERIFIED_COMPLETE', `${result.complete}/${result.strategies} full; ${result.unavailableWindows} confirmed unavailable windows`);
    // Manual reruns update CURRENT only; never replace the original MEGA archives.
  } catch (error) { state('FAILED', error.message); throw error; }
  finally {
    if (lease) {
      clearInterval(lease.timer); await new Promise(done => lease.server.close(done));
      if (readJson(lease.request)?.nonce === lease.nonce) unlinkSync(lease.request);
      // If an automatic worker yielded, restart it rather than leaving refresh disabled.
      const yielded = readJson(join(dirname(lease.request), 'rolling-yield.json'));
      if (yielded?.nonce === lease.nonce) await child('powershell.exe', ['-NoProfile', '-Command',
        "if(Get-ScheduledTask -TaskName 'ProTradingSystem-StrategyWindowRefresh' -ErrorAction SilentlyContinue){Start-ScheduledTask -TaskName 'ProTradingSystem-StrategyWindowRefresh'}"], root);
    }
  }
}

if (import.meta.url === pathToFileURL(resolve(process.argv[1] ?? '')).href) {
  const root = resolve(import.meta.dirname, '..'), option = (key, fallback) => {
    const at = process.argv.indexOf(key); return at < 0 ? fallback : process.argv[at + 1];
  };
  const out = resolve(root, option('--report-dir', 'reports/verification_build/mega_campaign'));
  const verifiedOut = resolve(root, option('--verified-dir', 'reports/verification_build/audit_failures'));
  try {
    const action = process.argv[2];
    if (action === 'inventory') {
      await child(process.execPath, [join(root, 'web-mvp/scripts/import-native-strategy-catalog.mjs'), '--output', join(out, 'inventory')], root, true);
      if (json(join(out, 'inventory/import-report.json')).failures.length) throw Error('STRATEGY_IMPORT_FAILED: see inventory/import-report.json');
      const engine = verifiedSnapshot(root, verifiedOut);
      const jobs = discoverJobs(json(join(out, 'inventory/catalog.private.json')), json(join(out, 'inventory/audit-input-profiles.private.json')), engine.jobs);
      console.log(JSON.stringify({ strategies: jobs.length, windows: jobs.length * WINDOWS.length,
        families: Object.fromEntries(families.map(f => [f, jobs.filter(j => j.family === f).length])) }));
    } else if (action === 'prepare') {
      const m = await prepare(root, out, verifiedOut); console.log(JSON.stringify({ strategies: m.strategies, families: m.families }));
    } else if (action === 'status') { const { details, ...status } = campaignStatus(out); console.log(JSON.stringify(status)); }
    else if (action === 'run') await run(root, out, verifiedOut);
    else throw Error('Use inventory, prepare, status or run');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
