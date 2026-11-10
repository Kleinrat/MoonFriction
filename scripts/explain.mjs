#!/usr/bin/env node
// Human-readable view; validation remains in MoonBit and JSON CLI stays stable.
import {loadBundle} from './cli.mjs';
import {describeDiagnostic} from './diagnostics.mjs';
const file=process.argv[2];
if(!file){console.error('用法：node scripts/explain.mjs 数据包/datapackage.json');process.exitCode=2;}
else try {
 const {report}=await loadBundle(file);
 console.log(report.ok?'检查通过：可以继续使用或导出数据包。':'检查未通过：请核对以下问题。');
 for(const e of report.errors??[]){
  const {title,fix}=describeDiagnostic(e.code);
  console.log(`${e.resource||'描述文件'} · ${e.row>0?'数据记录 '+e.row:'结构检查'} · ${e.field||'整表'}\n[${e.code}] ${title}\n原因：${e.message}\n建议：${fix}\n`);
 }
 console.log('记录号从表头之后第1条数据起算；含换行单元格时不等于文件行号。');
 process.exitCode=report.ok?0:1;
}catch(e){console.error('无法读取数据包：'+e.message);process.exitCode=2;}
