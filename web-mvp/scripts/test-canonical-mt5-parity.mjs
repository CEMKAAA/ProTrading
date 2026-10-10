import assert from 'node:assert/strict';
import { readFileSync,writeFileSync as rawWriteFileSync,existsSync,unlinkSync, renameSync } from 'node:fs';
function writeFileSync(path,data,options){rawWriteFileSync(path+'.partial',data,options);renameSync(path+'.partial',path);}
import { spawn } from 'node:child_process';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID,createHash } from 'node:crypto';
import { eaCatalog,defaultConfiguration,universalConfigurationSchema } from '../lib/universal-contract.ts';
import { summarizeResult } from '../lib/control-contract.ts';
import { parseResult,packet,unpack } from '../control-service/mt5-agent.mjs';
const root=fileURLToPath(new URL('../../',import.meta.url)),web=join(root,'web-mvp');
const stage=join(root,'tmp/universal_connection_validation'),state=join(web,'control-service/.state/agent-qa');
let installation,key;
const access=JSON.parse(readFileSync(join(web,'control-service/.state/dev-access.json'),'utf8')).accessToken;
const source=join(process.env.APPDATA,'MetaQuotes/Terminal/Common/Files/Stratum/canonical-macross.txt');
const baseline=readFileSync(source,'utf8').replace(/\r\n/g,'\n'),header=baseline.split('\nTRADES\n')[0];
const fields=Object.fromEntries(header.trimEnd().split('\n').map(l=>{const at=l.indexOf('=');return [l.slice(0,at),l.slice(at+1)];}));
assert.equal(fields.error,undefined,fields.error);assert.ok(Number(fields.rows)>0,'An empty baseline proves nothing');
const c=defaultConfiguration('macross');c.name=fields.name;
for(const group of ['inputs','runtime'])for(const s of eaCatalog.macross[group]){
  const value=fields[`${group==='inputs'?'i':'r'}.${s.key}`];assert.notEqual(value,undefined,s.key);
  c[group][s.key]=s.type==='bool'?value==='true':s.type==='string'?value:Number(value);
}
c.dayHourMasks=Array.from({length:7},(_,i)=>Number(fields['m.'+i]));
universalConfigurationSchema.parse(c);
writeFileSync(join(stage,'canonical-macross.txt'),baseline);
writeFileSync(join(stage,'canonical-configuration.json'),JSON.stringify(c,null,2));
const wait=ms=>new Promise(r=>setTimeout(r,ms));
async function api(path,body){const res=await fetch('http://127.0.0.1:4321'+path,{method:body===undefined?'GET':'POST',
 headers:{Authorization:'Bearer '+access,'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(10000)});
 const data=await res.json();if(!res.ok)throw new Error(path+': '+data.error);return data;}
function child(file,args,cwd=web){return spawn(file,args,{cwd,windowsHide:true,stdio:['ignore','pipe','pipe']});}
async function complete(p){let out='',err='';p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>err+=b);
 const code=await new Promise(r=>p.once('exit',r));if(code!==0)throw new Error(err||out);return out;}
const configFile=join(state,'installation.json');
if(existsSync(configFile)){
 const prior=JSON.parse(readFileSync(configFile,'utf8')),session=await api('/v1/session');
 if(session.installations.find(i=>i.id===prior.installationId)?.state==='revoked')unlinkSync(configFile);
}
if(!existsSync(configFile)){
 const pair=JSON.parse(await complete(child(process.execPath,['--experimental-strip-types','control-service/mt5-agent.mjs','pair','--state',state,'--label','Canonical parity QA'])));
 await api('/v1/pairings/review',{code:pair.pairingCode});await api('/v1/pairings/approve',{code:pair.pairingCode,fingerprint:pair.fingerprint});
}
installation=JSON.parse(readFileSync(configFile,'utf8'));key=readFileSync(join(installation.folder,'local.key'),'utf8');
await api('/v1/installations/'+installation.installationId+'/activate',{});
console.log(await complete(child('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',join(root,'scripts/validate_universal_connection.ps1'),'-Mode','attach','-InstallationId',installation.installationId],root)));
const agent=child(process.execPath,['--experimental-strip-types','control-service/mt5-agent.mjs','watch','--state',state]);
agent.stderr.on('data',b=>process.stderr.write(b));agent.stdout.on('data',b=>process.stdout.write(b));
const report={checkedAt:new Date().toISOString(),strategy:fields.name,strategyId:fields.strategyId,symbol:fields.symbol,
 baseline:'unmodified canonical MaCross source, saved-strategy application and normal historical audit',
 binarySha256:createHash('sha256').update(readFileSync(join(root,'IndicatorCodeExamples/universal/UniversalConnectionEA.ex5'))).digest('hex'),
 configurationSha256:createHash('sha256').update(JSON.stringify(c)).digest('hex'),rows:Number(fields.rows),differences:[],labelDifferences:[]};
let job,nativeResult;
try{
 const start=Date.now();let online=false;
 while(Date.now()-start<120000){const s=await api('/v1/session');const t=s.terminalStatuses.find(t=>t.installationId===installation.installationId);
  if(t?.reportedAt>Date.now()-10000){assert.equal(t.accountLogin,'260460316');assert.equal(t.brokerServer,fields.brokerServer);assert.equal(t.trading,false);online=true;break;}
  await wait(1000);}
 assert.ok(online,'Native terminal did not connect');
 const toUtc=new Date(Number(fields.to)*1000).toISOString();
 const request={version:2,installationId:installation.installationId,idempotencyKey:randomUUID(),symbol:fields.symbol,brokerServer:fields.brokerServer,
  fromUtc:new Date(Date.parse(toUtc)-14*86400000).toISOString(),toUtc,auditWeeks:2,dataPolicy:'existing_audit_semantics',configuration:c};
 report.fromUtc=request.fromUtc;report.toUtc=toUtc;job=await api('/v1/jobs',request);let finished;
 const deadline=Date.now()+300000;let last='';
 while(Date.now()<deadline){
  const path=join(installation.folder,'result.txt');
  if(existsSync(path)){try{const text=readFileSync(path,'utf8');if(unpack(text,key).fields.jobId===job.id)nativeResult=text;}catch{}}
  const j=await api('/v1/jobs/'+job.id);const progress=JSON.stringify(j.progress);
  if(progress!==last){console.log('PARITY',j.state,progress);last=progress;}
  if(j.state==='failed'||j.state==='cancelled')throw new Error(j.failureCode||j.state);
  if(j.state==='completed'){finished=j;break;}
  await wait(250);
 }
 assert.ok(finished,'Universal audit timed out');assert.ok(nativeResult,'Raw native trade capture missing');
 writeFileSync(join(stage,'canonical-universal-native.txt'),nativeResult);
 writeFileSync(join(stage,'canonical-universal-result.json'),JSON.stringify(finished.result,null,2));
 const ticket={jobId:job.id,attemptId:finished.result.attemptId,configurationHash:finished.configurationHash,requestHash:finished.result.requestHash,request};
 const reference=parseResult(packet(`jobId=${job.id}\nattemptId=${ticket.attemptId}\nconfigurationHash=${ticket.configurationHash}\nrequestHash=${ticket.requestHash}\nrows=${fields.rows}\nTRADES\n${baseline.split('\nTRADES\n')[1]}`,key),key,ticket);
 const a=baseline.split('\nTRADES\n')[1].trimEnd().split('\n').map(r=>r.split('|'));
 const b=unpack(nativeResult,key).body.split('\nTRADES\n')[1].trimEnd().split('\n').map(r=>r.split('|'));
 if(a.length!==b.length)report.differences.push({field:'tradeCount',original:a.length,universal:b.length});
 const names=['signalTime','entryTime','exitTime','direction','entryPrice','sl','tp','exitPrice','netR','valid','closed','reason','spreadPrice'];
 for(let i=0;i<Math.min(a.length,b.length);i++)for(let k=0;k<13;k++){
  const numeric=k>=4&&k<=8||k===12;
  // This preset uses the named quarter-R leg; web targetR uses a custom leg.
  // Accept only that exact label alias, never a different price, time or R.
  if(k===11&&c.runtime.targetR===0.25&&a[i][k]==='TP025'&&b[i][k]==='TP_R0.25000000'){
   report.labelDifferences.push({trade:i+1,original:a[i][k],universal:b[i][k]});continue;
  }
  if(numeric&&a[i][k]!==''&&b[i][k]!==''){
   if(!Number.isFinite(Number(a[i][k]))||!Number.isFinite(Number(b[i][k]))||Math.abs(Number(a[i][k])-Number(b[i][k]))>1e-10)
    report.differences.push({trade:i+1,field:names[k],original:a[i][k],universal:b[i][k]});
  }else if(a[i][k]!==b[i][k])report.differences.push({trade:i+1,field:names[k],original:a[i][k],universal:b[i][k]});
 }
 report.original=summarizeResult(reference);report.universal=finished.result.summary;
 report.status=report.differences.length?'FAIL':'PASS';assert.equal(report.differences.length,0,JSON.stringify(report.differences.slice(0,10)));
 assert.deepEqual(finished.result.trades,reference.trades,'Normalized web rows differ from original trades');
 console.log('CANONICAL_PARITY_PASS',fields.name,JSON.stringify(report.original));
}catch(e){report.status='FAIL';report.error=e.message;throw e;}
finally{
 if(job)await api('/v1/jobs/'+job.id+'/cancel',{}).catch(()=>{});
 await api('/v1/trading',{installationId:installation.installationId,enabled:false,jobId:null}).catch(()=>{});
 agent.kill();writeFileSync(join(stage,'canonical-parity-report.json'),JSON.stringify(report,null,2));
 await complete(child('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',join(root,'scripts/validate_universal_connection.ps1'),'-Mode','stop'],root));
}
