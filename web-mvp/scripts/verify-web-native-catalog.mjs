// Emit private SQL for an exact comparison; never infer a configuration from a strategy name.
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

export function verifyCatalogSql(records){
 // proposedConfiguration is importer diagnostics, not the saved native preset.
 const expected=records.map(r=>({...r,native_snapshot:Object.fromEntries(Object.entries(r.native_snapshot).filter(([k])=>k!=='proposedConfiguration'))}));
 const data=JSON.stringify(expected).replaceAll("'","''");
 return `with expected as (select * from jsonb_to_recordset('${data}'::jsonb)
  as x(id text,family text,name text,symbol text,source_hash text,configuration jsonb,native_snapshot jsonb,active boolean))
 select jsonb_build_object('checked',(select count(*) from expected),
  'missing',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'name',e.name)) from expected e
    left join stratum_private.strategy_catalog c using(id) where c.id is null),'[]'),
  'mismatched',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'name',e.name,
    'source',c.source_hash is distinct from e.source_hash,'configuration',c.configuration is distinct from e.configuration,
    'snapshot',c.native_snapshot is distinct from e.native_snapshot)) from expected e join stratum_private.strategy_catalog c using(id)
    where c.source_hash is distinct from e.source_hash or c.configuration is distinct from e.configuration
      or c.native_snapshot is distinct from e.native_snapshot or c.family is distinct from e.family or c.name is distinct from e.name
      or c.symbol is distinct from e.symbol or c.active is distinct from e.active),'[]')) as verification;`;
}

if(import.meta.url===pathToFileURL(resolve(process.argv[1]??'')).href){
 const records=JSON.parse(readFileSync(resolve(process.argv[2]),'utf8'));
 const offset=Number(process.argv[3]??0),count=Number(process.argv[4]??20);
 if(!Number.isSafeInteger(offset)||!Number.isSafeInteger(count)||offset<0||count<1)throw Error('INVALID_BATCH');
 process.stdout.write(verifyCatalogSql(records.slice(offset,offset+count)));
}
