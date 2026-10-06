import assert from 'node:assert/strict';
import { existsSync, readFileSync, writeFileSync, mkdirSync, unlinkSync } from 'node:fs';
import { spawn } from 'node:child_process';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID, createHash } from 'node:crypto';
import { defaultConfiguration } from '../lib/universal-contract.ts';
import { unpack, packet } from '../control-service/mt5-agent.mjs';
import { signEaCommand } from '../control-service/ea-authority.mjs';

const root=fileURLToPath(new URL('../../',import.meta.url)),web=join(root,'web-mvp');
const state=join(web,'control-service/.state/agent-qa'),stage=join(root,'tmp/universal_connection_validation');
mkdirSync(stage,{recursive:true});
const access=JSON.parse(readFileSync(join(web,'control-service/.state/dev-access.json'),'utf8')).accessToken;
const wait=ms=>new Promise(r=>setTimeout(r,ms));
async function api(path,body){const res=await fetch('http://127.0.0.1:4321'+path,{method:body===undefined?'GET':'POST',
  headers:{Authorization:'Bearer '+access,'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(10000)});
  const data=await res.json();if(!res.ok)throw new Error(path+': '+data.error);return data;}
function child(file,args,cwd=web){return spawn(file,args,{cwd,windowsHide:true,stdio:['ignore','pipe','pipe']});}
async function complete(p){let out='',err='';p.stdout.on('data',b=>{out+=b;});p.stderr.on('data',b=>{err+=b;});
  const code=await new Promise(r=>p.once('exit',r));if(code!==0)throw new Error(err||out||'Child failed: '+code);return out;}
const configFile=join(state,'installation.json');
if(existsSync(configFile)){
  const prior=JSON.parse(readFileSync(configFile,'utf8')),session=await api('/v1/session');
  if(session.installations.find(i=>i.id===prior.installationId)?.state==='revoked'){
    writeFileSync(join(state,'last-revoked-installation.json'),JSON.stringify(prior));
    unlinkSync(configFile); // Only this harness's revoked pairing; production pairing is untouched.
  }
}
const pair=existsSync(configFile)?null:JSON.parse(await complete(child(process.execPath,
  ['--experimental-strip-types','control-service/mt5-agent.mjs','pair','--state',state,'--label','Universal real MT5 QA'])));
if(pair){await api('/v1/pairings/review',{code:pair.pairingCode});await api('/v1/pairings/approve',{code:pair.pairingCode,fingerprint:pair.fingerprint});}
const installation=JSON.parse(readFileSync(join(state,'installation.json'),'utf8'));
const id=installation.installationId,key=readFileSync(join(installation.folder,'local.key'),'utf8');
await api('/v1/installations/'+id+'/activate',{});
console.log(await complete(child('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',join(root,'scripts/validate_universal_connection.ps1'),'-Mode','attach','-InstallationId',id],root)));
function startAgent(){const p=child(process.execPath,['--experimental-strip-types','control-service/mt5-agent.mjs','watch','--state',state]);
  p.stderr.on('data',b=>{const text=b.toString();if(!text.includes('ExperimentalWarning')&&!text.includes('trace-warnings'))process.stderr.write(text);});
  p.stdout.on('data',b=>process.stdout.write(b));return p;}
let agent=startAgent();
const report={checkedAt:new Date().toISOString(),installationId:id,compile:'0 errors, 0 warnings',
  binarySha256:createHash('sha256').update(readFileSync(join(root,'IndicatorCodeExamples/universal/UniversalConnectionEA.ex5'))).digest('hex'),families:[],authorization:{},chart:{}};
async function terminal(){const data=await api('/v1/session');return data.terminalStatuses.find(t=>t.installationId===id);}
async function until(check,timeout=30000){const end=Date.now()+timeout;while(Date.now()<end){const value=await check();if(value)return value;await wait(1000);}throw new Error('MT5_TEST_TIMEOUT');}
let activeJob;
try{
  const status=await until(async()=>{const s=await terminal();return s?.reportedAt>Date.now()-15000?s:null;},120000);
  assert.equal(status.brokerServer,'Exness-MT5Trial15','Only the configured DEMO account is permitted in this test');
  assert.equal(status.accountLogin,'260460316');assert.equal(status.trading,false);
  const profile=await api('/v1/session');
  await until(async()=>unpack(readFileSync(join(installation.folder,'status.txt'),'utf8'),key).fields.connectionLabel==='MT5 + WEB: SAGLIKLI');
  const panel=unpack(readFileSync(join(installation.folder,'status.txt'),'utf8'),key).fields;
  assert.equal(panel.subscriberName,profile.displayName);assert.ok(panel.helloLabel.startsWith('Merhaba '));
  assert.equal(panel.subscriptionLabel,'ABONELIK: AKTIF');report.chart.subscriberPanel=true;
  console.log('Real terminal online:',status.symbol,status.brokerServer,'Trading OFF');
  const selectedFamilies=process.argv.find(a=>a.startsWith('--families='))?.slice(11).split(',')??['orb','macross','sol','entrylab'];
  for(const family of selectedFamilies){
    const c=defaultConfiguration(family);c.name='QA '+family;
    if('InpSignalTimeframe' in c.inputs)c.inputs.InpSignalTimeframe=5;
    if('InpPipSlModeDefault' in c.inputs){c.inputs.InpPipSlModeDefault=true;c.inputs.InpPipSlPips=200;}
    if(family==='macross')c.inputs.InpMaCrossMode=2;
    if(family==='entrylab'){c.inputs.InpMaCrossMode=6;c.runtime.entryPreset=4;}
    const to=Date.now()-60000,toUtc=new Date(Math.floor(to/1000)*1000).toISOString();
    const request={version:2,installationId:id,idempotencyKey:randomUUID(),symbol:status.symbol,brokerServer:status.brokerServer,
      fromUtc:new Date(Date.parse(toUtc)-14*86400000).toISOString(),toUtc,auditWeeks:2,dataPolicy:'existing_audit_semantics',configuration:c};
    const started=Date.now(),job=await api('/v1/jobs',request);activeJob=job.id;let last='';
    const finished=await until(async()=>{const j=await api('/v1/jobs/'+job.id);const p=JSON.stringify(j.progress);
      if(p!==last){console.log(family,j.state,p);last=p;}if(j.state==='failed'||j.state==='cancelled')throw new Error(family+': '+j.failureCode);
      return j.state==='completed'?j:null;},300000);
    activeJob=null;assert.ok(finished.result);assert.ok(finished.result.trades.length>0,family+' empty audit is not validation');
    assert.equal(finished.configurationHash,finished.result.configurationHash);
    assert.equal((await terminal()).trading,false,'Apply must never turn trading on');
    const drawing=await until(async()=>{
      const s=unpack(readFileSync(join(installation.folder,'status.txt'),'utf8'),key).fields;
      return s.chartDone==='true'&&Number(s.chartDrawn)===finished.result.trades.length?s:null;
    },150000);
    assert.equal(Number(drawing.chartTrades),finished.result.trades.length);
    assert.equal(Number(drawing.chartFailures),0,'Native arrow/geometry coordinate assertions failed');
    report.chart[family]={trades:Number(drawing.chartTrades),drawn:Number(drawing.chartDrawn),coordinateSamples:Number(drawing.chartVerified),failures:Number(drawing.chartFailures)};
    writeFileSync(join(stage,family+'-result.json'),JSON.stringify(finished.result,null,2));
    report.families.push({family,jobId:job.id,elapsedMs:Date.now()-started,...finished.result.summary});
    console.log(family,'COMPLETE',JSON.stringify(finished.result.summary));
  }
  writeFileSync(join(stage,'four-engine-results.json'),JSON.stringify({checkedAt:report.checkedAt,families:report.families},null,2));
  // Trading authority is tested with terminal Algo Trading disabled: no orders are sent.
  const last=report.families.at(-1);assert.equal(last.coverageComplete,true);assert.equal(last.data,0);
  await api('/v1/trading',{installationId:id,enabled:true,jobId:last.jobId});
  await until(async()=>(await terminal())?.trading===true,30000);report.authorization.explicitTradingOn=true;
  const livePacket=readFileSync(join(installation.folder,'command.txt'),'utf8');agent.kill();
  await until(async()=>unpack(readFileSync(join(installation.folder,'status.txt'),'utf8'),key).fields.trading==='false',20000);
  report.authorization.helperLossFailsClosed=true;
  const offline=unpack(readFileSync(join(installation.folder,'status.txt'),'utf8'),key).fields;
  assert.notEqual(offline.connectionLabel,'MT5 + WEB: SAGLIKLI');report.chart.connectionLossBadge=true;
  writeFileSync(join(installation.folder,'command.txt'),livePacket);await wait(2500);
  assert.equal(unpack(readFileSync(join(installation.folder,'status.txt'),'utf8'),key).fields.trading,'false');report.authorization.expiredPacketRejected=true;
  agent=startAgent();await until(async()=>(await terminal())?.trading===true,30000);
  await api('/v1/trading',{installationId:id,enabled:false,jobId:null});
  await until(async()=>(await terminal())?.trading===false,30000);report.authorization.tradingOff=true;
  agent.kill();await wait(1000);
  const body='command=live\nissued='+Math.floor(Date.now()/1000)+'\nexpires='+(Math.floor(Date.now()/1000)+15);
  writeFileSync(join(installation.folder,'command.txt'),packet(body,key));await wait(2500);
  let native=unpack(readFileSync(join(installation.folder,'status.txt'),'utf8'),key).fields;
  assert.equal(native.trading,'false');report.authorization.localKeyForgeryRejected=true;
  // Signed read-only expiry vector checks the native badge without modifying an account's real entitlement.
  const certificate=readFileSync(join(installation.folder,'identity.txt'),'utf8').split('\nSERVER_RSA256=')[0];
  const fields=Object.fromEntries(certificate.split('\n').map(row=>{const at=row.indexOf('=');return [row.slice(0,at),row.slice(at+1)];}));
  const now=Math.floor(Date.now()/1000);Object.assign(fields,{issued:now,expires:now+15,sequence:Number(fields.sequence)+1,
    subscriptionActive:'false',subscriptionUntil:now-1,controllerActive:'false',accessMode:'inactive'});
  const authority=JSON.parse(readFileSync(join(web,'control-service/.state/ea-signing-key.json'),'utf8'));
  writeFileSync(join(installation.folder,'identity.txt'),signEaCommand(Object.entries(fields).map(([k,v])=>`${k}=${v}`).join('\n'),authority.privateKey));
  await until(async()=>unpack(readFileSync(join(installation.folder,'status.txt'),'utf8'),key).fields.subscriptionLabel==='ABONELIK: PASIF');
  assert.equal(unpack(readFileSync(join(installation.folder,'status.txt'),'utf8'),key).fields.trading,'false');report.chart.inactiveBadgeSignedVector=true;
  await api('/v1/installations/'+id+'/activate',{});
  const {DeviceClient}=await import('../control-service/device-client.mjs');const keys=JSON.parse(readFileSync(join(state,'device-key.json'),'utf8'));
  const client=new DeviceClient({...installation,privateKey:keys.privateKey});await client.heartbeat();
  // Reactivation invalidates the former generation; its old completed audit cannot enable trading.
  await assert.rejects(()=>api('/v1/trading',{installationId:id,enabled:true,jobId:last.jobId}),/AUDIT_REQUIRED/);
  report.authorization.oldControllerAuditRejected=true;
  await api('/v1/installations/'+id+'/revoke',{});
  await assert.rejects(()=>client.heartbeat(),/INSTALLATION_REVOKED_OR_UNKNOWN/);report.authorization.revocationRejected=true;
  report.status='PASS';
}catch(error){report.status='FAIL';report.error=error.message;throw error;}
finally{
  if(activeJob)await api('/v1/jobs/'+activeJob+'/cancel',{}).catch(()=>{});
  await api('/v1/trading',{installationId:id,enabled:false,jobId:null}).catch(()=>{});
  agent.kill();writeFileSync(join(stage,'roundtrip-report.json'),JSON.stringify(report,null,2));
  await complete(child('powershell.exe',['-NoProfile','-ExecutionPolicy','Bypass','-File',join(root,'scripts/validate_universal_connection.ps1'),'-Mode','stop'],root));
  console.log('Report:',join(stage,'roundtrip-report.json'));
}
