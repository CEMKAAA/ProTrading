// Isolated loopback + DEMO worker. Never activates trading or changes a cloud account.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,existsSync,unlinkSync,mkdirSync} from 'node:fs';
import {spawn} from 'node:child_process';
import {resolve,join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {unpack} from '../control-service/mt5-agent.mjs';

const root=resolve(import.meta.dirname,'../..'),web=join(root,'web-mvp'),stage=join(root,'reports/verification_build/universal_audit');
const state=join(web,'control-service/.state/agent-qa');mkdirSync(stage,{recursive:true});
const access=JSON.parse(readFileSync(join(web,'control-service/.state/dev-access.json'),'utf8')).accessToken;
async function api(path,body){const r=await fetch('http://127.0.0.1:4321'+path,{method:body===undefined?'GET':'POST',headers:{Authorization:'Bearer '+access,'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(10000)});const v=await r.json();if(!r.ok)throw Error(v.error);return v;}
function child(file,args,cwd=web){return spawn(file,args,{cwd,windowsHide:true,stdio:['ignore','pipe','pipe']});}
async function complete(p){let out='',err='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>err+=b);const code=await new Promise(r=>p.once('exit',r));if(code!==0)throw Error(err||out);return out;}
async function worker(mode,id){return complete(child('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',join(root,'scripts/validate_universal_connection.ps1'),'-Mode',mode,...id?['-InstallationId',id]:[]],root));}
const configFile=join(state,'installation.json');
if(existsSync(configFile)){const old=JSON.parse(readFileSync(configFile,'utf8')),s=await api('/v1/session');if(s.installations.find(i=>i.id===old.installationId)?.state==='revoked')unlinkSync(configFile);}
if(!existsSync(configFile)){const pair=JSON.parse(await complete(child(process.execPath,['--experimental-strip-types','control-service/mt5-agent.mjs','pair','--state',state,'--label','JP225 audit preparation QA'])));await api('/v1/pairings/approve',{code:pair.pairingCode,fingerprint:pair.fingerprint});}
const installation=JSON.parse(readFileSync(configFile,'utf8')),key=readFileSync(join(installation.folder,'local.key'),'utf8');
const blockedHistory=process.argv.includes('--blocked-history');
const common=join(root,'.tmp/orb_jp225_full_worker/config/common.ini');
const originalCommon=blockedHistory?readFileSync(common):null;
const commonEncoding=originalCommon?.readUInt16LE(0)===0xfeff?'utf16le':'utf8';
if(blockedHistory)writeFileSync(common,Buffer.from(originalCommon.toString(commonEncoding).replace(/MaxBars=\d+/, 'MaxBars=5000'),commonEncoding));
await api('/v1/installations/'+installation.installationId+'/activate',{});
console.log(await worker('attach',installation.installationId));
const agent=child(process.execPath,['--experimental-strip-types','control-service/mt5-agent.mjs','watch','--state',state]);
agent.stderr.on('data',b=>process.stderr.write(b));
const report={checkedAt:new Date().toISOString(),liveTradingRequested:false,scenario:blockedHistory?'max-bars-guard':'saved-jp225-strategy',phases:[]};let job;
try{
 let terminal;
 for(let i=0;i<120;i++){const s=await api('/v1/session');terminal=s.terminalStatuses.find(t=>t.installationId===installation.installationId&&t.reportedAt>Date.now()-15000);if(terminal)break;await new Promise(r=>setTimeout(r,1000));}
 assert.equal(terminal?.brokerServer,'Exness-MT5Trial15');assert.equal(terminal?.accountLogin,'260460316');assert.equal(terminal?.symbol,'JP225m');assert.equal(terminal?.trading,false);
 const fixture=JSON.parse(readFileSync(join(stage,'request.json'),'utf8'));const configuration=fixture.configuration;
 if(blockedHistory)configuration.name='QA terminal bar limit';
 const toUtc=new Date(Math.floor(Date.now()/1000)*1000).toISOString();
 job=await api('/v1/jobs',{...fixture,installationId:installation.installationId,idempotencyKey:randomUUID(),brokerServer:terminal.brokerServer,symbol:terminal.symbol,toUtc,fromUtc:new Date(Date.parse(toUtc)-14*86400000).toISOString(),auditWeeks:2,configuration});
 let last='',finished;const end=Date.now()+420000;
 while(Date.now()<end){const native=unpack(readFileSync(join(installation.folder,'status.txt'),'utf8'),key).fields;assert.equal(native.trading,'false');
  const j=await api('/v1/jobs/'+job.id);const marker=JSON.stringify({state:j.state,progress:j.progress});if(marker!==last){last=marker;report.phases.push({at:new Date().toISOString(),...JSON.parse(marker)});console.log(marker);}
  if(j.state==='completed'||j.state==='failed'||j.state==='cancelled'){finished=j;break;}await new Promise(r=>setTimeout(r,1000));
 }
 assert.ok(finished,'Native audit did not terminate');report.job=finished;
 if(blockedHistory){
  assert.equal(finished.state,'failed');assert.ok(['AUDIT_MAX_BARS_LIMIT','AUDIT_HISTORY_BLOCKED'].includes(finished.failureCode));assert.equal(finished.result,null);
  assert.match(finished.progress.detail,/max=5000/);
  report.status='PASS';console.log('MAX_BARS_GUARD_PASS',finished.progress.detail);
 }else{
  report.status=finished.state==='completed'?'PASS':'NATIVE_FAILURE';
  if(finished.state!=='completed')throw Error(finished.failureCode+': '+finished.progress?.detail);
  console.log('JP225_COMPLETE',JSON.stringify(finished.result.summary));
 }
}catch(e){report.error=e.message;report.status??='FAIL';throw e;}
finally{if(job)await api('/v1/jobs/'+job.id+'/cancel',{}).catch(()=>{});agent.kill();writeFileSync(join(stage,blockedHistory?'max-bars-probe.json':'jp225-probe.json'),JSON.stringify(report,null,2)+'\n');await worker('stop');if(originalCommon){await new Promise(r=>setTimeout(r,1500));writeFileSync(common,originalCommon);}}
