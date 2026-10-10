import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {publicPath} from '../lib/public-path.ts';
import {controlEndpoint,controlCredentials,controlTimeout} from '../lib/control-endpoint.ts';
import {CLOUD_CONTROL} from '../control-service/api-location.mjs';

test('public asset paths follow the build prefix; external/protocol-relative paths are refused',()=>{
 const base=process.env.NEXT_PUBLIC_BASE_PATH || '';
 assert.equal(publicPath('/favicon.svg'),base+'/favicon.svg');
 assert.equal(publicPath('/benchmark-evidence.json'),base+'/benchmark-evidence.json');
 for(const path of ['https://evil.test/a','//evil.test/a','asset.json'])assert.throws(()=>publicPath(path));
});
test('published frontend uses Supabase, not a visitor localhost service',()=>{
 assert.equal(controlEndpoint('cemkaaa.github.io'),CLOUD_CONTROL);
 assert.equal(controlEndpoint('127.0.0.1'), 'http://127.0.0.1:4321');
});

test('cloud bearer requests omit cookies; local browser sessions retain their HttpOnly cookie',()=>{
 assert.equal(controlCredentials(CLOUD_CONTROL),'omit');
 assert.equal(controlCredentials('http://127.0.0.1:4321'),'include');
 assert.equal(controlCredentials('http://localhost:4321'),'include');
});

test('cloud requests allow cold-start latency without changing local timeouts',()=>{
 assert.equal(controlTimeout(CLOUD_CONTROL),45000);
 assert.equal(controlTimeout('http://127.0.0.1:4321'),10000);
});

test('every control client uses the same environment-aware credentials policy',()=>{
 for(const file of ['components/connection-panel.tsx','components/universal-dashboard.tsx','components/admin-strategy-access.tsx','components/shared-strategy-library.tsx','components/studio-agent.tsx','components/studio.tsx','lib/ea-download.ts']){
  const source=readFileSync(new URL('../'+file,import.meta.url),'utf8');
  assert.match(source,/credentials:\s*CONTROL_CREDENTIALS/,file);
  assert.doesNotMatch(source,/credentials:\s*['"]include['"]/,file);
 }
});
test('main routes remain Next links while raw download/favicon links use the prefix',()=>{
 const page=readFileSync(new URL('../components/launch-page.tsx',import.meta.url),'utf8');
 assert.ok(page.includes('<Link href="/studio"'));
 assert.ok(page.includes('href={publicPath("/benchmark-evidence.json")}'));
 assert.ok(readFileSync(new URL('../app/layout.tsx',import.meta.url),'utf8').includes('publicPath("/favicon.svg")'));
});
