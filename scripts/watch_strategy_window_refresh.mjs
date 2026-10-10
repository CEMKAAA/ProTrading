import { createHash } from 'node:crypto';
import { readFileSync, writeFileSync, renameSync, mkdirSync, existsSync, readdirSync } from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { pathToFileURL } from 'node:url';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { csvRows } from './report_strategy_window_campaign.mjs';

const sha = s => createHash('sha256').update(s).digest('hex');
const families = ['orb', 'macross', 'entrylab', 'sol'];
export function manualCampaignRequest(root, now = Date.now(), alive = pid => {
  try { process.kill(pid, 0); return true; } catch { return false; }
}) {
  try {
    const request = JSON.parse(readFileSync(join(root, 'reports/verification_build/mega_campaign/manual-request.json'), 'utf8'));
    if (!Number.isInteger(request.pid) || request.pid < 1 || !/^[a-f0-9]{64}$/.test(request.nonce)
        || !Number.isSafeInteger(request.at) || now - request.at > 120000 || request.at > now + 5000 || !alive(request.pid)) return null;
    return request;
  } catch { return null; }
}
export function parseRefresh(text, now = Math.floor(Date.now() / 1000)) {
  const at = text.indexOf('\nSHA256=');
  if (at < 0 || sha(text.slice(0, at)) !== text.slice(at + 8)) throw Error('REQUEST_CHECKSUM');
  const [version, family, symbol, server, utc, broker, ...extra] = text.slice(0, at).split('\n');
  if (version !== 'SW_REFRESH_1' || extra.length || !families.includes(family)
      || !/^[A-Za-z0-9_.#-]{1,64}$/.test(symbol) || !server || server.length > 128
      || !/^\d+$/.test(utc) || !/^\d+$/.test(broker)) throw Error('REQUEST_DOMAIN');
  if (Number(utc) > now + 300 || now - Number(utc) > 86400) throw Error('REQUEST_EXPIRED');
  const offset = Number(broker) - Number(utc);
  if (Math.abs(offset) > 15 * 3600) throw Error('REQUEST_CLOCK');
  return { family, symbol, server, utc: Number(utc), broker: Number(broker), offset, hash: sha(text) };
}
export function rollingIntervals(weeks, oldEnd, newEnd) {
  if (!Number.isInteger(weeks) || weeks < 1 || !Number.isSafeInteger(oldEnd)
      || !Number.isSafeInteger(newEnd) || newEnd < oldEnd) throw Error('WINDOW_DOMAIN');
  const span = weeks * 7 * 86400, oldStart = oldEnd - span, newStart = newEnd - span;
  return { oldStart, newStart, oldEnd, newEnd,
    expired: [oldStart, Math.min(oldEnd, newStart)],
    appended: [Math.max(oldEnd, newStart), newEnd],
    retained: newStart < oldEnd ? [Math.max(oldStart, newStart), oldEnd] : null,
    replayAdmission: true, replayOpenTrades: true };
}
export function verifiedSnapshot(root, out) {
  const manifest = JSON.parse(readFileSync(join(out, 'manifest.private.json'), 'utf8'));
  const proof = JSON.parse(readFileSync(join(out, 'parity_verified.json'), 'utf8'));
  if (!proof.passed || ['sourceHash', 'templateHash', 'generatorHash'].some(k => proof[k] !== manifest[k]))
    throw Error('NATIVE_PARITY_REQUIRED');
  for (const source of manifest.sources)
    if (sha(readFileSync(join(root, 'IndicatorCodeExamples', source.file))) !== source.sha256)
      throw Error('ENGINE_CHANGED_REVERIFY');
  if (sha(readFileSync(join(root, 'tests/mql5/StrategyWindowCampaign.mq5.in'))) !== manifest.templateHash
      || sha(readFileSync(join(root, 'scripts/prepare_strategy_window_campaign.mjs'))) !== manifest.generatorHash)
    throw Error('CAMPAIGN_CHANGED_REVERIFY');
  return manifest;
}
function atomic(path, text) {
  mkdirSync(dirname(path), { recursive: true });
  const temp = path + '.' + process.pid + '.pending';
  writeFileSync(temp, text); renameSync(temp, path);
}
function status(path, state, detail) {
  const body = ['SW_REFRESH_STATUS1', state, Math.floor(Date.now() / 1000), detail.replace(/[\r\n]/g, ' ').slice(0, 180)].join('\n');
  atomic(path.replace(/\.request$/, '.status'), body + '\nSHA256=' + sha(body));
}
async function runFamily(root, out, request) {
  const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', join(root, 'scripts/run_strategy_window_campaign.ps1'),
    '-Mode', 'Run', '-ReportDir', out, '-Family', request.family, '-PublishMetrics', '-HistoryMaxBars', '5000000',
    '-RequestedBroker', request.server, '-FreshnessOffsetSeconds', String(request.offset), '-SkipChangedRecords'];
  return await new Promise((done, reject) => {
    const child = spawn('powershell.exe', args, { cwd: root, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    child.stdout.pipe(process.stdout); child.stderr.pipe(process.stderr);
    child.on('error', reject); child.on('close', code => code === 0 ? done() : reject(Error('AUDIT_WORKER_EXIT_' + code)));
  });
}
export async function watchRefresh({ root, out, once = false, dryRun = false, interval = 15000 }) {
  const queue = join(process.env.APPDATA, 'MetaQuotes/Terminal/Common/Files/StrategyWindowRefresh');
  mkdirSync(queue, { recursive: true });
  const statePath = join(out, 'rolling-state.json');
  const state = existsSync(statePath) ? JSON.parse(readFileSync(statePath, 'utf8')) : { version: 1, epoch: new Date().toISOString(), families: {} };
  do {
    // Yield only between audits, never interrupt a native replay or stop a terminal.
    // Diagnostic --once/--dry-run callers do not own the rolling worker.
    const manual = !once && !dryRun ? manualCampaignRequest(root) : null;
    if (manual) {
      atomic(join(root, 'reports/verification_build/mega_campaign/rolling-yield.json'),
        JSON.stringify({ nonce: manual.nonce, pid: process.pid, at: Date.now(), reportDir: out }));
      console.log('Automatic refresh yielded to the manual mega campaign at an idle boundary.');
      return;
    }
    // File identity and native parity are checked every pass, not only at startup.
    let manifest;
    try { manifest = verifiedSnapshot(root, out); } catch (error) {
      for (const name of readdirSync(queue).filter(n => n.endsWith('.request')))
        status(join(queue, name), 'NEEDS VERIFICATION', error.message);
      if (once) throw error;
      await new Promise(r => setTimeout(r, interval)); continue;
    }
    const requests = readdirSync(queue).filter(n => n.endsWith('.request')).map(name => {
      try { return { path: join(queue, name), ...parseRefresh(readFileSync(join(queue, name), 'utf8')) }; }
      catch { return null; }
    }).filter(Boolean);
    const groups = Map.groupBy(requests, r => r.family + '|' + r.server);
    for (const [key, own] of groups) {
      if (!once && !dryRun && manualCampaignRequest(root)) break;
      const last = state.families[key], now = Date.now();
      if (last && now - last.lastAttempt < (last.partial ? 3600000 : 86400000)) {
        for (const request of own) status(request.path, last.partial ? 'PARTIAL' : 'CURRENT', last.summary);
        continue;
      }
      const request = own.reduce((a, b) => a.utc > b.utc ? a : b);
      const jobs = manifest.jobs.filter(j => j.family === request.family);
      const plans = jobs.flatMap(job => {
        const path = join(out, 'results', job.id + '.csv');
        if (!existsSync(path)) return [];
        return csvRows(readFileSync(path, 'utf8')).filter(r => +r.as_of > 0 && request.broker >= +r.as_of)
          .map(r => ({ id: job.id, weeks: +r.weeks, ...rollingIntervals(+r.weeks, +r.as_of, request.broker) }));
      });
      if (dryRun) { console.log(JSON.stringify({ key, strategies: jobs.length, plans: plans.slice(0, 2) })); continue; }
      atomic(join(out, 'rolling-plan-' + request.family + '.json'), JSON.stringify({ at: new Date().toISOString(), plans }, null, 2));
      for (const r of own) status(r.path, 'RUNNING', 'Refreshing all 9 windows; existing dated results retained');
      const heartbeat = setInterval(() => {
        for (const r of own) status(r.path, 'RUNNING', 'Refreshing all 9 windows; existing dated results retained');
      }, 30000);
      try {
        await runFamily(root, out, request);
        const progress = JSON.parse(readFileSync(join(out, 'progress.json'), 'utf8').replace(/^\uFEFF/, ''));
        const partial = progress.errorsThisRun > 0;
        const summary = new Date().toISOString().slice(0, 16) + ' UTC; ' + (partial ? 'some windows unavailable' : 'verified windows updated');
        state.families[key] = { lastAttempt: Date.now(), partial, summary };
        for (const r of own) status(r.path, partial ? 'PARTIAL' : 'CURRENT', summary);
      } catch (error) {
        state.families[key] = { lastAttempt: Date.now(), partial: true, summary: error.message };
        for (const r of own) status(r.path, 'RETRY', error.message);
      } finally { clearInterval(heartbeat); }
      atomic(statePath, JSON.stringify(state, null, 2));
    }
    if (once) break;
    await new Promise(r => setTimeout(r, interval));
  } while (true);
}
if (import.meta.url === pathToFileURL(resolve(process.argv[1] ?? '')).href) {
  const root = resolve(import.meta.dirname, '..'), at = process.argv.indexOf('--report-dir');
  const out = resolve(root, at < 0 ? 'reports/strategy_audit_20261009_rolling' : process.argv[at + 1]);
  // One local audit worker owns the research terminal. No user terminal is stopped.
  const lock = createServer(socket => socket.end());
  lock.on('error', error => { console.error('Worker already active or port unavailable:', error.message); process.exit(1); });
  lock.listen(47937, '127.0.0.1', async () => {
    try { await watchRefresh({ root, out, once: process.argv.includes('--once'), dryRun: process.argv.includes('--dry-run') }); }
    catch (error) { console.error(error.message); process.exitCode = 1; }
    finally { lock.close(); }
  });
}
