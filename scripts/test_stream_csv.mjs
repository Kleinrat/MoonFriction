import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {createWriteStream} from 'node:fs';
import {once} from 'node:events';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {validateStream} from './cli.mjs';

const dir = await mkdtemp(path.join(tmpdir(), 'moonfriction-stream-'));
try {
  const schema = path.join(dir, 'schema.json');
  const csv = path.join(dir, 'rows.csv');
  const run = (...args) => spawnSync(process.execPath,
    ['--max-old-space-size=32', 'scripts/cli.mjs', 'validate-stream', schema, csv, ...args],
    {encoding:'utf8'});
  const allowed = '茶🙂;a\r\nb\'c';
  await writeFile(schema, JSON.stringify({fields:[
    {name:'title', constraints:{enum:[allowed]}}, {name:'id', type:'integer'},
  ]}));
  await writeFile(csv, "\uFEFFtitle;id\r\n'茶🙂;a\r\nb''c';12\r\nwrong;12\r\nwrong;13");
  for (const chunk of [1, 2, 3, 13, 65536]) {
    const report = await validateStream(schema, csv, ['--delimiter',';','--quote',"'",
      '--max-errors','1'], chunk);
    assert.equal(report.complete,true);
    assert.equal(report.rows,3);
    assert.equal(report.error_count,2);
    assert.deepEqual(report.errors.map(e => [e.code,e.row,e.field]), [['enum',2,'title']]);
  }
  for (const input of ['title;id\n\'unfinished', "title;id\n'closed'x;1", "title;id\na'b;1"]) {
    await writeFile(csv,input);
    const result = run('--delimiter',';','--quote',"'");
    assert.equal(result.status,1);
    const report = JSON.parse(result.stdout);
    assert.equal(report.complete,false);
    assert.equal(report.errors[0].code,'csv');
    assert.equal(report.errors[0].row,1);
  }
  await writeFile(csv,'wrong\n');
  assert.equal(JSON.parse(run().stdout).errors[0].code,'header');
  await writeFile(csv,Buffer.from([0x74,0xc3]));
  assert.equal(run().status,2);
  assert.equal(run('--max-errors','-1').status,2);
  await writeFile(schema, '{"fields":[{"name":"text"}]}');
  await writeFile(csv,'text\n');
  assert.equal(JSON.parse(run().stdout).rows,0);
  // > 32 MiB input under a 32 MiB JS old-space limit, without retaining generated rows.
  const out = createWriteStream(csv);
  out.write('text\n');
  const block = ('a'.repeat(1023)+'\n').repeat(256);
  for (let i=0; i<140; i++) if (!out.write(block)) await once(out,'drain');
  out.end();
  await once(out,'finish');
  const large = run('--max-errors','0');
  assert.equal(large.status,0,large.stderr);
  assert.deepEqual(JSON.parse(large.stdout), {ok:true,complete:true,rows:35840,error_count:0,errors:[]});
  console.log('Streaming CSV: chunk boundaries, UTF-8, diagnostics and 35 MiB file passed');
} finally {
  await rm(dir,{recursive:true,force:true});
}
