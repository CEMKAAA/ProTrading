import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,renameSync,existsSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {spawn} from 'node:child_process';
import {randomUUID,createHash} from 'node:crypto';
import {DeviceClient} from '../control-service/device-client.mjs';
import {unpack,parseResult} from '../control-service/mt5-agent.mjs';
import {defaultConfiguration,UNIVERSAL_RUNTIME} from '../lib/universal-contract.ts';

const root=resolve(import.meta.dirname,'../..'),web=join(root,'web-mvp');
const state=join(web,'control-service/.state/agent-qa');
const installation=JSON.parse(readFileSync(join(state,'installation.json'),'utf8'));
const keys=JSON.parse(readFileSync(join(state,'device-key.json'),'utf8'));
const key=readFileSync(join(installation.folder,'local.key'),'utf8');
const token=JSON.parse(readFileSync(join(web,'control-service/.state/dev-access.json'),'utf8')).accessToken;
const client=new DeviceClient({...installation,privateKey:keys.privateKey});
const wait=ms=>new Promise(r=>setTimeout(r,ms));
function atomic(path,bytes){writeFileSync(path+'.partial',bytes);renameSync(path+'.partial',path);}
async function api(path,body){
  const r=await fetch('http://127.0.0.1:4321'+path,{method:body===undefined?'GET':'POST',headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(10000)});
  const v=await r.json();if(!r.ok)throw Error(path+': '+v.error);return v;
}
async function worker(mode){
  const p=spawn('powershell.exe',['-NoProfile','-File',join(root,'scripts/validate_universal_connection.ps1'),'-Mode',mode,...(mode==='attach'?['-InstallationId',installation.installationId]:[])],{cwd:root,windowsHide:true,stdio:['ignore','pipe','pipe']});
  let output='';for(const stream of [p.stdout,p.stderr])stream.on('data',b=>output+=b);
  const code=await new Promise(r=>p.once('exit',r));if(code!==0)throw Error(output);console.log(output.trim());
}
const report={checkedAt:new Date().toISOString(),status:'FAIL',nativeTradingRequested:false,
  binarySha256:createHash('sha256').update(readFileSync(join(root,'IndicatorCodeExamples/universal/UniversalConnectionEA.ex5'))).digest('hex'),checks:[]};
let job,ticket,pausedAt=0,resumed=false;
try{
  await api('/v1/installations/'+installation.installationId+'/activate',{});
  // This is an isolated QA forwarder. Only command delivery is withheld;
  // real native status, signed heartbeat, identity and progress keep running.
  const dest=join(root,'.tmp/orb_jp225_full_worker/MQL5/Experts/StratumUniversal/UniversalConnectionEA.ex5');
  atomic(dest,readFileSync(join(root,'IndicatorCodeExamples/universal/UniversalConnectionEA.ex5')));
  await worker('attach');
  const deadline=Date.now()+360000;
  while(Date.now()<deadline){
    const statusFile=join(installation.folder,'status.txt');
    if(!existsSync(statusFile)){await wait(1000);continue;}
    const f=unpack(readFileSync(statusFile,'utf8'),key).fields;
    if(Number(f.at)*1000<Date.now()-10000){await wait(1000);continue;}
    assert.equal(f.accountLogin,'260460316');assert.equal(f.brokerServer,'Exness-MT5Trial15');assert.equal(f.trading,'false');
    await client.heartbeat();
    const identity=client.verified(await client.request('/v1/device/identity',{symbol:f.symbol,brokerServer:f.brokerServer,accountLogin:f.accountLogin}),'ea_identity');
    atomic(join(installation.folder,'identity.txt'),identity.certificate);
    await client.request('/v1/device/status',{symbol:f.symbol,brokerServer:f.brokerServer,accountLogin:f.accountLogin,runtime:UNIVERSAL_RUNTIME,build:'canonical-bundle/v1',openPositions:Number(f.openPositions),trading:false,configurationHash:f.configurationHash,error:f.error});
    if(!job){
      const c=defaultConfiguration('entrylab');c.name='Native authority renewal QA';c.inputs.InpSignalTimeframe=5;c.inputs.InpPipSlModeDefault=true;c.inputs.InpPipSlPips=200;c.inputs.InpMaCrossMode=6;c.runtime.entryPreset=4;
      const toUtc=new Date(Math.floor((Date.now()-60000)/1000)*1000).toISOString();
      job=await api('/v1/jobs',{version:2,installationId:installation.installationId,idempotencyKey:randomUUID(),symbol:f.symbol,brokerServer:f.brokerServer,fromUtc:new Date(Date.parse(toUtc)-14*86400000).toISOString(),toUtc,auditWeeks:2,dataPolicy:'existing_audit_semantics',configuration:c});
      ticket=await client.claim();assert.equal(ticket.jobId,job.id);
    }
    const resultFile=join(installation.folder,'result.txt');
    if(existsSync(resultFile)&&unpack(readFileSync(resultFile,'utf8'),key).fields.jobId===job.id){
      assert.ok(resumed,'Audit must exercise pause and renewal before completion');
      await client.request('/v1/device/result',parseResult(readFileSync(resultFile,'utf8'),key,ticket));
      const finished=await api('/v1/jobs/'+job.id);assert.equal(finished.state,'completed');assert.equal(f.error,'');
      report.checks.push('completed native result has no stale authority error');report.summary=finished.result.summary;report.status='PASS';break;
    }
    let phase='preparing',processed=0,total=null;
    const progressFile=join(installation.folder,'progress.txt');
    if(existsSync(progressFile)){
      const p=unpack(readFileSync(progressFile,'utf8'),key).fields;
      if(p.jobId===job.id&&p.attemptId===ticket.attemptId){phase=p.phase;processed=Number(p.processed);total=Number(p.total)||null;}
    }
    ticket=client.verified(await client.request('/v1/device/progress',{jobId:job.id,attemptId:ticket.attemptId,phase,processed,total}),'backtest_job');
    if(!pausedAt&&phase==='replaying'&&processed>=8){pausedAt=Date.now();console.log('Withholding native audit command renewal for 20 seconds');}
    if(pausedAt&&!resumed&&f.error==='AUDIT_AUTHORITY_EXPIRED'&&!report.checks.length){report.checks.push('expired authority actually pauses the real native audit');console.log('Native pause confirmed');}
    if(!pausedAt||Date.now()-pausedAt>=20000){
      const command=client.verified(await client.request('/v1/device/command',{jobId:job.id,attemptId:ticket.attemptId}),'ea_command');
      atomic(join(installation.folder,'command.txt'),command.command);
      if(pausedAt&&!resumed&&report.checks.length&&f.error===''){resumed=true;report.checks.push('fresh signed renewal clears the error on the same job and attempt');console.log('Same audit renewed; stale error cleared');}
    }
    await wait(1000);
  }
  assert.equal(report.status,'PASS','Native audit did not finish');
}catch(e){report.error=e.message;throw e;}
finally{
  if(job)await api('/v1/jobs/'+job.id+'/cancel',{}).catch(()=>{});
  await worker('stop');
  atomic(join(root,'tmp/universal_connection_validation/authority-renewal-report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report));
}
