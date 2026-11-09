#!/usr/bin/env node
import {readFile,realpath,stat,mkdtemp,mkdir,writeFile,rename,rm} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {inspect_json,validate_json} from '../_build/js/release/build/src/api/api.js';
const decode=bytes=>new TextDecoder('utf-8',{fatal:true}).decode(bytes);
export async function loadBundle(descriptorPath){
  const full=await realpath(descriptorPath),base=path.dirname(full);
  const text=decode(await readFile(full));
  const info=JSON.parse(inspect_json(text));
  if(!info.ok) return {report:info};
  const files=[];
  for(const item of info.resources){
    const file=await realpath(path.resolve(base,item.path));
    const rel=path.relative(base,file);
    if(rel==='..'||rel.startsWith('..'+path.sep)||path.isAbsolute(rel)) throw Error('Resource escapes package directory');
    const s=await stat(file);
    if(!s.isFile()||s.size>16*1024*1024) throw Error('Resource must be a regular file of at most 16 MiB');
    files.push({...item,bytes:await readFile(file)});
  }
  const descriptor=JSON.parse(text);
  const report=JSON.parse(validate_json(JSON.stringify({descriptor,resources:files.map(x=>({name:x.name,csv:decode(x.bytes)}))})));
  return {descriptor,files,report};
}
export async function exportBundle(bundle,destination){
  if(!bundle.report.ok) throw Error('Refusing to export an invalid package');
  const dest=path.resolve(destination),parent=path.dirname(dest);
  await mkdir(parent,{recursive:true});
  // Publish a staged directory; never merge into or overwrite an existing destination.
  try {await stat(dest);throw Error('Destination already exists');}catch(e){if(e.code!=='ENOENT')throw e;}
  const stage=await mkdtemp(path.join(parent,'.moonfriction-'));
  try{
    for(const f of bundle.files){const target=path.join(stage,f.path);await mkdir(path.dirname(target),{recursive:true});await writeFile(target,f.bytes);}
    await writeFile(path.join(stage,'datapackage.json'),JSON.stringify(bundle.descriptor,null,2)+'\n',{flag:'wx'});
    // Recheck for ordinary accidental overwrite before rename.
    try {await stat(dest);throw Error('Destination already exists');}catch(e){if(e.code!=='ENOENT')throw e;}
    await rename(stage,dest);
  }catch(e){await rm(stage,{recursive:true,force:true});throw e;}
}
if(process.argv[1]&&(await realpath(process.argv[1]).catch(()=>null))===fileURLToPath(import.meta.url)){
  const [command,file,destination]=process.argv.slice(2);
  if(!['inspect','validate','export'].includes(command)||!file||(command==='export'&&!destination)){
    console.error('Usage: node scripts/cli.mjs inspect|validate datapackage.json\n       node scripts/cli.mjs export datapackage.json DESTINATION');process.exitCode=2;
  }else{
    try{
      const bundle=command==='inspect'?{report:JSON.parse(inspect_json(decode(await readFile(file))))}:await loadBundle(file);
      if(command==='export'&&bundle.report.ok) await exportBundle(bundle,destination);
      console.log(JSON.stringify(bundle.report,null,2));process.exitCode=bundle.report.ok?0:1;
    }catch(error){console.error(JSON.stringify({ok:false,error:error.message}));process.exitCode=2;}
  }
}
