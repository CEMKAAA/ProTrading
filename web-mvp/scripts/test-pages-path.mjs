import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {publicPath} from '../lib/public-path.ts';
import {controlEndpoint} from '../lib/control-endpoint.ts';
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
test('main routes remain Next links while raw download/favicon links use the prefix',()=>{
 const page=readFileSync(new URL('../components/launch-page.tsx',import.meta.url),'utf8');
 assert.ok(page.includes('<Link href="/studio"'));
 assert.ok(page.includes('href={publicPath("/benchmark-evidence.json")}'));
 assert.ok(readFileSync(new URL('../app/layout.tsx',import.meta.url),'utf8').includes('publicPath("/favicon.svg")'));
});
