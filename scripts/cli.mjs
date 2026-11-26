#!/usr/bin/env node
import {readFile,realpath,stat,mkdtemp,mkdir,writeFile,rename,rm} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {schema_diff_json,inspect_json,inspect_data_package_json,validate_data_package_profiles_json,check_mixed_descriptor_json,validate_mixed_json,validate_profiled_tables_json,validate_json_files,open_csv_stream,push_csv_chunk,finish_csv_stream} from '../_build/js/release/build/src/api/api.js';
const packageFileLimit = 16 * 1024 * 1024;
const decode = (bytes, encoding = 'utf-8') => new TextDecoder(encoding, {fatal: true}).decode(bytes);
const isRemote = value => /^https?:\/\//i.test(value);
const safeRelative = value => !/[\\:\x00]/.test(value) &&
  value.split('/').every(part => part && part !== '.' && part !== '..');

async function readPackageFile(base, relative) {
  const file = await realpath(path.resolve(base, relative));
  const rel = path.relative(base, file);
  if (rel === '..' || rel.startsWith('..' + path.sep) || path.isAbsolute(rel)) {
    throw Error('Resource escapes package directory: ' + relative);
  }
  const info = await stat(file);
  if (!info.isFile() || info.size > packageFileLimit) {
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

function resourceError(resource, field, message) {
  return {report: {ok: false, errors: [{code: 'descriptor', resource, row: 0, field, message}]}};
}

async function readRemoteResource(location) {
  const address = new URL(location);
  if (!['http:', 'https:'].includes(address.protocol) || address.username || address.password) {
    throw Error('Expected an HTTP(S) resource URL without credentials');
  }
  const response = await fetch(address, {
    redirect: 'error', credentials: 'omit', signal: AbortSignal.timeout(15000),
  });
  if (!response.ok || response.body === null) {
    await response.body?.cancel();
    throw Error('Remote resource returned HTTP ' + response.status);
  }
  if (Number(response.headers.get('content-length')) > packageFileLimit) {
    await response.body.cancel();
    throw Error('Remote resource exceeds 16 MiB');
  }
  const chunks = [];
  let total = 0;
  for await (const chunk of response.body) {
    total += chunk.length;
    if (total > packageFileLimit) throw Error('Remote resource exceeds 16 MiB');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks, total);
}

async function readRelativePackageFile(base, relative) {
  if (typeof base === 'string') return readPackageFile(base, relative);
  const encoded = relative.split('/').map(encodeURIComponent).join('/');
  return readRemoteResource(new URL(encoded, base).href);
}

export async function loadBundle(descriptorPath, {allowRemote = false, profileSchemas} = {}) {
  const {base, descriptorText, report: manifest, profileDocuments} =
    await loadDataPackage(descriptorPath, false, {allowRemote, profileSchemas});
  if (!manifest.ok) return {report: manifest};
  const descriptor = parseDocument(descriptorText);
  const locations = new Map(manifest.resources.map(item => [item.name, item]));
  const cache = new Map();
  const files = new Map();
  async function read(location) {
    if (!cache.has(location)) {
      const bytes = isRemote(location)
        ? await readRemoteResource(location)
        : await readRelativePackageFile(base, location);
      cache.set(location, bytes);
    }
    return cache.get(location);
  }
  const references = Object.create(null);
  let hasReferences = false;
  for (const item of descriptor.resources) {
    const info = locations.get(item.name);
    for (const [field, ref] of [['schema', info.schemaReference], ['dialect', info.dialectReference]]) {
      if (ref === undefined) continue;
      if (!(isRemote(ref) ? allowRemote : safeRelative(ref))) {
        return resourceError(item.name, field, 'Expected a contained relative path or an enabled remote reference');
      }
      let document;
      const bytes = await read(ref);
      try {
        document = parseDocument(decode(bytes));
      } catch (error) {
        if (!(error instanceof SyntaxError)) throw error;
      }
      if (!document || typeof document !== 'object' || Array.isArray(document) || JSON.isRawJSON(document)) {
        return resourceError(item.name, field, 'Expected a JSON object in ' + ref);
      }
      if (profileDocuments) {
        references[ref] = document;
        if (!isRemote(ref)) {
          if (ref === 'datapackage.json') throw Error('A schema or dialect cannot overwrite the exported datapackage.json');
          files.set(ref, {path: ref, bytes});
        }
      } else {
        item[field] = document;
        hasReferences = true;
      }
    }
  }
  const text = hasReferences ? JSON.stringify(descriptor) : descriptorText;
  const resolved = profileDocuments && JSON.stringify(references);
  const profiled = resolved
    ? inputs => validate_profiled_tables_json(text, profileDocuments, resolved, inputs)
    : null;
  const preflight = JSON.parse(profiled ? profiled('') : check_mixed_descriptor_json(text));
  if (!preflight.ok) return {report: preflight};
  const inputs = [];
  for (const resource of manifest.resources) {
    if (resource.location === 'remote' && !allowRemote) {
      return resourceError(resource.name, 'path', 'Remote resources require --allow-remote');
    }
    const parts = [];
    for (const name of resource.paths ?? []) {
      if (resource.location === 'local' && name === 'datapackage.json') {
        throw Error('A resource cannot overwrite the exported datapackage.json');
      }
      const bytes = await read(name);
      if (resource.location === 'local') files.set(name, {path: name, bytes});
      parts.push(bytes);
    }
    if (resource.location !== 'inline') verifyResource(resource, parts);
    inputs.push({name: resource.name, parts: parts.map(bytes => decode(bytes, resource.encoding))});
  }
  return {
    descriptor: JSON.parse(text), descriptorText: text, files: [...files.values()],
    report: JSON.parse(profiled
      ? profiled(JSON.stringify(inputs))
      : validate_mixed_json(text, JSON.stringify(inputs))),
  };
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
function verifyResource(resource, parts) {
  if (resource.bytes !== undefined &&
      parts.reduce((total, bytes) => total + bytes.length, 0) !== resource.bytes) {
    throw Error('Resource size does not match bytes: ' + resource.name);
  }
  if (resource.hash !== undefined) {
    const separator = resource.hash.indexOf(':');
    const algorithm = separator === -1 ? 'md5' : resource.hash.slice(0, separator);
    const expected = resource.hash.slice(separator + 1).toLowerCase();
    const digest = createHash(algorithm);
    for (const bytes of parts) digest.update(bytes);
    if (digest.digest('hex') !== expected) {
      throw Error('Resource checksum does not match hash: ' + resource.name);
    }
  }
}
async function loadDataPackage(descriptorPath, readLocalFiles, {allowRemote = false, profileSchemas} = {}) {
  let base;
  let descriptorBytes;
  if (isRemote(descriptorPath)) {
    if (!allowRemote) throw Error('Remote descriptors require --allow-remote');
    descriptorBytes = await readRemoteResource(descriptorPath);
    base = new URL('.', descriptorPath);
  } else {
    const full = await realpath(descriptorPath);
    base = path.dirname(full);
    descriptorBytes = await readFile(full);
  }
  const descriptorText = decode(descriptorBytes);
  let report = JSON.parse(inspect_data_package_json(descriptorText));
  let profileDocuments;
  if (report.ok && report.profiles) {
    const documents = Object.create(null);
    if (profileSchemas) {
      const supplied = parseDocument(decode(await readFile(profileSchemas)));
      if (!supplied || typeof supplied !== 'object' || Array.isArray(supplied) || JSON.isRawJSON(supplied)) {
        throw Error('Expected a JSON object in --profile-schemas');
      }
      Object.assign(documents, supplied);
    }
    for (const id of report.profiles) {
      if (!Object.hasOwn(documents, id) && allowRemote && isRemote(id)) {
        documents[id] = parseDocument(decode(await readRemoteResource(id)));
      }
    }
    profileDocuments = JSON.stringify(documents);
    const validation = JSON.parse(validate_data_package_profiles_json(descriptorText, profileDocuments));
    if (!validation.ok) report = validation;
  }
  const files = new Map();
  if (report.ok && readLocalFiles) {
    const descriptorPaths = new Set();
    for (const resource of report.resources) {
      if (resource.location === 'local') {
        for (const file of resource.paths) files.set(file, null);
      }
      for (const ref of [resource.schemaReference, resource.dialectReference]) {
        if (ref && !isRemote(ref)) {
          if (!safeRelative(ref)) throw Error('Invalid descriptor reference: ' + ref);
          files.set(ref, null);
          descriptorPaths.add(ref);
        }
      }
    }
    if (files.has('datapackage.json')) {
      throw Error('A resource cannot overwrite the exported datapackage.json');
    }
    for (const file of files.keys()) {
      const bytes = await readRelativePackageFile(base, file);
      if (descriptorPaths.has(file)) {
        const schema = parseDocument(decode(bytes));
        if (!schema || typeof schema !== 'object' || Array.isArray(schema) || JSON.isRawJSON(schema)) {
          throw Error('Expected a JSON descriptor object in ' + file);
        }
      }
      files.set(file, {path: file, bytes});
    }
    for (const resource of report.resources) {
      if (resource.location === 'local') verifyResource(resource, resource.paths.map(file => files.get(file).bytes));
    }
  }
  return {base, descriptorText, report, profileDocuments, files: [...files.values()]};
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
    if (!info.isFile() || info.size > packageFileLimit) {
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
function packageOptions(options) {
  let allowRemote = false;
  let profileSchemas;
  for (let index = 0; index < options.length; index++) {
    const option = options[index];
    if (option === '--allow-remote' && !allowRemote) {
      allowRemote = true;
    } else if (option === '--profile-schemas' && !profileSchemas &&
               options[index + 1] && !options[index + 1].startsWith('--')) {
      profileSchemas = options[++index];
    } else {
      throw Error('Invalid command arguments');
    }
  }
  return {allowRemote, profileSchemas};
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
  } else if (['inspect-package', 'export-package'].includes(command) && file) {
    try {
      const exporting = command === 'export-package';
      const options = exporting ? args.slice(1) : args;
      if (exporting && (!destination || destination.startsWith('--'))) {
        throw Error('Expected export destination');
      }
      const bundle = await loadDataPackage(file, exporting, packageOptions(options));
      if (exporting && bundle.report.ok) await exportBundle(bundle, destination);
      console.log(JSON.stringify(bundle.report, null, 2));
      process.exitCode = bundle.report.ok ? 0 : 1;
    } catch (error) {
      console.error(JSON.stringify({ok:false,error:error.message}));
      process.exitCode = 2;
    }
  } else if(!['inspect','validate','export','validate-json','validate-stream'].includes(command)||!file||((command==='export'||command==='validate-json'||command==='validate-stream')&&!destination)){
    console.error('Usage: node scripts/cli.mjs schema diff OLD.json NEW.json\n       node scripts/cli.mjs inspect datapackage.json\n       node scripts/cli.mjs validate datapackage.json [--allow-remote] [--profile-schemas FILE]\n       node scripts/cli.mjs inspect-package datapackage.json [--allow-remote] [--profile-schemas FILE]\n       node scripts/cli.mjs export-package datapackage.json DESTINATION [--allow-remote] [--profile-schemas FILE]\n       node scripts/cli.mjs export datapackage.json DESTINATION [--allow-remote] [--profile-schemas FILE]\n       node scripts/cli.mjs validate-json datapackage.json RESOURCE=FILE.json ...\n       node scripts/cli.mjs validate-stream SCHEMA.json DATA.csv [--max-errors N] [--delimiter ,|;|tab] [--quote CHAR]');process.exitCode=2;
  }else{
    try{
      let bundle;
      if (command === 'validate-stream') {
        bundle = {report: await validateStream(file, args[0], args.slice(1))};
      } else if (command === 'validate-json') {
        bundle = {report: await checkJsonFiles(file, args)};
      } else {
        const options = command === 'export' ? args.slice(1) : args;
        if ((command === 'inspect' && options.length > 0) ||
            (command === 'export' && destination.startsWith('--'))) {
          throw Error('Invalid command arguments');
        }
        bundle = command === 'inspect'
          ? await loadDescriptor(file)
          : await loadBundle(file, packageOptions(options));
      }
      if(command==='export'&&bundle.report.ok) await exportBundle(bundle,destination);
      console.log(JSON.stringify(bundle.report,null,2));process.exitCode=bundle.report.ok?0:1;
    }catch(error){console.error(JSON.stringify({ok:false,error:error.message}));process.exitCode=2;}
  }
}
