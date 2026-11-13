#!/usr/bin/env node
// Host-side CSV reading and draft output; all inference lives in MoonBit core.
import {readFile,stat,writeFile,mkdir} from 'node:fs/promises';
import path from 'node:path';
import {infer_json} from '../_build/js/release/build/src/api/api.js';

const decode = bytes => new TextDecoder('utf-8', {fatal: true}).decode(bytes);
const usage = '用法：node scripts/infer.mjs 数据.csv [--out datapackage.json] [--name 包名] [--resource 资源名] [--sample 100]\n' +
  '只读取 CSV；--out 目标已存在时拒绝覆盖，不修改原 CSV。';

function parseArgs(argv) {
  const args = {file: null, out: null, name: null, resource: null, sample: 100};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') { args.help = true; continue; }
    if (arg === '--out' || arg === '--name' || arg === '--resource' || arg === '--sample') {
      const value = argv[++i];
      if (value === undefined) throw Error(`缺少 ${arg} 的参数`);
      if (arg === '--out') args.out = value;
      else if (arg === '--name') args.name = value;
      else if (arg === '--resource') args.resource = value;
      else {
        const sample = Number(value);
        if (!Number.isInteger(sample) || sample < 0) throw Error('--sample 必须是大于等于 0 的整数');
        args.sample = sample;
      }
    } else if (arg.startsWith('-')) {
      throw Error(`未知参数：${arg}`);
    } else if (args.file === null) {
      args.file = arg;
    } else {
      throw Error(`多余参数：${arg}`);
    }
  }
  return args;
}

const sanitizeName = value => {
  const cleaned = value.toLowerCase().replace(/[^a-z0-9._-]+/g, '-').replace(/^[-.]+|[-.]+$/g, '');
  return cleaned || 'table';
};

try {
  const args = parseArgs(process.argv.slice(2));
  if (args.help || !args.file) {
    console.error(usage);
    process.exitCode = args.help ? 0 : 2;
  } else {
    const csv = decode(await readFile(args.file));
    const base = path.basename(args.file);
    const stem = sanitizeName(base.replace(/\.csv$/i, ''));
    const package_name = args.name ? sanitizeName(args.name) : `${stem}-package`;
    const resource_name = args.resource ? sanitizeName(args.resource) : stem;
    const result = JSON.parse(infer_json(JSON.stringify({
      package_name,
      resource_name,
      path: base,
      csv,
      sample_limit: args.sample,
    })));
    if (!result.ok) {
      console.error(JSON.stringify(result, null, 2));
      process.exitCode = 2;
    } else {
      for (const hint of result.hints ?? []) {
        console.error(`[${hint.field || '全表'}] ${hint.message}`);
      }
      console.error(`采样 ${result.sampled_rows}/${result.total_rows} 条；草稿只是起点，请人工核对类型与约束。`);
      if (args.out) {
        try {
          await stat(args.out);
          throw Error(`目标已存在，拒绝覆盖：${args.out}`);
        } catch (error) {
          if (error.code !== 'ENOENT') throw error;
        }
        await mkdir(path.dirname(path.resolve(args.out)), {recursive: true});
        await writeFile(args.out, JSON.stringify(result.descriptor, null, 2) + '\n', {flag: 'wx'});
        if (path.dirname(path.resolve(args.out)) !== path.dirname(path.resolve(args.file))) {
          console.error('注意：描述文件的 path 只含文件名，请把 CSV 与描述文件放在同一目录，或手工调整 path。');
        }
        console.error(`已生成草稿：${args.out}`);
      } else {
        console.log(JSON.stringify(result.descriptor, null, 2));
      }
    }
  }
} catch (error) {
  console.error(JSON.stringify({ok: false, error: error.message}));
  process.exitCode = 2;
}
