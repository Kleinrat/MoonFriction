"""Build a genuinely independent registry consumer outside any source workspace."""
from pathlib import Path
import argparse,json,shutil,subprocess,tempfile,hashlib
parser=argparse.ArgumentParser();parser.add_argument('--reference',action='store_true');args=parser.parse_args()
ROOT=Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='asset-consumer-') as tmp:
 p=Path(tmp)/'app';shutil.copytree(ROOT/'examples/asset-loans',p,ignore=shutil.ignore_patterns('_build','.mooncakes','node_modules'))
 assert not (p/'moon.work').exists()
 for command in [['moon','update'],['moon','fmt','--check'],['moon','check','--target','js'],['moon','build','--target','js','--release']]:subprocess.run(command,cwd=p,check=True)
 def run(*argv,expected=0):
  r=subprocess.run(['node','app.mjs',*map(str,argv)],cwd=p,capture_output=True,text=True)
  assert r.returncode==expected,(argv,r.returncode,r.stdout,r.stderr)
  return json.loads(r.stdout or r.stderr)
 def digest(d):return {q.name:hashlib.sha256(q.read_bytes()).hexdigest() for q in d.iterdir() if q.is_file()}
 original=digest(p/'data');draft=Path(tmp)/'draft'
 report=run('draft','data',draft);assert report['descriptor']['resources'][0]['schema']['fields'][0]['type']=='string'
 run('draft','data',draft,expected=2)
 # Apply the explicitly reviewed business rules instead of claiming inference guessed keys.
 shutil.copyfile(p/'reviewed-rules.json',draft/'datapackage.json')
 assert run('check',draft)['ok']
 assert run('check-request','data/request.json')['ok']
 request_only=Path(tmp)/'request-only.json';request_only.write_text('[{"loan_id":103,"asset_id":"999","quantity":1000}]')
 scope=run('check-request',request_only);assert scope['ok'] and 'request-fields-only' in scope['scope']
 bad_request=Path(tmp)/'bad-request.json';bad_request.write_text('[{"loan_id":103,"asset_id":"001","quantity":0}]')
 assert any(e['code']=='minimum' for e in run('check-request',bad_request,expected=1)['errors'])
 # Errors in a temporary copy: missing referenced asset, duplicate loan ID and bad quantity.
 loans=draft/'loans.csv';good=loans.read_bytes()
 for wrong,code in [('loan_id,asset_id,quantity\n101,999,1\n','foreign-key'),('loan_id,asset_id,quantity\n101,001,1\n101,002,2\n','primary-key-duplicate'),('loan_id,asset_id,quantity\n101,001,0\n','minimum')]:
  loans.write_text(wrong);assert any(e['code']==code for e in run('check',draft,expected=1)['errors'])
  run('export',draft,Path(tmp)/'invalid-export',expected=1);assert not (Path(tmp)/'invalid-export').exists()
 loans.write_bytes(good);assert run('check',draft)['ok']
 exported=Path(tmp)/'exported';run('export',draft,exported)
 assert digest(exported)==digest(draft)
 assert run('check',exported)['ok'];run('export',draft,exported,expected=2)
 assert digest(p/'data')==original
 if args.reference:
  import frictionless
  assert frictionless.validate(str(exported/'datapackage.json')).valid
 print('Asset application: registry-only build, draft/review, JSON fields, three business errors, repair, byte-preserving export and overwrite refusal passed')
