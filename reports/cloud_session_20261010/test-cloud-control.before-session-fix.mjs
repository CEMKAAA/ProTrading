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
import { spawnSync } from 'node:child_process';

test('deployable cloud bundle boots with a Deno window alias but no browser location',()=>{
 const result=spawnSync(process.execPath,['--input-type=module','-e',"globalThis.window={}; await import('./supabase/functions/stratum-control/control-bundle.mjs');"],{
  cwd:new URL('../',import.meta.url),encoding:'utf8',timeout:10000,
 });
 assert.equal(result.status,0,result.stderr);
});

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

test('batched session snapshot equals canonical policy, including stale authority and controller scope',async()=>{
 const f=await fixture();try{
  const at=Date.now();f.plane.now=()=>at;
  await f.plane.setDisplayName(f.account,'Poll QA');
  await f.plane.run('INSERT INTO account_trials VALUES(?,?,?)',f.account,at-1000,at+30*86400000-1000);
  await f.plane.run('INSERT INTO supabase_accounts VALUES(?,?,?)',f.account,'poll@example.com',at+10000);
  await f.plane.run('INSERT INTO terminal_status VALUES(?,?,?)',f.installation.id,JSON.stringify({symbol:'USDJPYm',trading:false}),at);
  const snapshot=async tokenHash=>{
   const row=await f.db.get(`SELECT s.id AS sessionId,s.account_id AS accountId,s.expires_at AS sessionExpiry,a.disabled,
    a.entitlement_until AS paidUntil,t.starts_at AS trialStartsAt,t.expires_at AS trialExpiresAt,
    r.account_id AS remoteAccountId,r.authority_until AS authorityUntil,r.email,p.display_name AS profileName,i.email AS localEmail,
    l.installation_id AS leaseInstallationId,l.expires_at AS leaseExpiresAt,l.session_id AS leaseSessionId
    FROM sessions s JOIN accounts a ON a.id=s.account_id LEFT JOIN account_trials t ON t.account_id=a.id
    LEFT JOIN supabase_accounts r ON r.account_id=a.id LEFT JOIN account_profiles p ON p.account_id=a.id
    LEFT JOIN identities i ON i.account_id=a.id LEFT JOIN leases l ON l.account_id=a.id WHERE s.token_hash=?`,tokenHash);
   if(!row)return undefined;
   row.trading=await f.plane.tradingInfo(row.accountId);
   row.installations=await f.db.all('SELECT id,label,state,created_at AS createdAt FROM installations WHERE account_id=? ORDER BY created_at DESC',row.accountId);
   row.statuses=(await f.db.all('SELECT installation_id,status_json,at FROM terminal_status WHERE installation_id IN(SELECT id FROM installations WHERE account_id=?)',row.accountId))
    .map(r=>({...JSON.parse(r.status_json),installationId:r.installation_id,reportedAt:r.at}));
   return row;
  };
  for(const update of [()=>{},()=>f.plane.run('UPDATE supabase_accounts SET authority_until=0 WHERE account_id=?',f.account),
   ()=>f.plane.run('UPDATE supabase_accounts SET authority_until=? WHERE account_id=?',at+10000,f.account),
   ()=>f.plane.run('UPDATE leases SET expires_at=0 WHERE account_id=?',f.account),
   ()=>f.plane.run('UPDATE leases SET session_id=? WHERE account_id=?',id(),f.account)]){
   delete f.db.sessionSnapshot;await update();const expected=await f.plane.sessionInfo(f.access);
   f.db.sessionSnapshot=snapshot;assert.deepEqual(await f.plane.sessionInfo(f.access),expected);
  }
  await assert.rejects(()=>f.plane.sessionInfo('x'.repeat(43)),e=>e.code==='UNAUTHORIZED');
  await f.plane.run('UPDATE accounts SET disabled=1 WHERE id=?',f.account);
  await assert.rejects(()=>f.plane.sessionInfo(f.access),e=>e.code==='UNAUTHORIZED');
 }finally{f.db.db.close();}
});

test('Postgres authority sync and session snapshot use one statement each without widening owner scope',async()=>{
 const calls=[],db=new PostgresStore({async unsafe(sql,args){calls.push({sql,args});return Object.assign([],{count:0});}});
 const v={accountId:id(),paidUntil:0,disabled:0,startsAt:1,expiresAt:2,name:'Quant',email:'qa@example.com',authorityUntil:10,accessActive:0};
 await db.syncAuthority(v);assert.equal(calls.length,1);assert.equal(calls[0].args.length,9);
 assert.match(calls[0].sql,/UPDATE trading SET enabled=0,revision=revision\+1/);assert.match(calls[0].sql,/AND \$9=0/);
 await db.sessionSnapshot('token-hash');assert.equal(calls.length,2);assert.deepEqual(calls[1].args,['token-hash']);
 assert.match(calls[1].sql,/WHERE s\.token_hash=\$1/);assert.match(calls[1].sql,/owned\.account_id=a\.id/);
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
