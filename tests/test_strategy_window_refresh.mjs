import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { parseRefresh, rollingIntervals } from '../scripts/watch_strategy_window_refresh.mjs';
const sha = s => createHash('sha256').update(s).digest('hex');
const now = 1791560000;
const message = (family = 'macross', utc = now, broker = now) => {
  const body = ['SW_REFRESH_1', family, 'JP225m', 'Exness-MT5Trial15', utc, broker].join('\n');
  return body + '\nSHA256=' + sha(body);
};
test('two-week roll removes the leading interval and appends exactly two weeks', () => {
  const delta = 14 * 86400, p = rollingIntervals(260, now, now + delta);
  assert.equal(p.expired[1] - p.expired[0], delta);
  assert.equal(p.appended[1] - p.appended[0], delta);
  assert.equal(p.newEnd - p.newStart, 260 * 7 * 86400);
  assert.deepEqual(p.retained, [p.newStart, now]);
  assert.equal(p.replayAdmission, true); assert.equal(p.replayOpenTrades, true);
});
test('after the complete window has elapsed no old campaign interval remains', () => {
  const p = rollingIntervals(260, now, now + 261 * 7 * 86400);
  assert.equal(p.retained, null);
  assert.deepEqual(p.expired, [p.oldStart, p.oldEnd]);
  assert.deepEqual(p.appended, [p.newStart, p.newEnd]);
});
test('unchanged endpoint adds or removes nothing; clock reversal is rejected', () => {
  const p = rollingIntervals(2, now, now);
  assert.equal(p.expired[0], p.expired[1]); assert.equal(p.appended[0], p.appended[1]);
  assert.throws(() => rollingIntervals(2, now, now - 1), /DOMAIN/);
});
test('broker timezone is retained separately from UTC freshness time', () => {
  assert.equal(parseRefresh(message('orb', now, now + 3 * 3600), now).offset, 3 * 3600);
});
test('tampered, expired, future and unknown requests cannot run a campaign', () => {
  assert.throws(() => parseRefresh(message().replace('JP225m', 'EURUSDm'), now), /CHECKSUM/);
  assert.throws(() => parseRefresh(message('entrylab', now - 86401), now), /EXPIRED/);
  assert.throws(() => parseRefresh(message('orb', now + 301), now), /EXPIRED/);
  assert.throws(() => parseRefresh(message('unknown'), now), /DOMAIN/);
  assert.throws(() => parseRefresh(message('sol', now, now + 20 * 3600), now), /CLOCK/);
});
test('all four EAs trigger isolated refresh and poll without applying runtime settings', () => {
  const files = [['orb','OrbUltimateEA_StrategyLibrary.mq5','orb'],['macrossover_orb','MaCrossOverOrbEA.mq5','macross'],
    ['entry_engine_lab','EntryEngineLabEA.mq5','entrylab'],['SolAdvanced','LiqNarrativeSol_Advanced.mq5','sol']];
  for (const [folder,file,family] of files) {
    const code = readFileSync(new URL(`../IndicatorCodeExamples/${folder}/${file}`, import.meta.url), 'utf8');
    assert.ok(code.includes(`SwRefreshRequest("${family}")`));
    assert.ok(code.includes(`SwRefreshPoll("${family}")`));
    const poll = code.match(/if\(!IsTesterMode\(\)&&SwRefreshPoll[^\n]+/)[0];
    assert.doesNotMatch(poll, /ApplyValues|ApplyInteractive|TryOpen|ClosePosition/);
  }
});
test('all readers reject unverified old schema and bind identities to the broker', () => {
  for (const folder of ['orb','macrossover_orb','entry_engine_lab','SolAdvanced']) {
    const code = readFileSync(new URL(`../IndicatorCodeExamples/${folder}/StrategyWindowMetrics.mqh`, import.meta.url), 'utf8');
    assert.match(code, /v\[0\]!="SW_METRICS_2"/);
    assert.match(code, /SW_WINDOW_2\|.*AccountInfoString\(ACCOUNT_SERVER\)/);
    assert.match(code, /MQL_PROGRAM_TYPE\)!=PROGRAM_EXPERT/);
  }
});
