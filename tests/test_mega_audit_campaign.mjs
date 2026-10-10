import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { WINDOWS, discoverJobs, summarize, campaignStatus } from '../scripts/mega_audit_campaign.mjs';
import { manualCampaignRequest, watchRefresh } from '../scripts/watch_strategy_window_refresh.mjs';

const sha = s => createHash('sha256').update(s).digest('hex');
const profiles = Object.fromEntries(['orb','macross','sol','entrylab'].map(f => [f, { saved: { InpSignalTimeframe: 5, InpRiskPerTradePct: 1 } }]));
function record(family, id, symbol = 'USDJPYm') {
  return { id: family + '_' + id, family, name: id, symbol, source_hash: sha(id), active: true,
    configuration: { inputs: { InpSignalTimeframe: 5 } },
    native_snapshot: { origin: family + '/' + id + (family === 'sol' ? '.lns' : '.preset'), chartTimeframe: 5,
      lines: family === 'sol' ? ['version','family',symbol,id,'saved'] : ['version'], inputSignature: 'saved' } };
}
const records = ['orb','macross','entrylab','sol'].map(f => record(f, 'first'));
const manifest = { jobs: discoverJobs(records, profiles), sourceHash: 'engine', templateHash: 'template', generatorHash: 'generator' };
const stamp = 1791575217;
function row(job, weeks, extra = {}) {
  return { catalog_id: job.id, native_id: job.origin, name: job.name, symbol: job.symbol, chart_tf: '5', weeks: String(weeks),
    total: '3', wins: '2', losses: '1', open: '0', flat: '0', data: '0', order_attempts: '0',
    net_r: '1', min_cum_r: '-1', as_of: String(stamp), elapsed_ms: '100', status: 'AUDITED', metrics_saved: '1',
    settings_verified: '1', native_parity_verified: '1', unavailable_parity_verified: '0', settings_key: sha('settings'),
    trade_trace_hash: sha('trace'), engine_hash: 'engine', template_hash: 'template', generator_hash: 'generator', ...extra };
}
const fullRows = () => new Map(manifest.jobs.map(j => [j.id, WINDOWS.map(w => row(j, w))]));

test('every capture includes newly added strategies in all four libraries without a fixed count', () => {
  const additions = ['orb','macross','entrylab','sol'].flatMap(f => Array.from({length:50}, (_,i) => record(f, 'new_' + i)));
  const jobs = discoverJobs([...records, ...additions], profiles, manifest.jobs);
  assert.equal(jobs.length, 204);
  assert.equal(jobs.reduce((n,j) => n + j.windows.length, 0), 1836);
  for (const family of ['orb','macross','entrylab','sol']) assert.equal(jobs.filter(j => j.family === family).length, 51);
});
test('a same-name update is recaptured, and removed or inactive records are not resurrected', () => {
  const next = [{ ...records[0], source_hash: sha('updated') }, {...records[1], active:false}, records[2]];
  const jobs = discoverJobs(next, profiles, manifest.jobs);
  assert.equal(jobs.length, 2); assert.equal(jobs[0].nativeSourceHash, sha('updated'));
  assert.deepEqual(jobs[0].inputs, profiles.orb.saved); assert.equal(jobs.some(j => j.family === 'sol'), false);
});
test('unverified, unknown-base, duplicate and unsafe records cannot be silently skipped or defaulted', () => {
  assert.throws(() => discoverJobs([{...records[0], configuration:null}], profiles), /UNVERIFIED/);
  assert.throws(() => discoverJobs([{...records[0], native_snapshot:{...records[0].native_snapshot,inputSignature:'unknown'}}], profiles), /UNVERIFIED/);
  assert.throws(() => discoverJobs([records[0], records[0]], profiles), /DUPLICATE/);
  assert.throws(() => discoverJobs([{...records[0], native_snapshot:{...records[0].native_snapshot,origin:'../secret'}}], profiles), /UNSAFE/);
});
test('approved broker symbol substitutions carry over to newly discovered records', () => {
  const old = record('sol','old','JP225s'), added = record('sol','new','JP225s');
  const jobs = discoverJobs([old,added], profiles, [{...manifest.jobs[3],id:old.id,symbol:'JP225m'}]);
  assert.deepEqual(jobs.map(j => j.symbol), ['JP225m','JP225m']);
});
test('progress and success use the actual per-job window denominators', () => {
  const s = summarize(manifest, fullRows(), stamp);
  assert.equal(s.strategies, 4); assert.equal(s.windows, 36);
  assert.equal(s.complete, 4); assert.equal(s.progressPercent, 100); assert.equal(s.verifiedPercent, 100);
});
test('confirmed DATA is processed but is never counted as a successful audited window', () => {
  const rows = fullRows(), job = manifest.jobs[0];
  rows.get(job.id)[0] = row(job, WINDOWS[0], {status:'HISTORY_UNAVAILABLE',metrics_saved:'0',native_parity_verified:'0',unavailable_parity_verified:'1'});
  const s = summarize(manifest, rows, stamp);
  assert.equal(s.progressPercent, 100); assert.equal(s.complete, 3); assert.equal(s.partial, 1);
  assert.equal(s.unavailableWindows, 1); assert.equal(s.verifiedWindows, 35); assert.equal(s.settled, 4);
});
test('old endpoints, old engines and unattempted windows do not inflate this run', () => {
  const rows = fullRows(), job = manifest.jobs[0];
  rows.get(job.id)[0].as_of = String(stamp - 1); rows.get(job.id)[1].engine_hash = 'old'; rows.get(job.id).pop();
  const s = summarize(manifest, rows, stamp);
  assert.equal(s.pendingWindows, 3); assert.equal(s.verifiedWindows, 33); assert.equal(s.complete, 3);
});
test('parity failures, missing publication, unconfirmed gaps and duplicate windows are failures', () => {
  for (const bad of [{status:'PARITY_MISMATCH'}, {metrics_saved:'0'}, {trade_trace_hash:''}, {status:'HISTORY_UNAVAILABLE',metrics_saved:'0'}]) {
    const rows = fullRows(), job = manifest.jobs[0]; rows.get(job.id)[0] = row(job, WINDOWS[0], bad);
    assert.equal(summarize(manifest, rows, stamp).failedWindows, 1);
  }
  const rows = fullRows(); rows.get(manifest.jobs[0].id).push({...rows.get(manifest.jobs[0].id)[0]});
  assert.equal(summarize(manifest, rows, stamp).failedWindows, 1);
});

test('the real EA metric feed is read back, including checksum, settings and exact R/MC', () => {
  const base = resolve('reports/verification_build'), tmp = mkdtempSync(join(base, 'mega-test-'));
  try {
    const rows = fullRows(), folders = {orb:'OrbStrategyUserLibrary',macross:'MaCrossOrbStrategyLibrary',entrylab:'EntryEngineLabStrategyLibrary'};
    for (const job of manifest.jobs) for (const r of rows.get(job.id)) {
      const folder = job.family === 'sol' ? join('sol','WindowMetrics') : join(folders[job.family],'WindowMetrics');
      mkdirSync(join(tmp,folder), {recursive:true});
      const body = ['SW_METRICS_2',r.native_id,r.settings_key,r.weeks,r.as_of,r.total,r.wins,r.losses,r.open,r.flat,r.net_r,r.min_cum_r].join('\n');
      writeFileSync(join(tmp,folder,sha(r.native_id)+'.'+r.weeks+'.swm'), body+'\nSHA256='+sha(body));
    }
    assert.equal(summarize(manifest, rows, stamp, tmp).verifiedWindows, 36);
    const job = manifest.jobs[0], r = rows.get(job.id)[0];
    writeFileSync(join(tmp,folders.orb,'WindowMetrics',sha(r.native_id)+'.'+r.weeks+'.swm'),'tampered');
    assert.equal(summarize(manifest, rows, stamp, tmp).failedWindows, 1);
  } finally {
    assert.ok(tmp.startsWith(base + '\\') || tmp.startsWith(base + '/')); rmSync(tmp, {recursive:true});
  }
});

test('an automatic refresh yields only at an idle boundary to a live, fresh manual request', async () => {
  const base = resolve('reports/verification_build'), tmp = mkdtempSync(join(base, 'mega-test-'));
  const appdata = process.env.APPDATA, requestPath = join(tmp,'reports/verification_build/mega_campaign/manual-request.json');
  try {
    process.env.APPDATA = join(tmp,'appdata'); mkdirSync(join(tmp,'reports/verification_build/mega_campaign'), {recursive:true});
    const now = Date.now(), request = {pid:process.pid, nonce:sha('manual'), at:now};
    writeFileSync(requestPath,JSON.stringify(request));
    assert.equal(manualCampaignRequest(tmp,now).nonce,request.nonce);
    assert.equal(manualCampaignRequest(tmp,now+120001),null);
    assert.equal(manualCampaignRequest(tmp,now,()=>false),null);
    await watchRefresh({root:tmp,out:join(tmp,'no-engine-needed-at-idle'),interval:1});
    assert.equal(JSON.parse(readFileSync(join(tmp,'reports/verification_build/mega_campaign/rolling-yield.json'))).nonce,request.nonce);
  } finally {
    process.env.APPDATA = appdata; assert.ok(tmp.startsWith(base + '\\') || tmp.startsWith(base + '/')); rmSync(tmp, {recursive:true});
  }
});

test('BAT and launcher support monitoring without stopping any active campaign', () => {
  const bat = readFileSync(new URL('../Run-Mega-Audit.bat',import.meta.url),'utf8');
  assert.match(bat, /%~dp0scripts\\launch_mega_audit\.ps1/);
  const launcher = readFileSync(new URL('../scripts/launch_mega_audit.ps1',import.meta.url),'utf8');
  assert.match(launcher, /Active-Campaign/); assert.match(launcher, /StatusOnly/);
  assert.doesNotMatch(launcher, /Stop-Process|taskkill|Stop-ScheduledTask/);
  const runner = readFileSync(new URL('../scripts/mega_audit_campaign.mjs',import.meta.url),'utf8');
  assert.doesNotMatch(runner, /seal_strategy_window_campaign|prepare_strategy_window_campaign\.mjs'\s*\)/);
  assert.match(runner, /prepare\(root, out, verifiedOut\)/);
});
