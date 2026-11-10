import assert from 'node:assert/strict';
import {readdir,readFile,writeFile} from 'node:fs/promises';
import {hints,diagnosticTable,describeDiagnostic} from './diagnostics.mjs';
export async function sourceCodes(root='src'){
 const codes=new Set();
 async function walk(dir){for(const entry of await readdir(dir,{withFileTypes:true})){
  const p=`${dir}/${entry.name}`;if(entry.isDirectory())await walk(p);
  else if(p.endsWith('.mbt')&&!p.includes('test.mbt')){
   const text=(await readFile(p,'utf8')).replace(/\/\/[^\n]*/g,'');
   const calls=[...text.matchAll(/\bissue\s*\(\s*([^,]+)/g)].filter(m=>!text.slice(Math.max(0,m.index-3),m.index).includes('fn '));
   for(const m of calls){const literal=m[1].match(/^"([^"\n]+)"$/);assert(literal,`Dynamic diagnostic code needs explicit checker support: ${p}: ${m[1]}`);codes.add(literal[1]);}
   for(const m of text.matchAll(/"code"\s*:\s*"([^"\n]+)"/g))codes.add(m[1]);
  }
 }}await walk(root);return codes;
}
export function checkCoverage(codes,mapping){
 for(const code of codes){assert(Object.hasOwn(mapping,code),`Missing Chinese diagnostic: ${code}`);assert(mapping[code].title?.trim()&&mapping[code].fix?.trim(),`Empty diagnostic: ${code}`);}
}
const codes=await sourceCodes();checkCoverage(codes,hints);
// Prove missing mappings and newly emitted codes fail the coverage gate.
for(const code of codes){const copy={...hints};delete copy[code];assert.throws(()=>checkCoverage(codes,copy));}
assert.throws(()=>checkCoverage(new Set([...codes,'new-unmapped-code']),hints));
assert.equal(describeDiagnostic('__proto__').title,'未知诊断代码');
const file='docs/zh/getting-started.md',begin='<!-- diagnostics:start -->',end='<!-- diagnostics:end -->';
const doc=await readFile(file,'utf8');assert(doc.includes(begin)&&doc.includes(end));
const expected=doc.slice(0,doc.indexOf(begin)+begin.length)+'\n'+diagnosticTable()+'\n'+doc.slice(doc.indexOf(end));
if(process.argv.includes('--write'))await writeFile(file,expected);
else assert.equal(doc,expected,'Diagnostic table is stale: node scripts/check_diagnostics.mjs --write');
console.log(`Chinese diagnostics: ${codes.size} source codes covered; missing/new-code mutation checks passed`);
