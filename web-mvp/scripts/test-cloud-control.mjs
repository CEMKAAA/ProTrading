import assert from 'node:assert/strict';
import { test } from 'node:test';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { ControlPlane } from '../control-service/cloud/generated/control-plane.mjs';
import { controlHttp } from '../control-service/cloud/generated/http.mjs';
import { keyPair,id,makeProof,verifySigned,hash } from '../control-service/crypto.mjs';
import { defaultConfiguration } from '../lib/universal-contract.ts';
import { controlLocation,CLOUD_CONTROL } from '../control-service/api-location.mjs';
import { postgresQuery,PostgresStore } from '../control-service/cloud/postgres-store.mjs';
import { personalPackage } from '../control-service/cloud/generated/delivery.mjs';

function store(){
 const db=new DatabaseSync(':memory:');db.exec(readFileSync(new URL('../control-service/schema.sql',import.meta.url),'utf8'));let level=0;
 return {db,async get(sql,...args){return db.prepare(sql).get(...args);},async all(sql,...args){return db.prepare(sql).all(...args);},async run(sql,...args){return db.prepare(sql).run(...args);},
 async atomic(work){const point='test'+(++level);db.exec('SAVEPOINT '+point);try{const r=await work();db.exec('RELEASE '+point);return r;}catch(e){db.exec('ROLLBACK TO '+point);db.exec('RELEASE '+point);throw e;}}};
}
async function fixture(){
 const db=store(),plane=new ControlPlane({db}),account=await plane.provisionAccount(),session=await plane.issueBrowserSession(account),keys=keyPair();
 const pair=await plane.beginPairing({publicKey:keys.publicKey,label:'Cloud test'});
 await plane.approvePairing(session.accessToken,pair.code,pair.fingerprint);await plane.activate(session.accessToken,pair.installationId);
 const installation=await plane.get('SELECT * FROM installations WHERE id=?',pair.installationId);
 const request={version:2,installationId:pair.installationId,idempotencyKey:id(),symbol:'USDJPYm',brokerServer:'Exness-MT5Trial15',
 fromUtc:new Date(Date.now()-14*86400000).toISOString(),toUtc:new Date(Date.now()).toISOString(),auditWeeks:2,dataPolicy:'existing_audit_semantics',configuration:defaultConfiguration('orb')};
 return {db,plane,account,access:session.accessToken,keys,pair,installation,request};
}
test('cloud address keeps function prefix; rejects credentials, query, plaintext and arbitrary path',()=>{
 assert.equal(controlLocation(CLOUD_CONTROL),CLOUD_CONTROL);assert.equal(controlLocation('http://localhost:4321'),'http://localhost:4321');
 for(const value of ['http://example.com','https://u:p@host','https://host/?redirect=evil','https://host/random','https://host/functions/v1/stratum-control/../../evil'])assert.throws(()=>controlLocation(value));
});
test('Postgres placeholders ignore quoted question marks; aliases and sequence increments preserve policy',()=>{
 assert.deepEqual(postgresQuery("SELECT '?' AS token,s.id AS sessionId WHERE id=?",['a']),{sql:"SELECT '?' AS token,s.id AS \"sessionId\" WHERE id=$1",args:['a']});
 assert.throws(()=>postgresQuery('SELECT ?',[]));
 assert.match(postgresQuery('UPDATE ea_sequences SET sequence=sequence+1').sql,/ea_sequences.sequence/);
});
test('nested atomic mutations roll back independently of request authentication',async()=>{
 const commands=[],store=new PostgresStore({async unsafe(sql){commands.push(sql);return [];}});
 await assert.rejects(()=>store.atomic(async()=>{throw new Error('abort');}),/abort/);
 assert.deepEqual(commands,['SAVEPOINT stratum_1','ROLLBACK TO SAVEPOINT stratum_1','RELEASE SAVEPOINT stratum_1']);
});
test('async policy preserves personal identity, session arrays and settings upsert',async()=>{
 const f=await fixture();try{
 await f.plane.setDisplayName(f.account,'Cem');const s=await f.plane.sessionInfo(f.access);
 assert.equal(s.displayName,'Cem');assert.ok(Array.isArray(s.installations));assert.equal(s.trading.enabled,false);
 const c=defaultConfiguration('orb');c.runtime.targetR=.1;await f.plane.saveStrategy(f.access,c);
 assert.deepEqual(await f.plane.strategies(f.access),[c]);
 }finally{f.db.db.close();}
});
test('async policy retains scope, signature, nonce replay and per-owner job isolation',async()=>{
 const f=await fixture();try{
 const proof=makeProof(f.installation.id,'POST','/v1/device/heartbeat',{},f.keys.privateKey);
 await f.plane.authenticateDevice(proof,'POST',proof.path,{});
 await assert.rejects(()=>f.plane.authenticateDevice(proof,'POST',proof.path,{}),e=>e.code==='PROOF_REPLAY');
 const job=await f.plane.createJob(f.access,f.request);assert.equal(job.configurationHash,hash(f.request.configuration));
 const lease=await f.plane.heartbeat(f.installation);assert.ok(verifySigned(lease,f.plane.signingKey.publicKey));
 const claimed=await f.plane.claim(f.installation);assert.equal(claimed.job.payload.liveTradingAllowed,false);
 const other=await f.plane.issueBrowserSession(await f.plane.provisionAccount());
 await assert.rejects(()=>f.plane.readJob(other.accessToken,job.id),e=>e.code==='JOB_NOT_FOUND');
 await assert.rejects(()=>f.plane.setTrading(f.access,{installationId:f.installation.id,enabled:true,jobId:job.id}),e=>e.code==='AUDIT_REQUIRED');
 }finally{f.db.db.close();}
});
test('cloud Fetch handler requires real bearer authority, exact origin and validated personal package',async()=>{
 const f=await fixture();try{
 const handler=controlHttp(f.plane,{agent:{status:()=>({available:false})}});
 const get=(path,token,origin='https://cemkaaa.github.io')=>handler.fetch(new Request('https://project.supabase.co/stratum-control'+path,{headers:{Origin:origin,...(token?{Authorization:'Bearer '+token}:{})}}),path,'test');
 assert.equal((await get('/v1/session')).status,401);
 assert.equal((await get('/v1/session',f.access,'https://evil.test')).status,403);
 const good=await get('/v1/session',f.access);assert.equal(good.status,200);assert.equal((await good.json()).displayName,'Abone');
 const bundle=await personalPackage(f.plane,f.access,CLOUD_CONTROL,()=>({binary:Buffer.from('verified binary'),worker:Buffer.from('verified worker')}),async()=>Buffer.from('helper'),'https://cemkaaa.github.io');
 assert.ok(bundle.bytes.includes(Buffer.from(CLOUD_CONTROL)));assert.ok(bundle.bytes.includes(Buffer.from('https://cemkaaa.github.io')));
 }finally{f.db.db.close();}
});
