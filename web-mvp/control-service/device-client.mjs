import { makeProof, verifySigned, hash } from "./crypto.mjs";

export class DeviceClient {
  constructor({ apiUrl, installationId, privateKey, pinnedServerPublicKey }) {
    const url = new URL(apiUrl);
    if (url.protocol !== "https:" && !(url.protocol === "http:" && ["localhost", "127.0.0.1"].includes(url.hostname))) throw new Error("HTTPS required");
    if (url.pathname !== "/" || url.search || url.hash || url.username || url.password) throw new Error("API origin required");
    this.apiUrl = url.origin; this.installationId = installationId; this.privateKey = privateKey; this.serverKey = pinnedServerPublicKey;
  }
  async request(path, body = {}, method = "POST") {
    const proof = makeProof(this.installationId, method, path, body, this.privateKey);
    const response = await fetch(this.apiUrl + path, { method, headers: { "Content-Type": "application/json", "X-Stratum-Proof": Buffer.from(JSON.stringify(proof)).toString("base64url") }, ...(method === "POST" ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(10000), redirect: "error" });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error ?? "CONTROL_SERVICE_ERROR");
    return data;
  }
  verified(envelope, kind) {
    if (!verifySigned(envelope, this.serverKey)) throw new Error("SERVER_SIGNATURE_INVALID");
    const p = envelope.payload;
    if (p.version !== 1 || p.kind !== kind || p.audience !== "stratum-mt5" || p.installationId !== this.installationId || (kind!=="operation_lease"&&p.liveTradingAllowed !== false) || p.expiresAt <= Date.now() || p.issuedAt > Date.now() + 30000) throw new Error("TICKET_SCOPE_OR_EXPIRY_INVALID");
    if (kind === "backtest_job" && (!this.lease || this.lease.expiresAt <= Date.now() || p.generation !== this.lease.generation || p.accountId !== this.lease.accountId)) throw new Error("TICKET_CONTROLLER_MISMATCH");
    if (kind === "backtest_job" && (p.configurationHash !== hash(p.request.configuration) || p.requestHash !== hash(p.request))) throw new Error("TICKET_CONFIG_MISMATCH");
    return p;
  }
  async operation(){
    const p=this.verified(await this.request("/v1/device/operation"),"operation_lease");
    if(!this.lease||p.accountId!==this.lease.accountId||p.generation!==this.lease.generation)throw new Error("OPERATION_CONTROLLER_MISMATCH");
    if(p.liveTradingAllowed&&p.configurationHash!==hash(p.request.configuration))throw new Error("OPERATION_CONFIG_MISMATCH");
    return p;
  }
  async heartbeat() { this.lease = this.verified(await this.request("/v1/device/heartbeat"), "research_lease"); return this.lease; }
  async claim() {
    const { job } = await this.request("/v1/device/claim");
    return job ? this.verified(job, "backtest_job") : null;
  }
}
