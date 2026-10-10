// Generated from canonical policy. Run scripts/generate-cloud-control.mjs; do not edit.
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { z } from 'zod';
import { ControlError } from './control-plane.mjs';
import { universalConfigurationSchema } from '../../../lib/universal-contract.ts';
import { saveConversationSchema, conversationSummarySchema, savedConversationSchema, conversationListRequestSchema } from '../../../lib/studio-conversations.ts';
const credentials = z.object({ email: z.string().email().max(254), password: z.string().min(1).max(128) }).strict();
const signup = credentials.extend({ password: z.string().min(12).max(128),
    displayName: z.string().trim().min(1).max(60).regex(/^[^\r\n\x00-\x1f\x7f]+$/).optional() });
const check = (schema, input) => { const p = schema.safeParse(input); if (!p.success)
    throw new ControlError('INVALID_REQUEST', 400); return p.data; };
const authority = z.object({ accountId: z.string().uuid(), sessionId: z.string().uuid(), email: z.string().email(),
    displayName: z.string(), disabled: z.boolean(), accessActive: z.boolean(), accessMode: z.enum(['demo', 'paid', 'inactive']),
    paidUntil: z.number().finite().nonnegative(), serverNow: z.number().finite(),
    trial: z.object({ startsAt: z.number().finite(), expiresAt: z.number().finite() }) });
// BFF boundary: Supabase access/refresh tokens never leave this server.
export class SupabaseAuth {
    constructor(plane, { url, publishableKey, encryptionKey, studioOrigin = 'http://127.0.0.1:4310', studioBasePath = '', fetcher = fetch } = {}) {
        if (!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url ?? '') || !publishableKey?.startsWith('sb_publishable_')
            || !Buffer.isBuffer(encryptionKey) || encryptionKey.length !== 32)
            throw new Error('SUPABASE_CONFIG_INVALID');
        this.plane = plane;
        this.url = url;
        this.key = publishableKey;
        this.encryptionKey = encryptionKey;
        this.fetcher = fetcher;
        const studio = new URL(studioOrigin);
        if (studio.username || studio.password || studio.search || studio.hash || studio.pathname !== '/'
            || !(studio.protocol === 'https:' || (studio.protocol === 'http:' && ['127.0.0.1', 'localhost', '[::1]'].includes(studio.hostname))))
            throw new Error('STUDIO_ORIGIN_INVALID');
        // An operator-defined destination, never a redirect supplied in a signup body.
        if (typeof studioBasePath !== 'string' || !/^(?:\/[A-Za-z0-9_-]+)*$/.test(studioBasePath))
            throw new Error('STUDIO_BASE_PATH_INVALID');
        this.confirmationUrl = studio.origin + studioBasePath + '/studio' + (studioBasePath ? '/' : '');
        this.pending = new Map();
        this.mode = 'supabase';
    }
    seal(value, sessionId) {
        const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm', this.encryptionKey, iv);
        cipher.setAAD(Buffer.from(sessionId));
        const ciphertext = Buffer.concat([cipher.update(JSON.stringify(value), 'utf8'), cipher.final()]);
        return Buffer.concat([iv, cipher.getAuthTag(), ciphertext]).toString('base64url');
    }
    unseal(value, sessionId) {
        const bytes = Buffer.from(value, 'base64url'), cipher = createDecipheriv('aes-256-gcm', this.encryptionKey, bytes.subarray(0, 12));
        cipher.setAAD(Buffer.from(sessionId));
        cipher.setAuthTag(bytes.subarray(12, 28));
        return JSON.parse(Buffer.concat([cipher.update(bytes.subarray(28)), cipher.final()]).toString());
    }
    async request(path, { jwt, body, method = body === undefined ? 'GET' : 'POST', headers = {} } = {}) {
        let response;
        try {
            response = await this.fetcher(this.url + path, { method, headers: { apikey: this.key,
                    ...(jwt ? { Authorization: 'Bearer ' + jwt } : {}), ...(body === undefined ? {} : { 'Content-Type': 'application/json' }), ...headers },
                ...(body === undefined ? {} : { body: JSON.stringify(body) }), signal: AbortSignal.timeout(8000), redirect: 'error' });
        }
        catch {
            throw new ControlError('AUTH_PROVIDER_UNAVAILABLE', 503);
        }
        let data;
        try {
            data = await response.json();
        }
        catch {
            data = null;
        }
        if (!response.ok) {
            const message = data?.message ?? data?.msg ?? data?.error_description ?? '';
            for (const [marker, code, status] of [['STRATUM_ADMIN_REQUIRED', 'ADMIN_REQUIRED', 403], ['STRATUM_ACCESS_REQUIRED', 'ENTITLEMENT_EXPIRED', 403],
                ['STRATUM_GRANT_CONFLICT', 'GRANT_CONFLICT', 409], ['STRATUM_STRATEGY_NOT_AVAILABLE', 'STRATEGY_NOT_AVAILABLE', 403],
                ['STRATUM_STRATEGY_NOT_READY', 'STRATEGY_NOT_READY', 409], ['STRATUM_USER_UNKNOWN', 'USER_NOT_FOUND', 404], ['STRATUM_INVALID_REQUEST', 'INVALID_REQUEST', 400]])
                if (message.includes(marker))
                    throw new ControlError(code, status);
            if (response.status === 429)
                throw new ControlError('AUTH_RATE_LIMITED', 429);
            if (message.includes('STRATUM_SESSION_INVALID'))
                throw new ControlError('SESSION_REVOKED', 401);
            if (message.includes('STRATUM_ACCOUNT_UNKNOWN'))
                throw new ControlError('ACCOUNT_NOT_PROVISIONED', 403);
            if (data?.error_code === 'email_not_confirmed' || data?.code === 'email_not_confirmed')
                throw new ControlError('EMAIL_CONFIRMATION_REQUIRED', 403);
            if (/sending.*email|email.*(send|address)|smtp/i.test(message) && path.startsWith('/auth/v1/signup'))
                throw new ControlError('AUTH_EMAIL_DELIVERY_FAILED', 503);
            if (response.status >= 500)
                throw new ControlError('AUTH_PROVIDER_UNAVAILABLE', 503);
            if (path.startsWith('/auth/v1/token'))
                throw new ControlError('INVALID_CREDENTIALS', 401);
            if (response.status === 401 || response.status === 403)
                throw new ControlError('SESSION_REVOKED', 401);
            throw new ControlError('AUTH_REQUEST_FAILED', 400);
        }
        return data;
    }
    async register(input) {
        const v = check(signup, input);
        const result = await (await this.request('/auth/v1/signup?redirect_to=' + encodeURIComponent(this.confirmationUrl), { body: { email: v.email.toLowerCase(), password: v.password,
                data: { display_name: v.displayName ?? v.email.split('@')[0] } } }));
        if (!result?.access_token)
            return { confirmationRequired: true, message: 'Check your email, confirm your account, then sign in. Your demo starts at registration.' };
        return (await this.openSession(result));
    }
    async login(input) {
        const v = check(credentials, input);
        return (await this.openSession(await (await this.request('/auth/v1/token?grant_type=password', { body: v }))));
    }
    async state(jwt) { return check(authority, await (await this.request('/rest/v1/rpc/stratum_access_state', { jwt, body: {} }))); }
    async sync(state) {
        const p = this.plane, at = p.now();
        // Clock drift must not lengthen a demo or turn an old response into a new grant.
        if (Math.abs(state.serverNow - at) > 30000 || Math.abs(state.trial.expiresAt - state.trial.startsAt - 30 * 86400000) > 1)
            throw new ControlError('AUTH_CLOCK_OR_TRIAL_INVALID', 503);
        (await p.provisionAccount(state.accountId, Math.floor(state.paidUntil)));
        (await p.run('UPDATE accounts SET disabled=? WHERE id=?', state.disabled ? 1 : 0, state.accountId));
        (await p.run('INSERT INTO account_trials VALUES(?,?,?) ON CONFLICT(account_id) DO UPDATE SET starts_at=excluded.starts_at,expires_at=excluded.expires_at', state.accountId, Math.floor(state.trial.startsAt), Math.floor(state.trial.expiresAt)));
        const name = state.displayName.replace(/[\r\n\x00-\x1f\x7f]/g, '').trim().slice(0, 60) || 'Abone';
        (await p.setDisplayName(state.accountId, name));
        (await p.run('INSERT INTO supabase_accounts VALUES(?,?,?) ON CONFLICT(account_id) DO UPDATE SET email=excluded.email,authority_until=excluded.authority_until', state.accountId, state.email, at + 10000));
        if (!state.accessActive)
            (await p.run('UPDATE trading SET enabled=0,revision=revision+1 WHERE account_id=?', state.accountId));
    }
    async openSession(tokens) {
        if (typeof tokens?.access_token !== 'string' || typeof tokens?.refresh_token !== 'string')
            throw new ControlError('AUTH_SESSION_INVALID', 401);
        const state = await (await this.state(tokens.access_token)), p = this.plane;
        return (await p.atomic(async () => {
            (await this.sync(state));
            const result = (await p.issueBrowserSession(state.accountId, 12 * 3600000)), actor = (await p.browser(result.accessToken));
            (await p.run('INSERT INTO supabase_sessions VALUES(?,?,?,?)', actor.sessionId, state.sessionId, this.seal({ jwt: tokens.access_token, refresh: tokens.refresh_token, expiresAt: (tokens.expires_at ?? (p.now() / 1000 + tokens.expires_in)) * 1000 }, actor.sessionId), p.now()));
            return result;
        }));
    }
    async invalidate(sessionId) {
        const p = this.plane, row = (await p.get('SELECT account_id FROM sessions WHERE id=?', sessionId));
        if (!row)
            return;
        (await p.run('DELETE FROM leases WHERE session_id=?', sessionId));
        (await p.run('UPDATE jobs SET state=\'cancelled\',failure_code=\'SESSION_ENDED\',updated_at=? WHERE account_id=? AND state IN (\'queued\',\'running\')', p.now(), row.account_id));
        (await p.run('UPDATE trading SET enabled=0,revision=revision+1 WHERE account_id=?', row.account_id));
        (await p.run('UPDATE supabase_accounts SET authority_until=0 WHERE account_id=?', row.account_id));
        (await p.run('DELETE FROM enrollment_tickets WHERE account_id=? AND used=0', row.account_id));
        (await p.run('DELETE FROM sessions WHERE id=?', sessionId));
    }
    async refresh(sessionId, { force = false } = {}) {
        if (this.pending.has(sessionId))
            return this.pending.get(sessionId);
        const p = this.plane, row = (await p.get('SELECT x.*,s.account_id,s.expires_at FROM supabase_sessions x JOIN sessions s ON s.id=x.session_id WHERE x.session_id=?', sessionId));
        if (!row || row.expires_at <= p.now())
            throw new ControlError('UNAUTHORIZED', 401);
        if (!force && row.checked_at > p.now() - 3000)
            return;
        const promise = (async () => {
            try {
                let tokens = this.unseal(row.sealed_tokens, sessionId);
                if (tokens.expiresAt <= p.now() + 60000) {
                    const result = await (await this.request('/auth/v1/token?grant_type=refresh_token', { body: { refresh_token: tokens.refresh } }));
                    tokens = { jwt: result.access_token, refresh: result.refresh_token, expiresAt: (result.expires_at ?? (p.now() / 1000 + result.expires_in)) * 1000 };
                    // Persist rotation immediately even if the following authority request times out.
                    (await p.run('UPDATE supabase_sessions SET sealed_tokens=? WHERE session_id=?', this.seal(tokens, sessionId), sessionId));
                }
                const state = await (await this.state(tokens.jwt));
                if (state.accountId !== row.account_id || state.sessionId !== row.provider_session_id)
                    throw new ControlError('SESSION_SCOPE_MISMATCH', 401);
                if (!(await p.get('SELECT id FROM sessions WHERE id=?', sessionId)))
                    throw new ControlError('UNAUTHORIZED', 401);
                (await p.atomic(async () => { (await this.sync(state)); (await p.run('UPDATE supabase_sessions SET checked_at=? WHERE session_id=?', p.now(), sessionId)); }));
            }
            catch (error) {
                (await p.run('UPDATE supabase_accounts SET authority_until=0 WHERE account_id=?', row.account_id));
                if (error.status === 401 || error.status === 403)
                    (await this.invalidate(sessionId));
                throw error;
            }
        })().finally(() => this.pending.delete(sessionId));
        this.pending.set(sessionId, promise);
        return promise;
    }
    async forBrowser(token, { force = true } = {}) {
        const actor = (await this.plane.browser(token));
        await (await this.refresh(actor.sessionId, { force }));
        return actor;
    }
    async forAccount(accountId) {
        const p = this.plane;
        const row = (await p.get('SELECT s.id FROM sessions s JOIN supabase_sessions x ON x.session_id=s.id LEFT JOIN leases l ON l.session_id=s.id WHERE s.account_id=? AND s.expires_at>? ORDER BY (l.session_id IS NOT NULL) DESC,s.expires_at DESC LIMIT 1', accountId, p.now()));
        if (!row) {
            (await p.run('UPDATE supabase_accounts SET authority_until=0 WHERE account_id=?', accountId));
            throw new ControlError('CONTROLLER_REQUIRED', 403);
        }
        await (await this.refresh(row.id));
    }
    async forDevice(installation, path) {
        // Unowned QA/local identities can never use a Supabase-enabled HTTP server.
        if (!(await this.plane.get('SELECT account_id FROM supabase_accounts WHERE account_id=?', installation.account_id)))
            throw new ControlError('PROVIDER_ACCOUNT_REQUIRED', 403);
        try {
            await (await this.forAccount(installation.account_id));
        }
        catch (error) {
            if (path !== '/v1/device/identity')
                throw error;
        }
    }
    async tokens(token) {
        const actor = (await this.plane.browser(token)), row = (await this.plane.get('SELECT sealed_tokens FROM supabase_sessions WHERE session_id=?', actor.sessionId));
        if (!row)
            throw new ControlError('UNAUTHORIZED', 401);
        return { actor, ...this.unseal(row.sealed_tokens, actor.sessionId) };
    }
    async logout(token) {
        const { actor, jwt } = (await this.tokens(token));
        (await this.invalidate(actor.sessionId));
        // Local grants are gone even if Supabase is temporarily unreachable.
        await (await this.request('/auth/v1/logout?scope=local', { jwt, body: {} }));
        return { loggedOut: true };
    }
    async strategies(token) {
        const { actor, jwt } = (await this.tokens(token));
        (await this.plane.entitlement(actor.accountId));
        const rows = await (await this.request('/rest/v1/stratum_strategies?select=configuration&order=name.asc', { jwt }));
        return rows.map(row => check(universalConfigurationSchema, row.configuration));
    }
    async saveStrategy(token, input) {
        const c = check(universalConfigurationSchema, input), { actor, jwt } = (await this.tokens(token));
        (await this.plane.entitlement(actor.accountId));
        await (await this.request('/rest/v1/stratum_strategies?on_conflict=account_id,name', { jwt, body: { account_id: actor.accountId, name: c.name, configuration: c, updated_at: new Date().toISOString() },
            headers: { Prefer: 'resolution=merge-duplicates,return=minimal' } }));
        return { saved: true, name: c.name };
    }
    async adminStatus(token) {
        const { jwt } = (await this.tokens(token));
        return check(z.object({ isAdmin: z.boolean() }).strict(), await (await this.request('/rest/v1/rpc/stratum_admin_status', { jwt, body: {} })));
    }
    async adminUsers(token, input) {
        const v = check(z.object({ query: z.string().max(200), offset: z.number().int().min(0).max(1000000) }).strict(), input), { jwt } = (await this.tokens(token));
        return (await this.request('/rest/v1/rpc/stratum_admin_users', { jwt, body: { p_query: v.query, p_offset: v.offset } }));
    }
    async adminCatalog(token, input) {
        const v = check(z.object({ userId: z.string().uuid(), family: z.enum(['orb', 'macross', 'sol', 'entrylab']), query: z.string().max(200), offset: z.number().int().min(0).max(1000000) }).strict(), input), { jwt } = (await this.tokens(token));
        return (await this.request('/rest/v1/rpc/stratum_admin_catalog', { jwt, body: { p_user_id: v.userId, p_family: v.family, p_query: v.query, p_offset: v.offset } }));
    }
    async adminGrant(token, input) {
        const v = check(z.object({ userId: z.string().uuid(), strategyId: z.string().regex(/^[a-z0-9_-]{1,100}$/), enabled: z.boolean(), revision: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER) }).strict(), input), { jwt } = (await this.tokens(token));
        return (await this.request('/rest/v1/rpc/stratum_admin_grant', { jwt, body: { p_user_id: v.userId, p_strategy_id: v.strategyId, p_enabled: v.enabled, p_revision: v.revision } }));
    }
    async sharedStrategies(token) {
        const { jwt } = (await this.tokens(token));
        return (await this.request('/rest/v1/rpc/stratum_available_strategies', { jwt, body: {} }));
    }
    async loadSharedStrategy(token, input) {
        const v = check(z.object({ strategyId: z.string().regex(/^[a-z0-9_-]{1,100}$/) }).strict(), input), { jwt } = (await this.tokens(token));
        const result = await (await this.request('/rest/v1/rpc/stratum_load_strategy', { jwt, body: { p_strategy_id: v.strategyId } }));
        return { ...result, configuration: check(universalConfigurationSchema, result.configuration) };
    }
    conversationRow(row, full = false) {
        const summary = { id: row.id, title: row.title, provider: row.provider, locale: row.locale, messageCount: row.message_count, createdAt: row.created_at, updatedAt: row.updated_at };
        return check(full ? savedConversationSchema : conversationSummarySchema, full ? { ...summary, messages: row.messages } : summary);
    }
    async saveConversation(token, input) {
        const v = check(saveConversationSchema, input), { actor, jwt } = (await this.tokens(token));
        const rows = await (await this.request('/rest/v1/stratum_conversations?on_conflict=account_id,id', { jwt,
            body: { account_id: actor.accountId, ...v }, headers: { Prefer: 'resolution=merge-duplicates,return=representation' } }));
        if (!Array.isArray(rows) || rows.length !== 1)
            throw new ControlError('CONVERSATION_SAVE_FAILED', 502);
        return this.conversationRow(rows[0], true);
    }
    async listConversations(token, input) {
        const { offset } = check(conversationListRequestSchema, input), { actor, jwt } = (await this.tokens(token));
        const query = new URLSearchParams({ account_id: 'eq.' + actor.accountId, select: 'id,title,provider,locale,message_count,created_at,updated_at', order: 'updated_at.desc,id.asc', limit: '26', offset: String(offset) });
        const rows = await (await this.request('/rest/v1/stratum_conversations?' + query, { jwt }));
        if (!Array.isArray(rows))
            throw new ControlError('CONVERSATION_READ_FAILED', 502);
        return { items: rows.slice(0, 25).map(row => this.conversationRow(row)), hasMore: rows.length > 25 };
    }
    async readConversation(token, id) {
        check(z.string().uuid(), id);
        const { actor, jwt } = (await this.tokens(token));
        const query = new URLSearchParams({ account_id: 'eq.' + actor.accountId, id: 'eq.' + id, select: 'id,title,provider,locale,message_count,created_at,updated_at,messages', limit: '1' });
        const rows = await (await this.request('/rest/v1/stratum_conversations?' + query, { jwt }));
        if (!Array.isArray(rows))
            throw new ControlError('CONVERSATION_READ_FAILED', 502);
        if (!rows.length)
            throw new ControlError('CONVERSATION_NOT_FOUND', 404);
        return this.conversationRow(rows[0], true);
    }
    async deleteConversation(token, id) {
        check(z.string().uuid(), id);
        const { actor, jwt } = (await this.tokens(token));
        const query = new URLSearchParams({ account_id: 'eq.' + actor.accountId, id: 'eq.' + id, select: 'id' });
        const rows = await (await this.request('/rest/v1/stratum_conversations?' + query, { jwt, method: 'DELETE', headers: { Prefer: 'return=representation' } }));
        if (!Array.isArray(rows))
            throw new ControlError('CONVERSATION_DELETE_FAILED', 502);
        if (!rows.length)
            throw new ControlError('CONVERSATION_NOT_FOUND', 404);
        return { deleted: true };
    }
}
