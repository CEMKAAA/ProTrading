import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve, join, dirname, relative } from 'node:path';

const root=resolve(import.meta.dirname,'..'),source=join(root,'IndicatorCodeExamples');
const option=name=>{const at=process.argv.indexOf(name);return at<0?undefined:process.argv[at+1];};
const out=resolve(root,option('--out')??'reports/strategy_audit_20261008'),stage=join(out,'source');
const catalog=JSON.parse(readFileSync(join(root,'reports/admin_catalog/catalog.private.json'),'utf8'));
const profiles=JSON.parse(readFileSync(join(root,'reports/admin_catalog/audit-input-profiles.private.json'),'utf8'));
const families={orb:['orb','OrbUltimateEA_StrategyLibrary.mq5','CAMPAIGN_ORB'],macross:['macrossover_orb','MaCrossOverOrbEA.mq5','CAMPAIGN_MA'],sol:['SolAdvanced','LiqNarrativeSol_Advanced.mq5','CAMPAIGN_SOL'],entrylab:['entry_engine_lab','EntryEngineLabEA.mq5','CAMPAIGN_LAB']};
const sha=s=>createHash('sha256').update(s).digest('hex');
mkdirSync(out,{recursive:true});
const seen=new Set(),sources=[];
function stageFile(path){
 path=resolve(path);if(seen.has(path))return;seen.add(path);
 if(!path.startsWith(source+'\\'))throw Error('DEPENDENCY_ESCAPED_SOURCE:'+path);
 const name=relative(source,path),dest=join(stage,name);mkdirSync(dirname(dest),{recursive:true});
 copyFileSync(path,dest);const text=readFileSync(path,'utf8');sources.push({file:name,sha256:sha(readFileSync(path))});
 for(const m of text.matchAll(/^\s*#include\s+"([^"]+)"/gm))stageFile(join(dirname(path),m[1]));
}
function bodyRange(text,name){
 const at=text.indexOf('int '+name+'(');if(at<0)throw Error('INIT_NOT_FOUND');const begin=text.indexOf('{',at);
 let depth=1,end=begin+1;for(;depth&&end<text.length;end++){if(text[end]==='{')depth++;else if(text[end]==='}')depth--;}
 if(depth)throw Error('INIT_UNBALANCED');return [begin,end];
}
function stripInitLiveSideEffects(text,family){
 const [begin,end]=bodyRange(text,'OnInit');let body=text.slice(begin,end);
 if(family==='sol'){
  // Preserve all input/runtime initialization; skip chart/bridge startup blocks only.
  let at;while((at=body.indexOf('if(!IsTesterMode())'))>=0){
   const tail=at+'if(!IsTesterMode())'.length, next=body.slice(tail).search(/\S/)+tail;
   let i;
   if(body[next]!=='{'){i=body.indexOf(';',next)+1;if(i<=0)throw Error('INIT_STATEMENT_UNBALANCED');}
   else {let depth=1;i=next+1;for(;depth&&i<body.length;i++){if(body[i]==='{')depth++;else if(body[i]==='}')depth--;}if(depth)throw Error('INIT_BLOCK_UNBALANCED');}
   body=body.slice(0,at)+'/* Research: no live startup, bridge retry, or initial default audit. */'+body.slice(i);
  }
 }else{
  for(const call of ['TradeDayCalendarPublisherTick','RestoreOrbBridgePlan','RestoreNasManagedLifecycle','RestoreNasPending','EnsureNasExitLifecycle','RestoreNewDayReverseRetry'])
   body=body.replace(new RegExp('\\b'+call+'\\([^;]*\\);','g'),'/* Research startup side effect skipped. */');
  // Removing the call in an if/else must leave a statement, not just a comment.
  body=body.replaceAll('/* Research startup side effect skipped. */','CampaignNoop();');
 }
 return text.slice(0,begin)+body+text.slice(end);
}
function researchPersistence(text,name,validation){
 const at=text.indexOf('bool '+name+'(');if(at<0)throw Error('PERSISTENCE_FUNCTION_NOT_FOUND:'+name);
 const begin=text.indexOf('{',at);let depth=1,end=begin+1;
 for(;depth&&end<text.length;end++){if(text[end]==='{')depth++;else if(text[end]==='}')depth--;}
 if(depth)throw Error('PERSISTENCE_BODY_UNBALANCED');
 return text.slice(0,begin)+'{ /* Research: validate state without changing shared live settings. */ return '+validation+'; }'+text.slice(end);
}
const template=readFileSync(join(root,'tests/mql5/StrategyWindowCampaign.mq5.in'),'utf8');
const compiles=[];
for(const [family,[folder,main,define]] of Object.entries(families)){
 stageFile(join(source,folder,main));
 const staged=join(stage,folder,main),original=readFileSync(staged,'utf8');
 writeFileSync(staged,stripInitLiveSideEffects(original,family));
 if(family==='entrylab'){
  const path=join(stage,folder,'LabEntryBuilder.mqh');
  writeFileSync(path,researchPersistence(readFileSync(path,'utf8'),'LabPersistActive','LabValidEngine(g_labEngine)'));
 }
 if(family==='sol'){
  const path=join(stage,folder,'LiqSolAdvancedNas.mqh');
  writeFileSync(path,researchPersistence(readFileSync(path,'utf8'),'LnNasSaveRuntime','LnNasValid(g_lnNas)'));
 }
 const script='StrategyWindows_'+family,path=join(stage,folder,script+'.mq5');
 writeFileSync(path,template.replace('__FAMILY_DEFINE__','#define '+define).replace('__MAIN__',main));
 compiles.push({family,script,source:path});
}
let jobs=catalog.map(r=>{
 const snap=r.native_snapshot,origin=snap.origin;
 const signature=snap.lines?(r.family==='sol'?snap.lines[4]:snap.inputSignature):'';
 const base=signature?profiles[r.family][signature]:Object.values(profiles[r.family])[0];
 if(!base||!r.configuration)throw Error('UNVERIFIED_BASE_INPUTS:'+r.id);
 if(!/^\w+$/.test(r.symbol)||r.symbol==='ANY')throw Error('UNRESOLVED_SYMBOL:'+r.id);
 const tf=snap.chartTimeframe??(r.family==='sol'?5:r.configuration.inputs.InpSignalTimeframe??5);
 const period=tf===0?'M5':tf<60?'M'+tf:tf===16385?'H1':tf===16388?'H4':tf===16408?'D1':'M'+tf;
 return {id:r.id,family:r.family,name:r.name,symbol:r.symbol,origin,chartTf:tf,period,
  nativeSourceHash:r.source_hash,profileSignature:signature,inputs:base,
  windows:[260,208,156,104,52,20,10,5,2]};
});
// Preserve the frozen identities/input profiles and explicitly approved symbol remaps.
if(option('--from'))jobs=JSON.parse(readFileSync(resolve(root,option('--from')),'utf8')).jobs;
// Smaller pilot runs remain resumable and cannot overwrite a completed full campaign.
const fingerprints=sources.sort((a,b)=>a.file.localeCompare(b.file));
const manifest={version:2,preparedAt:new Date().toISOString(),sourceHash:sha(JSON.stringify(fingerprints)),templateHash:sha(template),
 generatorHash:sha(readFileSync(import.meta.filename)),
 researchOnlyAdaptations:['startup live side effects skipped','LabPersistActive validates without common state write','LnNasSaveRuntime validates without common state write'],
 verification:{fullCalendar:true,runtimeMatches:true,pilotParityRequired:true},
 safety:{nativeTrading:false,publishing:false,orderSendGuard:true,originalSourceUnchanged:true},
 windows:[260,208,156,104,52,20,10,5,2],strategies:jobs.length,
 families:Object.fromEntries(Object.keys(families).map(f=>[f,jobs.filter(j=>j.family===f).length])),compiles,sources:fingerprints,jobs};
for(const entry of compiles) {
 const text=readFileSync(entry.source,'utf8').replace('__SOURCE_HASH__',manifest.sourceHash)
  .replace('__TEMPLATE_HASH__',manifest.templateHash).replace('__GENERATOR_HASH__',manifest.generatorHash);
 writeFileSync(entry.source,text);
}
const path=join(out,'manifest.private.json');
if(existsSync(path)){
 const old=JSON.parse(readFileSync(path,'utf8'));
 if(old.sourceHash!==manifest.sourceHash&&existsSync(join(out,'progress.json')))throw Error('ENGINE_CHANGED_DURING_CAMPAIGN: use a new report directory');
}
writeFileSync(path,JSON.stringify(manifest,null,2));
console.log(JSON.stringify({output:out,strategies:jobs.length,families:manifest.families,sourceFiles:sources.length,sourceHash:manifest.sourceHash},null,2));
