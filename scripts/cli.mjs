#!/usr/bin/env node
import {readFile,realpath,stat,mkdtemp,mkdir,writeFile,rename,rm} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {inspect_json,validate_json,validate_json_files} from '../_build/js/release/build/src/api/api.js';
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
async function checkJsonFiles(descriptorPath, mappings) {
  const descriptor = decode(await readFile(descriptorPath));
  const batches = [];
  for (const mapping of mappings) {
    const separator = mapping.indexOf('=');
    if (separator < 1 || separator === mapping.length - 1) {
      throw Error('Expected RESOURCE=FILE.json');
    }
    const name = mapping.slice(0, separator);
    const file = mapping.slice(separator + 1);
    const info = await stat(file);
    if (!info.isFile() || info.size > 16 * 1024 * 1024) {
      throw Error('Resource must be a regular file of at most 16 MiB: ' + file);
    }
    // Pass the original text so JavaScript never rounds Int64 identifiers.
    batches.push({name, text: decode(await readFile(file))});
  }
  return JSON.parse(validate_json_files(descriptor, JSON.stringify(batches)));
}
if(process.argv[1]&&(await realpath(process.argv[1]).catch(()=>null))===fileURLToPath(import.meta.url)){
  const [command,file,...args]=process.argv.slice(2);
  const [destination] = args;
  if(!['inspect','validate','export','validate-json'].includes(command)||!file||((command==='export'||command==='validate-json')&&!destination)){
    console.error('Usage: node scripts/cli.mjs inspect|validate datapackage.json\n       node scripts/cli.mjs export datapackage.json DESTINATION\n       node scripts/cli.mjs validate-json datapackage.json RESOURCE=FILE.json ...');process.exitCode=2;
  }else{
    try{
      const bundle=command==='validate-json'?{report:await checkJsonFiles(file,args)}:command==='inspect'?{report:JSON.parse(inspect_json(decode(await readFile(file))))}:await loadBundle(file);
      if(command==='export'&&bundle.report.ok) await exportBundle(bundle,destination);
      console.log(JSON.stringify(bundle.report,null,2));process.exitCode=bundle.report.ok?0:1;
    }catch(error){console.error(JSON.stringify({ok:false,error:error.message}));process.exitCode=2;}
  }
}
