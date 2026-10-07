import assert from 'node:assert/strict';
import {test} from 'node:test';
import {mkdtempSync,writeFileSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {studioAgentEnvironment} from '../control-service/studio-agent-config.mjs';

test('missing optional file keeps only allowlisted server variables',()=>{
 const result=studioAgentEnvironment({env:{STRATUM_AI_OPENROUTER_MODEL:'test/model',NEXT_PUBLIC_SECRET:'not permitted'},file:join(tmpdir(),'stratum-does-not-exist','assistant.env')});
 assert.deepEqual(result,{STRATUM_AI_OPENROUTER_MODEL:'test/model'});
});

test('private file supplies defaults; explicit process variables win without mutating the process',()=>{
 const dir=mkdtempSync(join(tmpdir(),'stratum-agent-config-'));
 try{
  const file=join(dir,'assistant.env');
  writeFileSync(file,'STRATUM_AI_OPENROUTER_KEY=test-secret-not-real\nSTRATUM_AI_OPENROUTER_MODEL=test/file-model\nNEXT_PUBLIC_KEY=never-export\nNODE_ENV=production\n');
  const env={STRATUM_AI_OPENROUTER_MODEL:'test/operator-model'};
  assert.deepEqual(studioAgentEnvironment({env,file}),{STRATUM_AI_OPENROUTER_KEY:'test-secret-not-real',STRATUM_AI_OPENROUTER_MODEL:'test/operator-model'});
  assert.deepEqual(env,{STRATUM_AI_OPENROUTER_MODEL:'test/operator-model'});
 }finally{rmSync(dir,{recursive:true,force:true});}
});
