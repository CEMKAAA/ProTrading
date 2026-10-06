import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { eaKeyPair, eaModulus } from "../control-service/ea-authority.mjs";

const state = new URL("../control-service/.state/", import.meta.url);
mkdirSync(state, { recursive: true });
const file = new URL("ea-signing-key.json", state);
const key = existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : eaKeyPair();
if (!existsSync(file)) writeFileSync(file, JSON.stringify(key), { mode: 0o600 });
const header = new URL("../../IndicatorCodeExamples/universal/UniversalAuthorityKey.mqh", import.meta.url);
writeFileSync(header, `// Public verification key only. Rebuild EX5 when this deployment key changes.\n#define UC_AUTHORITY_MODULUS "${eaModulus(key.publicKey)}"\n`);
console.log("EA public key pinned:", fileURLToPath(header));
