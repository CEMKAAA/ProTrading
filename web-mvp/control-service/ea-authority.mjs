import { constants, createPublicKey, generateKeyPairSync, sign, verify } from "node:crypto";
import { hash } from "./crypto.mjs";
import { universalConfigurationSchema } from "../lib/universal-contract.ts";

// This key belongs only to the service. EX5 ships the public modulus, never a secret.
export function eaKeyPair() {
  const pair = generateKeyPairSync("rsa", { modulusLength: 2048, publicExponent: 65537 });
  return { publicKey: pair.publicKey.export({ type: "spki", format: "pem" }).toString(),
    privateKey: pair.privateKey.export({ type: "pkcs8", format: "pem" }).toString() };
}
export function eaModulus(publicKey) {
  const key = createPublicKey(publicKey), jwk = key.export({ format: "jwk" });
  if (key.asymmetricKeyType !== "rsa" || jwk.e !== "AQAB" || Buffer.from(jwk.n, "base64url").length !== 256) throw new Error("EA_RSA_KEY_INVALID");
  return Buffer.from(jwk.n, "base64url").toString("hex");
}
export function commandBody(kind, ticket, expiresAt = Date.now() + 15000, now = Date.now(), scope = {}) {
  const c = universalConfigurationSchema.parse(ticket.request.configuration), r = ticket.request;
  const rows = [`command=${kind}`, `issued=${Math.floor(now / 1000)}`, `expires=${Math.floor(Math.min(expiresAt, now + 15000) / 1000)}`,
    ...Object.entries(scope).map(([k, v]) => `${k}=${v}`),
    `family=${c.family}`, `name=${c.name}`, `symbol=${r.symbol}`, `brokerServer=${r.brokerServer}`, `configurationHash=${ticket.configurationHash}`,
    `requestHash=${ticket.requestHash ?? hash(r)}`, `jobId=${ticket.jobId ?? ""}`, `attemptId=${ticket.attemptId ?? ""}`,
    `from=${Date.parse(r.fromUtc) / 1000}`, `to=${Date.parse(r.toUtc) / 1000}`, `weeks=${r.auditWeeks}`];
  for (const [k, v] of Object.entries(c.inputs)) rows.push(`i.${k}=${v}`);
  for (const [k, v] of Object.entries(c.runtime)) rows.push(`r.${k}=${v}`);
  c.dayHourMasks.forEach((mask, i) => rows.push(`m.${i}=${mask}`));
  if (c.builder) for (const [k, v] of Object.entries(c.builder)) {
    if (!Array.isArray(v)) rows.push(`b.${k}=${v}`);
    else { rows.push(`b.${k}.count=${v.length}`); v.forEach((rule, i) => rows.push(`b.${k}.${i}=${[rule.feature, rule.comparator, rule.threshold, rule.gate, rule.negate, rule.period, rule.rhsFeature, rule.rhsPeriod].join(",")}`)); }
  }
  return rows.join("\n");
}
export function signEaCommand(body, privateKey) {
  return body + "\nSERVER_RSA256=" + sign("sha256", Buffer.from(body), { key: privateKey, padding: constants.RSA_PKCS1_PADDING }).toString("hex");
}
export function verifyEaCommand(packet, publicKey) {
  const at = packet.lastIndexOf("\nSERVER_RSA256="), signature = packet.slice(at + 15);
  return at >= 0 && /^[a-f0-9]{512}$/.test(signature) && verify("sha256", Buffer.from(packet.slice(0, at)),
    { key: publicKey, padding: constants.RSA_PKCS1_PADDING }, Buffer.from(signature, "hex"));
}
