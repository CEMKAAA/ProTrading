import { mkdirSync, existsSync, readFileSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { randomBytes } from 'node:crypto';
import { ControlPlane } from "./control-plane.mjs";
import { controlHttp } from "./http.mjs";
import { keyPair } from "./crypto.mjs";
import { eaKeyPair } from "./ea-authority.mjs";
import { SupabaseAuth } from './supabase-auth.mjs';
import { supabaseConfig } from './supabase-config.mjs';
import { supabaseTransport } from './supabase-transport.mjs';
import { createStudioAgent } from './studio-agent.mjs';
import { studioAgentEnvironment } from './studio-agent-config.mjs';

// Never silently turn a local test identity into production authorization.
if (!["--local-dev","--supabase"].includes(process.argv[2]) || process.env.NODE_ENV === "production") {
  console.error("Use --supabase for real DB-backed auth or --local-dev for isolated QA. This launcher binds loopback, not a public production deployment.");
  process.exit(1);
}
const root = fileURLToPath(new URL("./.state/", import.meta.url));
mkdirSync(root, { recursive: true });
const signingFile = join(root, "signing-key.json");
const signingKey = existsSync(signingFile) ? JSON.parse(readFileSync(signingFile, "utf8")) : keyPair();
if (!existsSync(signingFile)) writeFileSync(signingFile, JSON.stringify(signingKey), { mode: 0o600 });
writeFileSync(join(root, "server-public.pem"), signingKey.publicKey);
const eaSigningFile = join(root, "ea-signing-key.json");
const eaSigningKey = existsSync(eaSigningFile) ? JSON.parse(readFileSync(eaSigningFile, "utf8")) : eaKeyPair();
if (!existsSync(eaSigningFile)) writeFileSync(eaSigningFile, JSON.stringify(eaSigningKey), { mode: 0o600 });
const plane = new ControlPlane({ database: join(root, "control.sqlite"), signingKey, eaSigningKey });
const useSupabase=process.argv[2]==='--supabase';
let auth=null;
if(useSupabase){
  const file=join(root,'provider-encryption.key');
  if(!existsSync(file))writeFileSync(file,randomBytes(32),{mode:0o600,flag:'wx'});
  auth=new SupabaseAuth(plane,{...supabaseConfig,encryptionKey:readFileSync(file),fetcher:supabaseTransport(supabaseConfig)});
}
if(!useSupabase){
const accountId = "c8887b55-0952-42ad-a8b9-7c9f1f55e0fd";
plane.provisionAccount(accountId, Date.now() + 86400000);
plane.setDisplayName(accountId,"Yerel test abonesi");
const accessFile = join(root, "dev-access.json");
let session;
try { session = JSON.parse(readFileSync(accessFile, "utf8")); plane.browser(session.accessToken); } catch { session = plane.issueBrowserSession(accountId); }
writeFileSync(accessFile, JSON.stringify({ ...session, accountId, developmentOnly: true }, null, 2), { mode: 0o600 });
console.log(`Local QA session file: ${resolve(accessFile)} (never ship it)`);
}
const agent = createStudioAgent({env:studioAgentEnvironment(),report:event=>console.warn('[studio-agent]',JSON.stringify(event))});
const server = controlHttp(plane,{auth,agent});
server.listen(4321, "127.0.0.1", () => {
  console.log(`${useSupabase?'Supabase DB/Auth':'Local QA'}: http://127.0.0.1:4321. Apply is audit-only; Trading starts OFF.`);
  if(useSupabase)console.log(`Identity and demo authority: ${supabaseConfig.url}`);
  const ai=agent.status().providers.openrouter;
  console.log(`Assistant OpenRouter: ${ai.configured?'configured':'not configured'}${ai.model?` (${ai.model})`:''}.`);
});
function stop() { server.close(() => { plane.close(); process.exit(0); }); }
process.on("SIGINT", stop); process.on("SIGTERM", stop);
