#!/usr/bin/env node
import {readFile,realpath,stat,mkdtemp,mkdir,writeFile,rename,rm} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {schema_diff_json,inspect_json,validate_json,validate_json_files,open_csv_stream,push_csv_chunk,finish_csv_stream} from '../_build/js/release/build/src/api/api.js';
const decode=bytes=>new TextDecoder('utf-8',{fatal:true}).decode(bytes);
async function readPackageFile(base, relative) {
  const file = await realpath(path.resolve(base, relative));
  const rel = path.relative(base, file);
  if (rel === '..' || rel.startsWith('..' + path.sep) || path.isAbsolute(rel)) {
    throw Error('Resource escapes package directory: ' + relative);
  }
  const info = await stat(file);
  if (!info.isFile() || info.size > 16 * 1024 * 1024) {
    throw Error('Resource must be a regular file of at most 16 MiB: ' + relative);
  }
  return readFile(file);
}

// Preserve number literals when expanding descriptors, including extension metadata.
function parseDocument(text) {
  return JSON.parse(text, (_key, value, context) =>
    typeof value === 'number' ? JSON.rawJSON(context.source) : value);
}

async function loadDescriptor(descriptorPath) {
  const full = await realpath(descriptorPath);
  const base = path.dirname(full);
  let text = decode(await readFile(full));
  let descriptor;
  try {
    descriptor = parseDocument(text);
  } catch (error) {
    if (!(error instanceof SyntaxError)) throw error;
    return {report: JSON.parse(inspect_json(text))};
  }
  const schemas = new Map();
  for (const item of Array.isArray(descriptor?.resources) ? descriptor.resources : []) {
    if (typeof item?.schema !== 'string') continue;
    const ref = item.schema;
    const invalid = message => ({report: {ok: false, errors: [{
      code: 'descriptor', resource: typeof item.name === 'string' ? item.name : '',
      row: 0, field: 'schema', message,
    }]}});
    if (/[\\:\x00]/.test(ref) || ref.split('/').some(part => ['', '.', '..'].includes(part))) {
      return invalid('Expected a local relative schema path inside the package');
    }
    if (!schemas.has(ref)) {
      const source = decode(await readPackageFile(base, ref));
      try {
        schemas.set(ref, parseDocument(source));
      } catch (error) {
        if (!(error instanceof SyntaxError)) throw error;
        return invalid('Invalid schema JSON: ' + ref);
      }
    }
    const schema = schemas.get(ref);
    if (!schema || typeof schema !== 'object' || Array.isArray(schema) || JSON.isRawJSON(schema)) {
      return invalid('Expected a Table Schema object in ' + ref);
    }
    item.schema = schema;
  }
  if (schemas.size) text = JSON.stringify(descriptor);
  return {base, text, report: JSON.parse(inspect_json(text))};
}

export async function loadBundle(descriptorPath) {
  const {base, text, report: info} = await loadDescriptor(descriptorPath);
  if (!info.ok) return {report: info};
  const files = [];
  for (const item of info.resources) {
    files.push({...item, bytes: await readPackageFile(base, item.path)});
  }
  const resources = files.map(f => ({name: f.name, csv: decode(f.bytes)}));
  const request = '{"descriptor":' + text + ',"resources":' + JSON.stringify(resources) + '}';
  return {descriptor: JSON.parse(text), descriptorText: text, files, report: JSON.parse(validate_json(request))};
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
    await writeFile(path.join(stage,'datapackage.json'),(bundle.descriptorText ?? JSON.stringify(bundle.descriptor,null,2))+'\n',{flag:'wx'});
    // Recheck for ordinary accidental overwrite before rename.
    try {await stat(dest);throw Error('Destination already exists');}catch(e){if(e.code!=='ENOENT')throw e;}
    await rename(stage,dest);
  }catch(e){await rm(stage,{recursive:true,force:true});throw e;}
}
export async function checkJsonFiles(descriptorPath, mappings) {
  const {text: descriptor, report} = await loadDescriptor(descriptorPath);
  if (!report.ok) return report;
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
// Node owns file handles and UTF-8 decoder state; MoonBit owns CSV and validation.
export async function validateStream(schemaPath, csvPath, args = [], highWaterMark = 65536) {
  const options = new Map();
  for (let i = 0; i < args.length; i += 2) {
    const flag = args[i];
    if (!['--max-errors', '--delimiter', '--quote'].includes(flag) ||
        i + 1 >= args.length || options.has(flag)) throw Error('Invalid stream option: ' + flag);
    options.set(flag, args[i + 1]);
  }
  const max = options.get('--max-errors') ?? '10';
  if (!/^\d+$/.test(max) || Number(max) > 2147483647) throw Error('Invalid --max-errors');
  const delimiter = options.get('--delimiter') ?? ',';
  const quote = options.get('--quote') ?? '"';
  if (![',', ';', 'tab'].includes(delimiter) || !['"', "'"].includes(quote)) {
    throw Error('Expected comma, semicolon or tab and a single or double quote');
  }
  const session = open_csv_stream(decode(await readFile(schemaPath)), path.basename(csvPath),
    delimiter === 'tab' ? '\t' : delimiter, quote, Number(max));
  if (push_csv_chunk(session, '')) {
    const decoder = new TextDecoder('utf-8', {fatal:true});
    for await (const bytes of createReadStream(csvPath, {highWaterMark})) {
      if (!push_csv_chunk(session, decoder.decode(bytes, {stream:true}))) break;
    }
    if (push_csv_chunk(session, '')) push_csv_chunk(session, decoder.decode());
  }
  return JSON.parse(finish_csv_stream(session));
}
if(process.argv[1]&&(await realpath(process.argv[1]).catch(()=>null))===fileURLToPath(import.meta.url)){
  const [command,file,...args]=process.argv.slice(2);
  const [destination] = args;
  if (command === 'schema' && file === 'diff' && args.length === 2) {
    try {
      const [oldText, newText] = await Promise.all(args.map(async f => decode(await readFile(f))));
      const result = schema_diff_json(oldText, newText);
      console.log(result);
      process.exitCode = JSON.parse(result).ok ? 0 : 1;
    } catch (error) {
      console.error(JSON.stringify({ok:false,error:error.message}));
      process.exitCode = 2;
    }
  } else if(!['inspect','validate','export','validate-json','validate-stream'].includes(command)||!file||((command==='export'||command==='validate-json'||command==='validate-stream')&&!destination)){
    console.error('Usage: node scripts/cli.mjs schema diff OLD.json NEW.json\n       node scripts/cli.mjs inspect|validate datapackage.json\n       node scripts/cli.mjs export datapackage.json DESTINATION\n       node scripts/cli.mjs validate-json datapackage.json RESOURCE=FILE.json ...\n       node scripts/cli.mjs validate-stream SCHEMA.json DATA.csv [--max-errors N] [--delimiter ,|;|tab] [--quote CHAR]');process.exitCode=2;
  }else{
    try{
      let bundle;
      if (command === 'validate-stream') {
        bundle = {report: await validateStream(file, args[0], args.slice(1))};
      } else if (command === 'validate-json') {
        bundle = {report: await checkJsonFiles(file, args)};
      } else {
        bundle = command === 'inspect' ? await loadDescriptor(file) : await loadBundle(file);
      }
      if(command==='export'&&bundle.report.ok) await exportBundle(bundle,destination);
      console.log(JSON.stringify(bundle.report,null,2));process.exitCode=bundle.report.ok?0:1;
    }catch(error){console.error(JSON.stringify({ok:false,error:error.message}));process.exitCode=2;}
  }
}
