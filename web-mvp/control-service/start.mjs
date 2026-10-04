import { mkdirSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { ControlPlane } from "./control-plane.mjs";
import { controlHttp } from "./http.mjs";
import { keyPair } from "./crypto.mjs";

// Never silently turn a local test identity into production authorization.
if (process.argv[2] !== "--local-dev" || process.env.NODE_ENV === "production") {
  console.error("Refusing startup: production identity/billing adapters are not configured. Use --local-dev for the loopback test service.");
  process.exit(1);
}
const root = fileURLToPath(new URL("./.state/", import.meta.url));
mkdirSync(root, { recursive: true });
const signingFile = join(root, "signing-key.json");
const signingKey = existsSync(signingFile) ? JSON.parse(readFileSync(signingFile, "utf8")) : keyPair();
if (!existsSync(signingFile)) writeFileSync(signingFile, JSON.stringify(signingKey), { mode: 0o600 });
writeFileSync(join(root, "server-public.pem"), signingKey.publicKey);
const plane = new ControlPlane({ database: join(root, "control.sqlite"), signingKey });
const accountId = "c8887b55-0952-42ad-a8b9-7c9f1f55e0fd";
plane.provisionAccount(accountId, Date.now() + 86400000);
const accessFile = join(root, "dev-access.json");
let session;
try { session = JSON.parse(readFileSync(accessFile, "utf8")); plane.browser(session.accessToken); } catch { session = plane.issueBrowserSession(accountId); }
writeFileSync(accessFile, JSON.stringify({ ...session, accountId, developmentOnly: true }, null, 2), { mode: 0o600 });
const server = controlHttp(plane);
server.listen(4321, "127.0.0.1", () => {
  console.log("Local control service: http://127.0.0.1:4321 (NOT production auth, NOT connected to MT5, live orders disabled)");
  console.log(`Local session file: ${resolve(accessFile)} (keep private; never ship it)`);
});
function stop() { server.close(() => { plane.close(); process.exit(0); }); }
process.on("SIGINT", stop); process.on("SIGTERM", stop);
