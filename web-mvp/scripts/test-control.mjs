import assert from "node:assert/strict";
import { test } from "node:test";
import { mkdtempSync, rmSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { once } from "node:events";
import { ControlPlane } from "../control-service/control-plane.mjs";
import { controlHttp } from "../control-service/http.mjs";
import { DeviceClient } from "../control-service/device-client.mjs";
import { keyPair, id, hash, makeProof, verifySigned, signed } from "../control-service/crypto.mjs";
import { exampleRequest } from "../lib/control-example.ts";
import { configurationSchema, resultSchema, summarizeResult } from "../lib/control-contract.ts";
import { defaultConfiguration, universalConfigurationSchema, universalRequestSchema } from "../lib/universal-contract.ts";
import { commandBody, packet, unpack, parseResult } from "../control-service/mt5-agent.mjs";
import { verifyEaCommand, eaKeyPair } from "../control-service/ea-authority.mjs";

const forbidden = (work, code) => assert.throws(work, error => error.code === code);
function universal(f, family="orb") {
  f.request={version:2,installationId:f.installation.id,idempotencyKey:id(),brokerServer:"Exness-MT5Trial15",symbol:"JP225m",
    fromUtc:new Date(f.time()-14*86400000).toISOString(),toUtc:new Date(f.time()).toISOString(),auditWeeks:2,
    dataPolicy:"existing_audit_semantics",configuration:defaultConfiguration(family)};
  f.create=()=>f.plane.createJob(f.access,f.request);
  return f;
}

test('all four complete input catalogs validate; missing/unknown values fail closed',()=>{
 for(const family of ['orb','macross','sol','entrylab']){
  const c=defaultConfiguration(family);assert.equal(universalConfigurationSchema.safeParse(c).success,true,family);
  const missing=structuredClone(c);delete missing.inputs[Object.keys(missing.inputs)[0]];assert.equal(universalConfigurationSchema.safeParse(missing).success,false);
  assert.equal(universalConfigurationSchema.safeParse({...c,runtime:{...c.runtime,execute:'BUY'}}).success,false);
 }
});
test('line protocol cannot be injected through strategy name or broker server',()=>{
 const f=universal(fixture());
 assert.equal(universalConfigurationSchema.safeParse({...f.request.configuration,name:'x\ncommand=live'}).success,false);
 assert.equal(universalRequestSchema.safeParse({...f.request,brokerServer:'x\ncommand=live'}).success,false);f.plane.close();
});
test('new registrations get one 30-day demo; password authentication is real',()=>{
 const plane=new ControlPlane();const a=plane.register({email:'first@example.com',password:'a-long-private-password'});
 const s=plane.sessionInfo(a.accessToken);assert.equal(s.subscriptionActive,true);assert.equal(s.accessMode,'demo');assert.equal(s.trial.daysRemaining,30);
 assert.deepEqual(plane.strategies(a.accessToken),[]);
 forbidden(()=>plane.login({email:'first@example.com',password:'wrong'}),'INVALID_CREDENTIALS');
 assert.equal(plane.browser(plane.login({email:'first@example.com',password:'a-long-private-password'}).accessToken).accountId,plane.browser(a.accessToken).accountId);plane.close();
});
test('subscriber names persist and cannot inject a command line',()=>{
 const plane=new ControlPlane();const a=plane.register({email:'named@example.com',password:'a-long-private-password',displayName:'Cem Quant'});
 assert.equal(plane.sessionInfo(a.accessToken).displayName,'Cem Quant');
 forbidden(()=>plane.register({email:'bad@example.com',password:'a-long-private-password',displayName:'Cem\ncommand=live'}),'INVALID_REQUEST');
 plane.close();
});
test('identity is server-signed, read-only and reports actual subscription expiry',()=>{
 const f=fixture();f.plane.setDisplayName(f.account,'Cem Quant');
 const body={symbol:'JP225m',brokerServer:'Exness-MT5Trial15',accountLogin:'123'};
 const proof=makeProof(f.installation.id,'POST','/v1/device/identity',body,f.keys.privateKey,f.time(),id());
 const installed=f.plane.authenticateDevice(proof,'POST',proof.path,body);
 let result=f.plane.eaIdentity(installed,body);assert.ok(verifyEaCommand(result.payload.certificate,f.plane.eaSigningKey.publicKey));
 assert.ok(result.payload.certificate.includes('subscriberName=Cem Quant\nsubscriptionActive=true'));
 assert.ok(result.payload.certificate.includes('command=identity'));assert.equal(result.payload.liveTradingAllowed,false);
 f.advance(86400001);
 const next=makeProof(f.installation.id,'POST','/v1/device/identity',body,f.keys.privateKey,f.time(),id());
 result=f.plane.eaIdentity(f.plane.authenticateDevice(next,'POST',next.path,body),body);
 assert.ok(result.payload.certificate.includes('subscriptionActive=false'));assert.ok(result.payload.certificate.includes('controllerActive=false'));
 forbidden(()=>f.plane.heartbeat(installed),'ENTITLEMENT_EXPIRED');f.plane.close();
});
test('identity endpoint still requires a device signature and rejects revoked installations',()=>{
 const f=fixture(),body={symbol:'JP225m',brokerServer:'Exness-MT5Trial15',accountLogin:'123'};
 const proof=makeProof(f.installation.id,'POST','/v1/device/identity',body,f.keys.privateKey,f.time(),id());
 const forged=makeProof(f.installation.id,'POST','/v1/device/identity',body,keyPair().privateKey,f.time(),proof.agentId);
 forbidden(()=>f.plane.authenticateDevice(forged,'POST',proof.path,body),'INVALID_SIGNATURE');
 f.plane.revokeInstallation(f.access,f.installation.id);
 forbidden(()=>f.plane.authenticateDevice(proof,'POST',proof.path,body),'INSTALLATION_REVOKED_OR_UNKNOWN');f.plane.close();
});
test('strategy upsert restores every setting; other subscribers cannot see it',()=>{
 const f=universal(fixture(),'entrylab'),c=f.request.configuration;c.name='My exact setup';c.runtime.maxOpen=20;c.runtime.nasGate=2;c.runtime.nasFlowMultiplier=1.5;c.runtime.timeMatrixEnabled=true;c.dayHourMasks[1]=1<<13;
 f.plane.saveStrategy(f.access,c);c.runtime.maxOpen=10;f.plane.saveStrategy(f.access,c);
 assert.deepEqual(f.plane.strategies(f.access),[c]);const other=f.plane.issueBrowserSession(f.plane.provisionAccount());assert.deepEqual(f.plane.strategies(other.accessToken),[]);f.plane.close();
});
test('Apply is research-only; Trading ON requires a complete result and recent matching terminal',()=>{
 const f=universal(fixture());const job=f.create(),ticket=f.claim();
 assert.equal(f.plane.operation(f.installation).payload.liveTradingAllowed,false);
 forbidden(()=>f.plane.setTrading(f.access,{installationId:f.installation.id,enabled:true,jobId:job.id}),'AUDIT_REQUIRED');
 const result=resultFor(f,ticket);result.engineRuntime='universal-adapter/v2';result.coverage.mode='existing_audit';f.plane.finish(f.installation,result);
 forbidden(()=>f.plane.setTrading(f.access,{installationId:f.installation.id,enabled:true,jobId:job.id}),'TERMINAL_OFFLINE');
 f.plane.terminalStatus(f.installation,{symbol:f.request.symbol,brokerServer:f.request.brokerServer,accountLogin:'123',runtime:'universal-adapter/v2',build:'test-fixture',openPositions:0,trading:false,configurationHash:'',error:''});
 assert.equal(f.plane.setTrading(f.access,{installationId:f.installation.id,enabled:true,jobId:job.id}).enabled,true);
 assert.equal(f.plane.operation(f.installation).payload.liveTradingAllowed,true);
 f.advance(20000);assert.equal(f.plane.setTrading(f.access,{installationId:f.installation.id,enabled:false,jobId:null}).enabled,false);f.plane.close();
});
test('a newer Apply disables Trading; logout revokes authorization',()=>{
 const f=universal(fixture());const job=f.create(),ticket=f.claim(),r=resultFor(f,ticket);r.engineRuntime='universal-adapter/v2';r.coverage.mode='existing_audit';f.plane.finish(f.installation,r);
 f.plane.terminalStatus(f.installation,{symbol:f.request.symbol,brokerServer:f.request.brokerServer,accountLogin:'123',runtime:'universal-adapter/v2',build:'test-fixture',openPositions:0,trading:false,configurationHash:'',error:''});
 f.plane.setTrading(f.access,{installationId:f.installation.id,enabled:true,jobId:job.id});f.advance(1);f.request.idempotencyKey=id();f.create();
 assert.equal(f.plane.operation(f.installation).payload.liveTradingAllowed,false);f.plane.logout(f.access);forbidden(()=>f.plane.operation(f.installation),'CONTROLLER_LEASE_EXPIRED');f.plane.close();
});
test('local HMAC rejects tampering, binds settings and preserves DATA / actual R',()=>{
 const f=universal(fixture()),job=f.create(),ticket=f.claim(),key='0123456789abcdef0123456789abcdef';
 const body=commandBody('audit',ticket);assert.equal(unpack(packet(body,key),key).fields.command,'audit');assert.throws(()=>unpack(packet(body,key).replace('command=audit','command=live'),key));
 const at=Date.parse(f.request.fromUtc)/1000;
 const text=`jobId=${job.id}\nattemptId=${ticket.attemptId}\nconfigurationHash=${ticket.configurationHash}\nrequestHash=${ticket.requestHash}\nrows=2\nTRADES\n${at}|${at}|${at+60}|1|1.1|1.099|1.101|1.1009|0.9|1|1|TP|0.0001\n${at}|${at}|0|-1|1.1|1.101|1.099|0|0|0|0|DATA|\n`;
 const r=parseResult(packet(text,key),key,ticket);assert.equal(r.trades[0].netR,.9);assert.equal(r.trades[1].outcome,'DATA');assert.equal(r.trades[1].netR,null);assert.equal(resultSchema.safeParse(r).success,true);f.plane.close();
});
function fixture(options = {}) {
  let time = Date.UTC(2026, 9, 4, 12);
  const signingKey = keyPair(), plane = new ControlPlane({ ...options, signingKey, now: () => time });
  const account = plane.provisionAccount(), access = plane.issueBrowserSession(account).accessToken;
  const keys = keyPair(), pair = plane.beginPairing({ publicKey: keys.publicKey, label: "Test terminal" });
  plane.approvePairing(access, pair.code, pair.fingerprint);
  plane.activate(access, pair.installationId);
  const installation = plane.get("SELECT * FROM installations WHERE id=?", pair.installationId);
  const request = exampleRequest(installation.id, id(), time);
  return { plane, account, access, keys, signingKey, installation, pair, request,
    time: () => time, advance: ms => { time += ms; }, create: () => plane.createJob(access, request), claim: () => plane.claim(installation).job.payload };
}
function resultFor(f, ticket) {
  return { jobId: ticket.jobId, attemptId: ticket.attemptId, configurationHash: ticket.configurationHash, requestHash: ticket.requestHash,
    engineRuntime: "entrylab-adapter/v1", auditBuild: "fixture-only-not-market-data", brokerServer: f.request.brokerServer, symbol: f.request.symbol,
    coverage: { datasetFingerprint: hash("fixture"), realTicks: 123, generatedTicks: 0, missingIntervals: [] },
    trades: [{ id: "1", direction: "BUY", signalUtc: f.request.fromUtc, entryUtc: f.request.fromUtc, exitUtc: new Date(Date.parse(f.request.fromUtc) + 60000).toISOString(),
      entryPrice: 1.1, exitPrice: 1.1009, sl: 1.099, tp: 1.101, outcome: "WIN", exitReason: "TP", netR: .9, spreadPrice: .0001, slippagePrice: null, commission: null, swap: null }] };
}

function reportTerminal(f) {
  f.plane.terminalStatus(f.installation,{symbol:f.request.symbol,brokerServer:f.request.brokerServer,accountLogin:'123',
    runtime:'universal-adapter/v2',build:'test-fixture',openPositions:0,trading:false,configurationHash:'',error:''});
}
test('EA authority is server-signed: knowing the local HMAC key cannot grant live trading',()=>{
  const f=universal(fixture());f.create();const ticket=f.claim();reportTerminal(f);
  const command=f.plane.eaCommand(f.installation,{jobId:ticket.jobId,attemptId:ticket.attemptId}).payload.command;
  assert.ok(verifyEaCommand(command,f.plane.eaSigningKey.publicKey));
  assert.equal(verifyEaCommand(command.replace('command=audit','command=live'),f.plane.eaSigningKey.publicKey),false);
  assert.equal(verifyEaCommand(packet(commandBody('live',ticket),'0123456789abcdef0123456789abcdef'),f.plane.eaSigningKey.publicKey),false);
  assert.equal(verifyEaCommand(command,eaKeyPair().publicKey),false);f.plane.close();
});
test('EA signed command binds device, MT5 login, exact configuration and increasing replay fence',()=>{
  const f=universal(fixture());f.create();const ticket=f.claim();reportTerminal(f);
  const get=()=>f.plane.eaCommand(f.installation,{jobId:ticket.jobId,attemptId:ticket.attemptId}).payload.command;
  const first=get(),second=get(),fields=Object.fromEntries(first.split('\n').map(s=>s.split('=')));
  assert.equal(fields.installationId,f.installation.id);assert.equal(fields.accountLogin,'123');
  assert.equal(fields.configurationHash,ticket.configurationHash);assert.equal(fields.attemptId,ticket.attemptId);
  assert.equal(Number(fields.expires)-Number(fields.issued),15);
  assert.ok(second.includes('sequence=2\n'));f.plane.close();
});
test('EA command never authorizes live before explicit Trading ON and stops on OFF',()=>{
  const f=universal(fixture());const job=f.create(),ticket=f.claim();reportTerminal(f);
  const idle=()=>f.plane.eaCommand(f.installation,{jobId:null,attemptId:null}).payload.command;
  assert.equal(idle(),null);const r=resultFor(f,ticket);r.engineRuntime='universal-adapter/v2';r.coverage.mode='existing_audit';f.plane.finish(f.installation,r);
  assert.equal(idle(),null);f.plane.setTrading(f.access,{installationId:f.installation.id,jobId:job.id,enabled:true});
  assert.ok(idle().startsWith('command=live\n'));f.plane.setTrading(f.access,{installationId:f.installation.id,jobId:null,enabled:false});
  assert.equal(idle(),null);f.plane.close();
});
test('stale terminal, changed market, cancelled job and expired entitlement cannot obtain EA grants',()=>{
  const f=universal(fixture());const job=f.create(),ticket=f.claim();const get=()=>f.plane.eaCommand(f.installation,{jobId:ticket.jobId,attemptId:ticket.attemptId});
  forbidden(get,'TERMINAL_OFFLINE');reportTerminal(f);f.advance(15001);forbidden(get,'TERMINAL_OFFLINE');reportTerminal(f);
  f.plane.cancelJob(f.access,job.id);forbidden(get,'STALE_JOB_ATTEMPT');
  f.plane.provisionAccount(f.account,f.time()-1);forbidden(get,'ENTITLEMENT_EXPIRED');f.plane.close();
});
test('a copied installation key cannot run a second independent agent concurrently',()=>{
  const f=fixture(),agentA=id(),agentB=id();
  const call=(agentId,path)=>f.plane.authenticateDevice(makeProof(f.installation.id,'POST',path,{},f.keys.privateKey,f.time(),agentId),'POST',path);
  f.plane.connectAgent(call(agentA,'/v1/device/connect'));
  forbidden(()=>f.plane.connectAgent(call(agentB,'/v1/device/connect')),'AGENT_ALREADY_CONNECTED');
  forbidden(()=>call(agentB,'/v1/device/command'),'AGENT_SESSION_EXPIRED');
  f.advance(15001);f.plane.connectAgent(call(agentB,'/v1/device/connect'));
  forbidden(()=>call(agentA,'/v1/device/heartbeat'),'AGENT_SESSION_EXPIRED');
  f.plane.heartbeat(call(agentB,'/v1/device/heartbeat'));f.plane.close();
});
test('text-formatted MQL datetime cannot be silently interpreted as an epoch timestamp',()=>{
  const f=universal(fixture());f.create();const ticket=f.claim(),key='0123456789abcdef0123456789abcdef';
  const text=`jobId=${ticket.jobId}\nattemptId=${ticket.attemptId}\nconfigurationHash=${ticket.configurationHash}\nrequestHash=${ticket.requestHash}\nrows=1\nTRADES\n2026.10.06 14:00|2026.10.06 14:00|2026.10.06 14:01|1|1.1|1.099|1.101|1.101|1|1|1|TP|0.0001\n`;
  assert.throws(()=>parseResult(packet(text,key),key,ticket),/LOCAL_RESULT_TIMESTAMP_INVALID/);f.plane.close();
});
test('Sol legacy zero exit price stays unknown, never fabricated from R or OHLC',()=>{
  const f=universal(fixture(),'sol');f.create();const ticket=f.claim(),key='0123456789abcdef0123456789abcdef',at=Date.parse(f.request.fromUtc)/1000;
  const text=`jobId=${ticket.jobId}\nattemptId=${ticket.attemptId}\nconfigurationHash=${ticket.configurationHash}\nrequestHash=${ticket.requestHash}\nrows=1\nTRADES\n${at}|${at}|${at+60}|1|1.1|1.099|1.101|0|1|1|1|TICK_TP|0.0001\n`;
  const result=parseResult(packet(text,key),key,ticket);assert.equal(result.trades[0].exitPrice,null);assert.equal(result.trades[0].netR,1);
  assert.equal(resultSchema.safeParse(result).success,true);result.coverage.mode='real_ticks';assert.equal(resultSchema.safeParse(result).success,false);f.plane.close();
});
test('changing the terminal account disables Trading instead of silently carrying authorization over',()=>{
  const f=universal(fixture());const job=f.create(),ticket=f.claim();reportTerminal(f);
  const r=resultFor(f,ticket);r.engineRuntime='universal-adapter/v2';r.coverage.mode='existing_audit';f.plane.finish(f.installation,r);
  f.plane.setTrading(f.access,{installationId:f.installation.id,jobId:job.id,enabled:true});
  f.plane.terminalStatus(f.installation,{symbol:f.request.symbol,brokerServer:f.request.brokerServer,accountLogin:'456',
    runtime:'universal-adapter/v2',build:'test-fixture',openPositions:0,trading:false,configurationHash:'',error:''});
  assert.equal(f.plane.operation(f.installation).payload.liveTradingAllowed,false);f.plane.close();
});

test("unauthenticated/forged user headers cannot authorize a browser", () => {
  const f = fixture(); forbidden(() => f.plane.sessionInfo("forged"), "UNAUTHORIZED"); f.plane.close();
});
test("pairing is reviewed by fingerprint, expires, and is single-use", () => {
  const f = fixture();
  forbidden(() => f.plane.approvePairing(f.access, f.pair.code, f.pair.fingerprint), "PAIRING_EXPIRED_OR_UNKNOWN");
  const pair = f.plane.beginPairing({ publicKey: keyPair().publicKey, label: "Second" });
  assert.equal(f.plane.reviewPairing(f.access, pair.code).fingerprint, pair.fingerprint);
  forbidden(() => f.plane.approvePairing(f.access, pair.code, hash("wrong")), "PAIRING_FINGERPRINT_CHANGED");
  f.advance(300001); forbidden(() => f.plane.reviewPairing(f.access, pair.code), "PAIRING_EXPIRED_OR_UNKNOWN"); f.plane.close();
});
test("wrong-key device proof, body/path tampering and replay are rejected", () => {
  const f = fixture(), path = "/v1/device/heartbeat";
  const forged = makeProof(f.installation.id, "POST", path, {}, keyPair().privateKey, f.time());
  forbidden(() => f.plane.authenticateDevice(forged, "POST", path, {}), "INVALID_SIGNATURE");
  const proof = makeProof(f.installation.id, "POST", path, {}, f.keys.privateKey, f.time());
  forbidden(() => f.plane.authenticateDevice(proof, "POST", path, { change: 1 }), "PROOF_SCOPE_MISMATCH");
  forbidden(() => f.plane.authenticateDevice(proof, "POST", "/v1/device/claim", {}), "PROOF_SCOPE_MISMATCH");
  assert.equal(f.plane.authenticateDevice(proof, "POST", path).id, f.installation.id);
  forbidden(() => f.plane.authenticateDevice(proof, "POST", path), "PROOF_REPLAY"); f.plane.close();
});
test("device authorization uses current wall time, not a historical candle date", () => {
  const f = fixture();
  const proof = makeProof(f.installation.id, "POST", "/v1/device/heartbeat", {}, f.keys.privateKey, f.time() - 31000);
  forbidden(() => f.plane.authenticateDevice(proof, "POST", proof.path), "PROOF_EXPIRED"); f.plane.close();
});
test("pending installations cannot request jobs", () => {
  const f = fixture(), keys = keyPair(), pair = f.plane.beginPairing({ publicKey: keys.publicKey, label: "Pending" });
  const proof = makeProof(pair.installationId, "POST", "/v1/device/claim", {}, keys.privateKey, f.time());
  forbidden(() => f.plane.authenticateDevice(proof, "POST", proof.path), "PAIRING_REQUIRED"); f.plane.close();
});
test("cross-account installation and job access is denied", () => {
  const f = fixture(), job = f.create(), other = f.plane.issueBrowserSession(f.plane.provisionAccount()).accessToken;
  forbidden(() => f.plane.activate(other, f.installation.id), "INSTALLATION_NOT_FOUND");
  forbidden(() => f.plane.readJob(other, job.id), "JOB_NOT_FOUND");
  forbidden(() => f.plane.cancelJob(other, job.id), "JOB_NOT_FOUND"); f.plane.close();
});
test("exactly one controller; taking over fences the previous job and session", () => {
  const f = fixture(); const job = f.create(), ticket = f.claim(), other = f.plane.issueBrowserSession(f.account).accessToken;
  f.plane.activate(other, f.installation.id);
  assert.equal(f.plane.readJob(f.access, job.id).state, "cancelled");
  forbidden(() => f.plane.createJob(f.access, { ...f.request, idempotencyKey: id() }), "NOT_ACTIVE_CONTROLLER");
  forbidden(() => f.plane.finish(f.installation, resultFor(f, ticket)), "STALE_JOB_ATTEMPT"); f.plane.close();
});
test("controller lease and subscription expiry prevent new work", () => {
  const f = fixture(); f.advance(90001);
  forbidden(() => f.plane.heartbeat(f.installation), "CONTROLLER_LEASE_EXPIRED");
  f.plane.provisionAccount(f.account, f.time() - 1);
  forbidden(() => f.create(), "ENTITLEMENT_EXPIRED"); f.plane.close();
});
test("revocation prevents subsequent proofs and cancels in-flight work", () => {
  const f = fixture(), job = f.create(); f.claim();
  f.plane.revokeInstallation(f.access, f.installation.id);
  const proof = makeProof(f.installation.id, "POST", "/v1/device/heartbeat", {}, f.keys.privateKey, f.time());
  forbidden(() => f.plane.authenticateDevice(proof, "POST", proof.path), "INSTALLATION_REVOKED_OR_UNKNOWN");
  assert.equal(f.plane.readJob(f.access, job.id).state, "cancelled"); f.plane.close();
});
test("jobs are idempotent, immutable and one-active-per-account", () => {
  const f = fixture(), job = f.create(); assert.equal(f.create().id, job.id);
  forbidden(() => f.plane.createJob(f.access, { ...f.request, symbol: "BTCUSDm" }), "IDEMPOTENCY_CONFLICT");
  forbidden(() => f.plane.createJob(f.access, { ...f.request, idempotencyKey: id() }), "BACKTEST_ALREADY_ACTIVE");
  f.request.configuration.geometry.targetR = 500;
  assert.equal(f.plane.readJob(f.access, job.id).request.configuration.geometry.targetR, 1); f.plane.close();
});
test("only one claim; signed ticket binds exact request and research-only rights", () => {
  const f = fixture(); f.create(); const envelope = f.plane.claim(f.installation).job;
  assert.ok(verifySigned(envelope, f.signingKey.publicKey));
  assert.equal(envelope.payload.liveTradingAllowed, false);
  assert.equal(envelope.payload.configurationHash, hash(f.request.configuration));
  assert.equal(f.plane.claim(f.installation).job, null);
  envelope.payload.request.configuration.geometry.targetR = 5;
  assert.equal(verifySigned(envelope, f.signingKey.publicKey), false); f.plane.close();
});
test("wrong job attempt and configuration do not attach results", () => {
  const f = fixture(); f.create(); const ticket = f.claim(), result = resultFor(f, ticket);
  forbidden(() => f.plane.finish(f.installation, { ...result, attemptId: id() }), "STALE_JOB_ATTEMPT");
  forbidden(() => f.plane.finish(f.installation, { ...result, configurationHash: hash("wrong") }), "RESULT_CONFIG_MISMATCH");
  forbidden(() => f.plane.finish(f.installation, { ...result, symbol: "BTCUSDm" }), "RESULT_MARKET_MISMATCH"); f.plane.close();
});
test("progress is work-based, monotone and allows an unknown download total", () => {
  const f = fixture(); f.create(); const ticket = f.claim(), base = { jobId: ticket.jobId, attemptId: ticket.attemptId };
  f.plane.progress(f.installation, { ...base, phase: "downloading", processed: 100, total: null });
  f.plane.progress(f.installation, { ...base, phase: "replaying", processed: 25, total: 100 });
  forbidden(() => f.plane.progress(f.installation, { ...base, phase: "replaying", processed: 24, total: 100 }), "PROGRESS_REGRESSION");
  forbidden(() => f.plane.progress(f.installation, { ...base, phase: "replaying", processed: 26, total: 200 }), "PROGRESS_TOTAL_CHANGED");
  forbidden(() => f.plane.progress(f.installation, { ...base, phase: "downloading", processed: 200, total: null }), "PROGRESS_PHASE_REGRESSION"); f.plane.close();
});
test("expired worker cannot upload or be implicitly rerun", () => {
  const f = fixture(), job = f.create(), ticket = f.claim(); f.advance(90001);
  forbidden(() => f.plane.finish(f.installation, resultFor(f, ticket)), "CONTROLLER_LEASE_EXPIRED");
  assert.equal(f.plane.readJob(f.access, job.id).failureCode, "WORKER_TIMEOUT"); f.plane.close();
});
test("cancellation invalidates late uploads", () => {
  const f = fixture(), job = f.create(), ticket = f.claim(); f.plane.cancelJob(f.access, job.id);
  forbidden(() => f.plane.finish(f.installation, resultFor(f, ticket)), "STALE_JOB_ATTEMPT"); f.plane.close();
});
test("real-tick-only reports reject generated ticks and unknown wins", () => {
  const f = fixture(); f.create(); const result = resultFor(f, f.claim());
  assert.equal(resultSchema.safeParse({ ...result, coverage: { ...result.coverage, generatedTicks: 10 } }).success, false);
  assert.equal(resultSchema.safeParse({ ...result, trades: [{ ...result.trades[0], netR: null }] }).success, false);
  assert.equal(resultSchema.safeParse({ ...result, trades: [result.trades[0], result.trades[0]] }).success, false); f.plane.close();
});
test("actual net R is not cosmetically forced to target R; DATA stays unknown", () => {
  const f = fixture(); f.create(); const result = resultFor(f, f.claim());
  result.trades.push({ ...result.trades[0], id: "2", outcome: "DATA", exitReason: "DATA", exitUtc: null, exitPrice: null, netR: null });
  result.coverage.missingIntervals.push({ fromUtc: f.request.fromUtc, toUtc: new Date(Date.parse(f.request.fromUtc) + 1000).toISOString() });
  const done = f.plane.finish(f.installation, result);
  assert.equal(done.result.summary.netR, .9); assert.equal(done.result.summary.data, 1);
  assert.equal(done.result.summary.coverageComplete, false); assert.equal(done.result.summary.trust, "client_reported"); f.plane.close();
});
test("closed-equity drawdown follows exit chronology, not entry order", () => {
  const f = fixture(); f.create(); const result = resultFor(f, f.claim()), win = result.trades[0];
  result.trades = [{ ...win, id: "win", netR: 2, exitUtc: new Date(Date.parse(win.entryUtc) + 200000).toISOString() }, { ...win, id: "loss", outcome: "LOSS", netR: -1, exitReason: "SL" }];
  const summary = summarizeResult(result); assert.equal(summary.netR, 1); assert.equal(summary.maxClosedDrawdownR, 1); f.plane.close();
});
test("zero net R is FLAT, not a fabricated loss or win", () => {
  const f = fixture(); f.create(); const result = resultFor(f, f.claim());
  result.trades[0] = { ...result.trades[0], outcome: "FLAT", netR: 0 };
  assert.equal(resultSchema.safeParse(result).success, true);
  const summary = summarizeResult(result);
  assert.equal(summary.flat, 1); assert.equal(summary.wins, 0); assert.equal(summary.losses, 0); assert.equal(summary.winRate, null);
  assert.equal(resultSchema.safeParse({ ...result, trades: [{ ...result.trades[0], outcome: "LOSS" }] }).success, false); f.plane.close();
});
test("a lost result response can be retried exactly, but not altered", () => {
  const f = fixture(); f.create(); const result = resultFor(f, f.claim());
  const first = f.plane.finish(f.installation, result), repeated = f.plane.finish(f.installation, result);
  assert.deepEqual(repeated, first);
  result.trades[0].netR = .8;
  forbidden(() => f.plane.finish(f.installation, result), "RESULT_REPLAY_CONFLICT"); f.plane.close();
});
test("a signed job from another controller generation is not locally executable", () => {
  const f = fixture(); f.create(); const envelope = f.plane.claim(f.installation).job;
  envelope.payload.issuedAt = Date.now(); envelope.payload.expiresAt = Date.now() + 60000;
  const client = new DeviceClient({ apiUrl: "http://127.0.0.1:4321", installationId: f.installation.id, privateKey: f.keys.privateKey, pinnedServerPublicKey: f.signingKey.publicKey });
  client.lease = { accountId: f.account, generation: id(), expiresAt: Date.now() + 60000 };
  assert.throws(() => client.verified(signed(envelope.payload, f.signingKey.privateKey), "backtest_job"), /TICKET_CONTROLLER_MISMATCH/); f.plane.close();
});
test("configuration rejects future timing, unknown executable fields and oversized trees", () => {
  const f = fixture(), config = f.request.configuration;
  assert.equal(configurationSchema.safeParse({ ...config, arbitraryMqlSource: "run()" }).success, false);
  assert.equal(configurationSchema.safeParse({ ...config, engine: { ...config.engine, signalTiming: "forming_bar" } }).success, false);
  let expression = config.engine.buy;
  for (let i = 0; i < 30; i++) expression = { op: "not", arg: expression };
  assert.equal(configurationSchema.safeParse({ ...config, engine: { ...config.engine, buy: expression } }).success, false);
  const sell = configurationSchema.parse(config).engine.sell; assert.notDeepEqual(sell, config.engine.buy); f.plane.close();
});
test("persistent SQLite preserves pairing, jobs and proof replay protection across restart", () => {
  const dir = mkdtempSync(join(tmpdir(), "stratum-control-test-"));
  try {
    const database = join(dir, "control.sqlite"), f = fixture({ database }), job = f.create();
    const proof = makeProof(f.installation.id, "POST", "/v1/device/heartbeat", {}, f.keys.privateKey, f.time());
    f.plane.authenticateDevice(proof, "POST", proof.path); f.plane.close();
    const restored = new ControlPlane({ database, signingKey: f.signingKey, now: f.time });
    assert.equal(restored.readJob(f.access, job.id).configurationHash, job.configurationHash);
    forbidden(() => restored.authenticateDevice(proof, "POST", proof.path), "PROOF_REPLAY"); restored.close();
  } finally {
    const target = realpathSync(dir), root = realpathSync(tmpdir());
    assert.ok(target.startsWith(join(root, "stratum-control-test-")), "Only this test's resolved temporary directory may be deleted");
    rmSync(target, { recursive: true, force: true });
  }
});
test("device client rejects another server key, installation and expired tickets", () => {
  const f = fixture(); const client = new DeviceClient({ apiUrl: "http://127.0.0.1:4321", installationId: f.installation.id, privateKey: f.keys.privateKey, pinnedServerPublicKey: f.signingKey.publicKey });
  const p = { version: 1, kind: "research_lease", audience: "stratum-mt5", installationId: f.installation.id, liveTradingAllowed: false, expiresAt: Date.now() + 60000, issuedAt: Date.now() };
  assert.throws(() => client.verified(signed(p, keyPair().privateKey), "research_lease"), /SERVER_SIGNATURE_INVALID/);
  assert.throws(() => client.verified(signed({ ...p, installationId: id() }, f.signingKey.privateKey), "research_lease"), /TICKET_SCOPE/);
  assert.throws(() => client.verified(signed({ ...p, expiresAt: Date.now() - 1 }, f.signingKey.privateKey), "research_lease"), /TICKET_SCOPE/);
  assert.throws(() => new DeviceClient({ apiUrl: "http://example.com", pinnedServerPublicKey: f.signingKey.publicKey }), /HTTPS/); f.plane.close();
});
test("HTTP enforces bearer auth, origins, content type and device signatures", async () => {
  const plane = new ControlPlane(), account = plane.provisionAccount(), access = plane.issueBrowserSession(account).accessToken;
  const server = controlHttp(plane); server.listen(0, "127.0.0.1"); await once(server, "listening");
  const url = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(url + "/health")).status, 200);
    assert.equal((await fetch(url + "/v1/session", { headers: { "oai-authenticated-user-id": account } })).status, 401);
    assert.equal((await fetch(url + "/v1/session", { headers: { Authorization: `Bearer ${access}` } })).status, 200);
    assert.equal((await fetch(url + "/health", { headers: { Origin: "https://evil.example" } })).status, 403);
    assert.equal((await fetch(url + "/v1/pairings", { method: "POST", body: "{}" })).status, 415);
    assert.equal((await fetch(url + "/v1/device/claim", { method: "POST", headers: { "Content-Type": "application/json" }, body: "{}" })).status, 401);
    const keys = keyPair(), response = await fetch(url + "/v1/pairings", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ publicKey: keys.publicKey, label: "HTTP probe" }) });
    const pairing = await response.json(); assert.equal(response.status, 201);
    plane.approvePairing(access, pairing.code, pairing.fingerprint); plane.activate(access, pairing.installationId);
    const client = new DeviceClient({ apiUrl: url, installationId: pairing.installationId, privateKey: keys.privateKey, pinnedServerPublicKey: plane.signingKey.publicKey });
    const lease = await client.heartbeat(); assert.equal(lease.capabilities[0], "backtest");
    assert.equal(await client.claim(), null);
    const request = exampleRequest(pairing.installationId, id());
    const jobResponse = await fetch(url + "/v1/jobs", { method: "POST", headers: { "Content-Type": "application/json", Authorization: `Bearer ${access}` }, body: JSON.stringify(request) });
    assert.equal(jobResponse.status, 201); const job = await client.claim(); assert.equal(job.requestHash, hash(request));
    const failure = await client.request("/v1/device/failure", { jobId: job.jobId, attemptId: job.attemptId, code: "MT5_ADAPTER_NOT_CONNECTED" });
    assert.equal(failure.state, "failed"); assert.equal(failure.failureCode, "MT5_ADAPTER_NOT_CONNECTED");
  } finally { server.close(); await once(server, "close"); plane.close(); }
});
