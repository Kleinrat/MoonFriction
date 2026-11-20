import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtemp, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
const run = (...args) => spawnSync(process.execPath, ['scripts/cli.mjs', ...args], {encoding:'utf8'});
const base = 'examples/schema-diff/';
const old = base+'old.json', current = base+'new.json', orders = base+'orders.csv';
function compare(a,b) {
  const result = run('schema','diff',a,b);
  assert.equal(result.status,0,result.stderr);
  assert.equal(result.stderr, '');
  return JSON.parse(result.stdout).changes;
}
const expected = async name => JSON.parse(await readFile(base+'expected/'+name+'.json','utf8'));
const updated = run('schema', 'diff', old, base+'revised.json');
assert.equal(updated.status, 0);
assert.equal(updated.stderr, '');
assert.deepEqual(JSON.parse(updated.stdout), await expected('revised'));
const unchanged = run('schema', 'diff', old, old);
assert.equal(unchanged.status, 0);
assert.equal(unchanged.stderr, '');
assert.deepEqual(JSON.parse(unchanged.stdout), {ok:true, changes:[]});
const invalidSchema = base+'invalid.json';
const invalidReport = await expected('invalid');
for (const [left, right, side] of [[old,invalidSchema,'new'], [invalidSchema,old,'old'],
                                  [invalidSchema,invalidSchema,'old']]) {
  const result = run('schema', 'diff', left, right);
  assert.equal(result.status, 1);
  assert.equal(result.stderr, '');
  assert.deepEqual(JSON.parse(result.stdout), {...invalidReport, schema:side});
}
const changes = compare(old,current);
assert.deepEqual(changes,[{field:'status',rule:'enum',impact:'tightened',before:['draft','paid'],after:['paid'],members:['draft']}]);
assert.equal(compare(current,old)[0].impact,'relaxed');
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
    assert.equal(result.stderr, '');
    const report = JSON.parse(result.stdout);
    assert.equal(report.ok, false);
    assert.equal(report.schema, side);
    assert.ok(report.errors.length > 0);
  }
  const invalidUtf8 = path.join(dir, 'invalid-utf8.json');
  await writeFile(invalidUtf8, Buffer.from([0xff]));
  for (const file of [base+'absent.json', invalidUtf8]) {
    const result = run('schema', 'diff', old, file);
    assert.equal(result.status, 2);
    assert.equal(result.stdout, '');
    const failure = JSON.parse(result.stderr);
    assert.deepEqual(Object.keys(failure).sort(), ['error','ok']);
    assert.equal(failure.ok, false);
    assert.equal(typeof failure.error, 'string');
    assert.ok(failure.error.trim().length > 0);
  }
  for (const args of [[], [old], [old,current,old]]) {
    const result = run('schema', 'diff', ...args);
    assert.equal(result.status, 2);
    assert.equal(result.stdout, '');
    assert.match(result.stderr, /^Usage: .*schema diff OLD\.json NEW\.json/);
  }
} finally { await rm(dir,{recursive:true,force:true}); }
console.log('Schema diff and order validation agree in both directions');
