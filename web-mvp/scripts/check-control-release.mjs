import assert from "node:assert/strict";
import { existsSync, readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const clientRoot = join(root, "dist", "client");
assert.ok(existsSync(clientRoot), "Build the static client first");
const keys = JSON.parse(readFileSync(join(root, "control-service", ".state", "signing-key.json"), "utf8"));
const access = JSON.parse(readFileSync(join(root, "control-service", ".state", "dev-access.json"), "utf8"));
const privateMaterial = keys.privateKey.split("\n").find(line => line && !line.startsWith("---"));
assert.ok(privateMaterial && access.accessToken);
const queue = [clientRoot]; let files = 0;
while (queue.length) {
  const folder = queue.pop();
  for (const entry of readdirSync(folder, { withFileTypes: true })) {
    const path = join(folder, entry.name);
    if (entry.isDirectory()) { queue.push(path); continue; }
    if (!entry.isFile()) continue;
    const bytes = readFileSync(path); files++;
    assert.ok(!bytes.includes(Buffer.from(privateMaterial)), `Private signing material in client artifact: ${entry.name}`);
    assert.ok(!bytes.includes(Buffer.from(access.accessToken)), `Development credential in client artifact: ${entry.name}`);
  }
}
const health = await (await fetch("http://127.0.0.1:4321/health")).json();
assert.equal(health.liveTradingAllowed, false);
assert.equal(health.authMode, "local-development");
assert.equal(health.mt5Adapter, "not_connected");
const sessionResponse = await fetch("http://127.0.0.1:4321/v1/session", { headers: { Authorization: `Bearer ${access.accessToken}` } });
assert.equal(sessionResponse.status, 200);
console.log(`PASS: ${files} client artifacts contain neither local private signing material nor the development access token; persistent local API authenticates, MT5 not connected, live trading disabled.`);
