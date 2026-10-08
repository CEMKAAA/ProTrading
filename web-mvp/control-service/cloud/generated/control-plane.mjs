// Generated from canonical policy. Run scripts/generate-cloud-control.mjs; do not edit.
import { randomBytes, scryptSync, timingSafeEqual } from "node:crypto";
import { z } from "zod";
import { universalConfigurationSchema, UNIVERSAL_RUNTIME } from "../../../lib/universal-contract.ts";
import { backtestRequestSchema, deviceProofSchema, pairingRequestSchema, progressSchema, resultSchema, summarizeResult, ENGINE_RUNTIME } from "../../../lib/control-contract.ts";
import { checkedPublicKey, hash, id, keyPair, signed, token, verifySigned } from "../../crypto.mjs";
import { eaKeyPair, commandBody, signEaCommand } from "../../ea-authority.mjs";
import { saveConversationSchema, conversationListRequestSchema } from '../../../lib/studio-conversations.ts';
export class ControlError extends Error {
    constructor(code, status = 409) { super(code); this.code = code; this.status = status; }
}
const requireThat = (condition, code, status) => { if (!condition)
    throw new ControlError(code, status); };
const parse = (schema, value) => { const result = schema.safeParse(value); requireThat(result.success, "INVALID_REQUEST", 400); return result.data; };
const phases = ["preparing", "downloading", "replaying", "uploading"];
export class ControlPlane {
    constructor({ db, signingKey = keyPair(), eaSigningKey = eaKeyPair(), now = () => Date.now() } = {}) {
        this.db = db;
        this.signingKey = signingKey;
        this.eaSigningKey = eaSigningKey;
        this.now = now;
    }
    async get(sql, ...args) { return (await this.db.get(sql, ...args)); }
    async all(sql, ...args) { return (await this.db.all(sql, ...args)); }
    async run(sql, ...args) { return (await this.db.run(sql, ...args)); }
    async atomic(work) {
        return (await this.db.atomic(work));
    }
    async event(accountId, event, details = {}) { (await this.run("INSERT INTO audit_events(at,account_id,event,details_json) VALUES(?,?,?,?)", this.now(), accountId, event, JSON.stringify(details))); }
    close() { return; }
    async register(input) {
        const v = parse(z.object({ email: z.string().email().max(254), password: z.string().min(12).max(128),
            displayName: z.string().trim().min(1).max(60).regex(/^[^\r\n\x00-\x1f\x7f]+$/).optional() }).strict(), input);
        const email = v.email.toLowerCase(), salt = randomBytes(16).toString("hex"), accountId = id();
        return (await this.atomic(async () => {
            requireThat(!(await this.get("SELECT account_id FROM identities WHERE email=?", email)), "EMAIL_UNAVAILABLE", 409);
            (await this.provisionAccount(accountId, 0));
            (await this.run("INSERT INTO account_trials VALUES(?,?,?)", accountId, this.now(), this.now() + 30 * 86400000));
            (await this.event(accountId, "demo_started", { expiresAt: this.now() + 30 * 86400000 }));
            if (v.displayName)
                (await this.setDisplayName(accountId, v.displayName));
            (await this.run("INSERT INTO identities VALUES(?,?,?,?)", accountId, email, salt, scryptSync(v.password, salt, 64).toString("hex")));
            return (await this.issueBrowserSession(accountId));
        }));
    }
    async login(input) {
        const v = parse(z.object({ email: z.string().email().max(254), password: z.string().min(1).max(128) }).strict(), input);
        const row = (await this.get("SELECT * FROM identities WHERE email=?", v.email.toLowerCase()));
        const derived = scryptSync(v.password, row?.salt ?? "invalid-login-salt", 64);
        requireThat(row && timingSafeEqual(derived, Buffer.from(row.password_hash, "hex")), "INVALID_CREDENTIALS", 401);
        return (await this.issueBrowserSession(row.account_id));
    }
    async logout(accessToken) {
        const actor = (await this.browser(accessToken));
        (await this.run("DELETE FROM leases WHERE session_id=?", actor.sessionId));
        (await this.run("UPDATE jobs SET state='cancelled',failure_code='SESSION_ENDED',updated_at=? WHERE account_id=? AND state IN ('queued','running')", this.now(), actor.accountId));
        (await this.run("DELETE FROM sessions WHERE id=?", actor.sessionId));
        (await this.run("DELETE FROM enrollment_tickets WHERE account_id=? AND used=0", actor.accountId));
        (await this.run("UPDATE trading SET enabled=0,revision=revision+1 WHERE account_id=?", actor.accountId));
        return { loggedOut: true };
    }
    async saveStrategy(accessToken, input) {
        const actor = (await this.browser(accessToken));
        (await this.entitlement(actor.accountId));
        const c = parse(universalConfigurationSchema, input);
        requireThat((await this.get("SELECT COUNT(*) AS n FROM strategies WHERE account_id=?", actor.accountId)).n < 1024
            || (await this.get("SELECT name FROM strategies WHERE account_id=? AND name=?", actor.accountId, c.name)), "STRATEGY_LIMIT", 409);
        (await this.run("INSERT INTO strategies VALUES(?,?,?,?) ON CONFLICT(account_id,name) DO UPDATE SET configuration_json=excluded.configuration_json,updated_at=excluded.updated_at", actor.accountId, c.name, JSON.stringify(c), this.now()));
        return { saved: true, name: c.name };
    }
    async strategies(accessToken) {
        const actor = (await this.browser(accessToken));
        (await this.entitlement(actor.accountId));
        return (await this.all("SELECT configuration_json FROM strategies WHERE account_id=? ORDER BY name", actor.accountId)).map(r => JSON.parse(r.configuration_json));
    }
    conversationSummary(row) {
        return { id: row.id, title: row.title, provider: row.provider, locale: row.locale, messageCount: row.message_count,
            createdAt: new Date(row.created_at).toISOString(), updatedAt: new Date(row.updated_at).toISOString() };
    }
    async saveConversation(accessToken, input) {
        const actor = (await this.browser(accessToken)), v = parse(saveConversationSchema, input), at = this.now();
        (await this.run('INSERT INTO conversations VALUES(?,?,?,?,?,?,?,?,?) ON CONFLICT(account_id,id) DO UPDATE SET title=excluded.title,provider=excluded.provider,locale=excluded.locale,messages_json=excluded.messages_json,message_count=excluded.message_count,updated_at=excluded.updated_at', actor.accountId, v.id, v.title, v.provider, v.locale, JSON.stringify(v.messages), v.messages.length, at, at));
        return (await this.readConversation(accessToken, v.id));
    }
    async listConversations(accessToken, input) {
        const actor = (await this.browser(accessToken)), v = parse(conversationListRequestSchema, input);
        const rows = (await this.all('SELECT id,title,provider,locale,message_count,created_at,updated_at FROM conversations WHERE account_id=? ORDER BY updated_at DESC,id LIMIT 26 OFFSET ?', actor.accountId, v.offset));
        return { items: rows.slice(0, 25).map(r => this.conversationSummary(r)), hasMore: rows.length > 25 };
    }
    async readConversation(accessToken, conversationId) {
        const actor = (await this.browser(accessToken)), uuid = parse(z.string().uuid(), conversationId);
        const row = (await this.get('SELECT * FROM conversations WHERE account_id=? AND id=?', actor.accountId, uuid));
        requireThat(row, 'CONVERSATION_NOT_FOUND', 404);
        return { ...this.conversationSummary(row), messages: JSON.parse(row.messages_json) };
    }
    async deleteConversation(accessToken, conversationId) {
        const actor = (await this.browser(accessToken)), uuid = parse(z.string().uuid(), conversationId);
        const result = (await this.run('DELETE FROM conversations WHERE account_id=? AND id=?', actor.accountId, uuid));
        requireThat(result.changes > 0, 'CONVERSATION_NOT_FOUND', 404);
        return { deleted: true };
    }
    async terminalStatus(installation, input) {
        (await this.currentLease(installation));
        const v = parse(z.object({ symbol: z.string().min(1).max(64), brokerServer: z.string().min(1).max(100), accountLogin: z.string().max(32),
            runtime: z.literal(UNIVERSAL_RUNTIME), build: z.string().max(100), openPositions: z.number().int().min(0),
            trading: z.boolean(), configurationHash: z.string().max(64), error: z.string().max(200) }).strict(), input);
        const previous = (await this.get("SELECT status_json FROM terminal_status WHERE installation_id=?", installation.id));
        if (previous) {
            const old = JSON.parse(previous.status_json);
            if (old.accountLogin !== v.accountLogin || old.brokerServer !== v.brokerServer || old.symbol !== v.symbol) {
                (await this.run("UPDATE trading SET enabled=0,revision=revision+1,updated_at=? WHERE account_id=?", this.now(), installation.account_id));
                (await this.run("UPDATE jobs SET state='cancelled',failure_code='TERMINAL_CHANGED',updated_at=? WHERE installation_id=? AND state IN ('queued','running')", this.now(), installation.id));
                (await this.event(installation.account_id, 'terminal_context_changed', { installationId: installation.id }));
            }
        }
        (await this.run("INSERT INTO terminal_status VALUES(?,?,?) ON CONFLICT(installation_id) DO UPDATE SET status_json=excluded.status_json,at=excluded.at", installation.id, JSON.stringify(v), this.now()));
        return { accepted: true };
    }
    async setTrading(accessToken, input) {
        const v = parse(z.object({ installationId: z.string().uuid(), enabled: z.boolean(), jobId: z.string().uuid().nullable() }).strict(), input);
        const actor = (await this.browser(accessToken)), installation = (await this.ownedInstallation(actor, v.installationId));
        return (await this.atomic(async () => {
            if (v.enabled) {
                (await this.entitlement(actor.accountId));
                const lease = (await this.currentLease(installation));
                requireThat(lease.session_id === actor.sessionId, "NOT_ACTIVE_CONTROLLER", 403);
                const job = (await this.get("SELECT * FROM jobs WHERE id=? AND account_id=? AND installation_id=?", v.jobId, actor.accountId, installation.id));
                requireThat(job?.state === "completed" && job.generation === lease.generation, "AUDIT_REQUIRED", 409);
                const result = JSON.parse(job.result_json), request = JSON.parse(job.request_json);
                requireThat(request.version === 2 && result.summary.coverageComplete && result.summary.data === 0, "AUDIT_INCOMPLETE", 409);
                requireThat(!(await this.get("SELECT id FROM jobs WHERE account_id=? AND created_at>?", actor.accountId, job.created_at)), "NEWER_CONFIGURATION_EXISTS", 409);
                const status = (await this.get("SELECT * FROM terminal_status WHERE installation_id=?", installation.id));
                requireThat(status && status.at > this.now() - 15000, "TERMINAL_OFFLINE", 409);
                const current = JSON.parse(status.status_json);
                requireThat(current.symbol === request.symbol && current.brokerServer === request.brokerServer && current.runtime === UNIVERSAL_RUNTIME, "TERMINAL_MARKET_MISMATCH", 409);
                requireThat(current.openPositions === 0 || current.configurationHash === job.configuration_hash, "OPEN_POSITIONS_DIFFERENT_SETUP", 409);
                (await this.run("INSERT INTO trading VALUES(?,?,?,1,?,1,?) ON CONFLICT(account_id) DO UPDATE SET installation_id=excluded.installation_id,generation=excluded.generation,enabled=1,job_id=excluded.job_id,revision=trading.revision+1,updated_at=excluded.updated_at", actor.accountId, installation.id, lease.generation, job.id, this.now()));
            }
            else
                (await this.run("UPDATE trading SET enabled=0,revision=revision+1,updated_at=? WHERE account_id=?", this.now(), actor.accountId));
            (await this.event(actor.accountId, v.enabled ? "trading_requested_on" : "trading_requested_off", { jobId: v.jobId, installationId: installation.id }));
            return (await this.tradingInfo(actor.accountId));
        }));
    }
    async tradingInfo(accountId) {
        const row = (await this.get("SELECT * FROM trading WHERE account_id=?", accountId));
        return row ? { enabled: !!row.enabled, jobId: row.job_id, revision: row.revision, installationId: row.installation_id } : { enabled: false, jobId: null, revision: 0 };
    }
    async operation(installation) {
        const lease = (await this.currentLease(installation));
        const row = (await this.get("SELECT * FROM trading WHERE account_id=?", installation.account_id));
        const job = row?.enabled && row.generation === lease.generation && row.installation_id === installation.id ? (await this.get("SELECT * FROM jobs WHERE id=? AND state='completed'", row.job_id)) : null;
        return this.ticket({ version: 1, kind: "operation_lease", audience: "stratum-mt5", installationId: installation.id, accountId: installation.account_id,
            generation: lease.generation, expiresAt: Math.min(lease.expires_at, this.now() + 15000), liveTradingAllowed: !!job,
            configurationHash: job?.configuration_hash ?? null, request: job ? JSON.parse(job.request_json) : null });
    }
    async eaCommand(installation, input) {
        const v = parse(z.object({ jobId: z.string().uuid().nullable(), attemptId: z.string().uuid().nullable() }).strict(), input);
        return (await this.atomic(async () => {
            const lease = (await this.currentLease(installation));
            const status = (await this.get("SELECT * FROM terminal_status WHERE installation_id=?", installation.id));
            requireThat(status && status.at > this.now() - 15000, "TERMINAL_OFFLINE", 409);
            const terminal = JSON.parse(status.status_json);
            requireThat(/^[1-9][0-9]{0,19}$/.test(terminal.accountLogin), "TERMINAL_ACCOUNT_INVALID", 409);
            const remote = (await this.get('SELECT authority_until FROM supabase_accounts WHERE account_id=?', installation.account_id));
            let kind, ticket, expiry = Math.min(lease.expires_at, this.now() + 15000, remote?.authority_until ?? Infinity);
            if (v.jobId || v.attemptId) {
                requireThat(v.jobId && v.attemptId, "INVALID_REQUEST", 400);
                const job = (await this.runningJob(installation, v.jobId, v.attemptId));
                requireThat(JSON.parse(job.request_json).version === 2, "UNSUPPORTED_V1_CONFIG", 409);
                kind = "audit";
                ticket = (await this.jobTicket(job)).payload;
                expiry = Math.min(expiry, job.claim_until);
            }
            else {
                const operation = (await this.operation(installation)).payload;
                if (!operation.liveTradingAllowed)
                    return this.ticket({ version: 1, kind: "ea_command", audience: "stratum-mt5",
                        installationId: installation.id, expiresAt: expiry, liveTradingAllowed: false, command: null });
                kind = "live";
                ticket = operation;
            }
            requireThat(terminal.symbol === ticket.request.symbol && terminal.brokerServer === ticket.request.brokerServer, "TERMINAL_MARKET_MISMATCH", 409);
            const sequence = (await this.get("INSERT INTO ea_sequences VALUES(?,1) ON CONFLICT(installation_id) DO UPDATE SET sequence=sequence+1 RETURNING sequence", installation.id)).sequence;
            const body = commandBody(kind, ticket, expiry, this.now(), { installationId: installation.id,
                accountId: installation.account_id, generation: lease.generation, accountLogin: terminal.accountLogin, sequence });
            return this.ticket({ version: 1, kind: "ea_command", audience: "stratum-mt5", installationId: installation.id,
                expiresAt: expiry, liveTradingAllowed: false, command: signEaCommand(body, this.eaSigningKey.privateKey) });
        }));
    }
    // Internal identity-provider/operator boundary, deliberately not an HTTP signup endpoint.
    async setDisplayName(accountId, name) {
        const value = parse(z.string().trim().min(1).max(60).regex(/^[^\r\n\x00-\x1f\x7f]+$/), name);
        (await this.run("INSERT INTO account_profiles VALUES(?,?) ON CONFLICT(account_id) DO UPDATE SET display_name=excluded.display_name", accountId, value));
    }
    async displayName(accountId) {
        return (await this.get("SELECT display_name FROM account_profiles WHERE account_id=?", accountId))?.display_name
            ?? (await this.get("SELECT email FROM identities WHERE account_id=?", accountId))?.email.split('@')[0].slice(0, 60) ?? "Abone";
    }
    async eaIdentity(installation, input) {
        // Read-only display certificate. It never grants research or trading authority,
        // and remains readable when a subscription/controller lease has expired.
        const v = parse(z.object({ symbol: z.string().regex(/^[A-Za-z0-9._#-]{1,64}$/),
            brokerServer: z.string().min(1).max(100).regex(/^[^\r\n\x00-\x1f\x7f]+$/), accountLogin: z.string().regex(/^[1-9][0-9]{0,19}$/) }).strict(), input);
        return (await this.atomic(async () => {
            const account = (await this.get("SELECT * FROM accounts WHERE id=?", installation.account_id));
            requireThat(account, "ACCOUNT_UNKNOWN", 403);
            const lease = (await this.get("SELECT l.*,s.expires_at AS session_expiry FROM leases l JOIN sessions s ON s.id=l.session_id WHERE l.account_id=? AND l.installation_id=?", installation.account_id, installation.id));
            const agent = (await this.get("SELECT * FROM agent_sessions WHERE installation_id=?", installation.id));
            const access = (await this.accessState(installation.account_id)), active = access.accessActive;
            const controller = active && lease && lease.expires_at > this.now() && lease.session_expiry > this.now()
                && agent?.agent_id === installation.agentId && agent.expires_at > this.now() && agent.generation === lease.generation;
            const sequence = (await this.get("INSERT INTO ea_sequences VALUES(?,1) ON CONFLICT(installation_id) DO UPDATE SET sequence=sequence+1 RETURNING sequence", installation.id)).sequence;
            const expiry = this.now() + 15000;
            const body = ["command=identity", `issued=${Math.floor(this.now() / 1000)}`, `expires=${Math.floor(expiry / 1000)}`,
                `installationId=${installation.id}`, `accountId=${installation.account_id}`, `sequence=${sequence}`,
                `accountLogin=${v.accountLogin}`, `symbol=${v.symbol}`, `brokerServer=${v.brokerServer}`,
                `subscriberName=${(await this.displayName(installation.account_id))}`, `subscriptionActive=${!!active}`,
                `subscriptionUntil=${Math.floor(access.entitlementUntil / 1000)}`, `controllerActive=${!!controller}`,
                `accessMode=${access.accessMode}`, `trialUntil=${Math.floor((access.trial?.expiresAt ?? 0) / 1000)}`].join('\n');
            return this.ticket({ version: 1, kind: "ea_identity", audience: "stratum-mt5", installationId: installation.id,
                expiresAt: expiry, liveTradingAllowed: false, certificate: signEaCommand(body, this.eaSigningKey.privateKey) });
        }));
    }
    async provisionAccount(accountId = id(), entitlementUntil = this.now() + 86400000) {
        (await this.run("INSERT INTO accounts(id,entitlement_until) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET entitlement_until=excluded.entitlement_until", accountId, entitlementUntil));
        return accountId;
    }
    async accessState(accountId) {
        const account = (await this.get("SELECT * FROM accounts WHERE id=?", accountId));
        requireThat(account, "ACCOUNT_UNKNOWN", 403);
        const trial = (await this.get("SELECT starts_at AS startsAt,expires_at AS expiresAt FROM account_trials WHERE account_id=?", accountId));
        const remote = (await this.get("SELECT authority_until FROM supabase_accounts WHERE account_id=?", accountId));
        const fresh = !remote || remote.authority_until > this.now();
        const paid = fresh && !account.disabled && account.entitlement_until > this.now();
        const demo = fresh && !account.disabled && !!trial && trial.expiresAt > this.now();
        return { accessActive: paid || demo, accessMode: paid ? "paid" : demo ? "demo" : "inactive",
            entitlementUntil: Math.max(account.entitlement_until, trial?.expiresAt ?? 0),
            trial: trial ? { ...trial, daysRemaining: Math.max(0, Math.ceil((trial.expiresAt - this.now()) / 86400000)) } : null };
    }
    async issueEnrollment(accessToken) {
        const actor = (await this.browser(accessToken));
        (await this.entitlement(actor.accountId));
        return (await this.atomic(async () => {
            const raw = token(), expiresAt = this.now() + 30 * 60000;
            (await this.run("DELETE FROM enrollment_tickets WHERE expires_at<=? OR (account_id=? AND used=0)", this.now(), actor.accountId));
            (await this.run("INSERT INTO enrollment_tickets(token_hash,account_id,expires_at) VALUES(?,?,?)", hash(raw), actor.accountId, expiresAt));
            (await this.event(actor.accountId, "ea_package_issued"));
            return { enrollmentToken: raw, expiresAt, accountId: actor.accountId };
        }));
    }
    async enrollInstallation(input) {
        const v = parse(z.object({ enrollmentToken: z.string().regex(/^[A-Za-z0-9_-]{43}$/),
            publicKey: z.string().min(1).max(512), label: z.string().min(1).max(80), signature: z.string().min(1).max(128) }).strict(), input);
        let publicKey;
        try {
            publicKey = checkedPublicKey(v.publicKey);
        }
        catch {
            throw new ControlError("INVALID_PUBLIC_KEY", 400);
        }
        requireThat(verifySigned({ payload: { enrollmentToken: v.enrollmentToken, publicKey: v.publicKey, label: v.label }, signature: v.signature }, publicKey), "INVALID_SIGNATURE", 401);
        return (await this.atomic(async () => {
            const ticket = (await this.get("SELECT * FROM enrollment_tickets WHERE token_hash=?", hash(v.enrollmentToken)));
            requireThat(ticket && !ticket.used && ticket.expires_at > this.now(), "ENROLLMENT_EXPIRED_OR_USED", 403);
            (await this.entitlement(ticket.account_id));
            const pair = (await this.beginPairingRecord({ publicKey, label: v.label }, ticket.account_id));
            (await this.run("UPDATE enrollment_tickets SET used=1 WHERE token_hash=?", hash(v.enrollmentToken)));
            (await this.event(ticket.account_id, "personal_installation_pending", { installationId: pair.installationId }));
            return { ...pair, accountId: ticket.account_id };
        }));
    }
    async issueBrowserSession(accountId, lifetimeMs = 3600000) {
        requireThat((await this.get("SELECT id FROM accounts WHERE id=? AND disabled=0", accountId)), "ACCOUNT_DISABLED", 403);
        const accessToken = token(), sessionId = id();
        (await this.run("INSERT INTO sessions(id,token_hash,account_id,expires_at) VALUES(?,?,?,?)", sessionId, hash(accessToken), accountId, this.now() + lifetimeMs));
        return { accessToken, expiresAt: this.now() + lifetimeMs };
    }
    async browser(accessToken) {
        requireThat(typeof accessToken === "string" && accessToken.length >= 32 && accessToken.length <= 256, "UNAUTHORIZED", 401);
        const actor = (await this.get("SELECT s.id AS sessionId,s.account_id AS accountId,s.expires_at AS sessionExpiry,a.entitlement_until AS entitlementUntil,a.disabled FROM sessions s JOIN accounts a ON a.id=s.account_id WHERE token_hash=?", hash(accessToken)));
        requireThat(actor && actor.sessionExpiry > this.now() && !actor.disabled, "UNAUTHORIZED", 401);
        return { ...actor, entitlementUntil: (await this.accessState(actor.accountId)).entitlementUntil };
    }
    async entitlement(accountId) {
        const account = (await this.get("SELECT * FROM accounts WHERE id=?", accountId));
        requireThat(account && !account.disabled && (await this.accessState(accountId)).accessActive, "ENTITLEMENT_EXPIRED", 403);
        return { ...account, entitlement_until: (await this.accessState(accountId)).entitlementUntil };
    }
    async sessionInfo(accessToken) {
        const actor = (await this.browser(accessToken));
        const lease = (await this.get("SELECT installation_id AS installationId,expires_at AS expiresAt,session_id AS sessionId FROM leases WHERE account_id=?", actor.accountId));
        const access = (await this.accessState(actor.accountId));
        return { accountId: actor.accountId, displayName: (await this.displayName(actor.accountId)), ...access, subscriptionActive: access.accessActive,
            email: (await this.get("SELECT email FROM supabase_accounts WHERE account_id=?", actor.accountId))?.email
                ?? (await this.get("SELECT email FROM identities WHERE account_id=?", actor.accountId))?.email ?? null,
            trading: (await this.tradingInfo(actor.accountId)), terminalStatuses: (await this.all("SELECT installation_id AS installationId,status_json,at FROM terminal_status WHERE installation_id IN (SELECT id FROM installations WHERE account_id=?)", actor.accountId)).map(r => ({ ...JSON.parse(r.status_json), installationId: r.installationId, reportedAt: r.at })),
            installations: (await this.all("SELECT id,label,state,created_at AS createdAt FROM installations WHERE account_id=? ORDER BY created_at DESC", actor.accountId)),
            lease: lease ? { installationId: lease.installationId, expiresAt: lease.expiresAt, active: lease.expiresAt > this.now(), controlledHere: lease.sessionId === actor.sessionId } : null };
    }
    async beginPairing(input) {
        const request = parse(pairingRequestSchema, input);
        let publicKey;
        try {
            publicKey = checkedPublicKey(request.publicKey);
        }
        catch {
            throw new ControlError("INVALID_PUBLIC_KEY", 400);
        }
        return (await this.atomic(async () => (await this.beginPairingRecord({ ...request, publicKey }, null))));
    }
    async beginPairingRecord(request, owner) {
        const installationId = id(), raw = randomBytes(4).toString("hex").toUpperCase(), code = `${raw.slice(0, 4)}-${raw.slice(4)}`;
        (await this.run("INSERT INTO installations(id,account_id,public_key,label,state,created_at) VALUES(?,?,?,?,'pending',?)", installationId, owner, request.publicKey, request.label, this.now()));
        (await this.run("INSERT INTO pairings(code_hash,installation_id,expires_at) VALUES(?,?,?)", hash(code), installationId, this.now() + 300000));
        return { installationId, code, expiresAt: this.now() + 300000, fingerprint: hash(request.publicKey) };
    }
    async pairing(code) {
        requireThat(typeof code === "string" && /^[A-F0-9]{4}-[A-F0-9]{4}$/.test(code), "INVALID_PAIRING", 400);
        const row = (await this.get("SELECT p.*,i.label,i.public_key,i.account_id FROM pairings p JOIN installations i ON i.id=p.installation_id WHERE p.code_hash=?", hash(code)));
        requireThat(row && !row.used && row.expires_at > this.now(), "PAIRING_EXPIRED_OR_UNKNOWN", 404);
        return row;
    }
    async refreshPairing(installation, code) {
        requireThat(code === null || (typeof code === "string" && /^[A-F0-9]{4}-[A-F0-9]{4}$/.test(code)), "INVALID_PAIRING", 400);
        return (await this.atomic(async () => {
            const current = (await this.get("SELECT * FROM installations WHERE id=?", installation.id));
            requireThat(current && current.state !== "revoked", "INSTALLATION_REVOKED_OR_UNKNOWN", 401);
            let pairingCode = null, pairingExpiresAt = null;
            if (current.state === "pending") {
                requireThat(current.account_id, "PAIRING_OWNER_REQUIRED", 403);
                (await this.entitlement(current.account_id));
                const prior = (await this.get("SELECT * FROM pairings WHERE installation_id=?", current.id));
                // A restart keeps a still-valid code; an expired code cannot be revived.
                if (prior && !prior.used && prior.expires_at > this.now() && code && prior.code_hash === hash(code)) {
                    pairingCode = code;
                    pairingExpiresAt = prior.expires_at;
                }
                else {
                    const raw = randomBytes(4).toString("hex").toUpperCase();
                    pairingCode = `${raw.slice(0, 4)}-${raw.slice(4)}`;
                    pairingExpiresAt = this.now() + 300000;
                    (await this.run("INSERT INTO pairings(code_hash,installation_id,expires_at,used) VALUES(?,?,?,0) ON CONFLICT(installation_id) DO UPDATE SET code_hash=excluded.code_hash,expires_at=excluded.expires_at,used=0", hash(pairingCode), current.id, pairingExpiresAt));
                }
            }
            return this.ticket({ version: 1, kind: "pairing_status", audience: "stratum-mt5", installationId: current.id,
                accountId: current.account_id, state: current.state, fingerprint: hash(current.public_key), pairingCode, pairingExpiresAt,
                expiresAt: this.now() + 30000, liveTradingAllowed: false });
        }));
    }
    async reviewPairing(accessToken, code) {
        const actor = (await this.browser(accessToken));
        (await this.entitlement(actor.accountId));
        const row = (await this.pairing(code));
        requireThat(!row.account_id || row.account_id === actor.accountId, "PAIRING_OWNER_MISMATCH", 403);
        return { installationId: row.installation_id, label: row.label, fingerprint: hash(row.public_key), expiresAt: row.expires_at };
    }
    async approvePairing(accessToken, code, fingerprint) {
        const actor = (await this.browser(accessToken));
        (await this.entitlement(actor.accountId));
        return (await this.atomic(async () => {
            const row = (await this.pairing(code));
            requireThat(!row.account_id || row.account_id === actor.accountId, "PAIRING_OWNER_MISMATCH", 403);
            requireThat(hash(row.public_key) === fingerprint, "PAIRING_FINGERPRINT_CHANGED", 409);
            (await this.run("UPDATE pairings SET used=1 WHERE code_hash=?", hash(code)));
            (await this.run("UPDATE installations SET account_id=?,state='approved' WHERE id=? AND state='pending'", actor.accountId, row.installation_id));
            (await this.event(actor.accountId, "installation_approved", { installationId: row.installation_id }));
            return { installationId: row.installation_id };
        }));
    }
    async ownedInstallation(actor, installationId) {
        const installation = (await this.get("SELECT * FROM installations WHERE id=? AND account_id=? AND state='approved'", installationId, actor.accountId));
        requireThat(installation, "INSTALLATION_NOT_FOUND", 404);
        return installation;
    }
    async activate(accessToken, installationId) {
        const actor = (await this.browser(accessToken)), account = (await this.entitlement(actor.accountId));
        return (await this.atomic(async () => {
            (await this.ownedInstallation(actor, installationId));
            const generation = id(), expiresAt = Math.min(this.now() + 90000, actor.sessionExpiry, account.entitlement_until);
            // A new generation fences the previous controller AND every in-flight job.
            (await this.run("UPDATE jobs SET state='cancelled',failure_code='CONTROLLER_REPLACED',updated_at=? WHERE account_id=? AND state IN ('queued','running')", this.now(), actor.accountId));
            (await this.run("INSERT INTO leases(account_id,installation_id,session_id,generation,expires_at) VALUES(?,?,?,?,?) ON CONFLICT(account_id) DO UPDATE SET installation_id=excluded.installation_id,session_id=excluded.session_id,generation=excluded.generation,expires_at=excluded.expires_at", actor.accountId, installationId, actor.sessionId, generation, expiresAt));
            (await this.event(actor.accountId, "controller_activated", { installationId, generation }));
            (await this.run("UPDATE trading SET enabled=0,revision=revision+1 WHERE account_id=?", actor.accountId));
            return { installationId, generation, expiresAt };
        }));
    }
    async revokeInstallation(accessToken, installationId) {
        const actor = (await this.browser(accessToken));
        return (await this.atomic(async () => {
            (await this.ownedInstallation(actor, installationId));
            (await this.run("UPDATE installations SET state='revoked' WHERE id=?", installationId));
            (await this.run("DELETE FROM leases WHERE account_id=? AND installation_id=?", actor.accountId, installationId));
            (await this.run("UPDATE jobs SET state='cancelled',failure_code='INSTALLATION_REVOKED',updated_at=? WHERE installation_id=? AND state IN ('queued','running')", this.now(), installationId));
            (await this.event(actor.accountId, "installation_revoked", { installationId }));
            return { revoked: true };
        }));
    }
    async authenticateDevice(proofInput, method, path, body = {}, { deferAuthority = false } = {}) {
        const proof = parse(deviceProofSchema, proofInput), { signature, ...payload } = proof;
        requireThat(proof.method === method && proof.path === path && proof.bodyHash === hash(body), "PROOF_SCOPE_MISMATCH", 401);
        requireThat(Math.abs(proof.issuedAt - this.now()) <= 30000, "PROOF_EXPIRED", 401);
        const installation = (await this.get("SELECT * FROM installations WHERE id=?", proof.installationId));
        requireThat(installation && installation.state !== "revoked", "INSTALLATION_REVOKED_OR_UNKNOWN", 401);
        requireThat(installation.state === "approved" || ["/v1/device/pairing", "/v1/device/pairing/refresh"].includes(path), "PAIRING_REQUIRED", 403);
        requireThat(verifySigned({ payload, signature }, installation.public_key), "INVALID_SIGNATURE", 401);
        if (["/v1/device/command", "/v1/device/status", "/v1/device/connect", "/v1/device/identity"].includes(path))
            requireThat(proof.agentId, "AGENT_SESSION_REQUIRED", 403);
        if (proof.agentId && !["/v1/device/connect", "/v1/device/pairing", "/v1/device/pairing/refresh", "/v1/device/identity"].includes(path)) {
            const agent = (await this.get("SELECT * FROM agent_sessions WHERE installation_id=?", installation.id));
            requireThat(agent && agent.agent_id === proof.agentId && agent.expires_at > this.now(), "AGENT_SESSION_EXPIRED", 403);
            requireThat(agent.generation === (await this.currentLease(installation, !deferAuthority)).generation, "AGENT_CONTROLLER_CHANGED", 403);
        }
        (await this.atomic(async () => {
            (await this.run("DELETE FROM device_nonces WHERE expires_at<?", this.now()));
            requireThat(!(await this.get("SELECT nonce FROM device_nonces WHERE installation_id=? AND nonce=?", installation.id, proof.nonce)), "PROOF_REPLAY", 401);
            (await this.run("INSERT INTO device_nonces(installation_id,nonce,expires_at) VALUES(?,?,?)", installation.id, proof.nonce, this.now() + 60000));
        }));
        return { ...installation, agentId: proof.agentId };
    }
    async connectAgent(installation) {
        requireThat(installation.agentId, "AGENT_SESSION_REQUIRED", 403);
        return (await this.atomic(async () => {
            const lease = (await this.currentLease(installation)), prior = (await this.get("SELECT * FROM agent_sessions WHERE installation_id=?", installation.id));
            requireThat(!prior || prior.expires_at <= this.now() || prior.agent_id === installation.agentId || prior.generation !== lease.generation, "AGENT_ALREADY_CONNECTED", 409);
            const expiresAt = Math.min(lease.expires_at, this.now() + 15000);
            (await this.run("INSERT INTO agent_sessions VALUES(?,?,?,?) ON CONFLICT(installation_id) DO UPDATE SET agent_id=excluded.agent_id,generation=excluded.generation,expires_at=excluded.expires_at", installation.id, installation.agentId, lease.generation, expiresAt));
            return { connected: true, expiresAt };
        }));
    }
    async currentLease(installation, checkEntitlement = true) {
        requireThat(installation.account_id && installation.state === "approved", "PAIRING_REQUIRED", 403);
        if (checkEntitlement)
            (await this.entitlement(installation.account_id));
        const lease = (await this.get("SELECT l.*,s.expires_at AS session_expiry FROM leases l JOIN sessions s ON s.id=l.session_id WHERE l.account_id=? AND l.installation_id=?", installation.account_id, installation.id));
        requireThat(lease && lease.expires_at > this.now() && lease.session_expiry > this.now(), "CONTROLLER_LEASE_EXPIRED", 403);
        return lease;
    }
    async heartbeat(installation) {
        const lease = (await this.currentLease(installation)), account = (await this.entitlement(installation.account_id));
        const expiresAt = Math.min(this.now() + 90000, lease.session_expiry, account.entitlement_until);
        (await this.run("UPDATE leases SET expires_at=? WHERE account_id=? AND generation=?", expiresAt, installation.account_id, lease.generation));
        if (installation.agentId)
            (await this.run("UPDATE agent_sessions SET expires_at=? WHERE installation_id=? AND agent_id=? AND generation=?", Math.min(expiresAt, this.now() + 15000), installation.id, installation.agentId, lease.generation));
        return this.ticket({ version: 1, kind: "research_lease", audience: "stratum-mt5", accountId: installation.account_id, installationId: installation.id, generation: lease.generation, expiresAt, capabilities: ["backtest"], liveTradingAllowed: false });
    }
    ticket(payload) { return signed({ ...payload, issuedAt: this.now() }, this.signingKey.privateKey); }
    async createJob(accessToken, input) {
        const actor = (await this.browser(accessToken));
        (await this.entitlement(actor.accountId));
        const request = parse(backtestRequestSchema, input);
        requireThat(Date.parse(request.toUtc) <= this.now(), "FUTURE_BACKTEST", 400);
        return (await this.atomic(async () => {
            const installation = (await this.ownedInstallation(actor, request.installationId)), lease = (await this.currentLease(installation));
            requireThat(lease.session_id === actor.sessionId, "NOT_ACTIVE_CONTROLLER", 403);
            const requestHash = hash(request), configurationHash = hash(request.configuration);
            const prior = (await this.get("SELECT * FROM jobs WHERE account_id=? AND idempotency_key=?", actor.accountId, request.idempotencyKey));
            if (prior) {
                requireThat(prior.request_hash === requestHash && prior.generation === lease.generation, "IDEMPOTENCY_CONFLICT", 409);
                return this.viewJob(prior);
            }
            (await this.expireJobs());
            requireThat(!(await this.get("SELECT id FROM jobs WHERE account_id=? AND state IN ('queued','running')", actor.accountId)), "BACKTEST_ALREADY_ACTIVE", 409);
            const jobId = id();
            if (request.version === 2)
                (await this.run("UPDATE trading SET enabled=0,revision=revision+1 WHERE account_id=?", actor.accountId));
            (await this.run("INSERT INTO jobs(id,account_id,installation_id,generation,idempotency_key,request_json,configuration_hash,request_hash,state,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,'queued',?,?)", jobId, actor.accountId, installation.id, lease.generation, request.idempotencyKey, JSON.stringify(request), configurationHash, requestHash, this.now(), this.now()));
            (await this.event(actor.accountId, "backtest_queued", { jobId, configurationHash, requestHash }));
            return this.viewJob((await this.get("SELECT * FROM jobs WHERE id=?", jobId)));
        }));
    }
    async expireJobs() {
        (await this.run("UPDATE jobs SET state='failed',failure_code='WORKER_TIMEOUT',updated_at=? WHERE state='running' AND claim_until<=?", this.now(), this.now()));
        (await this.run("UPDATE jobs SET state='failed',failure_code='QUEUE_TIMEOUT',updated_at=? WHERE state='queued' AND created_at<?", this.now(), this.now() - 900000));
    }
    async claim(installation) {
        return (await this.atomic(async () => {
            const lease = (await this.currentLease(installation));
            (await this.expireJobs());
            const row = (await this.get("SELECT * FROM jobs WHERE installation_id=? AND generation=? AND state='queued' ORDER BY created_at LIMIT 1", installation.id, lease.generation));
            if (!row)
                return { job: null };
            const attemptId = id();
            (await this.run("UPDATE jobs SET state='running',attempt_id=?,claim_until=?,updated_at=? WHERE id=? AND state='queued'", attemptId, this.now() + 90000, this.now(), row.id));
            return { job: (await this.jobTicket((await this.get("SELECT * FROM jobs WHERE id=?", row.id)))) };
        }));
    }
    async jobTicket(row) {
        const lease = (await this.get("SELECT expires_at FROM leases WHERE account_id=? AND generation=?", row.account_id, row.generation));
        return this.ticket({ version: 1, kind: "backtest_job", audience: "stratum-mt5", accountId: row.account_id, installationId: row.installation_id,
            generation: row.generation, jobId: row.id, attemptId: row.attempt_id, configurationHash: row.configuration_hash, requestHash: row.request_hash,
            engineRuntime: JSON.parse(row.request_json).version === 2 ? UNIVERSAL_RUNTIME : ENGINE_RUNTIME, expiresAt: Math.min(row.claim_until, lease?.expires_at ?? 0), liveTradingAllowed: false, request: JSON.parse(row.request_json) });
    }
    async runningJob(installation, jobId, attemptId) {
        const lease = (await this.currentLease(installation)), row = (await this.get("SELECT * FROM jobs WHERE id=? AND installation_id=? AND account_id=?", jobId, installation.id, installation.account_id));
        requireThat(row, "JOB_NOT_FOUND", 404);
        requireThat(row.generation === lease.generation && row.state === "running" && row.attempt_id === attemptId && row.claim_until > this.now(), "STALE_JOB_ATTEMPT", 409);
        return row;
    }
    async progress(installation, input) {
        const update = parse(progressSchema, input);
        return (await this.atomic(async () => {
            const row = (await this.runningJob(installation, update.jobId, update.attemptId)), prior = row.progress_json ? JSON.parse(row.progress_json) : null;
            if (prior) {
                requireThat(phases.indexOf(update.phase) >= phases.indexOf(prior.phase), "PROGRESS_PHASE_REGRESSION", 409);
                if (prior.phase === update.phase) {
                    requireThat(update.processed >= prior.processed, "PROGRESS_REGRESSION", 409);
                    if (update.phase === "replaying" && prior.total !== null)
                        requireThat(update.total === prior.total, "PROGRESS_TOTAL_CHANGED", 409);
                }
            }
            (await this.run("UPDATE jobs SET progress_json=?,claim_until=?,updated_at=? WHERE id=?", JSON.stringify(update), this.now() + 90000, this.now(), row.id));
            return (await this.jobTicket((await this.get("SELECT * FROM jobs WHERE id=?", row.id))));
        }));
    }
    async finish(installation, input) {
        const result = parse(resultSchema, input);
        return (await this.atomic(async () => {
            const lease = (await this.currentLease(installation));
            const prior = (await this.get("SELECT * FROM jobs WHERE id=? AND installation_id=? AND account_id=?", result.jobId, installation.id, installation.account_id));
            if (prior?.state === "completed" && prior.generation === lease.generation && prior.attempt_id === result.attemptId) {
                const { summary, ...stored } = JSON.parse(prior.result_json);
                requireThat(hash(stored) === hash(result), "RESULT_REPLAY_CONFLICT", 409);
                return this.viewJob(prior);
            }
            const row = (await this.runningJob(installation, result.jobId, result.attemptId)), request = JSON.parse(row.request_json);
            requireThat(result.configurationHash === row.configuration_hash && result.requestHash === row.request_hash, "RESULT_CONFIG_MISMATCH", 409);
            requireThat(result.symbol === request.symbol && result.brokerServer === request.brokerServer, "RESULT_MARKET_MISMATCH", 409);
            requireThat(result.engineRuntime === (request.version === 2 ? UNIVERSAL_RUNTIME : ENGINE_RUNTIME), "RESULT_RUNTIME_MISMATCH", 409);
            const from = Date.parse(request.fromUtc), to = Date.parse(request.toUtc);
            requireThat(result.coverage.missingIntervals.every(i => Date.parse(i.fromUtc) >= from && Date.parse(i.toUtc) <= to), "COVERAGE_OUTSIDE_WINDOW", 400);
            requireThat(result.trades.every(t => Date.parse(t.entryUtc) >= from && Date.parse(t.entryUtc) < to && (t.exitUtc === null || Date.parse(t.exitUtc) <= to)), "RESULT_OUTSIDE_WINDOW", 400);
            const summary = summarizeResult(result);
            (await this.run("UPDATE jobs SET state='completed',result_json=?,updated_at=? WHERE id=?", JSON.stringify({ ...result, summary }), this.now(), row.id));
            (await this.event(row.account_id, "backtest_completed", { jobId: row.id, trust: summary.trust }));
            return this.viewJob((await this.get("SELECT * FROM jobs WHERE id=?", row.id)));
        }));
    }
    async fail(installation, { jobId, attemptId, code }) {
        requireThat(typeof code === "string" && /^[A-Z0-9_]{1,80}$/.test(code), "INVALID_FAILURE_CODE", 400);
        return (await this.atomic(async () => {
            const row = (await this.runningJob(installation, jobId, attemptId));
            (await this.run("UPDATE jobs SET state='failed',failure_code=?,updated_at=? WHERE id=?", code, this.now(), row.id));
            (await this.event(row.account_id, "backtest_failed", { jobId, code }));
            return this.viewJob((await this.get("SELECT * FROM jobs WHERE id=?", row.id)));
        }));
    }
    async readJob(accessToken, jobId) {
        const actor = (await this.browser(accessToken));
        (await this.expireJobs());
        const row = (await this.get("SELECT * FROM jobs WHERE id=? AND account_id=?", jobId, actor.accountId));
        requireThat(row, "JOB_NOT_FOUND", 404);
        return this.viewJob(row);
    }
    async listJobs(accessToken) {
        const actor = (await this.browser(accessToken));
        (await this.expireJobs());
        return (await this.all("SELECT * FROM jobs WHERE account_id=? ORDER BY created_at DESC,id DESC LIMIT 10", actor.accountId)).map(row => this.viewJob(row));
    }
    async cancelJob(accessToken, jobId) {
        const actor = (await this.browser(accessToken));
        return (await this.atomic(async () => {
            const row = (await this.get("SELECT * FROM jobs WHERE id=? AND account_id=?", jobId, actor.accountId));
            requireThat(row, "JOB_NOT_FOUND", 404);
            requireThat(["queued", "running"].includes(row.state), "JOB_ALREADY_TERMINAL", 409);
            (await this.run("UPDATE jobs SET state='cancelled',failure_code='USER_CANCELLED',updated_at=? WHERE id=?", this.now(), row.id));
            return this.viewJob((await this.get("SELECT * FROM jobs WHERE id=?", row.id)));
        }));
    }
    viewJob(row) {
        return { id: row.id, installationId: row.installation_id, state: row.state, configurationHash: row.configuration_hash, requestHash: row.request_hash,
            request: JSON.parse(row.request_json), progress: row.progress_json ? JSON.parse(row.progress_json) : null,
            result: row.result_json ? JSON.parse(row.result_json) : null, failureCode: row.failure_code, createdAt: row.created_at, updatedAt: row.updated_at };
    }
}
