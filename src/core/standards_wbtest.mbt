///|
test "structured and temporal constraints agree on CSV JSON and streaming rows" {
  let schema = parse_table_schema(
    (
      #|{"fields":[{"name":"code","constraints":{"pattern":"^[A-Z]{2}[0-9]+$"}},{"name":"tags","type":"array","constraints":{"minLength":1}},{"name":"details","type":"object","constraints":{"unique":true,"enum":[{"x":1,"y":[2]}]}},{"name":"delivered","type":"date","constraints":{"minimum":"2024-02-29","maximum":"2024-04-01"}}]}
    ),
  ).unwrap()
  let header = ["code", "tags", "details", "delivered"]
  let rows = [
    ["AB1", "[10]", "{\"x\":1,\"y\":[2]}", "2024-02-29"],
    ["001", "[]", "{\"y\":[2],\"x\":1}", "2024-02-28"],
  ]
  let csv = schema.validate("order", header, rows)
  let json = schema.validate_json(
    "order",
    input_from_json(
      "order",
      (
        #|[["AB1",[10],{"x":1,"y":[2]},"2024-02-29"],["001",[],{"y":[2],"x":1},"2024-02-28"]]
      ),
    ).unwrap(),
  )
  assert_eq(csv.errors.map(e => e.code), [
    "pattern", "minLength", "unique", "minimum",
  ])
  assert_eq(json.errors, csv.errors)
  let stream = RowValidator::new("order", schema, header).unwrap()
  for row in rows {
    stream.feed(row)
  }
  assert_eq(stream.finish().errors, csv.errors)
}

///|
test "declared string numeric boolean and geographical formats are applied" {
  let schema = parse_table_schema(
    (
      #|{"fields":[{"name":"uuid","format":"uuid"},{"name":"encoded","format":"binary"},{"name":"email","format":"email"},{"name":"link","format":"uri"},{"name":"price","type":"number","bareNumber":false,"decimalChar":",","groupChar":"."},{"name":"shipped","type":"boolean","trueValues":["yes"],"falseValues":["no"],"constraints":{"enum":["yes"]}},{"name":"point","type":"geopoint","format":"object"},{"name":"boundary","type":"geojson"},{"name":"elapsed","type":"duration"}]}
    ),
  ).unwrap()
  let header = schema.fields.map(f => f.name)
  let valid = [
    "f47ac10b-58cc-4372-a567-0e02b2c3d479", "MQ==", "ops@example.org", "https://example.org/orders?id=1",
    "€1.234,50", "yes", "{\"lon\":120,\"lat\":30}", "{\"type\":\"LineString\",\"coordinates\":[[0,0],[1,1]]}",
    "P1DT2.5S",
  ]
  let bad = [
    "foo", "MQ", "ops@", "https://example.org/bad%ZZ", "1,234.50", "no", "{\"lon\":120,\"lat\":100}",
    "{\"type\":\"LineString\",\"coordinates\":[[0,0]]}", "PT",
  ]
  let report = schema.validate("order", header, [valid, bad])
  assert_eq(report.errors.map(e => e.field), header)
  assert_eq(report.table.rows[0][4], NumberValue(1234.5))
  assert_eq(report.table.rows[0][5], BooleanValue(true))
  assert_true(report.table.rows[0][6] is StructuredValue(_))
}

///|
test "non-default constraints fail explicitly when the schema declaration is invalid" {
  for
    text in [
      (
        #|{"fields":[{"name":"x","constraints":{"pattern":"["}}]}
      ),
      (
        #|{"fields":[{"name":"x","type":"boolean","trueValues":["0"]}]}
      ),
      (
        #|{"fields":[{"name":"x","type":"number","groupChar":",","decimalChar":","}]}
      ),
      (
        #|{"fields":[{"name":"x","type":"date","constraints":{"maximum":"1900-02-29"}}]}
      ),
    ] {
    assert_true(parse_table_schema(text) is Err(_))
  }
}

///|
test "large integer and decimal bounds remain exact through JSON, CSV and diff" {
  let schema = parse_table_schema(
    (
      #|{"fields":[{"name":"id","type":"integer","constraints":{"minimum":"9223372036854775808"}},{"name":"precise","type":"number","constraints":{"maximum":"1.0000000000000000000000000001"}}]}
    ),
  ).unwrap()
  let witness =
    #|[[9223372036854775808,1.0000000000000000000000000001],[9223372036854775807,1.0000000000000000000000000002]]
  let json = schema.validate_json(
    "test",
    input_from_json("test", witness).unwrap(),
  )
  let csv = schema.validate("test", ["id", "precise"], [
    ["9223372036854775808", "1.0000000000000000000000000001"],
    ["9223372036854775807", "1.0000000000000000000000000002"],
  ])
  assert_eq(csv.errors, json.errors)
  assert_eq(csv.errors.map(error => error.code), ["minimum", "maximum"])
  assert_true(csv.table.rows[0][0] is BigIntegerValue(_))
  assert_true(csv.table.rows[0][1] is ExactNumberValue(_))
  let text =
    #|{"fields":[{"name":"x","type":"number","constraints":{"minimum":1e-99999999999999999999}}]}
  let tiny = parse_table_schema(text).unwrap()
  assert_false(tiny.validate("test", ["x"], [["0"]]).valid())
  assert_true(tiny.validate("test", ["x"], [["1e-99"]]).valid())
}

///|
test "format-aware timestamps geospatial input and duration use logical values" {
  let schema = parse_table_schema(
    (
      #|{"fields":[{"name":"when","type":"date","format":"%d/%m/%Y","constraints":{"minimum":"29/02/2024"}},{"name":"route","type":"geojson","format":"topojson"},{"name":"wait","type":"duration","constraints":{"enum":["P1D"]}}]}
    ),
  ).unwrap()
  let good =
    #|[["29/02/2024",{"type":"Topology","objects":{"route":{"type":"LineString","arcs":[-1]}},"arcs":[[[0,0],[1,1]]]},"PT24H"]]
  let valid = schema.validate_json(
    "test",
    input_from_json("test", good).unwrap(),
  )
  assert_true(valid.valid())
  let invalid_text = good
    .replace_all(old="29/02/2024", new="28/02/2024")
    .replace_all(old="[-1]", new="[1]")
  let invalid = schema.validate_json(
    "test",
    input_from_json("test", invalid_text).unwrap(),
  )
  assert_eq(invalid.errors.map(e => e.field), ["when", "route"])
}

///|
test "XML Schema patterns support Unicode categories blocks and subtraction" {
  fn accepts(pattern : String, value : String) -> Bool {
    let compiled = compile_field_pattern(pattern).unwrap()
    compiled.matcher.execute(value[:]) is Some(_)
  }
  let names = "\\i\\c*"
  assert_true(accepts(names, "张𐐀-7"))
  assert_false(accepts(names, "7abc"))
  assert_false(accepts(names, "bad name"))
  assert_true(accepts("\\p{L}[\\p{Nd}-[0-9]]\\p{IsGreek}+", "𐐀٣Ω"))
  assert_false(accepts("\\p{L}[\\p{Nd}-[0-9]]\\p{IsGreek}+", "𐐀3Ω"))
  assert_true(accepts("[a-z-[aeiou]]+", "sky"))
  assert_false(accepts("[a-z-[aeiou]]+", "skyline"))
  assert_false(accepts("[a-[a]]", "a"))
  assert_true(accepts("\\p{Lu}", "𐐀"))
  assert_false(accepts("\\p{Lu}", "𐐨"))
  assert_false(accepts("\\P{IsBasicLatin}", "A"))
  assert_true(accepts("\\P{IsBasicLatin}", "🙂"))
  assert_false(accepts(".", "\r"))
  assert_true(accepts(".", "🙂"))
  assert_true(accepts("^P[0-9]+$", "P10"))
  assert_true(accepts("\\^P\\$", "^P$"))
  assert_false(accepts("[A-Z]+", "aBC"))
  assert_true(compile_field_pattern("[a-z-[a]b]") is Err(_))
  assert_true(compile_field_pattern("\\p{Unknown}") is Err(_))
}

///|
test "TopoJSON joins quantized and reversed arcs and checks ring closure" {
  let base =
    #|{"type":"Topology","transform":{"scale":[1,1],"translate":[0,0]},"arcs":[[[0,0],[2,0],[0,2]],[[0,0],[0,2],[2,0]]],"objects":{"zone":{"type":"Polygon","arcs":[[0,-2]]}}}
  fn valid(raw : String) -> Bool {
    let parsed = @json.parse(raw) catch { _ => return false }
    topojson_cell(parsed) is Ok(_)
  }
  assert_true(valid(base))
  assert_false(valid(base.replace_all(old="[0,-2]", new="[0,1]")))
  assert_false(valid(base.replace_all(old="[0,-2]", new="[0]")))
  assert_false(valid(base.replace_all(old="[2,0]]]", new="[3,0]]]")))
}

///|
test "string formats validate components beyond simple character allowlists" {
  for
    uri in [
      "https://user:pass@[2001:db8::1]:443/a%20b?x=3#result", "https://[::ffff:192.0.2.1]/",
      "file:///tmp/file", "urn:isbn:9780123456789",
    ] {
    assert_true(valid_uri(uri))
  }
  for
    uri in [
      "https:///missing-host", "https://example.org:port/", "https://[1200::20::15]/",
      "https://[192.0.2.1]/", "https://example.org/twice##", "https://example.org/bad%0x",
      "https://example.org/unescaped[bracket]",
    ] {
    assert_false(valid_uri(uri))
  }
  assert_true(valid_email("o'reilly+docs@example.org"))
  assert_true(valid_email("\"quoted@local\"@example.org"))
  assert_true(valid_email("service@[IPv6:2001:db8::1]"))
  assert_false(valid_email("ops@-example.org"))
  assert_false(valid_email("a..b@example.org"))
  assert_true(valid_base64("MQ==") && valid_base64("MTI="))
  assert_false(valid_base64("MR==") || valid_base64("MTJ="))
}

///|
test "GeoJSON bbox checks dimensions, containment and antimeridian ordering" {
  for
    (text, valid) in [
      (
        (
          #|{"type":"MultiPoint","coordinates":[[177,-20],[-178,-16]],"bbox":[177,-20,-178,-16]}
        ),
        true,
      ),
      (
        (
          #|{"type":"FeatureCollection","features":[{"type":"Feature","properties":null,"geometry":{"type":"Point","coordinates":[1,2,3]}}],"bbox":[0,0,0,2,2,3]}
        ),
        true,
      ),
      (
        (
          #|{"type":"GeometryCollection","geometries":[{"type":"Point","coordinates":[0,-18]}],"bbox":[177,-20,-178,-16]}
        ),
        false,
      ),
      (
        (
          #|{"type":"Point","coordinates":[1,2,3],"bbox":[0,0,2,2]}
        ),
        false,
      ),
      (
        (
          #|{"type":"Point","coordinates":[1,2],"bbox":[0,3,2,2]}
        ),
        false,
      ),
      (
        (
          #|{"type":"Point","coordinates":[180,0],"bbox":[-180,-1,-177,1]}
        ),
        true,
      ),
    ] {
    let value = @json.parse(text)
    assert_eq(geojson_cell(value) is Ok(_), valid)
  }
}

///|
test "TopoJSON bbox uses decoded delta arcs and independently bounded geometries" {
  let text =
    #|{"type":"Topology","transform":{"scale":[2,3],"translate":[100,50]},"arcs":[[[1,2],[1,2],[1,-1]]],"objects":{"river":{"type":"LineString","arcs":[-1],"bbox":[102,56,106,62]},"point":{"type":"Point","coordinates":[0,0]}},"bbox":[100,50,106,62]}
  assert_true(topojson_cell(@json.parse(text)) is Ok(_))
  for
    invalid in [
      text.replace_all(old="106,62", new="106,59"),
      text.replace_all(old="102,56,106,62", new="0,0,3,4"),
      text.replace_all(old="100,50,106,62", new="106,50,100,62"),
      text.replace_all(old="100,50,106,62", new="100,50,0,106,62,9"),
    ] {
    assert_true(topojson_cell(@json.parse(invalid)) is Err(_))
  }
}
