import {readFileSync,writeFileSync,readdirSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {csvRows} from './report_strategy_window_campaign.mjs';
import {compareAudits,compareTrades} from './verify_strategy_campaign_parity.mjs';
const out=resolve(process.argv[2]);
const manifest=JSON.parse(readFileSync(join(out,'manifest.private.json'),'utf8'));
const rows=set=>readdirSync(join(out,set,'results')).filter(n=>n.endsWith('.csv'))
  .flatMap(n=>csvRows(readFileSync(join(out,set,'results',n),'utf8')));
const a=rows('campaign-proof'),b=rows('dashboard-proof');
const cases=a.map(row=>{
  const other=b.find(r=>r.catalog_id===row.catalog_id&&r.weeks===row.weeks);
  const trace=mode=>csvRows(readFileSync(join(out,mode+'-proof','trades',`Trace_${row.catalog_id}_${row.weeks}_${mode}.csv`),'utf8'));
  const issues=[...compareAudits(row,other),...compareTrades(trace('campaign'),trace('dashboard'))];
  if(row.engine_hash!==manifest.sourceHash||other?.engine_hash!==manifest.sourceHash)issues.push('STALE_ENGINE');
  return {id:row.catalog_id,weeks:+row.weeks,total:+row.total,wins:+row.wins,losses:+row.losses,open:+row.open,
    data:+row.data,netR:+row.net_r,minCumR:+row.min_cum_r,issues};
});
const report={sourceHash:manifest.sourceHash,verifiedAt:new Date().toISOString(),
  passed:[29,33].includes(cases.length)&&cases.every(c=>c.issues.length===0),windows:cases.length,cases};
writeFileSync(join(out,'failure-regression.json'),JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
if(!report.passed)process.exitCode=1;
