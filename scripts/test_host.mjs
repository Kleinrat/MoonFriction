import assert from 'node:assert/strict';
import {mkdtemp,writeFile,readFile,rm,symlink,mkdir,copyFile} from 'node:fs/promises';
import os from 'node:os';import path from 'node:path';
import {execFileSync,spawnSync} from 'node:child_process';
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
 const checkJson = (...mappings) => spawnSync(process.execPath, [
   'scripts/cli.mjs', 'validate-json', 'examples/shop/datapackage.json', ...mappings,
 ], {encoding: 'utf8'});
 const products = 'products=examples/shop/products.json';
 const orders = 'orders=examples/shop/orders.json';
 const validJson = checkJson(orders, products);
 assert.equal(validJson.status, 0, validJson.stderr);
 assert.deepEqual(JSON.parse(validJson.stdout).resources, [{name:'products',rows:1},{name:'orders',rows:1}]);
 const orderFile = path.join(temp, '订单.json');
 await writeFile(orderFile, '[{"id":101,"product_id":9007199254740992,"quantity":1}]');
 const invalidJson = checkJson(products, 'orders=' + orderFile);
 assert.equal(invalidJson.status, 1);
 const linkError = JSON.parse(invalidJson.stdout).errors[0];
 assert.equal(linkError.code, 'foreign-key');
 assert.equal(linkError.resource, 'orders');
 assert.equal(linkError.row, 1);
 const explainJson = (...mappings) => spawnSync(process.execPath, [
   'scripts/explain.mjs', '--json', 'examples/shop/datapackage.json', ...mappings,
 ], {encoding:'utf8'});
 const human = explainJson(products, 'orders=' + orderFile);
 assert.equal(human.status, 1);
 for (const hint of ['orders', '数据记录 1', 'product_id', '引用的记录不存在', '建议：']) {
   assert.ok(human.stdout.includes(hint), human.stdout);
 }
 assert.equal(explainJson(products, orders).status, 0);
 assert.equal(explainJson().status, 2);
 await writeFile(orderFile, '[');
 const syntax = checkJson(products, 'orders=' + orderFile);
 assert.equal(syntax.status, 1);
 assert.equal(JSON.parse(syntax.stdout).errors[0].resource, 'orders');
 assert.equal(checkJson(products).status, 1);
 assert.equal(checkJson(products, orders, orders).status, 1);
 assert.equal(checkJson('orders').status, 2);
 assert.equal(checkJson('orders=' + path.join(temp, 'missing.json')).status, 2);
 const original=await loadBundle('examples/shop/datapackage.json');assert.equal(original.report.ok,true);
 // Reuse the same on-disk schema in two independently named resources.
 const shared = path.join(temp, 'shared');
 await mkdir(shared);
 const schemaFile = path.join(shared, 'columns.json');
 const descriptorFile = path.join(shared, 'datapackage.json');
 const sharedResources = ['first', 'second'].map(name => ({
   name, path: name + '.csv', schema: 'columns.json',
 }));
 const descriptor = {resources:sharedResources};
 await writeFile(schemaFile, '{"fields":[{"name":"id","type":"integer"}],"primaryKey":"id"}');
 for (const item of sharedResources) await writeFile(path.join(shared, item.path), 'id\n1\n');
 await writeFile(descriptorFile, JSON.stringify(descriptor));
 const sharedBundle = await loadBundle(descriptorFile);
 assert.ok(sharedBundle.report.ok);
 const sharedJson = path.join(shared,'rows.json');
 await writeFile(sharedJson,'[{"id":1}]');
 const humanShared = spawnSync(process.execPath, ['scripts/explain.mjs','--json',descriptorFile,
   'first='+sharedJson, 'second='+sharedJson], {encoding:'utf8'});
 assert.equal(humanShared.status,0,humanShared.stdout+humanShared.stderr);
 const moved = path.join(temp, 'portable');
 await exportBundle(sharedBundle,moved);
 await rm(schemaFile);
 assert.ok((await loadBundle(path.join(moved,'datapackage.json'))).report.ok);
 await assert.rejects(loadBundle(descriptorFile), /ENOENT/);
 await writeFile(schemaFile,'{');
 assert.equal((await loadBundle(descriptorFile)).report.errors[0].resource, 'first');
 await rm(schemaFile);
 await symlink(path.resolve('examples/shop/datapackage.json'),schemaFile);
 await assert.rejects(loadBundle(descriptorFile),/escapes/);
 for (const ref of ['../outside.json','https://example.org/schema.json','/tmp/schema.json']) {
   sharedResources[0].schema=ref;
   await writeFile(descriptorFile,JSON.stringify(descriptor));
   assert.equal((await loadBundle(descriptorFile)).report.errors[0].field,'schema');
 }
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
