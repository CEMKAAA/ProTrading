import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { csvRows } from './report_strategy_window_campaign.mjs';

const integerFields=['total','wins','losses','open','flat','data','as_of','independent'];
const numericFields=['net_r','min_cum_r'];
const identityFields=['catalog_id','native_id','name','symbol','chart_tf','weeks','settings_key','calendar','engine_hash','template_hash','generator_hash'];
export function compareAudits(campaign,dashboard) {
 const issues=[];
 if(!campaign||!dashboard)return ['MISSING_PAIR'];
 for(const [label,row] of [['campaign',campaign],['dashboard',dashboard]]) {
  if(!['AUDITED','AUDITED_OPEN'].includes(row.status))issues.push(`${label}:INCOMPLETE`);
  if(row.settings_verified!=='1'||row.order_attempts!=='0'||row.data!=='0')issues.push(`${label}:UNVERIFIED`);
  if(!/^[a-f0-9]{64}$/.test(row.settings_key??''))issues.push(`${label}:KEY`);
  for(const key of [...integerFields,...numericFields])
   if(row[key]===''||!Number.isFinite(Number(row[key])))issues.push(`${label}:${key}:INVALID`);
 }
 for(const key of identityFields)if(campaign[key]!==dashboard[key])issues.push(key);
 for(const key of integerFields)if(Number(campaign[key])!==Number(dashboard[key]))issues.push(key);
 for(const key of numericFields)if(Math.abs(Number(campaign[key])-Number(dashboard[key]))>1e-8)issues.push(key);
 if(campaign.load_mode!=='campaign'||dashboard.load_mode!=='dashboard')issues.push('LOAD_PATH');
 return issues;
}
export function compareTrades(campaign,dashboard) {
 if(!campaign||!dashboard)return ['MISSING_TRADE_TRACE'];
 if(campaign.length!==dashboard.length)return ['TRADE_TRACE_COUNT'];
 for(let i=0;i<campaign.length;i++)
  for(const field of Object.keys(campaign[i]))
   if(campaign[i][field]!==dashboard[i][field])return [`TRADE_TRACE:${i}:${field}`];
 return [];
}
export function verifyParity(out) {
 const manifest=JSON.parse(readFileSync(join(out,'manifest.private.json'),'utf8'));
 const read=set=>readdirSync(join(out,set,'results')).filter(n=>n.endsWith('.csv'))
  .flatMap(n=>csvRows(readFileSync(join(out,set,'results',n),'utf8')));
 const a=read('campaign-proof'),b=read('dashboard-proof');
 const key=row=>`${row.catalog_id}:${row.weeks}`;
 const byDashboard=new Map(b.map(row=>[key(row),row]));
 const cases=a.map(row=>{
  const direct=byDashboard.get(key(row)),issues=compareAudits(row,direct);
  for(const [field,expected] of [['engine_hash',manifest.sourceHash],['template_hash',manifest.templateHash],['generator_hash',manifest.generatorHash]])
   if(row[field]!==expected||direct?.[field]!==expected)issues.push('STALE_PROOF:'+field);
  const trace=set=>{
   const path=join(out,set+'-proof','trades',`Trace_${row.catalog_id}_${row.weeks}_${set}.csv`);
   return existsSync(path)?csvRows(readFileSync(path,'utf8')):undefined;
  };
  const campaignTrades=trace('campaign'),dashboardTrades=trace('dashboard');
  issues.push(...compareTrades(campaignTrades,dashboardTrades));
  return {id:row.catalog_id,weeks:Number(row.weeks),family:manifest.jobs.find(j=>j.id===row.catalog_id)?.family,
   total:Number(row.total),traceRows:campaignTrades?.length,netR:Number(row.net_r),minCumR:Number(row.min_cum_r),asOf:Number(row.as_of),issues};
 });
 const families=[...new Set(cases.filter(c=>!c.issues.length&&c.total>0).map(c=>c.family))];
 const errors=cases.filter(c=>c.issues.length);
 const missingFamilies=Object.keys(manifest.families).filter(f=>!families.includes(f));
 return {verifiedAt:new Date().toISOString(),sourceHash:manifest.sourceHash,templateHash:manifest.templateHash,generatorHash:manifest.generatorHash,
  passed:cases.length>0&&errors.length===0&&missingFamilies.length===0&&a.length===b.length,
  strategies:new Set(cases.map(c=>c.id)).size,windows:cases.length,families,missingFamilies,cases};
}
if(import.meta.url===pathToFileURL(resolve(process.argv[1]??'')).href) {
 const out=resolve(process.argv[2]??'reports/strategy_audit_20261009_parity');const proof=verifyParity(out);
 writeFileSync(join(out,'parity_verified.json'),JSON.stringify(proof,null,2));
 console.log(JSON.stringify(proof,null,2));if(!proof.passed)process.exitCode=1;
}
