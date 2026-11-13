"""Compile and run separate MoonBit consumers against the public library API."""
from pathlib import Path
import json, re, subprocess, tempfile

ROOT = Path(__file__).resolve().parent.parent
VERSION = re.search(r'^version\s*=\s*"([^"]+)"', (ROOT / 'moon.mod').read_text(), re.M).group(1)
with tempfile.TemporaryDirectory(prefix='moonfriction-embedding-') as temporary:
    work = Path(temporary)
    consumers = []
    for directory, source in [
        ('consumer', ROOT / 'src/main/main.mbt'),
        ('standalone', ROOT / 'examples/standalone-consumer/main.mbt'),
        ('json', ROOT / 'examples/json-consumer/main.mbt'),
    ]:
        consumer = work / directory
        consumer.mkdir()
        (consumer / 'moon.mod').write_text(
            f'name = "example/frictionless-{directory}"\nversion = "0.0.1"\npreferred_target = "js"\nimport {{ "Kleinrat/frictionless@{VERSION}" }}\n'
        )
        (consumer / 'moon.pkg').write_text('import { "Kleinrat/frictionless/src/core" }\noptions(is_main: true)\n')
        (consumer / 'main.mbt').write_text(source.read_text())
        consumers.append(consumer)
    (work / 'moon.work').write_text('members = ' + json.dumps([str(ROOT)] + [str(c) for c in consumers], ensure_ascii=False) + '\n')
    for consumer in consumers:
        result = subprocess.run(['moon', '-C', str(consumer), 'run', '.', '--target', 'js'], capture_output=True, text=True, check=True)
        if consumer.name == 'consumer':
            assert 'Table valid: true' in result.stdout, result.stdout
            assert 'Primary key errors: 0' in result.stdout, result.stdout
        elif consumer.name == 'standalone':
            assert 'Standalone valid: false' in result.stdout, result.stdout
            assert 'First code: primary-key-duplicate' in result.stdout, result.stdout
        else:
            assert 'JSON array rows valid: true' in result.stdout, result.stdout
            assert 'JSON object rows valid: true' in result.stdout, result.stdout
            assert 'Extra property code: extra-property' in result.stdout, result.stdout
    print('Independent MoonBit consumers: package and standalone public APIs compiled and ran successfully')
