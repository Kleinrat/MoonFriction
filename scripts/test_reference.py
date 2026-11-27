"""Optional interoperability checks against Frictionless Framework 5.21.0.
Run after building: python scripts/test_reference.py (in a dedicated reference venv).
"""
from pathlib import Path
from datetime import datetime, timezone
import csv, hashlib, json, shutil, subprocess, tempfile
from xml.etree import ElementTree
import frictionless
from jsonschema import Draft4Validator

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
    example = ROOT / 'examples/schema-diff'
    for version, expected in [('old', True), ('new', False)]:
        schema = frictionless.Schema.from_descriptor(json.loads((example / f'{version}.json').read_text()))
        resource = frictionless.Resource(path='orders.csv', basepath=str(example), schema=schema)
        assert resource.validate().valid == expected, ('schema diff witness', version)
    print('schema-diff-order-reference PASS')

    # Swapping composite key positions preserves which rows violate uniqueness.
    for key in (['a', 'b'], ['b', 'a']):
        descriptor = {'fields': [{'name': name, 'type': 'string'} for name in ('a', 'b')],
                      'primaryKey': key}
        schema = frictionless.Schema.from_descriptor(descriptor)
        path = work / 'key.schema.json'
        path.write_text(json.dumps(descriptor))
        data_path = work / 'pairs.csv'
        for suffix, valid in [('', True), ('x,y\n', False)]:
            data_path.write_text('a,b\nx,y\ny,x\n' + suffix)
            reference = frictionless.Resource(path=data_path.name, basepath=str(work), schema=schema)
            assert reference.validate().valid == valid
            actual = subprocess.run(['node', 'scripts/cli.mjs', 'validate-stream', str(path), str(data_path)],
                                    cwd=ROOT, capture_output=True, text=True)
            assert actual.returncode == int(not valid)
            assert [e['row'] for e in json.loads(actual.stdout)['errors']] == ([] if valid else [3])
    print('composite-key order: both validators agree for distinct and duplicate tuples')

    exchange = work / 'standard-exchange'
    shutil.copytree(ROOT / 'examples/standard-exchange', exchange)
    manifest = exchange / 'datapackage.json'
    cli = ['node', str(ROOT / 'scripts/cli.mjs')]
    assert frictionless.Package(str(manifest)).validate().valid
    assert subprocess.run(cli + ['validate', str(manifest)], capture_output=True).returncode == 0
    csv_file = exchange / 'shipments.csv'
    original = csv_file.read_bytes()
    for before, after, code, field in [
        (b'2024-02-29', b'2024-02-28', 'minimum', 'shipped_on'),
        (b'2024-02-29', b'2023-02-29', 'type', 'shipped_on'),
        (b',P10,', b',P99,', 'foreign-key', 'sku'),
        (b',2,yes,', b',0,yes,', 'minimum', 'quantity'),
        (b',2,yes,', b',2,maybe,', 'type', 'packed'),
    ]:
        csv_file.write_bytes(original.replace(before, after, 1))
        reference = frictionless.Package(str(manifest)).validate()
        actual = subprocess.run(cli + ['validate', str(manifest)], capture_output=True, text=True)
        assert not reference.valid and actual.returncode == 1, (field, reference.to_descriptor())
        error, = json.loads(actual.stdout)['errors']
        assert (error['code'], error['resource'], error['row'], error['field']) == (code, 'shipments', 1, field)
    csv_file.write_bytes(original)
    tabular_export = work / 'tabular-roundtrip'
    subprocess.run(cli + ['export', str(manifest), str(tabular_export)], check=True, capture_output=True)
    assert frictionless.Package(str(tabular_export / 'datapackage.json')).validate().valid
    assert (tabular_export / 'shipments.csv').read_bytes() == original
    print('Table Schema v1: typed CSV, invalid date, bounds, boolean, foreign key and export/read-back PASS')

    mixed_export = work / 'mixed-roundtrip'
    mixed_path = exchange / 'mixed.json'
    checked = subprocess.run(cli + ['export-package', str(mixed_path), str(mixed_export)],
                             check=True, capture_output=True, text=True)
    mixed = json.loads(checked.stdout)
    assert [item['location'] for item in mixed['resources']] == ['local', 'inline', 'remote']
    copied = mixed_export / 'datapackage.json'
    assert json.loads(copied.read_text()) == json.loads(mixed_path.read_text())
    for part in ('products.csv', 'products-annex.csv'):
        assert (mixed_export / part).read_bytes() == (exchange / part).read_bytes()
    reference_pkg = frictionless.Package(str(copied))
    assert reference_pkg.get_resource('metadata').data['warehouse'] == 'main'
    assert reference_pkg.get_resource('tracking').path == 'https://example.org/tracking.csv'
    assert reference_pkg.get_resource('files').path == 'products.csv'
    print('Data Package v1: multipart local files and preserved inline/remote descriptors PASS')

    multipart = exchange / 'multipart.json'
    multipart_reference = frictionless.Package(str(multipart))
    assert multipart_reference.validate().valid
    assert [len(r.read_rows()) for r in multipart_reference.resources] == [3, 2]
    assert multipart_reference.get_resource('shipments').read_rows()[0]['id'] == 9007199254740993
    multipart_export = work / 'multipart-roundtrip'
    subprocess.run(cli + ['export', str(multipart), str(multipart_export)], check=True, capture_output=True)
    assert frictionless.Package(str(multipart_export / 'datapackage.json')).validate().valid
    broken = multipart_export / 'products-annex.csv'
    broken.write_text('sku,name\nP10,Duplicate\n')
    duplicate = subprocess.run(cli + ['validate', str(multipart_export / 'datapackage.json')],
                               capture_output=True, text=True)
    assert duplicate.returncode == 1
    assert any(e['code'] == 'primary-key-duplicate' and e['row'] == 3 for e in json.loads(duplicate.stdout)['errors'])
    assert not frictionless.Package(str(multipart_export / 'datapackage.json')).validate().valid
    print('Mixed Table Schema: inline JSON keys resolve against the second CSV part and round-trip PASS')

    time_schema = work / 'fraction.schema.json'
    time_data = work / 'fraction.csv'
    for dtype, format_name, valid, invalid in [
        ('time', '%H:%M:%S.%f', '12:34:56.12', '12:34:56.1234567'),
        ('datetime', '%Y-%m-%dT%H:%M:%S.%f%z', '2024-03-01T00:01:02.003000+01:00',
         '2023-02-29T00:01:02.003000+01:00'),
        ('date', '%d %b %Y', '29 Feb 2024', '29 Feb 2023'),
        ('date', '%Y-%j', '2024-060', '2024-367'),
        ('date', '%G-W%V-%u', '2020-W53-7', '2020-W54-7'),
        ('time', '%I:%M %p', '7:05 PM', '13:05 PM'),
    ]:
        descriptor = {'fields': [{'name': 'when', 'type': dtype, 'format': format_name}]}
        time_schema.write_text(json.dumps(descriptor))
        schema = frictionless.Schema.from_descriptor(descriptor)
        for raw, expected in [(valid, True), (invalid, False)]:
            with time_data.open('w', encoding='utf-8', newline='') as stream:
                csv.writer(stream).writerows([['when'], [raw]])
            report = frictionless.Resource(path=time_data.name, basepath=str(work), schema=schema).validate()
            actual = subprocess.run(cli + ['validate-stream', str(time_schema), str(time_data)],
                                    capture_output=True, text=True)
            assert report.valid == expected and actual.returncode == int(not expected), (dtype, raw)
    print('Custom time formats: Frictionless and MoonFriction agree on fractions, month names, ordinal dates, ISO week dates and 12-hour time')

    # Compare normal forms with Python and cover valid and malformed offsets
    # via normal CLI validation paths as well as export/readback.
    offset_format = '%Y-%m-%dT%H:%M:%S.%f%z'
    timed = work / 'second-offset'
    timed.mkdir()
    timed_manifest = timed / 'datapackage.json'
    timed_csv = timed / 'times.csv'
    timestamp_field = {'name': 'when', 'type': 'datetime', 'format': offset_format}
    threshold = '2024-03-01T00:00:00.000001Z'
    timed_manifest.write_text(json.dumps({'resources': [{
        'name': 'times', 'path': timed_csv.name,
        'schema': {'fields': [{**timestamp_field, 'constraints': {'minimum': threshold}}]},
    }]}), encoding='utf-8')
    time_schema.write_text(json.dumps({'fields': [timestamp_field]}), encoding='utf-8')
    cases = [
        ('2024-03-01T01:02:03.200001+01:02:03.2', True, True),
        ('2024-03-01T00:00:00.000001+000000.000001', True, False),
        ('2024-03-01T01:02:03.2+01:0203', False, False),
        ('2024-03-01T01:02:03.2+01:02:60', False, False),
    ]
    for raw, valid, within_bound in cases:
        try:
            instant = datetime.strptime(raw, offset_format).astimezone(timezone.utc)
        except ValueError:
            assert not valid
        else:
            assert valid and (instant >= datetime.strptime(threshold, offset_format)) == within_bound
        with timed_csv.open('w', encoding='utf-8', newline='') as stream:
            csv.writer(stream).writerows([['when'], [raw]])
        stream_result = subprocess.run(cli + ['validate-stream', str(time_schema), str(timed_csv)],
                                       capture_output=True, text=True)
        batch_result = subprocess.run(cli + ['validate', str(timed_manifest)], capture_output=True, text=True)
        assert stream_result.returncode == int(not valid), stream_result.stdout
        assert batch_result.returncode == int(not within_bound), batch_result.stdout
        errors = json.loads(batch_result.stdout)['errors']
        assert [error['code'] for error in errors] == ([] if within_bound else ['minimum' if valid else 'type'])
    timed_csv.write_text('when\n' + cases[0][0] + '\n', encoding='utf-8')
    timed_export = work / 'second-offset-roundtrip'
    subprocess.run(cli + ['export', str(timed_manifest), str(timed_export)], check=True, capture_output=True)
    assert (timed_export / 'times.csv').read_bytes() == timed_csv.read_bytes()
    exported_package = frictionless.Package(str(timed_export / 'datapackage.json'))
    assert exported_package.validate().valid
    date_value = exported_package.get_resource('times').read_rows()[0]['when']
    assert date_value.astimezone(timezone.utc) == datetime.strptime(threshold, offset_format)
    print('Second and fractional %z offsets agree with Python strptime and survive export to Frictionless')

    # §5.8 of RFC 3339 uses these two spellings for the same leap second.
    created = work / 'created.json'
    for timestamp, expected in [
        ('1990-12-31T23:59:60Z', True), ('1990-12-31T15:59:60-08:00', True),
        ('1990-12-30T23:59:60Z', False), ('1990-12-31T23:59:60-08:00', False),
    ]:
        created.write_text(json.dumps({
            'created': timestamp, 'resources': [{'name': 'items', 'data': []}],
        }), encoding='utf-8')
        actual = subprocess.run(cli + ['inspect-package', str(created)], capture_output=True, text=True)
        assert actual.returncode == int(not expected), actual.stdout
        if not expected:
            assert json.loads(actual.stdout)['errors'][0]['field'] == 'created'
    print('RFC 3339 leap-second examples accepted; equivalent invalid date or offset rejected')

    tabular_manifest = work / 'tabular-profile.json'
    tabular_items = {
        'name': 'items', 'profile': 'tabular-data-resource', 'data': [{'id': 1}],
        'schema': {'fields': [{'name': 'id', 'type': 'integer'}]},
    }
    for change, code_field in [(None, None), ('profile', 'profile'), ('schema', 'schema'), ('data', 'data')]:
        item = tabular_items.copy()
        if change == 'data':
            item['data'] = [1]
        elif change:
            del item[change]
        tabular_manifest.write_text(json.dumps({
            'profile': 'tabular-data-package', 'resources': [item],
        }), encoding='utf-8')
        try:
            reference_valid = frictionless.Package(str(tabular_manifest)).validate().valid
        except frictionless.FrictionlessException:
            reference_valid = False
        expected = change is None
        assert reference_valid == expected, change
        for command in ('inspect-package', 'validate'):
            actual = subprocess.run(cli + [command, str(tabular_manifest)], capture_output=True, text=True)
            assert actual.returncode == int(not expected), actual.stdout + actual.stderr
            if not expected:
                error = json.loads(actual.stdout)['errors'][0]
                assert (error['resource'], error['field']) == ('items', code_field)
    print('Built-in tabular package profiles agree with Frictionless on required profile, schema and rows')

    geography = {
        'type': 'MultiPoint',
        'coordinates': [[177, -20], [-178, -16]],
        'bbox': [177, -20, -178, -16],
    }
    descriptor = {'fields': [{'name': 'region', 'type': 'geojson'}]}
    geo_data = work / 'geo.csv'
    time_schema.write_text(json.dumps(descriptor))
    schema = frictionless.Schema.from_descriptor(descriptor)
    # RFC 7946 §5.2 Fiji antimeridian envelope. Frictionless validates
    # the exchanged geometry, while MoonFriction also checks containment.
    for point, expected in [([-178, -16], True), ([0, -16], False)]:
        geography['coordinates'][1] = point
        with geo_data.open('w', encoding='utf-8', newline='') as stream:
            csv.writer(stream).writerows([['region'], [json.dumps(geography)]])
        actual = subprocess.run(cli + ['validate-stream', str(time_schema), str(geo_data)],
                                capture_output=True, text=True)
        assert actual.returncode == int(not expected), actual.stdout
        if expected:
            assert frictionless.Resource(path=geo_data.name, basepath=str(work), schema=schema).validate().valid
    print('GeoJSON: Fiji antimeridian fixture exchanges with Frictionless, outside point rejected locally')

    profile_path = work / 'profiled.json'
    profile_file = work / 'profiles.json'
    package_profile = 'warehouse-profile'
    resource_profile = 'https://example.org/retention-resource.json'
    documents = {
        package_profile: {'type': 'object', 'required': ['title']},
        resource_profile: {
            'type': 'object', 'required': ['retention'],
            'properties': {'retention': {'type': 'integer', 'minimum': 1}},
        },
    }
    for schema in documents.values():
        Draft4Validator.check_schema(schema)
    profile_file.write_text(json.dumps(documents))
    profiled = {
        'profile': package_profile, 'title': 'Warehouse',
        'resources': [{'name': 'archive', 'profile': resource_profile, 'data': {'sku': 'P01'}}],
    }
    for retention in (30, 0):
        resource, = profiled['resources']
        resource['retention'] = retention
        profile_path.write_text(json.dumps(profiled))
        expected = (Draft4Validator(documents[package_profile]).is_valid(profiled) and
                    Draft4Validator(documents[resource_profile]).is_valid(resource))
        actual = subprocess.run(cli + ['inspect-package', str(profile_path), '--profile-schemas', str(profile_file)],
                                capture_output=True, text=True)
        assert actual.returncode == int(not expected), actual.stdout
        if not expected:
            error, = json.loads(actual.stdout)['errors']
            assert (error['resource'], error['field']) == ('archive', 'profile/retention')
    unsupported = subprocess.run(cli + ['inspect-package', str(profile_path)], capture_output=True, text=True)
    assert unsupported.returncode == 1
    assert {e['code'] for e in json.loads(unsupported.stdout)['errors']} == {'unsupported'}
    resource['retention'] = 30
    profile_path.write_text(json.dumps(profiled))
    profiled_export = work / 'profiled-roundtrip'
    subprocess.run(cli + ['export-package', str(profile_path), str(profiled_export), '--profile-schemas',
                          str(profile_file)], check=True, capture_output=True)
    copied_profiled = json.loads((profiled_export / 'datapackage.json').read_text())
    assert copied_profiled == profiled
    assert Draft4Validator(documents[package_profile]).is_valid(copied_profiled)
    assert Draft4Validator(documents[resource_profile]).is_valid(copied_profiled['resources'][0])
    # A profile can deliberately require an external schema locator. Evaluate
    # the original descriptor, then resolve it for tabular validation.
    table_schema = work / 'table-schema.json'
    table_schema.write_text(json.dumps({'fields': [{'name': 'sku', 'type': 'string'}]}))
    documents[resource_profile]['properties']['schema'] = {'type': 'string'}
    documents[resource_profile]['required'].append('schema')
    profile_file.write_text(json.dumps(documents))
    resource['schema'] = table_schema.name
    resource['data'] = [{'sku': 'P01'}]
    profile_path.write_text(json.dumps(profiled))
    profile_options = ['--profile-schemas', str(profile_file)]
    tables = work / 'profiled-tables-roundtrip'
    subprocess.run(cli + ['export', str(profile_path), str(tables)] + profile_options,
                   check=True, capture_output=True)
    roundtrip = tables / 'datapackage.json'
    assert json.loads(roundtrip.read_text()) == profiled
    assert (tables / table_schema.name).read_bytes() == table_schema.read_bytes()
    subprocess.run(cli + ['validate', str(roundtrip)] + profile_options, check=True, capture_output=True)
    print('Data Package profiles: package and resource constraints and export agree with Python jsonschema')

    if shutil.which('xmllint'):
        xml = work / 'value.xml'
        xsd = work / 'value.xsd'
        schema_path = work / 'pattern.schema.json'
        data_path = work / 'pattern.csv'
        namespace = '{http://www.w3.org/2001/XMLSchema}'
        for pattern, valid, invalid in [
            ('[a-z-[aeiou]]+', 'sky', 'skyline'),
            (r'\p{IsGreek}+', 'Ωβ', 'ΩA'),
            (r'\p{L}\d+', 'Ω٣', 'ΩX'),
            (r'[\p{Lu}-[A-Z]]+', 'Ω', 'A'),
            ('[A-Z]+', 'ABC', 'aBC'),
        ]:
            schema = ElementTree.Element(namespace + 'schema')
            field = ElementTree.SubElement(schema, namespace + 'element', name='value')
            simple = ElementTree.SubElement(field, namespace + 'simpleType')
            restricted = ElementTree.SubElement(simple, namespace + 'restriction', {'base': 'xs:string', 'xmlns:xs': 'http://www.w3.org/2001/XMLSchema'})
            ElementTree.SubElement(restricted, namespace + 'pattern', value=pattern)
            ElementTree.ElementTree(schema).write(xsd, encoding='utf-8')
            schema_path.write_text(json.dumps({'fields': [{'name': 'value', 'constraints': {'pattern': pattern}}]}))
            for value, expected in [(valid, True), (invalid, False)]:
                element = ElementTree.Element('value')
                element.text = value
                ElementTree.ElementTree(element).write(xml, encoding='utf-8')
                external = subprocess.run(['xmllint', '--noout', '--schema', str(xsd), str(xml)],
                                          capture_output=True)
                assert (external.returncode == 0) == expected, (pattern, value, external.stderr)
                with data_path.open('w', encoding='utf-8', newline='') as stream:
                    csv.writer(stream).writerows([['value'], [value]])
                actual = subprocess.run(cli + ['validate-stream', str(schema_path), str(data_path)],
                                        capture_output=True, text=True)
                assert actual.returncode == int(not expected), (pattern, value, actual.stdout, actual.stderr)
                if not expected:
                    error, = json.loads(actual.stdout)['errors']
                    assert (error['code'], error['field'], error['row']) == ('pattern', 'value', 1)
        print('XML Schema regular expressions: five positive/negative pairs agree with xmllint')

        for kind, builtin, values in [
            ('year', 'gYear', [('10000', True), ('-0001', True), ('-0000', False), ('01234', False)]),
            ('yearmonth', 'gYearMonth', [('10000-01', True), ('-0001-02', True), ('0000-02', False),
                                       ('10000-13', False)]),
        ]:
            xsd.write_text(f'<xs:schema xmlns:xs="{namespace[1:-1]}">'
                           f'<xs:element name="value" type="xs:{builtin}"/></xs:schema>', encoding='utf-8')
            schema_path.write_text(json.dumps({'fields': [{'name': 'value', 'type': kind}]}), encoding='utf-8')
            for value, expected in values:
                xml.write_text(f'<value>{value}</value>', encoding='utf-8')
                external = subprocess.run(['xmllint', '--noout', '--schema', str(xsd), str(xml)],
                                          capture_output=True)
                with data_path.open('w', newline='', encoding='utf-8') as stream:
                    csv.writer(stream).writerows([['value'], [value]])
                actual = subprocess.run(cli + ['validate-stream', str(schema_path), str(data_path)],
                                        capture_output=True, text=True)
                assert (external.returncode == 0) == expected, (value, external.stderr)
                assert actual.returncode == int(not expected), (value, actual.stdout, actual.stderr)
        print('Expanded and signed years match the XML Schema 1.0 lexical examples checked with xmllint')

    tz = ROOT / 'examples/iana-tzdb'
    data = tz / 'zones.csv'
    assert hashlib.sha256(data.read_bytes()).hexdigest() == '245e82d730c1fff286117da6e34241ca70704b57113385d2f282a9c4a631195a'
    with data.open(encoding='utf-8', newline='') as file:
        rows = list(csv.DictReader(file))
    affected = [i for i, row in enumerate(rows, 1) if len(row['country_codes']) > 2]
    assert len(rows) == 312 and len(affected) == 34
    cli = ['node', str(ROOT / 'scripts/cli.mjs')]
    comparison = subprocess.check_output(cli + ['schema', 'diff', str(tz / 'schema.json'),
                                                str(tz / 'single-country.schema.json')])
    change, = json.loads(comparison)['changes']
    assert (change['field'], change['rule'], change['impact'], change['before'], change['after']) == (
        'country_codes', 'maxLength', 'tightened', None, 2)
    for schema_file, expected in [('schema.json', []), ('single-country.schema.json', affected)]:
        schema = frictionless.Schema.from_descriptor(json.loads((tz / schema_file).read_text()))
        report = frictionless.Resource(path='zones.csv', basepath=str(tz), schema=schema).validate()
        diagnostics = report.to_dict()['tasks'][0]['errors']
        # Frictionless counts the header; MoonFriction starts with the first data record.
        assert report.valid == (not expected)
        assert [(e['rowNumber'] - 1, e['fieldName']) for e in diagnostics] == [
            (i, 'country_codes') for i in expected]
        checked = subprocess.run(cli + ['validate-stream', str(tz / schema_file), str(data),
                                        '--max-errors', '100'], capture_output=True, text=True)
        actual = json.loads(checked.stdout)
        assert checked.returncode == int(bool(expected)) and actual['complete']
        assert (actual['rows'], actual['error_count']) == (312, len(expected))
        assert [(e['row'], e['field'], e['code']) for e in actual['errors']] == [
            (i, 'country_codes', 'maxLength') for i in expected]
    print('IANA tzdb 2025b: all 312 rows checked; 34 affected records match Frictionless')

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
        schema_file = enumerated / 'products.schema.json'
        schema_file.write_text(json.dumps(descriptor['resources'][0]['schema']))
        stream = subprocess.run(['node', str(ROOT / 'scripts/cli.mjs'), 'validate-stream',
                                 str(schema_file), str(enumerated / 'products.csv')],
                                capture_output=True, text=True)
        stream_report = json.loads(stream.stdout)
        assert stream.returncode == command.returncode and stream_report['ok'] == expected
        assert [(e['code'], e['field'], e['row']) for e in stream_report['errors']] == [
            (e['code'], e['field'], e['row']) for e in report['errors']]
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
