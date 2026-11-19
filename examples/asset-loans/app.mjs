#!/usr/bin/env node
import {readFile,stat,realpath,mkdir,writeFile,rename,rm,mkdtemp} from 'node:fs/promises';
import path from 'node:path';
import {check_bundle,draft_bundle,check_request} from './_build/js/release/build/asset-loans.js';
const decode=b=>new TextDecoder('utf-8',{fatal:true}).decode(b);
async function read(file){const s=await stat(file);if(!s.isFile()||s.size>16*1024*1024)throw Error('Expected a regular file at most 16 MiB');return readFile(file);}
async function bundle(dir,needsRules){
 const base=await realpath(dir);const bytes={};
 for(const name of ['assets.csv','loans.csv',...(needsRules?['datapackage.json']:[])]){
  const file=await realpath(path.join(base,name));const rel=path.relative(base,file);
  if(rel.startsWith('..')||path.isAbsolute(rel))throw Error('File escapes input directory');bytes[name]=await read(file);
 }
 const descriptor=needsRules?JSON.parse(decode(bytes['datapackage.json'])):{};
 if(needsRules){const rs=descriptor.resources;if(!Array.isArray(rs)||rs.length!==2||['assets','loans'].some(n=>rs.filter(r=>r.name===n&&r.path===n+'.csv').length!==1))throw Error('This application requires exactly assets/assets.csv and loans/loans.csv');}
 return {bytes,payload:JSON.stringify({descriptor,assets:decode(bytes['assets.csv']),loans:decode(bytes['loans.csv'])})};
}
async function save(destination,files){
 const dest=path.resolve(destination);await mkdir(path.dirname(dest),{recursive:true});
 async function absent(){try{await stat(dest);throw Error('Destination exists; choose a new directory');}catch(e){if(e.code!=='ENOENT')throw e;}}
 await absent();const temp=await mkdtemp(path.join(path.dirname(dest),'.asset-loans-'));
 try{for(const [name,bytes] of Object.entries(files))await writeFile(path.join(temp,name),bytes);await absent();await rename(temp,dest);}catch(e){await rm(temp,{recursive:true,force:true});throw e;}
}
try{
 const [command,input,destination,...extra]=process.argv.slice(2);
 if(extra.length||!input||!['draft','check','export','check-request'].includes(command)||(['draft','export'].includes(command)?!destination:destination))throw Error('Usage: node app.mjs draft INPUT_DIR NEW_DIR | check DIR | export DIR NEW_DIR | check-request FILE.json');
 let report;
 if(command==='check-request')report=JSON.parse(check_request(decode(await read(input))));
 else{
  const b=await bundle(input,command!=='draft');
  report=JSON.parse(command==='draft'?draft_bundle(b.payload):check_bundle(b.payload));
  if(report.ok&&command==='draft')await save(destination,{'assets.csv':b.bytes['assets.csv'],'loans.csv':b.bytes['loans.csv'],'datapackage.json':JSON.stringify(report.descriptor,null,2)+'\n'});
  if(report.ok&&command==='export')await save(destination,b.bytes);
 }
 console.log(JSON.stringify(report,null,2));process.exitCode=report.ok?0:1;
}catch(e){console.error(JSON.stringify({ok:false,error:e.message}));process.exitCode=2;}
