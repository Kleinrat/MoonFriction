import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,rm,symlink,mkdir,copyFile} from 'node:fs/promises';
import os from 'node:os';import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {loadBundle,exportBundle} from './cli.mjs';
const temp=await mkdtemp(path.join(os.tmpdir(),'moonfriction-test-'));
try{
 const chinese=path.join(temp,'中文项目');
 await mkdir(path.join(chinese,'scripts'),{recursive:true});
 await mkdir(path.join(chinese,'_build/js/release/build/src/api'),{recursive:true});
 await copyFile('scripts/cli.mjs',path.join(chinese,'scripts/cli.mjs'));
 await copyFile('_build/js/release/build/src/api/api.js',path.join(chinese,'_build/js/release/build/src/api/api.js'));
 await writeFile(path.join(chinese,'package.json'),'{"type":"module"}');
 const fromChinese=JSON.parse(execFileSync(process.execPath,[path.join(chinese,'scripts/cli.mjs'),'validate',path.resolve('examples/shop/datapackage.json')],{encoding:'utf8'}));
 assert.equal(fromChinese.ok,true);
 const original=await loadBundle('examples/shop/datapackage.json');assert.equal(original.report.ok,true);
 const dest=path.join(temp,'exported');await exportBundle(original,dest);
 const copied=await loadBundle(path.join(dest,'datapackage.json'));assert.equal(copied.report.ok,true);assert.deepEqual(copied.descriptor,original.descriptor);
 assert.equal(await readFile(path.join(dest,'products.csv'),'utf8'),await readFile('examples/shop/products.csv','utf8'));
 await assert.rejects(exportBundle(original,dest),/already exists/);
 await writeFile(path.join(dest,'orders.csv'),'id,product_id,quantity\n101,999,1\n');
 const bad=await loadBundle(path.join(dest,'datapackage.json'));assert.equal(bad.report.ok,false);assert(bad.report.errors.some(e=>e.code==='foreign-key'));
 await assert.rejects(exportBundle(bad,path.join(temp,'bad')),/invalid package/);
 await rm(path.join(dest,'products.csv'));await symlink(path.resolve('examples/shop/products.csv'),path.join(dest,'products.csv'));
 await assert.rejects(loadBundle(path.join(dest,'datapackage.json')),/escapes/);
 console.log('Host integration: import, export, metadata/byte preservation, overwrite refusal, foreign key failure and symlink containment and Chinese CLI path passed');
}finally{await rm(temp,{recursive:true,force:true});}
