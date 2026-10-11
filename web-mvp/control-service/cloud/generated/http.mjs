// Generated from canonical policy. Run scripts/generate-cloud-control.mjs; do not edit.
import { createServer } from "../fetch-http.mjs";
import { ControlError } from "./control-plane.mjs";
import { eaCatalog } from "../../../lib/universal-contract.ts";
import { billingCheckout, billingWebhook, billingConfigured } from "../billing-disabled.mjs";
import { personalPackage, verifiedArtifacts } from "./delivery.mjs";
import { createStudioAgent } from '../../studio-agent.mjs';
export function controlHttp(plane, { origins = ["https://cemkaaa.github.io"], auth = null, agent = createStudioAgent() } = {}) {
    const rates = new Map();
    const server = createServer(async (req, res) => {
        res.setHeader("Cache-Control", "no-store");
        res.setHeader("X-Content-Type-Options", "nosniff");
        const reply = (status, value) => { res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" }); res.end(JSON.stringify(value)); };
        try {
            const expected = server.address().port;
            const origin = req.headers.origin;
            if (origin && !origins.includes(origin))
                throw new ControlError("ORIGIN_DENIED", 403);
            if (origin) {
                res.setHeader("Access-Control-Allow-Origin", origin);
                res.setHeader("Access-Control-Allow-Credentials", "true");
                res.setHeader("Vary", "Origin");
            }
            if (req.method === "OPTIONS") {
                res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
                res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Stratum-Proof");
                res.writeHead(204);
                res.end();
                return;
            }
            if (!req.url || req.url.includes("?") || req.url.includes("%"))
                throw new ControlError("INVALID_PATH", 400);
            const path = req.url, method = req.method, now = Date.now();
            for (const [key, rate] of rates)
                if (rate.until < now)
                    rates.delete(key);
            const sensitive = ["/v1/pairings", "/v1/device/pairing/refresh", "/v1/auth/login", "/v1/auth/register", "/v1/ea/enroll", "/v1/ea/package"].includes(path);
            const rateKey = `${req.socket.remoteAddress}:${sensitive ? "identity" : "all"}`;
            const rate = rates.get(rateKey) ?? { until: now + 60000, count: 0 };
            if (++rate.count > (sensitive ? 5 : 240))
                throw new ControlError("RATE_LIMITED", 429);
            rates.set(rateKey, rate);
            let body = {}, rawBody = Buffer.alloc(0);
            if (method === "POST") {
                if (req.headers["content-type"]?.split(";")[0] !== "application/json")
                    throw new ControlError("JSON_REQUIRED", 415);
                let size = 0;
                const chunks = [];
                for await (const chunk of req) {
                    size += chunk.length;
                    if (size > (path.startsWith('/v1/assistant/') && !path.startsWith('/v1/assistant/conversations') ? 128 * 1024 : 4 * 1024 * 1024))
                        throw new ControlError("BODY_TOO_LARGE", 413);
                    chunks.push(chunk);
                }
                rawBody = Buffer.concat(chunks);
                try {
                    body = JSON.parse(rawBody.toString("utf8"));
                }
                catch {
                    throw new ControlError("INVALID_JSON", 400);
                }
                if (!body || typeof body !== "object" || Array.isArray(body))
                    throw new ControlError("INVALID_REQUEST", 400);
            }
            const browserToken = () => {
                const authorization = req.headers.authorization;
                if (authorization?.startsWith("Bearer ") && authorization !== 'Bearer cookie-session')
                    return authorization.slice(7);
                const value = req.headers.cookie?.split(';').map(x => x.trim()).find(x => x.startsWith('stratum_session='))?.slice(16);
                if (!value || !/^[A-Za-z0-9_-]{43}$/.test(value))
                    throw new ControlError("UNAUTHORIZED", 401);
                if (method === 'POST' && !origin)
                    throw new ControlError('CSRF_ORIGIN_REQUIRED', 403);
                return value;
            };
            let authenticatedDevice;
            const device = async () => {
                if (authenticatedDevice)
                    return authenticatedDevice;
                let proof;
                try {
                    const header = req.headers["x-stratum-proof"];
                    if (typeof header !== "string" || header.length > 2048)
                        throw new Error();
                    proof = JSON.parse(Buffer.from(header, "base64url").toString("utf8"));
                }
                catch {
                    throw new ControlError("INVALID_DEVICE_PROOF", 401);
                }
                return authenticatedDevice = (await plane.authenticateDevice(proof, method, path, body, { deferAuthority: !!auth }));
            };
            const keys = Object.keys(body);
            const exact = expectedKeys => { if (keys.length !== expectedKeys.length || keys.some(key => !expectedKeys.includes(key)))
                throw new ControlError("INVALID_REQUEST", 400); };
            const cookie = (value, maxAge = 604800) => undefined;
            if (method === "GET" && path === "/health")
                return reply(200, { service: "stratum-control", protocolVersion: 2, authMode: auth?.mode ?? "local-development", mt5Adapter: "universal-connection", billingConfigured: billingConfigured(), liveTradingDefault: false });
            if (method === "POST" && (path === "/v1/auth/register" || path === "/v1/auth/login")) {
                const result = await (auth ?? plane)[path.endsWith('register') ? 'register' : 'login'](body);
                return reply(path.endsWith('register') ? 201 : 200, result);
            }
            if (method === "POST" && path === "/v1/auth/logout") {
                exact([]);
                cookie('', 0);
                return reply(200, await (auth ?? plane).logout(browserToken()));
            }
            if (auth) {
                if (path.startsWith('/v1/device/'))
                    await auth.forDevice((await device()), path);
                else if (path === '/v1/ea/enroll') {
                    const { hash } = await import('../../crypto.mjs');
                    const ticket = typeof body.enrollmentToken === 'string' && (await plane.get('SELECT account_id FROM enrollment_tickets WHERE token_hash=? AND used=0 AND expires_at>?', hash(body.enrollmentToken), plane.now()));
                    if (!ticket)
                        throw new ControlError('ENROLLMENT_EXPIRED_OR_USED', 403);
                    await auth.forAccount(ticket.account_id);
                    // Reads reuse the server-verified three-second authority window; mutations always revalidate.
                }
                else if (!['/v1/pairings', '/v1/subscription/webhook'].includes(path))
                    await auth.forBrowser(browserToken(), { force: method !== 'GET' });
            }
            if (method === 'GET' && path === '/v1/auth/session') {
                (await plane.browser(browserToken()));
                return reply(200, { accessToken: browserToken() });
            }
            if (path.startsWith('/v1/admin/') || path.startsWith('/v1/library/')) {
                if (!auth)
                    throw new ControlError('SUPABASE_REQUIRED', 503);
                const token = browserToken();
                if (method === 'GET' && path === '/v1/admin/status')
                    return reply(200, await auth.adminStatus(token));
                if (method === 'POST' && path === '/v1/admin/users')
                    return reply(200, await auth.adminUsers(token, body));
                if (method === 'POST' && path === '/v1/admin/catalog')
                    return reply(200, await auth.adminCatalog(token, body));
                if (method === 'POST' && path === '/v1/admin/grant')
                    return reply(200, await auth.adminGrant(token, body));
                if (method === 'GET' && path === '/v1/library/strategies')
                    return reply(200, await auth.sharedStrategies(token));
                if (method === 'POST' && path === '/v1/library/load')
                    return reply(200, await auth.loadSharedStrategy(token, body));
                throw new ControlError('NOT_FOUND', 404);
            }
            if (path === '/v1/assistant/status' && method === 'GET') {
                const actor = (await plane.browser(browserToken()));
                (await plane.entitlement(actor.accountId));
                return reply(200, agent.status());
            }
            if (path === '/v1/assistant/conversations' && method === 'POST')
                return reply(200, await (auth ?? plane).saveConversation(browserToken(), body));
            if (path === '/v1/assistant/conversations/list' && method === 'POST')
                return reply(200, await (auth ?? plane).listConversations(browserToken(), body));
            const conversationRoute = /^\/v1\/assistant\/conversations\/([a-f0-9-]{36})(\/delete)?$/.exec(path);
            if (conversationRoute && method === 'GET' && !conversationRoute[2])
                return reply(200, await (auth ?? plane).readConversation(browserToken(), conversationRoute[1]));
            if (conversationRoute && method === 'POST' && conversationRoute[2]) {
                exact([]);
                return reply(200, await (auth ?? plane).deleteConversation(browserToken(), conversationRoute[1]));
            }
            if (path === '/v1/assistant/chat' && method === 'POST') {
                const token = browserToken(), actor = (await plane.browser(token));
                (await plane.entitlement(actor.accountId));
                const job = body.context?.jobId ? (await plane.readJob(token, body.context.jobId)) : null;
                const strategies = await (auth ?? plane).strategies(token);
                const abort = new AbortController(), disconnect = () => { if (!res.writableEnded)
                    abort.abort(); };
                res.once?.('close', disconnect);
                try {
                    return reply(200, await agent.chat(body, { actor, strategies, job, jobs: (await plane.listJobs(token)), signal: abort.signal }));
                }
                finally {
                    res.off?.('close', disconnect);
                }
            }
            if (method === "GET" && path === "/v1/catalog") {
                (await plane.browser(browserToken()));
                return reply(200, eaCatalog);
            }
            if (method === "POST" && path === "/v1/subscription/checkout") {
                exact([]);
                return reply(200, await billingCheckout(plane, browserToken()));
            }
            if (method === "POST" && path === "/v1/subscription/webhook")
                return reply(200, await billingWebhook(plane, rawBody, req.headers["stripe-signature"]));
            if (method === "GET" && path === "/v1/strategies")
                return reply(200, { strategies: await (auth ?? plane).strategies(browserToken()) });
            if (method === "POST" && path === "/v1/strategies")
                return reply(200, await (auth ?? plane).saveStrategy(browserToken(), body));
            if (method === "POST" && path === "/v1/trading")
                return reply(200, (await plane.setTrading(browserToken(), body)));
            if (method === "GET" && path === "/v1/ea/download") {
                const actor = (await plane.browser(browserToken()));
                (await plane.entitlement(actor.accountId));
                const { binary } = verifiedArtifacts(plane);
                res.writeHead(200, { "Content-Type": "application/octet-stream", "Content-Disposition": 'attachment; filename="StratumConnection.ex5"' });
                return res.end(binary);
            }
            if (method === "POST" && path === "/v1/ea/package") {
                exact([]);
                const bundle = await personalPackage(plane, browserToken(), plane.apiUrl, verifiedArtifacts, plane.helperFactory, plane.studioUrl);
                res.writeHead(200, { "Content-Type": "application/zip", "Content-Disposition": `attachment; filename="${bundle.filename}"` });
                return res.end(bundle.bytes);
            }
            if (method === "POST" && path === "/v1/ea/enroll")
                return reply(201, (await plane.enrollInstallation(body)));
            if (method === "GET" && path === "/v1/session")
                return reply(200, (await plane.sessionInfo(browserToken())));
            if (method === "POST" && path === "/v1/pairings")
                throw new ControlError("PERSONAL_PACKAGE_REQUIRED", 403);
            if (method === "POST" && path === "/v1/pairings/review") {
                exact(["code"]);
                return reply(200, (await plane.reviewPairing(browserToken(), body.code)));
            }
            if (method === "POST" && path === "/v1/pairings/approve") {
                exact(["code", "fingerprint"]);
                return reply(200, (await plane.approvePairing(browserToken(), body.code, body.fingerprint)));
            }
            const installationRoute = /^\/v1\/installations\/([a-f0-9-]{36})\/(activate|revoke)$/.exec(path);
            if (method === "POST" && installationRoute) {
                exact([]);
                return reply(200, installationRoute[2] === "activate" ? (await plane.activate(browserToken(), installationRoute[1])) : (await plane.revokeInstallation(browserToken(), installationRoute[1])));
            }
            if (method === "POST" && path === "/v1/jobs")
                return reply(201, (await plane.createJob(browserToken(), body)));
            if (method === "GET" && path === "/v1/jobs")
                return reply(200, { jobs: (await plane.listJobs(browserToken())) });
            const jobRoute = /^\/v1\/jobs\/([a-f0-9-]{36})(\/cancel)?$/.exec(path);
            if (jobRoute && method === "GET" && !jobRoute[2])
                return reply(200, (await plane.readJob(browserToken(), jobRoute[1])));
            if (jobRoute && method === "POST" && jobRoute[2]) {
                exact([]);
                return reply(200, (await plane.cancelJob(browserToken(), jobRoute[1])));
            }
            if (method === "GET" && path === "/v1/device/pairing") {
                const installation = (await device());
                return reply(200, { installationId: installation.id, state: installation.state });
            }
            if (method === "POST" && path === "/v1/device/pairing/refresh") {
                exact(["code"]);
                return reply(200, (await plane.refreshPairing((await device()), body.code)));
            }
            if (method === "POST" && path === "/v1/device/heartbeat") {
                exact([]);
                return reply(200, (await plane.heartbeat((await device()))));
            }
            if (method === "POST" && path === "/v1/device/claim") {
                exact([]);
                return reply(200, (await plane.claim((await device()))));
            }
            if (method === "POST" && path === "/v1/device/progress")
                return reply(200, (await plane.progress((await device()), body)));
            if (method === "POST" && path === "/v1/device/result")
                return reply(200, (await plane.finish((await device()), body)));
            if (method === "POST" && path === "/v1/device/failure") {
                exact(["jobId", "attemptId", "code", ...(keys.includes("detail") ? ["detail"] : [])]);
                return reply(200, (await plane.fail((await device()), body)));
            }
            if (method === "POST" && path === "/v1/device/status")
                return reply(200, (await plane.terminalStatus((await device()), body)));
            if (method === "POST" && path === "/v1/device/operation") {
                exact([]);
                return reply(200, (await plane.operation((await device()))));
            }
            if (method === "POST" && path === "/v1/device/command")
                return reply(200, (await plane.eaCommand((await device()), body)));
            if (method === "POST" && path === "/v1/device/connect") {
                exact([]);
                return reply(200, (await plane.connectAgent((await device()))));
            }
            if (method === "POST" && path === "/v1/device/identity")
                return reply(200, (await plane.eaIdentity((await device()), body)));
            throw new ControlError("NOT_FOUND", 404);
        }
        catch (error) {
            if (!res.writableEnded)
                reply(error instanceof ControlError ? error.status : 500, { error: error instanceof ControlError ? error.code : "INTERNAL_ERROR" });
        }
    });
    server.requestTimeout = 15000;
    server.headersTimeout = 10000;
    return server;
}
