import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
const run = (...args) => spawnSync(process.execPath, ['scripts/cli.mjs', ...args], {encoding:'utf8'});
const base = 'examples/schema-diff/';
const old = base+'old.json', current = base+'new.json', orders = base+'orders.csv';
function compare(a,b) {
  const result = run('schema','diff',a,b);
  assert.equal(result.status,0,result.stderr);
  return JSON.parse(result.stdout).changes;
}
const changes = compare(old,current);
assert.deepEqual(changes,[{field:'status',rule:'enum',impact:'tightened',before:['draft','paid'],after:['paid'],members:['draft']}]);
assert.equal(compare(current,old)[0].impact,'relaxed');
assert.deepEqual(compare(old,old),[]);
assert.equal(run('validate-stream',old,orders).status,0);
const invalid = run('validate-stream',current,orders);
assert.equal(invalid.status,1);
assert.equal(JSON.parse(invalid.stdout).errors[0].code,'enum');
const dir = await mkdtemp(path.join(tmpdir(),'mf-schema-diff-'));
try {
  const first = path.join(dir, 'first.json');
  const second = path.join(dir, 'second.json');
  const fields = [{name:'a', type:'integer', constraints:{required:true}}, {name:'b'}];
  await writeFile(first, JSON.stringify({fields, primaryKey:['a','b']}));
  await writeFile(second, JSON.stringify({
    fields:[{name:'a', type:'number'}, fields[1]], primaryKey:['b','a']
  }));
  const [type, constraints, key] = compare(first, second);
  assert.deepEqual([type.rule, type.before, type.after], ['type', 'integer', 'number']);
  assert.deepEqual([constraints.field, constraints.rule, constraints.impact], ['a', 'fieldConstraints', 'review']);
  assert.equal(constraints.before.required, true);
  assert.equal(constraints.after.required, false);
  assert.deepEqual(key, {field:'', rule:'primaryKeyOrder', impact:'orderOnly',
    before:['a','b'], after:['b','a']});

  const bad = path.join(dir, 'invalid.json');
  await writeFile(bad,'{');
  for (const [a,b,side] of [[old,bad,'new'],[bad,current,'old']]) {
    const result = run('schema','diff',a,b);
    assert.equal(result.status,1);
    assert.equal(JSON.parse(result.stdout).schema,side);
  }
  assert.equal(run('schema','diff',old).status,2);
  assert.equal(run('schema','diff',old,path.join(dir,'missing')).status,2);
} finally { await rm(dir,{recursive:true,force:true}); }
console.log('Schema diff and order validation agree in both directions');
