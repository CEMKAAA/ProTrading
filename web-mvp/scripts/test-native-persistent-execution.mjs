import assert from 'node:assert/strict';
import { readFileSync, writeFileSync, renameSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { spawn } from 'node:child_process';
import { randomUUID, createHash } from 'node:crypto';
import { ControlPlane } from '../control-service/control-plane.mjs';
import { unpack } from '../control-service/mt5-agent.mjs';
import { defaultConfiguration } from '../lib/universal-contract.ts';

const root=resolve(import.meta.dirname,'../..'),web=join(root,'web-mvp'),state=join(web,'control-service/.state');
const agentState=join(state,'agent-qa'),installation=JSON.parse(readFileSync(join(agentState,'installation.json'),'utf8'));
const key=readFileSync(join(installation.folder,'local.key'),'utf8');
const database=new ControlPlane({database:join(state,'control.sqlite'),
  signingKey:JSON.parse(readFileSync(join(state,'signing-key.json'),'utf8')),
  eaSigningKey:JSON.parse(readFileSync(join(state,'ea-signing-key.json'),'utf8'))});
const account='c8887b55-0952-42ad-a8b9-7c9f1f55e0fd';
assert.equal(database.get('SELECT account_id FROM installations WHERE id=?',installation.installationId)?.account_id,account);
let token=database.issueBrowserSession(account,12*3600000).accessToken;
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function api(path,body){const r=await fetch('http://127.0.0.1:4321'+path,{method:body===undefined?'GET':'POST',
  headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(10000)});
  const v=await r.json();if(!r.ok)throw Error(path+': '+v.error);return v;}
async function worker(mode){const p=spawn('powershell.exe',['-NoProfile','-File',join(root,'scripts/validate_universal_connection.ps1'),'-Mode',mode,
  ...(mode==='attach'?['-InstallationId',installation.installationId]:[])],{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});
  let output='';p.stdout.on('data',b=>{output+=b;});p.stderr.on('data',b=>{output+=b;});
  if(await new Promise(r=>p.once('exit',r))!==0)throw Error(output);console.log(output.trim());}
let agent;
function startAgent(){agent=spawn(process.execPath,['--experimental-strip-types','control-service/mt5-agent.mjs','watch','--state',agentState],
  {cwd:web,windowsHide:true,stdio:['ignore','ignore','pipe']});agent.stderr.on('data',b=>{if(!b.toString().includes('ExperimentalWarning'))process.stderr.write(b);});}
async function stopAgent(){if(agent){const p=agent;agent=null;p.kill();await new Promise(r=>p.once('exit',r));}}
function terminal(){const f=unpack(readFileSync(join(installation.folder,'status.txt'),'utf8'),key).fields;
  assert.equal(f.accountLogin,'260460316');assert.equal(f.brokerServer,'Exness-MT5Trial15');assert.equal(Number(f.openPositions),0,'No broker orders are permitted');return f;}
async function until(check,timeout=30000){const end=Date.now()+timeout;while(Date.now()<end){const r=await check();if(r)return r;await sleep(500);}throw Error('NATIVE_PERSISTENCE_TIMEOUT');}
const report={checkedAt:new Date().toISOString(),status:'FAIL',brokerOrdersEnabled:false,actualBrokerOrdersPlaced:false,
  expirySimulation:'Expired only the isolated QA browser database row; wall clock and market data unchanged.',
  binarySha256:createHash('sha256').update(readFileSync(join(root,'IndicatorCodeExamples/universal/UniversalConnectionEA.ex5'))).digest('hex'),checks:[]};
let job;
try{
  await api('/v1/installations/'+installation.installationId+'/activate',{});await worker('attach');
  // The harness configuration disables terminal Algo Trading before starting the real EX5.
  assert.match(readFileSync(join(root,'tmp/universal_connection_validation/attach.ini'),'utf8'),/Enabled=0/);
  startAgent();const status=await until(()=>{const f=terminal();return Number(f.at)*1000>Date.now()-5000&&f.connectionLabel==='MT5 + WEB: SAGLIKLI'?f:null;},120000);
  const c=defaultConfiguration('orb');c.name='Persistent authority native QA';c.inputs.InpSignalTimeframe=5;
  const toUtc=new Date(Math.floor((Date.now()-60000)/1000)*1000).toISOString();
  job=await api('/v1/jobs',{version:2,installationId:installation.installationId,idempotencyKey:randomUUID(),symbol:status.symbol,brokerServer:status.brokerServer,
    fromUtc:new Date(Date.parse(toUtc)-14*86400000).toISOString(),toUtc,auditWeeks:2,dataPolicy:'existing_audit_semantics',configuration:c});
  const finished=await until(async()=>{const r=await api('/v1/jobs/'+job.id);if(['failed','cancelled'].includes(r.state))throw Error(r.failureCode);return r.state==='completed'?r:null;},300000);
  assert.ok(finished.result.trades.length>0);assert.equal(finished.result.summary.data,0);
  await api('/v1/trading',{installationId:installation.installationId,jobId:job.id,enabled:true});
  await until(()=>terminal().trading==='true');report.checks.push('Real signed Trading ON accepted by native EX5; Algo Trading remains disabled.');
  const actor=database.browser(token),generation=database.get('SELECT generation FROM leases WHERE account_id=?',account).generation;
  database.run('UPDATE sessions SET expires_at=? WHERE id=?',Date.now()-1,actor.sessionId);
  await assert.rejects(()=>api('/v1/session'),/UNAUTHORIZED/);
  await sleep(20000);
  assert.equal(terminal().trading,'true');assert.equal(terminal().configurationHash,finished.configurationHash);
  assert.equal(database.get('SELECT generation FROM leases WHERE account_id=?',account).generation,generation);
  report.checks.push('Past browser expiry, real helper renews native live authority beyond one signed-command lifetime.');
  await stopAgent();await until(()=>terminal().trading==='false',25000);
  report.checks.push('Stopped helper causes native new-entry authority to expire.');
  startAgent();await until(()=>terminal().trading==='true',30000);
  assert.equal(terminal().configurationHash,finished.configurationHash);
  report.checks.push('Restarted helper resumes identical approved config without login, audit or another Trading ON.');
  token=database.issueBrowserSession(account,12*3600000).accessToken;
  const activated=await api('/v1/installations/'+installation.installationId+'/activate',{});assert.equal(activated.generation,generation);
  assert.equal((await api('/v1/session')).trading.enabled,true);
  await api('/v1/trading',{installationId:installation.installationId,jobId:null,enabled:false});
  await until(()=>terminal().trading==='false');report.checks.push('Same-device web reauthorization preserves config; explicit OFF stops native authorization.');
  report.summary=finished.result.summary;report.status='PASS';
}catch(error){report.error=error.message;throw error;}
finally{
  database.run('UPDATE trading SET enabled=0 WHERE account_id=?',account);
  if(job)await api('/v1/jobs/'+job.id+'/cancel',{}).catch(()=>{});
  await stopAgent();await worker('stop');database.close();
  const path=join(root,'tmp/universal_connection_validation/persistent-native-report.json');
  writeFileSync(path+'.partial',JSON.stringify(report,null,2)+'\n');renameSync(path+'.partial',path);console.log(JSON.stringify(report));
}
