import assert from 'node:assert/strict';
import {test} from 'node:test';
import {readFileSync} from 'node:fs';
import {ControlPlane} from '../control-service/control-plane.mjs';
import {keyPair,id} from '../control-service/crypto.mjs';
import {defaultConfiguration} from '../lib/universal-contract.ts';
import {progressSchema} from '../lib/control-contract.ts';
import {once} from 'node:events';
import {controlHttp} from '../control-service/http.mjs';
import {DeviceClient} from '../control-service/device-client.mjs';

function fixture(){
 const plane=new ControlPlane(),account=plane.provisionAccount(),session=plane.issueBrowserSession(account),keys=keyPair();
 const pair=plane.beginPairing({publicKey:keys.publicKey,label:'Audit preparation QA'});
 plane.approvePairing(session.accessToken,pair.code,pair.fingerprint);plane.activate(session.accessToken,pair.installationId);
 const installation=plane.get('SELECT * FROM installations WHERE id=?',pair.installationId);
 const now=Date.now(),request={version:2,installationId:installation.id,idempotencyKey:id(),symbol:'JP225m',brokerServer:'QA',
  fromUtc:new Date(now-14*86400000).toISOString(),toUtc:new Date(now).toISOString(),auditWeeks:2,dataPolicy:'existing_audit_semantics',configuration:defaultConfiguration('orb')};
 const job=plane.createJob(session.accessToken,request),ticket=plane.claim(installation).job.payload;
 return {plane,session,installation,job,keys,base:{jobId:job.id,attemptId:ticket.attemptId}};
}
test('legacy progress remains valid; native diagnostics are bounded, single-line and inert',()=>{
 const base={jobId:id(),attemptId:id(),phase:'downloading',processed:0,total:null};
 assert.ok(progressSchema.safeParse(base).success);
 assert.ok(progressSchema.safeParse({...base,detail:'NAS_CACHE_NO_DATA bars=-1 / tf=PERIOD_M5 requested=60000 max=5000'}).success);
 assert.ok(!progressSchema.safeParse({...base,detail:'x'.repeat(1025)}).success);
 assert.ok(!progressSchema.safeParse({...base,detail:'x\ncommand=live'}).success);
});
test('confirmed native preparation failure ends the job and retains its exact diagnostic',()=>{
 const f=fixture();try{
  const detail='NAS_CACHE_NO_DATA bars=-1 | NAS tf=PERIOD_M5 requested=60000 max=5000';
  f.plane.progress(f.installation,{...f.base,phase:'downloading',processed:0,total:null,detail:'Preparing NAS'});
  const result=f.plane.fail(f.installation,{...f.base,code:'AUDIT_MAX_BARS_LIMIT',detail});
  assert.equal(result.state,'failed');assert.equal(result.failureCode,'AUDIT_MAX_BARS_LIMIT');assert.equal(result.progress.detail,detail);
  assert.equal(result.result,null);assert.equal(f.plane.sessionInfo(f.session.accessToken).trading.enabled,false);
  assert.throws(()=>f.plane.fail(f.installation,{...f.base,code:'AUDIT_HISTORY_STALLED',detail}),e=>e.code==='STALE_JOB_ATTEMPT');
 }finally{f.plane.close();}
});
test('failure diagnostics do not bypass validation or make fake successful results',()=>{
 const f=fixture();try{
  assert.throws(()=>f.plane.fail(f.installation,{...f.base,code:'AUDIT_HISTORY_BLOCKED',detail:'x\ncommand=live'}),e=>e.code==='INVALID_FAILURE_DETAIL');
  assert.equal(f.plane.readJob(f.session.accessToken,f.job.id).state,'running');
 }finally{f.plane.close();}
});
test('signed helper failure traverses the actual HTTP boundary with native detail',async()=>{
 const f=fixture(),server=controlHttp(f.plane);server.listen(0,'127.0.0.1');await once(server,'listening');
 try{
  const client=new DeviceClient({apiUrl:'http://127.0.0.1:'+server.address().port,installationId:f.installation.id,privateKey:f.keys.privateKey,pinnedServerPublicKey:f.plane.signingKey.publicKey});
  await client.heartbeat();
  const detail='NAS_CACHE_PARTIAL first=2026.10.01 required=2026.09.10';
  const failed=await client.request('/v1/device/failure',{...f.base,code:'AUDIT_HISTORY_STALLED',detail});
  assert.equal(failed.state,'failed');assert.equal(failed.progress.detail,detail);assert.equal(failed.result,null);
 }finally{server.close();await once(server,'close');f.plane.close();}
});
test('native adapter surfaces hard blocks and only watches preparation, not tick replay',()=>{
 const source=readFileSync(new URL('../../IndicatorCodeExamples/universal/UniversalRuntime.mqh',import.meta.url),'utf8');
 assert.ok(source.includes('blocked=orb_g_histCoverageHardBlocked'));
 assert.ok(source.includes('if(!UcHistoryWait(detail,blocked,nasTf,nasRequested))return;'));
 assert.ok(source.includes('AUDIT_MAX_BARS_LIMIT'));assert.ok(source.includes('AUDIT_HISTORY_STALLED'));
 const guard=source.split('bool UcHistoryWait(')[1].split('#include "UniversalChart.mqh"')[0];
 assert.ok(!guard.includes('SERIES_LASTBAR_DATE'),'new bars do not count as progress at the missing old edge');
 assert.ok(source.includes('g_ucHistoryChangedAt=0;g_ucHistoryFingerprint="";'));
});
