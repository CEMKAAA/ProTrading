import assert from 'node:assert/strict';
import { writeFileSync } from 'node:fs';
import { supabaseConfig as c } from '../control-service/supabase-config.mjs';
import { supabaseTransport } from '../control-service/supabase-transport.mjs';
const fetch=supabaseTransport(c);
const headers={apikey:c.publishableKey,'Content-Type':'application/json'};
const settings=await fetch(c.url+'/auth/v1/settings',{headers,signal:AbortSignal.timeout(10000)});
assert.equal(settings.status,200);const s=await settings.json();
const access=await fetch(c.url+'/rest/v1/rpc/stratum_access_state',{method:'POST',headers,body:'{}',signal:AbortSignal.timeout(10000)});
assert.ok([401,403].includes(access.status));
const strategies=await fetch(c.url+'/rest/v1/stratum_strategies?select=name',{headers,signal:AbortSignal.timeout(10000)});
assert.ok([401,403].includes(strategies.status));
const report={projectUrl:c.url,status:'PASS',emailEnabled:!!s.external?.email,emailAutoconfirm:!!s.mailer_autoconfirm,
  publicAccessRpcDenied:access.status,publicStrategiesDenied:strategies.status};
writeFileSync(new URL('../../tmp/universal_connection_validation/supabase-api-report.json',import.meta.url),JSON.stringify(report,null,2));
console.log(JSON.stringify(report));
fetch.close?.();
