#!/usr/bin/env node
// Human-readable view; validation remains in MoonBit and JSON CLI stays stable.
import {loadBundle} from './cli.mjs';
export const hints = {
  header: ['表头与规则不一致', '按规则的字段名称和顺序修正 CSV 第一条记录。'],
  type: ['字段类型不正确', '按字段定义填写数字、文字或布尔值。'],
  required: ['必填字段缺失', '补充有效值；不要直接删除记录。'],
  unique: ['字段值重复', '检查重复记录或字段的唯一约束。'],
  minimum: ['数值低于下限', '核对数值及定义的最小值。'],
  maximum: ['数值高于上限', '核对数值及定义的最大值。'],
  'primary-key-duplicate': ['记录编号重复', '让主键或组合主键能够唯一标识记录。'],
  'primary-key-null': ['记录编号缺失', '补齐主键的所有组成字段。'],
  'foreign-key': ['引用的记录不存在', '对照目标表修正编号，或补充确实存在的目标记录。'],
  'row-width': ['记录列数不匹配', '检查分隔符、引号和缺少或多余的列。'],
};
const file=process.argv[2];
if(!file){console.error('用法：node scripts/explain.mjs 数据包/datapackage.json');process.exitCode=2;}
else try {
 const {report}=await loadBundle(file);
 console.log(report.ok?'检查通过：可以继续使用或导出数据包。':'检查未通过：请核对以下问题。');
 for(const e of report.errors??[]){
  const [title,fix]=hints[e.code]??['当前描述或数据无法通过检查','查看原始原因和支持范围，不能视为校验通过。'];
  console.log(`${e.resource||'描述文件'} · ${e.row>0?'数据记录 '+e.row:'结构检查'} · ${e.field||'整表'}\n[${e.code}] ${title}\n原因：${e.message}\n建议：${fix}\n`);
 }
 console.log('记录号从表头之后第1条数据起算；含换行单元格时不等于文件行号。');
 process.exitCode=report.ok?0:1;
}catch(e){console.error('无法读取数据包：'+e.message);process.exitCode=2;}
