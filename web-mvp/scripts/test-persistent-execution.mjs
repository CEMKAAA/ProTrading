import assert from 'node:assert/strict';
import { test } from 'node:test';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { randomBytes } from 'node:crypto';
import { ControlPlane as LocalPlane } from '../control-service/control-plane.mjs';
import { ControlPlane as CloudPlane } from '../control-service/cloud/generated/control-plane.mjs';
import { SupabaseAuth as LocalAuth } from '../control-service/supabase-auth.mjs';
import { SupabaseAuth as CloudAuth } from '../control-service/cloud/generated/supabase-auth.mjs';
import { PostgresStore } from '../control-service/cloud/postgres-store.mjs';
import { hash, id, keyPair, makeProof } from '../control-service/crypto.mjs';
import { verifyEaCommand } from '../control-service/ea-authority.mjs';
import { defaultConfiguration } from '../lib/universal-contract.ts';

const DAY=86400000, HOUR=3600000;
function asyncStore() {
  const db=new DatabaseSync(':memory:');
  db.exec(readFileSync(new URL('../control-service/schema.sql',import.meta.url),'utf8'));
  let sequence=0;
  return {db,
    async get(sql,...args){return db.prepare(sql).get(...args);},
    async all(sql,...args){return db.prepare(sql).all(...args);},
    async run(sql,...args){return db.prepare(sql).run(...args);},
    async atomic(work){const name='persistent_'+(++sequence);db.exec('SAVEPOINT '+name);
      try{const r=await work();db.exec('RELEASE '+name);return r;}
      catch(e){db.exec('ROLLBACK TO '+name);db.exec('RELEASE '+name);throw e;}}
  };
}
async function fixture(cloud,{live=true,provider=false}={}) {
  let at=Date.UTC(2026,9,11,12),privateReads=0;
  const store=cloud?asyncStore():null;
  const p=cloud?new CloudPlane({db:store,now:()=>at}):new LocalPlane({now:()=>at});
  const account=await p.provisionAccount(id(),at+40*DAY);
  const session=await p.issueBrowserSession(account,12*HOUR);
  const keys=keyPair(),pair=await p.beginPairing({publicKey:keys.publicKey,label:'Persistent execution QA'});
  await p.approvePairing(session.accessToken,pair.code,pair.fingerprint);
  const lease=await p.activate(session.accessToken,pair.installationId);
  const installation={...await p.get('SELECT * FROM installations WHERE id=?',pair.installationId),agentId:id()};
  const configuration=defaultConfiguration('orb');configuration.name='Unchanged approved configuration';configuration.runtime.targetR=.1;
  const request={version:2,installationId:installation.id,idempotencyKey:id(),symbol:'USDJPYm',brokerServer:'Exness-MT5Trial15',
    fromUtc:new Date(at-14*DAY).toISOString(),toUtc:new Date(at).toISOString(),auditWeeks:2,
    dataPolicy:'existing_audit_semantics',configuration};
  const job=await p.createJob(session.accessToken,request),ticket=(await p.claim(installation)).job.payload;
  await p.finish(installation,{jobId:job.id,attemptId:ticket.attemptId,configurationHash:ticket.configurationHash,requestHash:ticket.requestHash,
    engineRuntime:'universal-adapter/v2',auditBuild:'fixture-only-not-a-broker-execution',symbol:request.symbol,brokerServer:request.brokerServer,
    coverage:{datasetFingerprint:hash('fixture'),realTicks:0,generatedTicks:0,missingIntervals:[],mode:'existing_audit'},
    trades:[{id:'1',direction:'BUY',signalUtc:request.fromUtc,entryUtc:request.fromUtc,exitUtc:new Date(at-13*DAY).toISOString(),
      entryPrice:1.1,exitPrice:1.1009,sl:1.099,tp:1.101,outcome:'WIN',exitReason:'TP',netR:.9,
      spreadPrice:.0001,slippagePrice:null,commission:null,swap:null}]});
  const status={symbol:request.symbol,brokerServer:request.brokerServer,accountLogin:'123',runtime:'universal-adapter/v2',build:'fixture',
    openPositions:0,trading:false,configurationHash:job.configurationHash,error:''};
  const terminal=()=>p.terminalStatus(installation,status);
  await terminal();await p.connectAgent(installation);
  if(live)await p.setTrading(session.accessToken,{installationId:installation.id,jobId:job.id,enabled:true});
  const state={accountId:account,email:'qa@example.com',displayName:'QA subscriber',disabled:false,accessActive:true,accessMode:'demo',paidUntil:0,
    serverNow:at,trial:{startsAt:at,expiresAt:at+30*DAY}};
  let readFailure=null,readOverride;
  const db=store??p.db;
  db.deviceAccess=async requested=>{assert.equal(requested,account);privateReads++;if(readFailure)throw readFailure;
    return readOverride===undefined?{...state,serverNow:at}:readOverride;};
  const Auth=cloud?CloudAuth:LocalAuth;
  const auth=new Auth(p,{url:'https://project.supabase.co',publishableKey:'sb_publishable_qa',encryptionKey:randomBytes(32),
    fetcher:async()=>{throw Error('Browser JWT must not be refreshed for durable execution');}});
  if(provider)await auth.sync(state);
  return {p,db,auth,state,account,session,keys,lease,installation,request,job,status,terminal,
    time:()=>at,advance:ms=>{at+=ms;},setReadFailure:value=>{readFailure=value;},setReadOverride:value=>{readOverride=value;},reads:()=>privateReads,
    async close(){if(store)store.db.close();else p.close();}};
}
async function rejects(fn,code){await assert.rejects(async()=>fn(),e=>e.code===code);}
function fields(command){return Object.fromEntries(command.split('\n').filter(x=>x.includes('=')).map(x=>{const i=x.indexOf('=');return [x.slice(0,i),x.slice(i+1)];}));}

for(const cloud of [false,true]) {
  const name=cloud?'cloud async':'local canonical';
  test(`${name}: explicit live consent survives 12h timeout and helper restart with identical config`,async()=>{
    const f=await fixture(cloud);
    try{
      const before=await f.p.eaCommand(f.installation,{jobId:null,attemptId:null});
      f.advance(13*HOUR);
      await rejects(()=>f.p.browser(f.session.accessToken),'UNAUTHORIZED');
      await f.p.connectAgent(f.installation);await f.p.heartbeat(f.installation);await f.terminal();
      const after=await f.p.eaCommand(f.installation,{jobId:null,attemptId:null});
      assert.ok(verifyEaCommand(after.payload.command,f.p.eaSigningKey.publicKey));
      const a=fields(before.payload.command),b=fields(after.payload.command);
      assert.equal(b.command,'live');assert.equal(b.generation,a.generation);assert.equal(b.configurationHash,a.configurationHash);
      assert.equal(Number(b.expires)-Number(b.issued),15);assert.ok(Number(b.sequence)>Number(a.sequence));
      assert.equal((await f.p.operation(f.installation)).payload.request.configuration.runtime.targetR,.1);
      assert.match((await f.p.eaIdentity(f.installation,{symbol:f.status.symbol,brokerServer:f.status.brokerServer,accountLogin:f.status.accountLogin})).payload.certificate,/controllerActive=true/);
    }finally{await f.close();}
  });
  test(`${name}: research-only approval never becomes durable automatically`,async()=>{
    const f=await fixture(cloud,{live:false});
    try{f.advance(13*HOUR);assert.equal(await f.p.durableOperation(f.installation),null);
      await rejects(()=>f.p.connectAgent(f.installation),'CONTROLLER_LEASE_EXPIRED');
    }finally{await f.close();}
  });
  test(`${name}: same-device web reauthorization preserves live job and fences old browser`,async()=>{
    const f=await fixture(cloud);
    try{const session=await f.p.issueBrowserSession(f.account,12*HOUR);
      const lease=await f.p.activate(session.accessToken,f.installation.id);
      assert.equal(lease.generation,f.lease.generation);assert.equal((await f.p.tradingInfo(f.account)).enabled,true);
      await rejects(()=>f.p.createJob(f.session.accessToken,{...f.request,idempotencyKey:id()}),'NOT_ACTIVE_CONTROLLER');
      assert.equal((await f.p.eaCommand(f.installation,{jobId:null,attemptId:null})).payload.command.startsWith('command=live\n'),true);
      await f.p.setTrading(session.accessToken,{installationId:f.installation.id,enabled:false,jobId:null});
      assert.equal((await f.p.eaCommand(f.installation,{jobId:null,attemptId:null})).payload.command,null);
    }finally{await f.close();}
  });
  test(`${name}: OFF after expired browser stops consent; login alone cannot resume`,async()=>{
    const f=await fixture(cloud);
    try{f.advance(13*HOUR);const session=await f.p.issueBrowserSession(f.account);
      await f.p.setTrading(session.accessToken,{installationId:f.installation.id,enabled:false,jobId:null});
      assert.equal(await f.p.durableOperation(f.installation),null);
      await rejects(()=>f.p.connectAgent(f.installation),'CONTROLLER_LEASE_EXPIRED');
    }finally{await f.close();}
  });
  test(`${name}: explicit logout removes live authority`,async()=>{
    const f=await fixture(cloud);
    try{await f.p.logout(f.session.accessToken);assert.equal(await f.p.durableOperation(f.installation),null);
      await rejects(()=>f.p.eaCommand(f.installation,{jobId:null,attemptId:null}),'CONTROLLER_LEASE_EXPIRED');
    }finally{await f.close();}
  });
  test(`${name}: new audit disables consent before settings can change`,async()=>{
    const f=await fixture(cloud);
    try{await f.p.createJob(f.session.accessToken,{...f.request,idempotencyKey:id()});
      assert.equal(await f.p.durableOperation(f.installation),null);
      assert.equal((await f.p.eaCommand(f.installation,{jobId:null,attemptId:null})).payload.command,null);
    }finally{await f.close();}
  });
  test(`${name}: device takeover and revocation do not inherit consent`,async()=>{
    const f=await fixture(cloud);
    try{const pair=await f.p.beginPairing({publicKey:keyPair().publicKey,label:'Other device'});
      await f.p.approvePairing(f.session.accessToken,pair.code,pair.fingerprint);
      const lease=await f.p.activate(f.session.accessToken,pair.installationId);assert.notEqual(lease.generation,f.lease.generation);
      assert.equal(await f.p.durableOperation(f.installation),null);
      await rejects(()=>f.p.heartbeat(f.installation),'CONTROLLER_LEASE_EXPIRED');
      await f.p.revokeInstallation(f.session.accessToken,f.installation.id);
      await rejects(()=>f.p.authenticateDevice(makeProof(f.installation.id,'POST','/v1/device/identity',{},f.keys.privateKey,f.time(),id()),'POST','/v1/device/identity',{}),'INSTALLATION_REVOKED_OR_UNKNOWN');
    }finally{await f.close();}
  });
  test(`${name}: expired subscription and mismatched job/generation fail closed`,async()=>{
    const f=await fixture(cloud);
    try{await f.p.run('UPDATE trading SET generation=? WHERE account_id=?',id(),f.account);
      assert.equal(await f.p.durableOperation(f.installation),null);
      await f.p.run('UPDATE trading SET generation=? WHERE account_id=?',f.lease.generation,f.account);
      await f.p.provisionAccount(f.account,f.time()-1);
      await rejects(()=>f.p.connectAgent(f.installation),'ENTITLEMENT_EXPIRED');
    }finally{await f.close();}
  });
  test(`${name}: cloned second helper stays blocked after browser expiry`,async()=>{
    const f=await fixture(cloud);
    try{f.advance(13*HOUR);await f.p.connectAgent(f.installation);await f.p.heartbeat(f.installation);
      await rejects(()=>f.p.connectAgent({...f.installation,agentId:id()}),'AGENT_ALREADY_CONNECTED');
      const path='/v1/device/command',proof=makeProof(f.installation.id,'POST',path,{},f.keys.privateKey,f.time(),f.installation.agentId);
      await f.p.authenticateDevice(proof,'POST',path,{});
      await rejects(()=>f.p.authenticateDevice(proof,'POST',path,{}),'PROOF_REPLAY');
    }finally{await f.close();}
  });
  test(`${name}: durable provider checks use private account data, not expired browser JWT`,async()=>{
    const f=await fixture(cloud,{provider:true});
    try{f.advance(13*HOUR);await f.auth.forDevice(f.installation,'/v1/device/connect');await f.p.connectAgent(f.installation);
      await f.auth.forDevice(f.installation,'/v1/device/heartbeat');await f.p.heartbeat(f.installation);await f.terminal();
      const command=await f.p.eaCommand(f.installation,{jobId:null,attemptId:null});
      assert.equal(fields(command.payload.command).command,'live');assert.equal(f.reads(),2);
      assert.ok(command.payload.expiresAt>f.time());assert.ok(command.payload.expiresAt<=f.time()+10000);
      await rejects(()=>f.p.browser(f.session.accessToken),'UNAUTHORIZED');
    }finally{await f.close();}
  });
  test(`${name}: denied/missing provider state revokes consent; returning subscription cannot auto-enable`,async()=>{
    for(const missing of [false,true]){
      const f=await fixture(cloud,{provider:true});
      try{f.advance(13*HOUR);
        if(missing)f.setReadOverride(null);else {f.state.disabled=true;f.state.accessActive=false;f.state.accessMode='inactive';}
        if(missing)await rejects(()=>f.auth.forDevice(f.installation,'/v1/device/heartbeat'),'PROVIDER_ACCOUNT_REQUIRED');
        else await f.auth.forDevice(f.installation,'/v1/device/heartbeat');
        assert.equal((await f.p.tradingInfo(f.account)).enabled,false);assert.equal(await f.p.durableOperation(f.installation),null);
        await rejects(()=>f.p.currentLease(f.installation),'ENTITLEMENT_EXPIRED');
      }finally{await f.close();}
    }
  });
  test(`${name}: temporary database failure pauses renewal without destroying explicit consent`,async()=>{
    const f=await fixture(cloud,{provider:true});
    try{f.advance(13*HOUR);f.setReadFailure(Error('private database offline'));
      await assert.rejects(()=>f.auth.forDevice(f.installation,'/v1/device/heartbeat'),/database offline/);
      assert.equal((await f.p.tradingInfo(f.account)).enabled,true);
      await rejects(()=>f.p.currentLease(f.installation),'ENTITLEMENT_EXPIRED');
      f.setReadFailure(null);await f.auth.forDevice(f.installation,'/v1/device/connect');await f.p.connectAgent(f.installation);
      assert.equal((await f.p.operation(f.installation)).payload.liveTradingAllowed,true);
    }finally{await f.close();}
  });
  test(`${name}: crossed or stale provider response cannot renew a signed command`,async()=>{
    const f=await fixture(cloud,{provider:true});
    try{f.advance(13*HOUR);f.setReadOverride({...f.state,serverNow:f.time(),accountId:id()});
      await rejects(()=>f.auth.forDevice(f.installation,'/v1/device/heartbeat'),'SESSION_SCOPE_MISMATCH');
      await rejects(()=>f.p.currentLease(f.installation),'ENTITLEMENT_EXPIRED');
      f.setReadOverride({...f.state,serverNow:f.time()-60000});
      await rejects(()=>f.auth.forDevice(f.installation,'/v1/device/heartbeat'),'AUTH_CLOCK_OR_TRIAL_INVALID');
    }finally{await f.close();}
  });
}

test('private SQL validates current paid/demo entitlement, confirmed identity, account ban and deletion',async()=>{
  let statement,parameters;const state={accountId:id()};
  const store=new PostgresStore({async unsafe(sql,args){statement=sql;parameters=args;return [{state}];}});
  assert.equal(await store.deviceAccess(state.accountId),state);
  assert.deepEqual(parameters,[state.accountId]);assert.match(statement,/WHERE a.user_id=\$1::uuid/);
  for(const marker of ['stratum_private.accounts','stratum_private.trial_claims','auth.users','email_confirmed_at','banned_until','deleted_at','paid_until','expires_at'])assert.ok(statement.includes(marker),marker);
  assert.ok(!statement.includes('user_metadata'));assert.ok(!statement.includes('auth.sessions'));
});
