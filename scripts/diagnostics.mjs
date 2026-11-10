import {readFileSync} from 'node:fs';
export const hints=JSON.parse(readFileSync(new URL('./diagnostics.zh.json',import.meta.url),'utf8'));
export function describeDiagnostic(code){return Object.hasOwn(hints,code)?hints[code]:{title:'未知诊断代码',fix:'保留原始代码和原因，检查版本或联系维护者；不能视为校验通过。'};}
export function diagnosticTable(){
 const escape=s=>s.replaceAll('|','\\|').replaceAll('\n',' ');
 return ['| 错误码 | 含义 | 处理方法 |','|---|---|---|',...Object.entries(hints).sort(([a],[b])=>a.localeCompare(b)).map(([code,h])=>`| ${code} | ${escape(h.title)} | ${escape(h.fix)} |`)].join('\n');
}
