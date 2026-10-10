import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,existsSync} from 'node:fs';
import {universalConfigurationSchema} from '../lib/universal-contract.ts';
const path=new URL('../../reports/admin_catalog/catalog.private.json',import.meta.url);
const records=existsSync(path)?JSON.parse(readFileSync(path,'utf8')):[];
test('all captured native catalog configurations validate; no source is silently omitted',{skip:!records.length},()=>{
 const report=JSON.parse(readFileSync(new URL('../../reports/admin_catalog/import-report.json',import.meta.url),'utf8'));assert.deepEqual(report.failures,[]);
 const expected=Object.values(report.counts).reduce((n,f)=>n+f.total,0);
 assert.equal(records.length,expected);assert.equal(new Set(records.map(r=>r.id)).size,expected);
 for(const record of records){assert.ok(record.configuration,record.name);const c=universalConfigurationSchema.parse(record.configuration);assert.equal(c.name,record.name);assert.equal(c.family,record.family);assert.match(record.source_hash,/^[a-f0-9]{64}$/);
  if(record.family==='sol'&&record.native_snapshot.values){const v=record.native_snapshot.values;assert.equal(c.inputs.InpDefaultHtf,v[0]);assert.equal(c.inputs.InpDefaultEntryTf,v[1]);assert.equal(c.runtime.inversion,!!v[16]);assert.equal(c.inputs.InpPipSlPips,v[20]);assert.equal(c.runtime.reverseExit,c.inputs.InpCloseOnReverse);}
  const lines=record.native_snapshot.lines;if(!lines)continue;
  if(record.family!=='sol'){
   assert.equal(c.inputs.InpSignalTimeframe,Number(lines[64+29]));
   const engine=lines[5].split('|').find(m=>m.startsWith('LABENGINE1='))?.slice(11).split('~');
   const pip=engine&&['LAB4','LAB5'].includes(engine[0])?engine[8].split(',').map(Number):[0,0];
   const policy=engine&&Boolean(Number(engine[7].split(',')[0]));
   assert.equal(c.inputs.InpPipSlPips,policy&&pip[0]?pip[1]:Number(lines[64+39]),record.name);
   if(policy)assert.equal(c.inputs.InpPipSlModeDefault,true,record.name);
   const meta=lines[5].split('|').find(m=>m.startsWith('MAENTRY1='));if(meta){const [ind,max]=meta.slice(9).split(',').map(Number);assert.equal(c.runtime.independent,!!ind);assert.equal(c.runtime.maxOpen,max);}
   const tcal=lines[5].split('|').find(m=>m.startsWith('TCAL1='));if(tcal){const v=tcal.slice(6).split(',').map(Number);assert.deepEqual(c.dayHourMasks,v.slice(1,8));assert.equal(c.runtime.timeMatrixEnabled,!!v[0]);}
  }else{const v=lines.slice(6,6+Number(lines[5])).map(Number);assert.equal(c.inputs.InpDefaultHtf,v[0]);assert.equal(c.inputs.InpDefaultEntryTf,v[1]);assert.equal(c.inputs.InpPipSlPips,v[20]);assert.equal(c.runtime.inversion,!!v[16]);
   const nas=lines.find(s=>s.startsWith('LN_NAS_V1|'));
   if(nas){const n=nas.split('|').slice(1).map(Number);
    const keys=['nasGate','nasExit','nasStateVolume','nasFlowVolume','independent','reverseExit','nasStateMultiplier','nasFlowMultiplier','nasSensitivity','nasWaitMinutes','nasAgeMinutes','maxOpen','reverseWaitMinutes'];
    const booleans=new Set(['nasStateVolume','nasFlowVolume','independent','reverseExit']);
    // Legacy's inactive MAX=0 still admits only one position.
    keys.forEach((key,i)=>assert.equal(c.runtime[key],booleans.has(key)?!!n[i]:key==='maxOpen'?Math.max(1,n[i]):n[i],record.name+':'+key));
   }else{assert.equal(c.runtime.maxOpen,1,record.name);assert.equal(c.runtime.reverseExit,c.inputs.InpCloseOnReverse,record.name);}
  }
 }
});
test('Sol H1.5 is accepted without changing 90 to another timeframe',{skip:!records.length},()=>{
 const values=records.filter(r=>r.configuration.inputs.InpDefaultHtf===90);assert.ok(values.length>=3);for(const r of values)assert.equal(universalConfigurationSchema.parse(r.configuration).inputs.InpDefaultHtf,90);
});
