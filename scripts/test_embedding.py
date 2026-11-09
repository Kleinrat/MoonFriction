"""Compile and run a separate MoonBit consumer against the public library API."""
from pathlib import Path
import json, subprocess, tempfile

ROOT = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='moonfriction-embedding-') as temporary:
    work = Path(temporary)
    consumer = work / 'consumer'
    consumer.mkdir()
    (work / 'moon.work').write_text('members = ' + json.dumps([str(ROOT), str(consumer)], ensure_ascii=False) + '\n')
    (consumer / 'moon.mod').write_text('name = "example/frictionless-consumer"\nversion = "0.0.1"\npreferred_target = "js"\nimport { "Kleinrat/frictionless@0.1.0" }\n')
    (consumer / 'moon.pkg').write_text('import { "Kleinrat/frictionless/src/core" }\noptions(is_main: true)\n')
    (consumer / 'main.mbt').write_text((ROOT / 'src/main/main.mbt').read_text())
    result = subprocess.run(['moon', '-C', str(consumer), 'run', '.', '--target', 'js'], capture_output=True, text=True, check=True)
    assert 'Table valid: true' in result.stdout, result.stdout
    assert 'Primary key errors: 0' in result.stdout, result.stdout
    print('Independent MoonBit consumer: public API compiled and ran successfully')
