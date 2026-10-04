import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { keyPair } from "./crypto.mjs";
import { DeviceClient } from "./device-client.mjs";

// Protocol probe only. This is NOT an EA, installer, or a market-data simulator.
const root = new URL("./.state/", import.meta.url), file = new URL("device-dev.json", root);
mkdirSync(fileURLToPath(root), { recursive: true });
const apiUrl = "http://127.0.0.1:4321";
if (process.argv[2] === "pair") {
  if (existsSync(file)) throw new Error("A development installation already exists. Reuse its printed code/session or revoke it before creating a different development installation.");
  const keys = keyPair();
  const response = await fetch(apiUrl + "/v1/pairings", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ publicKey: keys.publicKey, label: "Development protocol probe (not MT5)" }), signal: AbortSignal.timeout(10000) });
  const pairing = await response.json();
  if (!response.ok) throw new Error(pairing.error);
  writeFileSync(file, JSON.stringify({ ...keys, ...pairing }, null, 2), { mode: 0o600 });
  console.log(`Pairing code: ${pairing.code}\nKey fingerprint: ${pairing.fingerprint}\nApprove only as a local protocol test. No backtest will be fabricated.`);
} else if (process.argv[2] === "watch") {
  const device = JSON.parse(readFileSync(file, "utf8"));
  const client = new DeviceClient({ apiUrl, installationId: device.installationId, privateKey: device.privateKey, pinnedServerPublicKey: readFileSync(new URL("server-public.pem", root), "utf8") });
  console.log("Protocol probe started. MT5 execution adapter is NOT connected.");
  while (true) {
    try {
      await client.heartbeat();
      const job = await client.claim();
      if (job) {
        await client.request("/v1/device/failure", { jobId: job.jobId, attemptId: job.attemptId, code: "MT5_ADAPTER_NOT_CONNECTED" });
        console.log(`Job ${job.jobId}: correctly refused, no fake result.`);
      }
    } catch (error) { console.log(error.message); }
    await new Promise(resolve => setTimeout(resolve, 10000));
  }
} else { console.log("Use: node --experimental-strip-types control-service/device-dev.mjs pair | watch"); process.exitCode = 1; }
