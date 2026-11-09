"""Optional interoperability checks against Frictionless Framework 5.21.0.
Run after building: python scripts/test_reference.py (in a dedicated reference venv).
"""
from pathlib import Path
import json, shutil, subprocess, tempfile
import frictionless

ROOT = Path(__file__).resolve().parent.parent
CASES = [
    ('valid-package', None, None, True),
    ('dangling-foreign-key', 'orders.csv', 'id,product_id,quantity\n101,999,1\n', False),
    ('duplicate-primary-key', 'products.csv', 'id,title\n1,Book\n01,Pen\n', False),
    ('required-missing', 'products.csv', 'id,title\n1,\n2,Pen\n', False),
    ('below-minimum', 'orders.csv', 'id,product_id,quantity\n101,1,0\n', False),
    ('invalid-integer', 'orders.csv', 'id,product_id,quantity\n101,1,no\n', False),
    ('optional-foreign-key', 'orders.csv', 'id,product_id,quantity\n101,,1\n', True),
]
with tempfile.TemporaryDirectory(prefix='moonfriction-reference-') as temporary:
    work = Path(temporary)
    for name, filename, contents, expected in CASES:
        dest = work / name
        shutil.copytree(ROOT / 'examples/shop', dest)
        if filename:
            (dest / filename).write_text(contents, encoding='utf-8')
        path = dest / 'datapackage.json'
        reference = frictionless.Package(str(path)).validate()
        result = subprocess.run(['node', str(ROOT / 'scripts/cli.mjs'), 'validate', str(path)], capture_output=True, text=True)
        actual = json.loads(result.stdout)
        assert reference.valid == expected, (name, 'reference', reference.to_dict())
        assert actual['ok'] == expected, (name, 'MoonFriction', actual)
        assert result.returncode == (0 if expected else 1), (name, result.returncode)
        print(name, 'PASS', 'valid=' + str(expected))
    for example in ['school','sensors']:
        path = ROOT / 'examples' / example / 'datapackage.json'
        assert frictionless.Package(str(path)).validate().valid
        result = subprocess.run(['node',str(ROOT / 'scripts/cli.mjs'),'validate',str(path)],capture_output=True,text=True,check=True)
        assert json.loads(result.stdout)['ok']
        print(example + '-reference-import PASS')
    exported = work / 'exported'
    subprocess.run(['node', str(ROOT / 'scripts/cli.mjs'), 'export', str(ROOT / 'examples/shop/datapackage.json'), str(exported)], check=True, capture_output=True)
    assert frictionless.Package(str(exported / 'datapackage.json')).validate().valid
    print('exported-package-reference-import PASS')
print('Reference tool:', frictionless.__version__)
