import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {resolve} from 'node:path';
import {keyPair,id,hash,signed,makeProof,verifySigned} from '../control-service/crypto.mjs';
import {CLOUD_CONTROL,PUBLIC_STUDIO} from '../control-service/api-location.mjs';
import {defaultConfiguration} from '../lib/universal-contract.ts';

// An unattached, isolated QA installation. No native EA or broker order is used.
// The completed result below is a fixture, not a claimed market backtest.
const qa=JSON.parse(readFileSync(new URL('../control-service/.state/real-demo-qa.json',import.meta.url),'utf8'));
const cli=process.env.SUPABASE_CLI;assert.ok(cli,'SUPABASE_CLI must name an authenticated official CLI');
const report={checkedAt:new Date().toISOString(),status:'FAIL',nativeTradingRequested:false,brokerOrdersPlaced:false,
  fixtureResult:true,checks:[]};
async function api(path,body,token,proof){
  const r=await fetch(CLOUD_CONTROL+path,{method:body===undefined?'GET':'POST',headers:{Origin:PUBLIC_STUDIO,
    ...(token?{Authorization:'Bearer '+token}:{}),...(body===undefined?{}:{'Content-Type':'application/json'}),
    ...(proof?{'X-Stratum-Proof':Buffer.from(JSON.stringify(proof)).toString('base64url')}:{})},
    ...(body===undefined?{}:{body:JSON.stringify(body)}),signal:AbortSignal.timeout(45000),redirect:'error'});
  const value=r.headers.get('Content-Type')?.includes('application/zip')?Buffer.from(await r.arrayBuffer()):await r.json();
  return {status:r.status,value};
}
const ok=(r,status=200)=>{assert.equal(r.status,status,Buffer.isBuffer(r.value)?'ZIP error':JSON.stringify(r.value));return r.value;};
const login=async()=>{const before=Date.now(),s=ok(await api('/v1/auth/login',{email:qa.email,password:qa.password}));
  assert.ok(s.expiresAt>=before+7*86400000&&s.expiresAt<=Date.now()+7*86400000);return s.accessToken;};
let token=await login(),installationId,account,job,agentId=id();const keys=keyPair();
const device=async(path,body={})=>api(path,body,undefined,makeProof(installationId,'POST',path,body,keys.privateKey,Date.now(),agentId));
try{
  const session=ok(await api('/v1/session',undefined,token));account=session.accountId;
  assert.equal(session.email.toLowerCase(),qa.email.toLowerCase());
  const zip=ok(await api('/v1/ea/package',{},token));let offset=0,setup;
  while(zip.readUInt32LE(offset)===0x04034b50){const n=zip.readUInt16LE(offset+26),size=zip.readUInt32LE(offset+18),extra=zip.readUInt16LE(offset+28),at=offset+30+n+extra;
    if(zip.subarray(offset+30,offset+30+n).toString()==='personal-setup.json')setup=JSON.parse(zip.subarray(at,at+size));offset=at+size;}
  assert.ok(verifySigned(setup.envelope,setup.serverPublicKey));
  const body={enrollmentToken:setup.envelope.payload.enrollmentToken,publicKey:keys.publicKey,label:'Persistent authority QA'};
  const enrollment=ok(await api('/v1/ea/enroll',{...body,signature:signed(body,keys.privateKey).signature}),201);
  installationId=enrollment.installationId;assert.equal(enrollment.accountId,account);
  ok(await api('/v1/pairings/approve',{code:enrollment.code,fingerprint:enrollment.fingerprint},token));
  const lease=ok(await api('/v1/installations/'+installationId+'/activate',{},token));ok(await device('/v1/device/connect'));
  const c=defaultConfiguration('orb');c.name='Persistent policy fixture only';
  const to=Date.now()-60000,from=to-14*86400000;
  const request={version:2,installationId,idempotencyKey:id(),symbol:'USDJPYm',brokerServer:'Exness-MT5Trial15',
    fromUtc:new Date(from).toISOString(),toUtc:new Date(to).toISOString(),auditWeeks:2,dataPolicy:'existing_audit_semantics',configuration:c};
  job=ok(await api('/v1/jobs',request,token),201);const ticket=ok(await device('/v1/device/claim')).job.payload;
  ok(await device('/v1/device/result',{jobId:job.id,attemptId:ticket.attemptId,configurationHash:ticket.configurationHash,requestHash:ticket.requestHash,
    engineRuntime:'universal-adapter/v2',auditBuild:'fixture-only-not-a-broker-execution',symbol:request.symbol,brokerServer:request.brokerServer,
    coverage:{datasetFingerprint:hash('fixture'),realTicks:0,generatedTicks:0,missingIntervals:[],mode:'existing_audit'},
    trades:[{id:'1',direction:'BUY',signalUtc:request.fromUtc,entryUtc:request.fromUtc,exitUtc:new Date(from+3600000).toISOString(),
      entryPrice:150,exitPrice:150.1,sl:149.9,tp:150.1,outcome:'WIN',exitReason:'TP',netR:1,spreadPrice:.001,slippagePrice:null,commission:null,swap:null}]}));
  const status={symbol:request.symbol,brokerServer:request.brokerServer,accountLogin:'123',runtime:'universal-adapter/v2',build:'fixture-only',
    openPositions:0,trading:false,configurationHash:job.configurationHash,error:''};
  ok(await device('/v1/device/status',status));
  ok(await api('/v1/trading',{installationId,jobId:job.id,enabled:true},token));
  const before=ok(await device('/v1/device/command',{jobId:null,attemptId:null}));assert.ok(before.payload.command.startsWith('command=live\n'));
  report.checks.push('Real cloud login issues a seven-day BFF session; isolated signed live consent accepted.');
  // Expire only our known QA session and lease, not the wall clock or market data.
  for(const v of [account,installationId])assert.match(v,/^[a-f0-9-]{36}$/);const tokenHash=hash(token);
  const rows=JSON.parse(execFileSync(cli,['db','query',`WITH target AS (
    SELECT s.id FROM stratum_runtime.sessions s JOIN stratum_runtime.leases l ON l.session_id=s.id
    JOIN stratum_runtime.installations i ON i.id=l.installation_id
    WHERE s.account_id='${account}' AND s.token_hash='${tokenHash}' AND i.id='${installationId}' AND i.label='Persistent authority QA'
  ), expired AS (UPDATE stratum_runtime.sessions s SET expires_at=0 FROM target t WHERE s.id=t.id RETURNING s.id)
  UPDATE stratum_runtime.leases l SET expires_at=0 FROM expired e WHERE l.session_id=e.id RETURNING l.installation_id`,
    '--linked','--project-ref','uvzhrrqzzdjqtmydpvwo','--agent','no','--output','json'],{encoding:'utf8',timeout:45000}));
  assert.equal(rows.length,1);assert.equal((await api('/v1/session',undefined,token)).status,401);
  await new Promise(r=>setTimeout(r,17000));agentId=id();ok(await device('/v1/device/connect'));
  ok(await device('/v1/device/heartbeat'));ok(await device('/v1/device/status',status));
  const after=ok(await device('/v1/device/command',{jobId:null,attemptId:null}));
  assert.ok(verifySigned(after,setup.serverPublicKey));assert.ok(after.payload.command.startsWith('command=live\n'));
  const field=(packet,name)=>packet.split('\n').find(row=>row.startsWith(name+'='))?.slice(name.length+1);
  assert.equal(field(after.payload.command,'configurationHash'),job.configurationHash);
  assert.equal(field(after.payload.command,'generation'),lease.generation);
  report.checks.push('Expired BFF and persisted lease do not interrupt prior consent; new signed helper session resumes identical configuration/generation.');
  token=await login();const activated=ok(await api('/v1/installations/'+installationId+'/activate',{},token));assert.equal(activated.generation,lease.generation);
  ok(await api('/v1/trading',{installationId,jobId:null,enabled:false},token));
  assert.equal(ok(await device('/v1/device/command',{jobId:null,attemptId:null})).payload.command,null);
  report.checks.push('New web login preserves approved setup; explicit Trading OFF stops new signed live commands.');report.status='PASS';
}catch(e){report.error=e.message;throw e;}
finally{
  if(installationId){token=await login();ok(await api('/v1/installations/'+installationId+'/revoke',{},token));}
  ok(await api('/v1/auth/logout',{},token));
  const dir=resolve(import.meta.dirname,'../../tmp/universal_connection_validation');mkdirSync(dir,{recursive:true});
  writeFileSync(resolve(dir,'persistent-cloud-report.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
}
