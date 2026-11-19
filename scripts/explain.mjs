#!/usr/bin/env node
// Human-readable view; validation remains in MoonBit and JSON CLI stays stable.
import {checkJsonFiles,loadBundle} from './cli.mjs';
import {describeDiagnostic} from './diagnostics.mjs';
const args = process.argv.slice(2);
const json = args[0] === '--json';
if (json) args.shift();
const [file, ...tables] = args;
if(!file || (json && !tables.length)){console.error('用法：node scripts/explain.mjs 数据包/datapackage.json 或 --json 描述文件 资源名=JSON文件 ...');process.exitCode=2;}
else try {
 const report = json ? await checkJsonFiles(file, tables) : (await loadBundle(file)).report;
 console.log(report.ok?(json?'检查通过：JSON 数据符合数据包规则。':'检查通过：可以继续使用或导出数据包。'):'检查未通过：请核对以下问题。');
 for(const e of report.errors??[]){
  const {title,fix}=describeDiagnostic(e.code);
  console.log(`${e.resource||'描述文件'} · ${e.row>0?'数据记录 '+e.row:'结构检查'} · ${e.field||'整表'}\n[${e.code}] ${title}\n原因：${e.message}\n建议：${fix}\n`);
 }
 console.log(json?'记录号从对应 JSON 数组的第1条数据起算。':'记录号从表头之后第1条数据起算；含换行单元格时不等于文件行号。');
 process.exitCode=report.ok?0:1;
}catch(e){console.error('无法读取数据包：'+e.message);process.exitCode=2;}
