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
    enumerated = work / 'enum'
    shutil.copytree(ROOT / 'examples/shop', enumerated)
    description = enumerated / 'datapackage.json'
    descriptor = json.loads(description.read_text())
    descriptor['resources'][0]['schema']['fields'][1]['constraints']['enum'] = ['draft', 'paid']
    description.write_text(json.dumps(descriptor))
    for status, expected in [('paid', True), ('void', False)]:
        (enumerated / 'products.csv').write_text('id,title\n1,' + status + '\n2,draft\n')
        assert frictionless.Package(str(description)).validate().valid == expected
        command = subprocess.run(['node', str(ROOT / 'scripts/cli.mjs'), 'validate', str(description)],
                                 capture_output=True, text=True)
        report = json.loads(command.stdout)
        assert report['ok'] == expected and command.returncode == (0 if expected else 1)
        if not expected:
            assert [(e['code'], e['field'], e['row']) for e in report['errors']] == [('enum', 'title', 1)]
    print('enum-allowed-and-disallowed-reference PASS')

    # Two different v1 resource dialects in one package, with mixed quoting.
    varied = work / 'dialects'
    shutil.copytree(ROOT / 'examples/shop', varied)
    description = varied / 'datapackage.json'
    descriptor = json.loads(description.read_text())
    descriptor['resources'][0]['dialect'] = {'delimiter': ';', 'quoteChar': "'"}
    descriptor['resources'][1]['dialect'] = {'delimiter': '\t'}
    description.write_text(json.dumps(descriptor))
    (varied / 'products.csv').write_text("id;title\n1;'tea; it''s good'\n")
    (varied / 'orders.csv').write_text('id\tproduct_id\tquantity\n101\t1\t2\n')
    cli = ['node', str(ROOT / 'scripts/cli.mjs')]
    assert frictionless.Package(str(description)).validate().valid
    exported_dialects = work / 'exported-dialects'
    subprocess.run(cli + ['export', str(description), str(exported_dialects)], check=True)
    assert json.loads((exported_dialects / 'datapackage.json').read_text()) == descriptor
    for resource in descriptor['resources']:
        filename = resource['path']
        assert (exported_dialects / filename).read_bytes() == (varied / filename).read_bytes()
    assert frictionless.Package(str(exported_dialects / 'datapackage.json')).validate().valid
    (varied / 'orders.csv').write_text('id\tproduct_id\tquantity\n101\t42\t2\n')
    assert not frictionless.Package(str(description)).validate().valid
    invalid = subprocess.run(cli + ['validate', str(description)], capture_output=True, text=True)
    assert invalid.returncode == 1 and json.loads(invalid.stdout)['errors'][0]['code'] == 'foreign-key'
    print('mixed-resource-dialects-reference-and-export PASS')
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

    shared = work / 'shared-schema'
    shutil.copytree(ROOT / 'examples/shop', shared)
    descriptor_path = shared / 'datapackage.json'
    descriptor = json.loads(descriptor_path.read_text())
    product = descriptor['resources'][0]
    (shared / 'columns.json').write_text(json.dumps(product['schema']))
    product['schema'] = 'columns.json'
    descriptor_path.write_text(json.dumps(descriptor))
    assert frictionless.Package(str(descriptor_path)).validate().valid
    portable = work / 'portable'
    subprocess.run(['node', str(ROOT / 'scripts/cli.mjs'), 'export', str(descriptor_path),
                    str(portable)], check=True, capture_output=True)
    shutil.rmtree(shared)
    assert frictionless.Package(str(portable / 'datapackage.json')).validate().valid
    print('shared-schema-reference-import-and-export PASS')

    # Generated draft -> validate/export -> official tool reads it.
    inferred = work / 'inferred'
    inferred.mkdir()
    inferred_csv = inferred / 'items.csv'
    inferred_csv.write_text(
        'id,name,price,active,sku,note\n'
        '001,Pen,1.50,true,ABC-1,\n'
        '002,Notebook,2,false,ABC-2,hello\n',
        encoding='utf-8',
    )
    inferred_descriptor = inferred / 'datapackage.json'
    subprocess.run(
        ['node', str(ROOT / 'scripts/infer.mjs'), str(inferred_csv), '--out', str(inferred_descriptor)],
        check=True, capture_output=True, text=True,
    )
    generated = frictionless.Package(str(inferred_descriptor))
    assert generated.validate().valid, generated.validate().to_dict()
    print('inferred-draft-reference-import PASS')
print('Reference tool:', frictionless.__version__)
