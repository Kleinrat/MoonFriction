///|
fn fixture_descriptor() -> String {
  (
    #|{"name":"shop","resources":[{"name":"products","path":"products.csv","schema":{"fields":[{"name":"id","type":"integer"},{"name":"title"}],"primaryKey":"id"}},{"name":"orders","path":"orders.csv","schema":{"fields":[{"name":"product_id","type":"integer"}],"foreignKeys":[{"fields":"product_id","reference":{"resource":"products","fields":"id"}}]}}]}
  )
}

///|
test "two-resource descriptor preserves original metadata and resolves keys" {
  let d = parse_descriptor(fixture_descriptor()).unwrap()
  assert_eq(d.resources.length(), 2)
  assert_eq(d.resources[0].fields[1].kind, Text)
  assert_eq(d.resources[0].missing_values, [""])
  assert_eq(d.resources[1].foreign_keys[0].resource, "products")
  assert_eq(prop(d.original, "name"), Json::string("shop"))
}

///|
test "malformed JSON and descriptor root are rejected" {
  assert_true(parse_descriptor("{") is Err(_))
  for text in ["null", "[]", "{}", "{\"resources\":null}"] {
    assert_true(parse_descriptor(text) is Err(_))
  }
}

///|
test "safe path policy rejects traversal and nonlocal sources" {
  for
    p in [
      "../data.csv", "/data.csv", "https://example.com/a.csv", "x\\y.csv", "a/../b.csv",
      "a//b.csv", "./a.csv", "",
    ] {
    assert_false(safe_resource_path(p))
  }
  assert_true(safe_resource_path("data/orders.csv"))
}

///|
test "unsupported features never silently pass" {
  let good = fixture_descriptor()
  for
    (before, after) in [
      ("\"integer\"", "\"date\""),
      ("\"schema\":{", "\"encoding\":\"latin1\",\"schema\":{"),
      ("\"schema\":{", "\"dialect\":{},\"schema\":{"),
      ("\"schema\":{", "\"profile\":\"custom\",\"schema\":{"),
      (
        "\"type\":\"integer\"", "\"type\":\"integer\",\"constraints\":{\"enum\":[1]}",
      ),
    ] {
    let bad = good.replaced(before, after)
    assert_true(parse_descriptor(bad) is Err(_))
  }
}

///|
test "missing marker array and field boolean constraints are typed" {
  assert_true(
    parse_descriptor(
      fixture_descriptor().replaced(
        "\"primaryKey\":\"id\"", "\"primaryKey\":\"id\",\"missingValues\":[1]",
      ),
    )
    is Err(_),
  )
  assert_true(
    parse_descriptor(
      fixture_descriptor().replaced(
        "\"type\":\"integer\"", "\"type\":\"integer\",\"constraints\":{\"required\":\"yes\"}",
      ),
    )
    is Err(_),
  )
}

///|
test "invalid key fields and forms are rejected while loading" {
  let good = fixture_descriptor()
  for
    (before, after) in [
      ("\"primaryKey\":\"id\"", "\"primaryKey\":\"unknown\""),
      ("\"primaryKey\":\"id\"", "\"primaryKey\":[]"),
      ("\"resource\":\"products\"", "\"resource\":\"unknown\""),
      ("\"fields\":\"product_id\"", "\"fields\":[\"product_id\"]"),
      ("\"fields\":\"product_id\"", "\"fields\":\"unknown\""),
    ] {
    assert_true(parse_descriptor(good.replaced(before, after)) is Err(_))
  }
}

///|
test "duplicate resource names are rejected" {
  assert_true(
    parse_descriptor(
      fixture_descriptor().replaced(
        "\"name\":\"orders\"", "\"name\":\"products\"",
      ),
    )
    is Err(_),
  )
}

///|
fn String::replaced(
  self : String,
  old : StringView,
  new : StringView,
) -> String {
  self.replace(old~, new~)
}

///|
test "whole package validates typed joins and preserves caller data" {
  let d = parse_descriptor(fixture_descriptor()).unwrap()
  let inputs : Array[InputTable] = [
    { name: "products", header: ["id", "title"], rows: [["1", "书"]], },
    { name: "orders", header: ["product_id"], rows: [["01"]], },
  ]
  assert_true(validate_package(d, inputs).valid())
  assert_eq(inputs[1].rows[0][0], "01")
  let bad = [inputs[0], { ..inputs[1], rows: [["2"]], }]
  assert_eq(validate_package(d, bad).errors[0].code, "foreign-key")
}

///|
test "a missing resource cannot masquerade as a valid empty table" {
  let d = parse_descriptor(fixture_descriptor()).unwrap()
  assert_false(validate_package(d, []).valid())
}

///|
test "explicit null is not treated as an omitted descriptor property" {
  let good = fixture_descriptor()
  for
    (before, after) in [
      ("\"type\":\"integer\"", "\"type\":null"),
      (
        "\"type\":\"integer\"", "\"type\":\"integer\",\"constraints\":{\"required\":null}",
      ),
      ("\"primaryKey\":\"id\"", "\"primaryKey\":null"),
      ("\"primaryKey\":\"id\"", "\"primaryKey\":\"id\",\"missingValues\":null"),
      ("\"schema\":{", "\"encoding\":null,\"schema\":{"),
    ] {
    assert_true(parse_descriptor(good.replaced(before, after)) is Err(_))
  }
}

///|
test "empty packages are rejected before validation" {
  assert_true(parse_descriptor("{\"resources\":[]}") is Err(_))
  assert_false(
    validate_package({ original: Json::null(), resources: [], }, []).valid(),
  )
}

///|
test "an unrelated table error does not hide an otherwise checkable foreign key error" {
  let d = parse_descriptor(fixture_descriptor()).unwrap()
  let extra : Resource = {
    name: "meta",
    path: "meta.csv",
    fields: [{ ..field("k", Text), required: true, }],
    missing_values: [""],
    primary_key: [],
    foreign_keys: [],
  }
  let descriptor = { ..d, resources: [d.resources[0], d.resources[1], extra], }
  let report = validate_package(descriptor, [
    { name: "products", header: ["id", "title"], rows: [["1", "Book"]], },
    { name: "orders", header: ["product_id"], rows: [["2"]], },
    { name: "meta", header: ["k"], rows: [[""]], },
  ])
  assert_true(report.errors.any(e => e.code == "required"))
  assert_true(report.errors.any(e => e.code == "foreign-key"))
}
