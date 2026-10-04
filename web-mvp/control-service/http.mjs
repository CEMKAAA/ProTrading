import { createServer } from "node:http";
import { ControlError } from "./control-plane.mjs";

export function controlHttp(plane, { origins = ["http://127.0.0.1:4310", "http://localhost:4310"] } = {}) {
  const rates = new Map();
  const server = createServer(async (req, res) => {
    res.setHeader("Cache-Control", "no-store");
    res.setHeader("X-Content-Type-Options", "nosniff");
    const reply = (status, value) => { res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" }); res.end(JSON.stringify(value)); };
    try {
      const expected = server.address().port;
      if (!["127.0.0.1", "localhost", "[::1]"].some(h => req.headers.host === `${h}:${expected}`)) throw new ControlError("INVALID_HOST", 403);
      const origin = req.headers.origin;
      if (origin && !origins.includes(origin)) throw new ControlError("ORIGIN_DENIED", 403);
      if (origin) { res.setHeader("Access-Control-Allow-Origin", origin); res.setHeader("Vary", "Origin"); }
      if (req.method === "OPTIONS") {
        res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
        res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Stratum-Proof");
        res.writeHead(204); res.end(); return;
      }
      if (!req.url || req.url.includes("?") || req.url.includes("%")) throw new ControlError("INVALID_PATH", 400);
      const path = req.url, method = req.method, now = Date.now();
      for (const [key, rate] of rates) if (rate.until < now) rates.delete(key);
      const rateKey = `${req.socket.remoteAddress}:${path === "/v1/pairings" ? "pair" : "all"}`;
      const rate = rates.get(rateKey) ?? { until: now + 60000, count: 0 };
      if (++rate.count > (path === "/v1/pairings" ? 5 : 240)) throw new ControlError("RATE_LIMITED", 429);
      rates.set(rateKey, rate);
      let body = {};
      if (method === "POST") {
        if (req.headers["content-type"]?.split(";")[0] !== "application/json") throw new ControlError("JSON_REQUIRED", 415);
        let size = 0;
        const chunks = [];
        for await (const chunk of req) {
          size += chunk.length;
          if (size > 4 * 1024 * 1024) throw new ControlError("BODY_TOO_LARGE", 413);
          chunks.push(chunk);
        }
        try { body = JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { throw new ControlError("INVALID_JSON", 400); }
        if (!body || typeof body !== "object" || Array.isArray(body)) throw new ControlError("INVALID_REQUEST", 400);
      }
      const browserToken = () => {
        const authorization = req.headers.authorization;
        if (!authorization?.startsWith("Bearer ")) throw new ControlError("UNAUTHORIZED", 401);
        return authorization.slice(7);
      };
      const device = () => {
        let proof;
        try { const header = req.headers["x-stratum-proof"]; if (typeof header !== "string" || header.length > 2048) throw new Error(); proof = JSON.parse(Buffer.from(header, "base64url").toString("utf8")); }
        catch { throw new ControlError("INVALID_DEVICE_PROOF", 401); }
        return plane.authenticateDevice(proof, method, path, body);
      };
      const keys = Object.keys(body);
      const exact = expectedKeys => { if (keys.length !== expectedKeys.length || keys.some(key => !expectedKeys.includes(key))) throw new ControlError("INVALID_REQUEST", 400); };
      if (method === "GET" && path === "/health") return reply(200, { service: "stratum-control", protocolVersion: 1, authMode: "local-development", mt5Adapter: "not_connected", liveTradingAllowed: false });
      if (method === "GET" && path === "/v1/session") return reply(200, plane.sessionInfo(browserToken()));
      if (method === "POST" && path === "/v1/pairings") return reply(201, plane.beginPairing(body));
      if (method === "POST" && path === "/v1/pairings/review") { exact(["code"]); return reply(200, plane.reviewPairing(browserToken(), body.code)); }
      if (method === "POST" && path === "/v1/pairings/approve") { exact(["code", "fingerprint"]); return reply(200, plane.approvePairing(browserToken(), body.code, body.fingerprint)); }
      const installationRoute = /^\/v1\/installations\/([a-f0-9-]{36})\/(activate|revoke)$/.exec(path);
      if (method === "POST" && installationRoute) { exact([]); return reply(200, installationRoute[2] === "activate" ? plane.activate(browserToken(), installationRoute[1]) : plane.revokeInstallation(browserToken(), installationRoute[1])); }
      if (method === "POST" && path === "/v1/jobs") return reply(201, plane.createJob(browserToken(), body));
      if (method === "GET" && path === "/v1/jobs") return reply(200, { jobs: plane.listJobs(browserToken()) });
      const jobRoute = /^\/v1\/jobs\/([a-f0-9-]{36})(\/cancel)?$/.exec(path);
      if (jobRoute && method === "GET" && !jobRoute[2]) return reply(200, plane.readJob(browserToken(), jobRoute[1]));
      if (jobRoute && method === "POST" && jobRoute[2]) { exact([]); return reply(200, plane.cancelJob(browserToken(), jobRoute[1])); }
      if (method === "GET" && path === "/v1/device/pairing") { const installation = device(); return reply(200, { installationId: installation.id, state: installation.state }); }
      if (method === "POST" && path === "/v1/device/heartbeat") { exact([]); return reply(200, plane.heartbeat(device())); }
      if (method === "POST" && path === "/v1/device/claim") { exact([]); return reply(200, plane.claim(device())); }
      if (method === "POST" && path === "/v1/device/progress") return reply(200, plane.progress(device(), body));
      if (method === "POST" && path === "/v1/device/result") return reply(200, plane.finish(device(), body));
      if (method === "POST" && path === "/v1/device/failure") { exact(["jobId", "attemptId", "code"]); return reply(200, plane.fail(device(), body)); }
      throw new ControlError("NOT_FOUND", 404);
    } catch (error) {
      if (!res.writableEnded) reply(error instanceof ControlError ? error.status : 500, { error: error instanceof ControlError ? error.code : "INTERNAL_ERROR" });
    }
  });
  server.requestTimeout = 15000;
  server.headersTimeout = 10000;
  return server;
}
