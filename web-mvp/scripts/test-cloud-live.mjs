import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { signed,keyPair,makeProof,id,verifySigned,hash } from '../control-service/crypto.mjs';
import { CLOUD_CONTROL,PUBLIC_STUDIO } from '../control-service/api-location.mjs';
import { defaultConfiguration } from '../lib/universal-contract.ts';

const qa=JSON.parse(readFileSync(new URL('../control-service/.state/real-demo-qa.json',import.meta.url),'utf8'));
async function api(path,body,token,proof,origin=PUBLIC_STUDIO){
 const response=await fetch(CLOUD_CONTROL+path,{method:body===undefined?'GET':'POST',headers:{Origin:origin,...(body===undefined?{}:{'Content-Type':'application/json'}),
  ...(token?{Authorization:'Bearer '+token}:{}),...(proof?{'X-Stratum-Proof':Buffer.from(JSON.stringify(proof)).toString('base64url')}:{})},
  ...(body===undefined?{}:{body:JSON.stringify(body)}),redirect:'error',signal:AbortSignal.timeout(30000)});
 const value=response.headers.get('Content-Type')?.includes('application/zip')?Buffer.from(await response.arrayBuffer()):await response.json();
 return {status:response.status,value};
}
const check=(r,status)=>assert.equal(r.status,status,JSON.stringify(Buffer.isBuffer(r.value)?{binaryBytes:r.value.length}:r.value));
check(await api('/health'),200);
check(await api('/v1/session'),401);
check(await api('/v1/session',undefined,undefined,undefined,'https://evil.example'),403);
const login=await api('/v1/auth/login',{email:qa.email,password:qa.password});check(login,200);
const token=login.value.accessToken;assert.match(token,/^[A-Za-z0-9_-]{43}$/);
const session=await api('/v1/session',undefined,token);check(session,200);assert.equal(session.value.accessMode,'demo');
const account=session.value.accountId;
check(await api('/v1/auth/session',undefined,token),200);
const role=await api('/v1/admin/status',undefined,token);check(role,200);assert.equal(role.value.isAdmin,false);
check(await api('/v1/admin/users',{query:'',offset:0},token),403);
check(await api('/v1/admin/catalog',{userId:account,family:'orb',query:'',offset:0},token),403);
const library=await api('/v1/library/strategies',undefined,token);check(library,200);
// This persistent QA account may have explicit grants made through the admin UI.
// New-account default denial is separately tested in the rollback SQL suite.
assert.ok(Array.isArray(library.value.items));
assert.ok(library.value.items.every(item=>!('configuration' in item)&&!('nativeSnapshot' in item)));
check(await api('/v1/admin/grant',{userId:account,strategyId:'orb_unauthorized',enabled:true,revision:0},token),403);
check(await api('/v1/library/load',{strategyId:'orb_unauthorized'},token),403);
const c=defaultConfiguration('orb');c.name='Cloud QA '+id().slice(0,8);c.runtime.targetR=.1;
check(await api('/v1/strategies',c,token),200);
const strategies=await api('/v1/strategies',undefined,token);check(strategies,200);assert.ok(strategies.value.strategies.some(s=>s.name===c.name&&s.runtime.targetR===.1));
const zip=await api('/v1/ea/package',{},token);check(zip,200);const bytes=zip.value;assert.equal(bytes.readUInt32LE(),0x04034b50);
let offset=0,setup;
while(bytes.readUInt32LE(offset)===0x04034b50){const length=bytes.readUInt16LE(offset+26),size=bytes.readUInt32LE(offset+18),extra=bytes.readUInt16LE(offset+28);
 const name=bytes.subarray(offset+30,offset+30+length).toString(),at=offset+30+length+extra;if(name==='personal-setup.json')setup=JSON.parse(bytes.subarray(at,at+size));offset=at+size;}
assert.ok(verifySigned(setup.envelope,setup.serverPublicKey));assert.equal(setup.envelope.payload.apiUrl,CLOUD_CONTROL);assert.equal(setup.envelope.payload.studioUrl,PUBLIC_STUDIO);
const keys=keyPair(),body={enrollmentToken:setup.envelope.payload.enrollmentToken,publicKey:keys.publicKey,label:'Isolated cloud verification'};
const enrollment=await api('/v1/ea/enroll',{...body,signature:signed(body,keys.privateKey).signature});check(enrollment,201);
const {installationId,code,fingerprint}=enrollment.value;assert.equal(enrollment.value.accountId,account);
const proof=makeProof(installationId,'POST','/v1/device/pairing/refresh',{code},keys.privateKey);
const pairing=await api('/v1/device/pairing/refresh',{code},undefined,proof);check(pairing,200);assert.ok(verifySigned(pairing.value,setup.serverPublicKey));
check(await api('/v1/device/pairing/refresh',{code},undefined,proof),401);
check(await api('/v1/pairings/review',{code},token),200);
check(await api('/v1/pairings/approve',{code,fingerprint},token),200);
try{
 check(await api('/v1/installations/'+installationId+'/activate',{},token),200);
 const agentId=id();
 async function device(path,body){return api(path,body,undefined,makeProof(installationId,'POST',path,body,keys.privateKey,Date.now(),agentId));}
 check(await device('/v1/device/connect',{}),200);
 const heartbeat=await device('/v1/device/heartbeat',{});check(heartbeat,200);assert.equal(heartbeat.value.payload.liveTradingAllowed,false);
 // Keep the agent lease alive while crossing the authority-cache refresh boundary.
 // A silent 11-second gap plus HTTP latency can expire the 15-second agent lease.
 for(let i=0;i<6;i++){
  await new Promise(resolve=>setTimeout(resolve,2000));
  check(await device('/v1/device/heartbeat',{}),200);
 }
 const renewed=await device('/v1/device/heartbeat',{});check(renewed,200);assert.equal(renewed.value.payload.liveTradingAllowed,false);
 const auditEnd=Date.now();
 const request={version:2,installationId,idempotencyKey:id(),symbol:'USDJPYm',brokerServer:'Exness-MT5Trial15',
  fromUtc:new Date(auditEnd-14*86400000).toISOString(),toUtc:new Date(auditEnd).toISOString(),auditWeeks:2,dataPolicy:'existing_audit_semantics',configuration:c};
 // The real browser and installed helper are independent processes. Browser
 // network requests must not suspend the helper's 15-second agent lease.
 let stopHeartbeat=false,heartbeatError;
 const keepAlive=(async()=>{
  while(!stopHeartbeat){
   await new Promise(resolve=>setTimeout(resolve,2000));
   if(stopHeartbeat)break;
   try{check(await device('/v1/device/heartbeat',{}),200);}catch(error){heartbeatError=error;break;}
  }
 })();
 try{
  const job=await api('/v1/jobs',request,token);check(job,201);assert.equal(job.value.configurationHash,hash(c));
  const claim=await device('/v1/device/claim',{});check(claim,200);assert.ok(verifySigned(claim.value.job,setup.serverPublicKey));assert.equal(claim.value.job.payload.liveTradingAllowed,false);
  check(await api('/v1/trading',{installationId,enabled:true,jobId:job.value.id},token),409);
  const attemptId=claim.value.job.payload.attemptId;
  const detail='QA native history diagnostic: M1 need~20361 max=5000 bars=5000 oldest=syncing';
  check(await device('/v1/device/progress',{jobId:job.value.id,attemptId,phase:'downloading',processed:0,total:null,detail}),200);
  const failed=await device('/v1/device/failure',{jobId:job.value.id,attemptId,code:'AUDIT_HISTORY_BLOCKED',detail});check(failed,200);
  assert.equal(failed.value.state,'failed');assert.equal(failed.value.progress.detail,detail);assert.equal(failed.value.result,null);
  const read=await api('/v1/jobs/'+job.value.id,undefined,token);check(read,200);assert.equal(read.value.failureCode,'AUDIT_HISTORY_BLOCKED');assert.equal(read.value.progress.detail,detail);
 }finally{stopHeartbeat=true;await keepAlive;}
 if(heartbeatError)throw heartbeatError;
}finally{
 check(await api('/v1/installations/'+installationId+'/revoke',{},token),200);
 check(await api('/v1/auth/logout',{},token),200);
 check(await api('/v1/session',undefined,token),401);
}
console.log(JSON.stringify({status:'PASS',checks:['Supabase login/live demo','bearer/origin isolation','non-admin access denied','shared library default denied','strategy persistence','verified private ZIP','owner-bound enrollment','signed pairing/replay rejection','controller activation','stale authority renewed','signed research job','Trading ON without audit denied','revocation/logout'],nativeTradingRequested:false,brokerBacktestClaimed:false}));
