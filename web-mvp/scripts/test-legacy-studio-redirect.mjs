import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {runInNewContext} from 'node:vm';

const html=readFileSync(new URL('./legacy-studio-redirect.html',import.meta.url),'utf8');
const script=/<script>([\s\S]*?)<\/script>/.exec(html)[1];
test('old email/helper Studio URLs keep their local fragments and land at the new same-origin route',()=>{
 for(const [search,hash] of [['',''],['?setup=1','#access_token=fixture'],['?next=https://evil.test','#error=expired']]){
  let target;runInNewContext(script,{window:{location:{search,hash,replace:value=>target=value}}});
  const destination=new URL(target,'https://cemkaaa.github.io');
  assert.equal(destination.origin,'https://cemkaaa.github.io');
  assert.equal(destination.pathname,'/CemkaCapital/studio/');
  assert.equal(destination.search,search);assert.equal(destination.hash,hash);
 }
 assert.ok(!/fetch\(|XMLHttpRequest|localStorage|sessionStorage/.test(script));
 assert.ok(html.includes('content="no-referrer"'));
});
