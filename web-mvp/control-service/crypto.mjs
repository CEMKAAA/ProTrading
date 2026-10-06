import { createHash, createPublicKey, generateKeyPairSync, randomBytes, randomUUID, sign, verify } from "node:crypto";

// Protocol v1 canonical JSON profile. No executable code is carried in a job.
export function canonical(value) {
  if (value === null || typeof value === "string" || typeof value === "boolean") return JSON.stringify(value);
  if (typeof value === "number" && Number.isFinite(value)) return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && Object.getPrototypeOf(value) === Object.prototype) return `{${Object.keys(value).sort().map(k => `${JSON.stringify(k)}:${canonical(value[k])}`).join(",")}}`;
  throw new Error("Non-JSON value");
}
export const hash = value => createHash("sha256").update(typeof value === "string" ? value : canonical(value)).digest("hex");
export const token = () => randomBytes(32).toString("base64url");
export const id = () => randomUUID();
export function keyPair() {
  const pair = generateKeyPairSync("ed25519");
  return { publicKey: pair.publicKey.export({ type: "spki", format: "pem" }).toString(), privateKey: pair.privateKey.export({ type: "pkcs8", format: "pem" }).toString() };
}
export function checkedPublicKey(pem) {
  const key = createPublicKey(pem);
  if (key.asymmetricKeyType !== "ed25519" || pem.includes("PRIVATE")) throw new Error("Ed25519 public key required");
  return key.export({ type: "spki", format: "pem" }).toString();
}
export function signed(payload, privateKey) {
  return { payload, signature: sign(null, Buffer.from(canonical(payload)), privateKey).toString("base64url") };
}
export function verifySigned(envelope, publicKey) {
  try { return verify(null, Buffer.from(canonical(envelope.payload)), publicKey, Buffer.from(envelope.signature, "base64url")); } catch { return false; }
}
export function makeProof(installationId, method, path, body, privateKey, issuedAt = Date.now(), agentId) {
  const payload = { version: 1, installationId, method, path, bodyHash: hash(body), issuedAt, nonce: id(), ...(agentId ? {agentId} : {}) };
  return { ...payload, signature: signed(payload, privateKey).signature };
}
