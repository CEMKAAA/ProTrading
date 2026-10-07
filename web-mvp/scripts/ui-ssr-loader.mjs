import {readFileSync,existsSync} from 'node:fs';
import {resolve,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {runInNewContext} from 'node:vm';
import ts from 'typescript';
const root=fileURLToPath(new URL('..',import.meta.url)),require=createRequire(import.meta.url),cache=new Map();
export function loadUi(path){
 const file=resolve(root,path);if(cache.has(file))return cache.get(file);
 const module={exports:{}};cache.set(file,module.exports);
 const output=ts.transpileModule(readFileSync(file,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,jsx:ts.JsxEmit.ReactJSX,esModuleInterop:true,target:ts.ScriptTarget.ES2022}}).outputText;
 const local=id=>{
  if(id.startsWith('@/')||id.startsWith('.')){
   const base=id.startsWith('@/')?resolve(root,id.slice(2)):resolve(dirname(file),id);
   const candidate=[base,base+'.tsx',base+'.ts',base+'.json'].find(existsSync);
   if(candidate?.endsWith('.json'))return require(candidate);
   if(candidate)return loadUi(candidate);
  }
  return require(id);
 };
 runInNewContext(output,{module,exports:module.exports,require:local,process,structuredClone,console});cache.set(file,module.exports);return module.exports;
}
