import assert from 'node:assert/strict';
import {mkdtemp,readFile,writeFile,rm,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const run = (args, options = {}) => spawnSync(process.execPath, args, {encoding: 'utf8', ...options});
const digest = async file => createHash('sha256').update(await readFile(file)).digest('hex');
const temp = await mkdtemp(path.join(os.tmpdir(), 'moonfriction-infer-'));
try {
  const dir = path.join(temp, 'data');
  await mkdir(dir);
  const csv = path.join(dir, 'items.csv');
  const descriptorPath = path.join(dir, 'datapackage.json');
  const csvText = 'id,name,price,active,sku,note\n001,Pen,1.50,true,ABC-1,\n002,Notebook,2,false,ABC-2,hello\n';
  await writeFile(csv, csvText);
  const before = await digest(csv);

  const first = run(['scripts/infer.mjs', csv, '--out', descriptorPath]);
  assert.equal(first.status, 0, first.stderr);
  assert(first.stderr.includes('[id]') && first.stderr.includes('前导零'), first.stderr);
  const descriptor = JSON.parse(await readFile(descriptorPath, 'utf8'));
  const fields = Object.fromEntries(descriptor.resources[0].schema.fields.map(f => [f.name, f.type]));
  assert.deepEqual(fields, {id: 'string', name: 'string', price: 'number', active: 'boolean', sku: 'string', note: 'string'});
  assert.equal(await digest(csv), before, 'inference must not modify the source CSV');

  const output = await readFile(descriptorPath, 'utf8');
  const second = run(['scripts/infer.mjs', csv, '--out', descriptorPath]);
  assert.equal(second.status, 2, 'existing descriptor must not be overwritten');
  assert.equal(await readFile(descriptorPath, 'utf8'), output, 'refused overwrite must leave descriptor unchanged');

  // Simulate the human edit step: add a required constraint, then validate/export.
  descriptor.resources[0].schema.fields[1].constraints = {required: true};
  await writeFile(descriptorPath, JSON.stringify(descriptor, null, 2) + '\n');
  const validate = run(['scripts/cli.mjs', 'validate', descriptorPath]);
  assert.equal(validate.status, 0, validate.stdout + validate.stderr);
  assert.equal(JSON.parse(validate.stdout).ok, true);
  const exported = path.join(temp, 'exported');
  const exportResult = run(['scripts/cli.mjs', 'export', descriptorPath, exported]);
  assert.equal(exportResult.status, 0, exportResult.stdout + exportResult.stderr);
  const exportedValidate = run(['scripts/cli.mjs', 'validate', path.join(exported, 'datapackage.json')]);
  assert.equal(exportedValidate.status, 0, exportedValidate.stdout + exportedValidate.stderr);
  assert.equal(await readFile(path.join(exported, 'items.csv'), 'utf8'), csvText);
  assert.equal(await digest(csv), before, 'export must not modify the source CSV');

  // Empty sample: conservative string fallback and a clear hint.
  const emptyDir = path.join(temp, 'empty');
  await mkdir(emptyDir);
  const emptyCsv = path.join(emptyDir, 'empty.csv');
  const emptyDescriptor = path.join(emptyDir, 'datapackage.json');
  await writeFile(emptyCsv, 'id,note\n');
  const empty = run(['scripts/infer.mjs', emptyCsv, '--out', emptyDescriptor]);
  assert.equal(empty.status, 0, empty.stderr);
  assert(empty.stderr.includes('样本为空'), empty.stderr);
  const emptyFields = JSON.parse(await readFile(emptyDescriptor, 'utf8')).resources[0].schema.fields;
  assert.deepEqual(emptyFields.map(f => f.type), ['string', 'string']);
  assert.equal(run(['scripts/cli.mjs', 'validate', emptyDescriptor]).status, 0);

  // Sampling limit is reported rather than silently pretending to inspect all rows.
  const sampledDir = path.join(temp, 'sampled');
  await mkdir(sampledDir);
  const sampledCsv = path.join(sampledDir, 'sampled.csv');
  await writeFile(sampledCsv, 'id\n1\n2\n3\n');
  const sampled = run(['scripts/infer.mjs', sampledCsv, '--out', path.join(sampledDir, 'datapackage.json'), '--sample', '1']);
  assert.equal(sampled.status, 0, sampled.stderr);
  assert(sampled.stderr.includes('仅采样前 1 条'), sampled.stderr);

  // Missing input/argument errors use the documented exit code 2.
  assert.equal(run(['scripts/infer.mjs']).status, 2);
  assert.equal(run(['scripts/infer.mjs', path.join(temp, 'missing.csv')]).status, 2);

  console.log('Inference: types, leading zero, hints, no-overwrite, human edit, validate, export and source preservation passed');
} finally {
  await rm(temp, {recursive: true, force: true});
}
