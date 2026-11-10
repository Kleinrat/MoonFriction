import assert from 'node:assert/strict';
import {mkdtemp,readFile,rm,readdir} from 'node:fs/promises';
import path from 'node:path';import os from 'node:os';import {spawnSync} from 'node:child_process';import {createHash} from 'node:crypto';
async function fixtureDigest(dir='examples'){
 const hash=createHash('sha256');
 async function walk(p){for(const e of (await readdir(p,{withFileTypes:true})).sort((a,b)=>a.name.localeCompare(b.name))){const q=path.join(p,e.name);if(e.isDirectory())await walk(q);else{hash.update(q);hash.update(await readFile(q));}}}await walk(dir);return hash.digest('hex');
}
const before=await fixtureDigest();const temp=await mkdtemp(path.join(os.tmpdir(),'moonfriction-docs-'));
try{
 let script='set +e\n',count=0;
 for(const file of ['docs/zh/getting-started.md','docs/zh/errors-demo.md']){
  const doc=await readFile(file,'utf8');
  const blocks=[...doc.matchAll(/<!-- test: exit=(\d+) -->\s*```sh\n([\s\S]*?)\n```/g)];
  assert.equal(blocks.length,[...doc.matchAll(/```sh\n/g)].length,`Unannotated shell block: ${file}`);
  for(const [,exit,body] of blocks){count++;script+=`{\n${body}\n}\nactual=$?\nif [ "$actual" -ne ${exit} ]; then echo 'Tutorial block ${count} failed: ${file}' >&2; exit 99; fi\n`;}
 }
 assert.equal(count,19,'Expected preparation/export and four full repair flows');
 const result=spawnSync('bash',['-c',script],{encoding:'utf8',env:{...process.env,MOONFRICTION_DEMO:temp},timeout:180000,maxBuffer:2*1024*1024});
 assert.equal(result.status,0,result.stdout+result.stderr+String(result.error??''));
 assert.equal(await fixtureDigest(),before,'Tutorial changed source examples');
 console.log(`Tutorial: ${count} actual documentation blocks passed; four failure/repair flows and export; source fixtures unchanged`);
}finally{await rm(temp,{recursive:true,force:true});}
