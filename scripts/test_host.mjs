import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtemp,writeFile,readFile,rm,symlink,mkdir,copyFile} from 'node:fs/promises';
import os from 'node:os';import path from 'node:path';
import {execFile,execFileSync,spawnSync} from 'node:child_process';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {promisify} from 'node:util';
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
 const general = path.join(temp, 'general');
 await mkdir(general);
 const generalManifest = path.join(general, 'package.json');
 const generalDestination = path.join(temp, 'general-export');
 const bytes = Buffer.from([0, 255, 17, 0]);
 await writeFile(path.join(general, 'part-a.bin'), bytes.subarray(0, 2));
 await writeFile(path.join(general, 'part-b.bin'), bytes.subarray(2));
 await writeFile(path.join(general, 'schema.json'), '{"description":"arbitrary resource schema"}');
 const hash = 'sha256:' + createHash('sha256').update(bytes).digest('hex');
 const resource = {
   name: 'binary', path: ['part-a.bin', 'part-b.bin'], format: 'binary',
   schema: 'schema.json', bytes: bytes.length, hash,
 };
 const generalDescriptor = {resources: [resource, {name:'inline', data:{items:[1]}},
   {name:'remote', path:'https://example.org/part'}]};
 const generic = (...args) => spawnSync(process.execPath, ['scripts/cli.mjs', ...args], {encoding:'utf8'});
 await writeFile(generalManifest, JSON.stringify(generalDescriptor));
 const exported = generic('export-package', generalManifest, generalDestination);
 assert.equal(exported.status, 0, exported.stderr);
 assert.deepEqual(JSON.parse(await readFile(path.join(generalDestination,'datapackage.json'),'utf8')), generalDescriptor);
 assert.deepEqual(await readFile(path.join(generalDestination,'part-b.bin')), bytes.subarray(2));
 assert.ok(await readFile(path.join(generalDestination,'schema.json')));
 assert.equal(generic('export-package', generalManifest, generalDestination).status, 2);
 await writeFile(path.join(general,'part-b.bin'), Buffer.from([12, 0]));
 const tampered = generic('export-package', generalManifest, path.join(temp,'bad-checksum'));
 assert.equal(tampered.status, 2);
 assert.match(tampered.stderr, /checksum/);
 await writeFile(path.join(general,'part-b.bin'), Buffer.alloc(1));
 const differentSize = generic('export-package', generalManifest, path.join(temp,'bad-size'));
 assert.equal(differentSize.status, 2);
 assert.match(differentSize.stderr, /size/);
 await rm(path.join(general,'part-b.bin'));
 await symlink(path.resolve('examples/shop/products.csv'), path.join(general,'part-b.bin'));
 const escaped = generic('export-package', generalManifest, path.join(temp,'escaped'));
 assert.equal(escaped.status, 2);
 assert.match(escaped.stderr, /escapes/);
 const fixture = 'examples/standard-exchange/multipart.json';
 const multipart = generic('validate', fixture);
 assert.equal(multipart.status, 0, multipart.stdout + multipart.stderr);
 assert.deepEqual(JSON.parse(multipart.stdout).resources, [{name:'products',rows:3},{name:'shipments',rows:2}]);
 const multipartCopy = path.join(temp, 'multipart-copy');
 assert.equal(generic('export', fixture, multipartCopy).status, 0);
 const multipartManifest = path.join(multipartCopy, 'datapackage.json');
 const exactDescriptor = await readFile(multipartManifest,'utf8');
 assert.match(exactDescriptor, /9007199254740993/);
 assert.equal(generic('validate', multipartManifest).status, 0);
 const badInline = exactDescriptor.replace('"P30"', '"P99"');
 await writeFile(multipartManifest, badInline);
 const badFk = generic('validate', multipartManifest);
 assert.equal(badFk.status, 1, badFk.stdout + badFk.stderr);
 assert.equal(JSON.parse(badFk.stdout).errors[0].code, 'foreign-key');
 await writeFile(multipartManifest, exactDescriptor);
 const annex = path.join(multipartCopy,'products-annex.csv');
 await writeFile(annex,'sku,name\nP10,Duplicate\n');
 const duplicate = generic('validate', multipartManifest);
 assert.equal(duplicate.status, 1);
 assert.ok(JSON.parse(duplicate.stdout).errors.some(error =>
   error.resource === 'products' && error.row === 3 && error.code === 'primary-key-duplicate'));
 await writeFile(annex,'wrong,name\nP30,Pencil\n');
 const badHeader = generic('validate', multipartManifest);
 assert.equal(badHeader.status, 1);
 assert.equal(JSON.parse(badHeader.stdout).errors[0].code, 'header');

 const requests = [];
 const server = createServer((request,response) => {
   requests.push(request.url);
   switch (request.url) {
     case '/datapackage.json':
       response.end(JSON.stringify({resources:[{name:'items',path:['first.csv','second.csv'],
         schema:'schema.json',dialect:'dialect.json',encoding:'iso-8859-1'}]}));
       break;
     case '/schema.json':
       response.end(JSON.stringify({fields:[{name:'id',type:'integer'},{name:'title'}],primaryKey:'id'}));
       break;
     case '/dialect.json':
       response.end(JSON.stringify({header:false, delimiter:';', lineTerminator:'\n'}));
       break;
     case '/first.csv':
       response.end(Buffer.from('1;café\n','latin1'));
       break;
     case '/second.csv':
       response.end(Buffer.from('2;olé\n','latin1'));
       break;
     case '/redirect.csv':
       response.writeHead(302, {location:'/first.csv'}).end();
       break;
     default:
       response.writeHead(404).end();
   }
 });
 try {
   server.listen(0, '127.0.0.1');
   await once(server,'listening');
   const url = 'http://127.0.0.1:' + server.address().port;
   const remoteDescriptor = {
     resources:[{name:'items',path:[url+'/first.csv',url+'/second.csv'],schema:url+'/schema.json',
       dialect:url+'/dialect.json',encoding:'iso-8859-1'}],
   };
   const remoteManifest = path.join(temp,'remote.json');
   await writeFile(remoteManifest,JSON.stringify(remoteDescriptor));
   assert.equal(generic('validate', remoteManifest).status, 1);
   assert.deepEqual(requests, []);
   const runAsync = promisify(execFile);
   const remote = await runAsync(process.execPath,['scripts/cli.mjs','validate',remoteManifest,'--allow-remote']);
   assert.deepEqual(JSON.parse(remote.stdout).resources,[{name:'items',rows:2}]);
   assert.deepEqual(requests, ['/schema.json','/dialect.json','/first.csv','/second.csv']);
   remoteDescriptor.resources[0].path = url+'/redirect.csv';
   await writeFile(remoteManifest,JSON.stringify(remoteDescriptor));
   await assert.rejects(runAsync(process.execPath,['scripts/cli.mjs','validate',remoteManifest,'--allow-remote']),
     error => error.code === 2 && JSON.parse(error.stderr).ok === false);
   assert.equal(requests.at(-1), '/redirect.csv');
   const remotePackage = url + '/datapackage.json';
   const fromRemote = await runAsync(process.execPath, ['scripts/cli.mjs','validate',remotePackage,'--allow-remote']);
   assert.deepEqual(JSON.parse(fromRemote.stdout).resources, [{name:'items',rows:2}]);
   const remoteCopy = path.join(temp,'remote-export');
   await runAsync(process.execPath, ['scripts/cli.mjs','export',remotePackage,remoteCopy,'--allow-remote']);
   assert.equal(generic('validate', path.join(remoteCopy,'datapackage.json')).status, 0);
   assert.deepEqual(await readFile(path.join(remoteCopy,'first.csv')),Buffer.from('1;café\n','latin1'));
 } finally {
   await new Promise(resolve => server.close(resolve));
 }
 console.log('Host integration: import, export, metadata/byte preservation, overwrite refusal, foreign key failure and symlink containment and Chinese CLI path passed');
}finally{await rm(temp,{recursive:true,force:true});}
