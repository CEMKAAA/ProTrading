import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createHash} from 'node:crypto';
import {csvRows,checkRow} from '../../scripts/report_strategy_window_campaign.mjs';
import {baselineIssues} from '../../scripts/seal_strategy_window_campaign.mjs';

const sha=value=>createHash('sha256').update(value).digest('hex');
export const campaignWeeks=[2,5,10,20,52,104,156,208,260];

export function campaignRecord(job,rows,manifest,catalog,asOf){
 const approvedAlias=catalog&&job.sourceSymbol===catalog.symbol&&job.symbolOverride==='explicit_user_approval_20261009';
 if(!catalog||catalog.source_hash!==job.nativeSourceHash||catalog.family!==job.family||catalog.name!==job.name||
  (catalog.symbol!==job.symbol&&!approvedAlias))
  throw Error('CATALOG_SNAPSHOT_MISMATCH:'+job.id);
 if(rows.length!==campaignWeeks.length||new Set(rows.map(r=>Number(r.weeks))).size!==campaignWeeks.length)
  throw Error('WINDOW_COUNT:'+job.id);
 const issues=rows.flatMap(r=>checkRow(r,job).concat(baselineIssues([r],manifest)));
 if(issues.length)throw Error('UNVERIFIED_WINDOW:'+job.id+':'+issues.join(','));
 if(rows.some(r=>Number(r.as_of)!==asOf||!['0','1'].includes(r.independent)||!/^[a-f0-9]{64}$/.test(r.settings_key??'')))
  throw Error('EPOCH_OR_SETTINGS:'+job.id);
 if(new Set(rows.map(r=>r.independent)).size!==1||new Set(rows.map(r=>r.settings_key)).size!==1)
  throw Error('MIXED_SETTINGS:'+job.id);
 const windows=campaignWeeks.map(weeks=>{
  const r=rows.find(r=>Number(r.weeks)===weeks);
  if(!r)throw Error('WINDOW_MISSING:'+job.id+':'+weeks);
  const available=['AUDITED','AUDITED_OPEN'].includes(r.status);
  const metrics=available?{total:Number(r.total),wins:Number(r.wins),losses:Number(r.losses),open:Number(r.open),flat:Number(r.flat),
   winRate:Number(r.wins)+Number(r.losses)>0?100*Number(r.wins)/(Number(r.wins)+Number(r.losses)):null,
   netR:Number(r.net_r),minCumR:Number(r.min_cum_r)}:null;
  return {weeks,status:r.status,available,metrics,...(!available?{detail:r.detail||r.status}:{})};
 });
 return {id:job.id,sourceHash:catalog.source_hash,campaign:{version:1,kind:'MEGA',strategySourceHash:catalog.source_hash,
  engineHash:manifest.sourceHash,asOf,symbol:job.symbol,chartTimeframe:job.chartTf,independent:rows[0].independent==='1',windows}};
}

export function importCampaign(baseline,catalog){
 const manifest=JSON.parse(readFileSync(join(baseline,'manifest.private.json'),'utf8'));
 const seal=JSON.parse(readFileSync(join(baseline,'seal.json'),'utf8'));
 const asOf=Date.parse(seal.asOf.replaceAll('.','-').replace(' ','T')+'Z')/1000;
 if(!Number.isSafeInteger(asOf)||asOf<=0||seal.sourceHash!==manifest.sourceHash||manifest.version!==2)
  throw Error('INVALID_BASELINE_SEAL');
 if(seal.files.length!==manifest.jobs.length||new Set(seal.files.map(f=>f.name)).size!==manifest.jobs.length)
  throw Error('INVALID_BASELINE_FILES');
 const catalogs=new Map(catalog.map(c=>[c.id,c]));
 return manifest.jobs.map(job=>{
  const file=seal.files.find(f=>f.name===job.id+'.csv');
  if(!file)throw Error('UNSEALED_STRATEGY:'+job.id);
  const bytes=readFileSync(join(baseline,'results',file.name));
  if(sha(bytes)!==file.sha256)throw Error('BASELINE_CHECKSUM:'+job.id);
  return campaignRecord(job,csvRows(bytes.toString('utf8')),manifest,catalogs.get(job.id),asOf);
 });
}

export function uploadSql(records){
 const payload=JSON.stringify(records).replaceAll("'","''");
 // Match the original strategy fingerprint, not its name. Never modify grants or configurations.
 return `do $campaign$\ndeclare payload jsonb := '${payload}'::jsonb; changed integer;\nbegin
 if exists(select 1 from jsonb_array_elements(payload) p left join stratum_private.strategy_catalog c on c.id=p->>'id'
  where c.id is null or c.source_hash<>p->>'sourceHash' or not c.active) then raise exception 'CAMPAIGN_CATALOG_MISMATCH'; end if;
 if exists(select 1 from jsonb_array_elements(payload) p join stratum_private.strategy_catalog c on c.id=p->>'id'
  where (c.campaign_results->>'asOf')::bigint>(p->'campaign'->>'asOf')::bigint) then raise exception 'CAMPAIGN_BASELINE_IS_NEWER'; end if;
 update stratum_private.strategy_catalog c set campaign_results=p->'campaign'
  from jsonb_array_elements(payload) p where c.id=p->>'id' and c.source_hash=p->>'sourceHash';
 get diagnostics changed=row_count;
 if changed<>jsonb_array_length(payload) then raise exception 'CAMPAIGN_IMPORT_COUNT'; end if;
end $campaign$;\nselect count(*) as strategies,sum(jsonb_array_length(campaign_results->'windows')) as windows
 from stratum_private.strategy_catalog where campaign_results is not null;\n`;
}

if(import.meta.url===pathToFileURL(resolve(process.argv[1]??'')).href){
 const root=resolve(import.meta.dirname,'../..');
 const baseline=resolve(root,process.argv[2]??'reports/verification_build/audit_failures/mega-baseline');
 const output=resolve(root,process.argv[3]??'reports/admin_campaign');
 const records=importCampaign(baseline,JSON.parse(readFileSync(join(root,'reports/admin_catalog/catalog.private.json'),'utf8')));
 mkdirSync(output,{recursive:true});
 writeFileSync(join(output,'campaign.private.json'),JSON.stringify(records,null,2));
 writeFileSync(join(output,'upload.private.sql'),uploadSql(records));
 const report={strategies:records.length,windows:records.reduce((n,r)=>n+r.campaign.windows.length,0),
  available:records.reduce((n,r)=>n+r.campaign.windows.filter(w=>w.available).length,0),
  unavailable:records.reduce((n,r)=>n+r.campaign.windows.filter(w=>!w.available).length,0),asOf:records[0]?.campaign.asOf,
  engineHash:records[0]?.campaign.engineHash};
 writeFileSync(join(output,'import-report.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));
}
