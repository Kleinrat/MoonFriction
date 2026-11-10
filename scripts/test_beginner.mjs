import assert from 'node:assert/strict';
import {hints} from './diagnostics.mjs';
import {mkdtemp,cp,readFile,writeFile,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
const cases=[['shop',null],['broken-type','type'],['broken-primary-key','primary-key-duplicate'],['broken-foreign-key','foreign-key'],['broken-header','header']];
for(const [name,code] of cases){
 const file=`examples/${name}/datapackage.json`;
 const raw=spawnSync(process.execPath,['scripts/cli.mjs','validate',file],{encoding:'utf8'});
 assert.equal(raw.status,code?1:0,raw.stderr);const report=JSON.parse(raw.stdout);
 if(code)assert(report.errors.some(e=>e.code===code),raw.stdout);
 const human=spawnSync(process.execPath,['scripts/explain.mjs',file],{encoding:'utf8'});
 assert.equal(human.status,raw.status,human.stderr);
 assert(human.stdout.includes(code?`[${code}]`:'检查通过'),human.stdout);
 if(code){const title=hints[code].title;assert(human.stdout.includes(title)&&human.stdout.includes('建议：'),human.stdout);}
}
for(const args of [[],['does-not-exist.json']])assert.equal(spawnSync(process.execPath,['scripts/explain.mjs',...args]).status,2);
console.log('Beginner examples: valid package, four errors, Chinese explanations and I/O exits passed');

const temp=await mkdtemp(path.join(os.tmpdir(),'moonfriction-repair-'));
try {
 for(const [name] of cases.filter(x=>x[1])){
  const dest=path.join(temp,name);await cp(`examples/${name}`,dest,{recursive:true});
  const csv=path.join(dest,['broken-primary-key','broken-header'].includes(name)?'products.csv':'orders.csv');
  let text=await readFile(csv,'utf8');
  text=text.replace('two','2').replace('1,钢笔','2,钢笔').replace('999','1').replace('id,wrong','id,title');await writeFile(csv,text);
  const fixed=spawnSync(process.execPath,['scripts/explain.mjs',path.join(dest,'datapackage.json')],{encoding:'utf8'});
  assert.equal(fixed.status,0,fixed.stdout+fixed.stderr);assert(fixed.stdout.includes('检查通过'));
 }
 console.log('All four documented repairs passed without modifying source fixtures');
}finally{await rm(temp,{recursive:true,force:true});}

const headerTemp=await mkdtemp(path.join(os.tmpdir(),'moonfriction-header-'));
try{
 await cp('examples/shop',headerTemp,{recursive:true});
 const file=path.join(headerTemp,'products.csv');const original=await readFile(file,'utf8');
 await writeFile(file,original.replace('id,title','id,wrong'));
 let h=spawnSync(process.execPath,['scripts/explain.mjs',path.join(headerTemp,'datapackage.json')],{encoding:'utf8'});
 assert.equal(h.status,1);assert(h.stdout.includes('[header]')&&h.stdout.includes('表头与规则不一致'));
 await writeFile(file,original);
 h=spawnSync(process.execPath,['scripts/explain.mjs',path.join(headerTemp,'datapackage.json')],{encoding:'utf8'});assert.equal(h.status,0);
 console.log('Header explanation and repair passed');
}finally{await rm(headerTemp,{recursive:true,force:true});}
