import { build } from 'rolldown';
import { resolve } from 'node:path';
import { readFileSync,mkdirSync,writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import './generate-cloud-control.mjs';

const root=resolve(import.meta.dirname,'..'),out=resolve(root,'supabase/functions/stratum-control');
mkdirSync(out,{recursive:true});
const generated=resolve(root,'control-service/cloud/generated/control-plane.mjs');
const result=await build({input:resolve(root,'control-service/cloud/runtime.mjs'),platform:'node',write:false,
 external:id=>id.startsWith('node:')||id==='zod',output:{format:'esm',codeSplitting:false,minify:true},
 plugins:[{name:'cloud-boundaries',resolveId(source,importer){
  if(source.endsWith('control-plane.mjs')&&importer){
    const path=resolve(importer,'..',source);
    if(path===resolve(root,'control-service/control-plane.mjs'))return generated;
  }
  if(source.endsWith('studio-agent-transport.mjs'))return resolve(root,'control-service/cloud/agent-fetch.mjs');
 }}]});
const chunks=result.output.filter(x=>x.type==='chunk');
if(chunks.length!==1||/node:(fs|sqlite|http|https)/.test(chunks[0].code))throw new Error('CLOUD_BUNDLE_INVALID');
writeFileSync(resolve(out,'control-bundle.mjs'),chunks[0].code);
const key=JSON.parse(readFileSync(resolve(root,'control-service/.state/signing-key.json'),'utf8'));
writeFileSync(resolve(out,'operator-public-key.mjs'),'export default '+JSON.stringify(key.publicKey)+';\n');
let schema=readFileSync(resolve(root,'control-service/schema.sql'),'utf8').replace(/^PRAGMA.*\r?\n/gm,'')
 .replace('id INTEGER PRIMARY KEY, at','id BIGSERIAL PRIMARY KEY, at').replaceAll(' INTEGER',' BIGINT');
schema='CREATE SCHEMA IF NOT EXISTS stratum_runtime;\nSET search_path TO stratum_runtime;\n'+schema+'\n';
schema+=`CREATE TABLE IF NOT EXISTS deployment_configuration(id int PRIMARY KEY CHECK(id=1),sealed text NOT NULL);
CREATE TABLE IF NOT EXISTS rate_limits(key text PRIMARY KEY,until_at bigint NOT NULL,count int NOT NULL);
CREATE INDEX IF NOT EXISTS sessions_account ON sessions(account_id,expires_at DESC);
CREATE INDEX IF NOT EXISTS installations_account ON installations(account_id);
CREATE INDEX IF NOT EXISTS events_account ON audit_events(account_id,at DESC);
REVOKE ALL ON SCHEMA stratum_runtime FROM PUBLIC,anon,authenticated;
REVOKE ALL ON ALL TABLES IN SCHEMA stratum_runtime FROM PUBLIC,anon,authenticated;
DO $$DECLARE r record;BEGIN FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='stratum_runtime' LOOP
 EXECUTE format('ALTER TABLE stratum_runtime.%I ENABLE ROW LEVEL SECURITY',r.tablename);
END LOOP;END$$;
RESET search_path;
`;
writeFileSync(resolve(root,'control-service/cloud/schema.sql'),schema);
writeFileSync(resolve(out,'build.json'),JSON.stringify({canonical:JSON.parse(readFileSync(resolve(root,'control-service/cloud/generated/sources.json'),'utf8')),
 bundleSha256:createHash('sha256').update(chunks[0].code).digest('hex')},null,2)+'\n');
console.log('Cloud bundle prepared: '+chunks[0].code.length+' bytes; no private keys or EA binaries included.');
