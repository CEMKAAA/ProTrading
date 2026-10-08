import { makeProof, verifySigned, hash, id } from "./crypto.mjs";
import { controlLocation } from './api-location.mjs';

export class DeviceClient {
  constructor({ apiUrl, installationId, privateKey, pinnedServerPublicKey }) {
    this.apiUrl = controlLocation(apiUrl); this.installationId = installationId; this.privateKey = privateKey; this.serverKey = pinnedServerPublicKey;
    this.agentId = id();this.connected = false;
  }
  async request(path, body = {}, method = "POST") {
    const proof = makeProof(this.installationId, method, path, body, this.privateKey, Date.now(), this.agentId);
    const response = await fetch(this.apiUrl + path, { method, headers: { "Content-Type": "application/json", "X-Stratum-Proof": Buffer.from(JSON.stringify(proof)).toString("base64url") }, ...(method === "POST" ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(10000), redirect: "error" });
    const data = await response.json();
    if (!response.ok) {if(["AGENT_SESSION_EXPIRED","AGENT_CONTROLLER_CHANGED"].includes(data.error))this.connected=false;throw new Error(data.error ?? "CONTROL_SERVICE_ERROR");}
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
  async heartbeat() { if(!this.connected){await this.request('/v1/device/connect');this.connected=true;}
    this.lease = this.verified(await this.request("/v1/device/heartbeat"), "research_lease"); return this.lease; }
  async claim() {
    const { job } = await this.request("/v1/device/claim");
    return job ? this.verified(job, "backtest_job") : null;
  }
}
