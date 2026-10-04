import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { backtestRequestSchema, deviceProofSchema, pairingRequestSchema, progressSchema, resultSchema, summarizeResult, ENGINE_RUNTIME } from "../lib/control-contract.ts";
import { checkedPublicKey, hash, id, keyPair, signed, token, verifySigned } from "./crypto.mjs";

export class ControlError extends Error {
  constructor(code, status = 409) { super(code); this.code = code; this.status = status; }
}
const requireThat = (condition, code, status) => { if (!condition) throw new ControlError(code, status); };
const parse = (schema, value) => { const result = schema.safeParse(value); requireThat(result.success, "INVALID_REQUEST", 400); return result.data; };
const phases = ["preparing", "downloading", "replaying", "uploading"];

export class ControlPlane {
  constructor({ database = ":memory:", signingKey = keyPair(), now = () => Date.now() } = {}) {
    this.db = new DatabaseSync(database);
    this.db.exec(readFileSync(new URL("./schema.sql", import.meta.url), "utf8"));
    this.signingKey = signingKey;
    this.now = now;
  }
  get(sql, ...args) { return this.db.prepare(sql).get(...args); }
  all(sql, ...args) { return this.db.prepare(sql).all(...args); }
  run(sql, ...args) { return this.db.prepare(sql).run(...args); }
  atomic(work) {
    this.db.exec("BEGIN IMMEDIATE");
    try { const result = work(); this.db.exec("COMMIT"); return result; }
    catch (error) { this.db.exec("ROLLBACK"); throw error; }
  }
  event(accountId, event, details = {}) { this.run("INSERT INTO audit_events(at,account_id,event,details_json) VALUES(?,?,?,?)", this.now(), accountId, event, JSON.stringify(details)); }
  close() { this.db.close(); }

  // Internal identity-provider/operator boundary, deliberately not an HTTP signup endpoint.
  provisionAccount(accountId = id(), entitlementUntil = this.now() + 86400000) {
    this.run("INSERT INTO accounts(id,entitlement_until) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET entitlement_until=excluded.entitlement_until", accountId, entitlementUntil);
    return accountId;
  }
  issueBrowserSession(accountId, lifetimeMs = 3600000) {
    requireThat(this.get("SELECT id FROM accounts WHERE id=? AND disabled=0", accountId), "ACCOUNT_DISABLED", 403);
    const accessToken = token(), sessionId = id();
    this.run("INSERT INTO sessions(id,token_hash,account_id,expires_at) VALUES(?,?,?,?)", sessionId, hash(accessToken), accountId, this.now() + lifetimeMs);
    return { accessToken, expiresAt: this.now() + lifetimeMs };
  }
  browser(accessToken) {
    requireThat(typeof accessToken === "string" && accessToken.length >= 32 && accessToken.length <= 256, "UNAUTHORIZED", 401);
    const actor = this.get("SELECT s.id AS sessionId,s.account_id AS accountId,s.expires_at AS sessionExpiry,a.entitlement_until AS entitlementUntil,a.disabled FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE token_hash=?", hash(accessToken));
    requireThat(actor && actor.sessionExpiry > this.now() && !actor.disabled, "UNAUTHORIZED", 401);
    return actor;
  }
  entitlement(accountId) {
    const account = this.get("SELECT * FROM accounts WHERE id=?", accountId);
    requireThat(account && !account.disabled && account.entitlement_until > this.now(), "ENTITLEMENT_EXPIRED", 403);
    return account;
  }
  sessionInfo(accessToken) {
    const actor = this.browser(accessToken);
    const lease = this.get("SELECT installation_id AS installationId,expires_at AS expiresAt,session_id AS sessionId FROM leases WHERE account_id=?", actor.accountId);
    return { accountId: actor.accountId, entitlementUntil: actor.entitlementUntil, subscriptionActive: actor.entitlementUntil > this.now(),
      installations: this.all("SELECT id,label,state,created_at AS createdAt FROM installations WHERE account_id=? ORDER BY created_at DESC", actor.accountId),
      lease: lease ? { installationId: lease.installationId, expiresAt: lease.expiresAt, active: lease.expiresAt > this.now(), controlledHere: lease.sessionId === actor.sessionId } : null };
  }
  beginPairing(input) {
    const request = parse(pairingRequestSchema, input);
    let publicKey;
    try { publicKey = checkedPublicKey(request.publicKey); } catch { throw new ControlError("INVALID_PUBLIC_KEY", 400); }
    return this.atomic(() => {
      const installationId = id(), raw = randomBytes(4).toString("hex").toUpperCase(), code = `${raw.slice(0, 4)}-${raw.slice(4)}`;
      this.run("INSERT INTO installations(id,public_key,label,state,created_at) VALUES(?,?,?,'pending',?)", installationId, publicKey, request.label, this.now());
      this.run("INSERT INTO pairings(code_hash,installation_id,expires_at) VALUES(?,?,?)", hash(code), installationId, this.now() + 300000);
      return { installationId, code, expiresAt: this.now() + 300000, fingerprint: hash(publicKey) };
    });
  }
  pairing(code) {
    requireThat(typeof code === "string" && /^[A-F0-9]{4}-[A-F0-9]{4}$/.test(code), "INVALID_PAIRING", 400);
    const row = this.get("SELECT p.*,i.label,i.public_key FROM pairings p JOIN installations i ON i.id=p.installation_id WHERE p.code_hash=?", hash(code));
    requireThat(row && !row.used && row.expires_at > this.now(), "PAIRING_EXPIRED_OR_UNKNOWN", 404);
    return row;
  }
  reviewPairing(accessToken, code) {
    const actor = this.browser(accessToken); this.entitlement(actor.accountId);
    const row = this.pairing(code);
    return { installationId: row.installation_id, label: row.label, fingerprint: hash(row.public_key), expiresAt: row.expires_at };
  }
  approvePairing(accessToken, code, fingerprint) {
    const actor = this.browser(accessToken); this.entitlement(actor.accountId);
    return this.atomic(() => {
      const row = this.pairing(code);
      requireThat(hash(row.public_key) === fingerprint, "PAIRING_FINGERPRINT_CHANGED", 409);
      this.run("UPDATE pairings SET used=1 WHERE code_hash=?", hash(code));
      this.run("UPDATE installations SET account_id=?,state='approved' WHERE id=? AND state='pending'", actor.accountId, row.installation_id);
      this.event(actor.accountId, "installation_approved", { installationId: row.installation_id });
      return { installationId: row.installation_id };
    });
  }
  ownedInstallation(actor, installationId) {
    const installation = this.get("SELECT * FROM installations WHERE id=? AND account_id=? AND state='approved'", installationId, actor.accountId);
    requireThat(installation, "INSTALLATION_NOT_FOUND", 404); return installation;
  }
  activate(accessToken, installationId) {
    const actor = this.browser(accessToken), account = this.entitlement(actor.accountId);
    return this.atomic(() => {
      this.ownedInstallation(actor, installationId);
      const generation = id(), expiresAt = Math.min(this.now() + 90000, actor.sessionExpiry, account.entitlement_until);
      // A new generation fences the previous controller AND every in-flight job.
      this.run("UPDATE jobs SET state='cancelled',failure_code='CONTROLLER_REPLACED',updated_at=? WHERE account_id=? AND state IN ('queued','running')", this.now(), actor.accountId);
      this.run("INSERT INTO leases(account_id,installation_id,session_id,generation,expires_at) VALUES(?,?,?,?,?) ON CONFLICT(account_id) DO UPDATE SET installation_id=excluded.installation_id,session_id=excluded.session_id,generation=excluded.generation,expires_at=excluded.expires_at", actor.accountId, installationId, actor.sessionId, generation, expiresAt);
      this.event(actor.accountId, "controller_activated", { installationId, generation });
      return { installationId, generation, expiresAt };
    });
  }
  revokeInstallation(accessToken, installationId) {
    const actor = this.browser(accessToken);
    return this.atomic(() => {
      this.ownedInstallation(actor, installationId);
      this.run("UPDATE installations SET state='revoked' WHERE id=?", installationId);
      this.run("DELETE FROM leases WHERE account_id=? AND installation_id=?", actor.accountId, installationId);
      this.run("UPDATE jobs SET state='cancelled',failure_code='INSTALLATION_REVOKED',updated_at=? WHERE installation_id=? AND state IN ('queued','running')", this.now(), installationId);
      this.event(actor.accountId, "installation_revoked", { installationId });
      return { revoked: true };
    });
  }
  authenticateDevice(proofInput, method, path, body = {}) {
    const proof = parse(deviceProofSchema, proofInput), { signature, ...payload } = proof;
    requireThat(proof.method === method && proof.path === path && proof.bodyHash === hash(body), "PROOF_SCOPE_MISMATCH", 401);
    requireThat(Math.abs(proof.issuedAt - this.now()) <= 30000, "PROOF_EXPIRED", 401);
    const installation = this.get("SELECT * FROM installations WHERE id=?", proof.installationId);
    requireThat(installation && installation.state !== "revoked", "INSTALLATION_REVOKED_OR_UNKNOWN", 401);
    requireThat(installation.state === "approved" || path === "/v1/device/pairing", "PAIRING_REQUIRED", 403);
    requireThat(verifySigned({ payload, signature }, installation.public_key), "INVALID_SIGNATURE", 401);
    this.atomic(() => {
      this.run("DELETE FROM device_nonces WHERE expires_at<?", this.now());
      requireThat(!this.get("SELECT nonce FROM device_nonces WHERE installation_id=? AND nonce=?", installation.id, proof.nonce), "PROOF_REPLAY", 401);
      this.run("INSERT INTO device_nonces(installation_id,nonce,expires_at) VALUES(?,?,?)", installation.id, proof.nonce, this.now() + 60000);
    });
    return installation;
  }
  currentLease(installation) {
    requireThat(installation.account_id && installation.state === "approved", "PAIRING_REQUIRED", 403);
    this.entitlement(installation.account_id);
    const lease = this.get("SELECT l.*,s.expires_at AS session_expiry FROM leases l JOIN sessions s ON s.id=l.session_id WHERE l.account_id=? AND l.installation_id=?", installation.account_id, installation.id);
    requireThat(lease && lease.expires_at > this.now() && lease.session_expiry > this.now(), "CONTROLLER_LEASE_EXPIRED", 403);
    return lease;
  }
  heartbeat(installation) {
    const lease = this.currentLease(installation), account = this.entitlement(installation.account_id);
    const expiresAt = Math.min(this.now() + 90000, lease.session_expiry, account.entitlement_until);
    this.run("UPDATE leases SET expires_at=? WHERE account_id=? AND generation=?", expiresAt, installation.account_id, lease.generation);
    return this.ticket({ version: 1, kind: "research_lease", audience: "stratum-mt5", accountId: installation.account_id, installationId: installation.id, generation: lease.generation, expiresAt, capabilities: ["backtest"], liveTradingAllowed: false });
  }
  ticket(payload) { return signed({ ...payload, issuedAt: this.now() }, this.signingKey.privateKey); }
  createJob(accessToken, input) {
    const actor = this.browser(accessToken); this.entitlement(actor.accountId);
    const request = parse(backtestRequestSchema, input);
    requireThat(Date.parse(request.toUtc) <= this.now(), "FUTURE_BACKTEST", 400);
    return this.atomic(() => {
      const installation = this.ownedInstallation(actor, request.installationId), lease = this.currentLease(installation);
      requireThat(lease.session_id === actor.sessionId, "NOT_ACTIVE_CONTROLLER", 403);
      const requestHash = hash(request), configurationHash = hash(request.configuration);
      const prior = this.get("SELECT * FROM jobs WHERE account_id=? AND idempotency_key=?", actor.accountId, request.idempotencyKey);
      if (prior) { requireThat(prior.request_hash === requestHash && prior.generation === lease.generation, "IDEMPOTENCY_CONFLICT", 409); return this.viewJob(prior); }
      this.expireJobs();
      requireThat(!this.get("SELECT id FROM jobs WHERE account_id=? AND state IN ('queued','running')", actor.accountId), "BACKTEST_ALREADY_ACTIVE", 409);
      const jobId = id();
      this.run("INSERT INTO jobs(id,account_id,installation_id,generation,idempotency_key,request_json,configuration_hash,request_hash,state,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,'queued',?,?)", jobId, actor.accountId, installation.id, lease.generation, request.idempotencyKey, JSON.stringify(request), configurationHash, requestHash, this.now(), this.now());
      this.event(actor.accountId, "backtest_queued", { jobId, configurationHash, requestHash });
      return this.viewJob(this.get("SELECT * FROM jobs WHERE id=?", jobId));
    });
  }
  expireJobs() {
    this.run("UPDATE jobs SET state='failed',failure_code='WORKER_TIMEOUT',updated_at=? WHERE state='running' AND claim_until<=?", this.now(), this.now());
    this.run("UPDATE jobs SET state='failed',failure_code='QUEUE_TIMEOUT',updated_at=? WHERE state='queued' AND created_at<?", this.now(), this.now() - 900000);
  }
  claim(installation) {
    return this.atomic(() => {
      const lease = this.currentLease(installation); this.expireJobs();
      const row = this.get("SELECT * FROM jobs WHERE installation_id=? AND generation=? AND state='queued' ORDER BY created_at LIMIT 1", installation.id, lease.generation);
      if (!row) return { job: null };
      const attemptId = id();
      this.run("UPDATE jobs SET state='running',attempt_id=?,claim_until=?,updated_at=? WHERE id=? AND state='queued'", attemptId, this.now() + 90000, this.now(), row.id);
      return { job: this.jobTicket(this.get("SELECT * FROM jobs WHERE id=?", row.id)) };
    });
  }
  jobTicket(row) {
    const lease = this.get("SELECT expires_at FROM leases WHERE account_id=? AND generation=?", row.account_id, row.generation);
    return this.ticket({ version: 1, kind: "backtest_job", audience: "stratum-mt5", accountId: row.account_id, installationId: row.installation_id,
      generation: row.generation, jobId: row.id, attemptId: row.attempt_id, configurationHash: row.configuration_hash, requestHash: row.request_hash,
      engineRuntime: ENGINE_RUNTIME, expiresAt: Math.min(row.claim_until, lease?.expires_at ?? 0), liveTradingAllowed: false, request: JSON.parse(row.request_json) });
  }
  runningJob(installation, jobId, attemptId) {
    const lease = this.currentLease(installation), row = this.get("SELECT * FROM jobs WHERE id=? AND installation_id=? AND account_id=?", jobId, installation.id, installation.account_id);
    requireThat(row, "JOB_NOT_FOUND", 404);
    requireThat(row.generation === lease.generation && row.state === "running" && row.attempt_id === attemptId && row.claim_until > this.now(), "STALE_JOB_ATTEMPT", 409);
    return row;
  }
  progress(installation, input) {
    const update = parse(progressSchema, input);
    return this.atomic(() => {
      const row = this.runningJob(installation, update.jobId, update.attemptId), prior = row.progress_json ? JSON.parse(row.progress_json) : null;
      if (prior) {
        requireThat(phases.indexOf(update.phase) >= phases.indexOf(prior.phase), "PROGRESS_PHASE_REGRESSION", 409);
        if (prior.phase === update.phase) {
          requireThat(update.processed >= prior.processed, "PROGRESS_REGRESSION", 409);
          if (update.phase === "replaying" && prior.total !== null) requireThat(update.total === prior.total, "PROGRESS_TOTAL_CHANGED", 409);
        }
      }
      this.run("UPDATE jobs SET progress_json=?,claim_until=?,updated_at=? WHERE id=?", JSON.stringify(update), this.now() + 90000, this.now(), row.id);
      return this.jobTicket(this.get("SELECT * FROM jobs WHERE id=?", row.id));
    });
  }
  finish(installation, input) {
    const result = parse(resultSchema, input);
    return this.atomic(() => {
      const lease = this.currentLease(installation);
      const prior = this.get("SELECT * FROM jobs WHERE id=? AND installation_id=? AND account_id=?", result.jobId, installation.id, installation.account_id);
      if (prior?.state === "completed" && prior.generation === lease.generation && prior.attempt_id === result.attemptId) {
        const { summary, ...stored } = JSON.parse(prior.result_json);
        requireThat(hash(stored) === hash(result), "RESULT_REPLAY_CONFLICT", 409);
        return this.viewJob(prior);
      }
      const row = this.runningJob(installation, result.jobId, result.attemptId), request = JSON.parse(row.request_json);
      requireThat(result.configurationHash === row.configuration_hash && result.requestHash === row.request_hash, "RESULT_CONFIG_MISMATCH", 409);
      requireThat(result.symbol === request.symbol && result.brokerServer === request.brokerServer, "RESULT_MARKET_MISMATCH", 409);
      const from = Date.parse(request.fromUtc), to = Date.parse(request.toUtc);
      requireThat(result.coverage.missingIntervals.every(i => Date.parse(i.fromUtc) >= from && Date.parse(i.toUtc) <= to), "COVERAGE_OUTSIDE_WINDOW", 400);
      requireThat(result.trades.every(t => Date.parse(t.entryUtc) >= from && Date.parse(t.entryUtc) < to && (t.exitUtc === null || Date.parse(t.exitUtc) <= to)), "RESULT_OUTSIDE_WINDOW", 400);
      const summary = summarizeResult(result);
      this.run("UPDATE jobs SET state='completed',result_json=?,updated_at=? WHERE id=?", JSON.stringify({ ...result, summary }), this.now(), row.id);
      this.event(row.account_id, "backtest_completed", { jobId: row.id, trust: summary.trust });
      return this.viewJob(this.get("SELECT * FROM jobs WHERE id=?", row.id));
    });
  }
  fail(installation, { jobId, attemptId, code }) {
    requireThat(typeof code === "string" && /^[A-Z0-9_]{1,80}$/.test(code), "INVALID_FAILURE_CODE", 400);
    return this.atomic(() => {
      const row = this.runningJob(installation, jobId, attemptId);
      this.run("UPDATE jobs SET state='failed',failure_code=?,updated_at=? WHERE id=?", code, this.now(), row.id);
      this.event(row.account_id, "backtest_failed", { jobId, code });
      return this.viewJob(this.get("SELECT * FROM jobs WHERE id=?", row.id));
    });
  }
  readJob(accessToken, jobId) {
    const actor = this.browser(accessToken); this.expireJobs();
    const row = this.get("SELECT * FROM jobs WHERE id=? AND account_id=?", jobId, actor.accountId);
    requireThat(row, "JOB_NOT_FOUND", 404); return this.viewJob(row);
  }
  listJobs(accessToken) {
    const actor = this.browser(accessToken); this.expireJobs();
    return this.all("SELECT * FROM jobs WHERE account_id=? ORDER BY created_at DESC,rowid DESC LIMIT 10", actor.accountId).map(row => this.viewJob(row));
  }
  cancelJob(accessToken, jobId) {
    const actor = this.browser(accessToken);
    return this.atomic(() => {
      const row = this.get("SELECT * FROM jobs WHERE id=? AND account_id=?", jobId, actor.accountId);
      requireThat(row, "JOB_NOT_FOUND", 404);
      requireThat(["queued", "running"].includes(row.state), "JOB_ALREADY_TERMINAL", 409);
      this.run("UPDATE jobs SET state='cancelled',failure_code='USER_CANCELLED',updated_at=? WHERE id=?", this.now(), row.id);
      return this.viewJob(this.get("SELECT * FROM jobs WHERE id=?", row.id));
    });
  }
  viewJob(row) {
    return { id: row.id, installationId: row.installation_id, state: row.state, configurationHash: row.configuration_hash, requestHash: row.request_hash,
      request: JSON.parse(row.request_json), progress: row.progress_json ? JSON.parse(row.progress_json) : null,
      result: row.result_json ? JSON.parse(row.result_json) : null, failureCode: row.failure_code, createdAt: row.created_at, updatedAt: row.updated_at };
  }
}
