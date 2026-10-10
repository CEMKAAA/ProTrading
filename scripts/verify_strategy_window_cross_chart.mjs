import { readFileSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { csvRows } from './report_strategy_window_campaign.mjs';
import { compareAudits, compareTrades } from './verify_strategy_campaign_parity.mjs';
const out = resolve(process.argv[2]), id = process.argv[3];
const manifest = JSON.parse(readFileSync(join(out, 'manifest.private.json'), 'utf8'));
const read = set => csvRows(readFileSync(join(out, set, 'results', id + '.csv'), 'utf8'));
const a = read('campaign-proof'), b = read('cross-chart-proof');
const cases = b.map(row => {
  const original = a.find(r => r.weeks === row.weeks);
  const issues = compareAudits(original, { ...row, chart_tf: original?.chart_tf });
  const trace = (set, mode) => csvRows(readFileSync(join(out, set, 'trades', `Trace_${id}_${row.weeks}_${mode}.csv`), 'utf8'));
  issues.push(...compareTrades(trace('campaign-proof', 'campaign'), trace('cross-chart-proof', 'dashboard')));
  if (row.chart_tf === original?.chart_tf) issues.push('NO_CHART_CHANGE');
  return { weeks: +row.weeks, total: +row.total, netR: +row.net_r, chartTf: row.chart_tf, savedTf: original?.chart_tf, issues };
});
const report = { sourceHash: manifest.sourceHash, passed: cases.length === 3 && cases.every(c => !c.issues.length), cases };
writeFileSync(join(out, 'cross_chart_verified.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2)); if (!report.passed) process.exitCode = 1;
