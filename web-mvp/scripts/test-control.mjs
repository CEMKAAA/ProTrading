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

const forbidden = (work, code) => assert.throws(work, error => error.code === code);
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
