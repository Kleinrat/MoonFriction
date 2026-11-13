///|
test "standalone table schema supports primary key without a package" {
  let schema_text =
    #|{"fields":[{"name":"id","type":"integer"},{"name":"title"}],"primaryKey":"id"}
  let schema = parse_table_schema(schema_text).unwrap()
  let report = validate_table_schema("books", schema, ["id", "title"], [
    ["1", "MoonBit"],
    ["1", "dup"],
  ])
  assert_false(report.valid())
  assert_eq(report.errors[0].code, "primary-key-duplicate")
  assert_eq(report.table.rows.length(), 2)
}

///|
test "standalone schema keeps self foreign keys checkable" {
  let schema_text =
    #|{"fields":[{"name":"id","type":"integer"},{"name":"parent","type":"integer"}],"primaryKey":"id","foreignKeys":[{"fields":"parent","reference":{"resource":"","fields":"id"}}]}
  let schema = parse_table_schema(schema_text).unwrap()
  let good = validate_table_schema("nodes", schema, ["id", "parent"], [
    ["1", ""],
    ["2", "1"],
  ])
  assert_true(good.valid())
  let bad = validate_table_schema("nodes", schema, ["id", "parent"], [
    ["1", ""],
    ["2", "3"],
  ])
  assert_false(bad.valid())
  assert_eq(bad.errors[0].code, "foreign-key")
}

///|
test "cross-table foreign keys are reported by single-table validation" {
  let schema_text =
    #|{"fields":[{"name":"product_id","type":"integer"}],"foreignKeys":[{"fields":"product_id","reference":{"resource":"products","fields":"id"}}]}
  let schema = parse_table_schema(schema_text).unwrap()
  let report = validate_table_schema("orders", schema, ["product_id"], [["1"]])
  assert_false(report.valid())
  assert_eq(report.errors[0].code, "foreign-key-scope")
}

///|
test "standalone schema rejects invalid key rules at parse time" {
  let case1 =
    #|{"fields":[{"name":"id","type":"integer"}],"primaryKey":"missing"}
  let case2 =
    #|{"fields":[{"name":"id","type":"integer"}],"foreignKeys":[{"fields":"missing","reference":{"resource":"other","fields":"id"}}]}
  let case3 =
    #|{"fields":[{"name":"id","type":"integer"}],"foreignKeys":[{"fields":"id","reference":{"resource":"other","fields":"id"}}],"primaryKey":null}
  for text in [case1, case2, case3] {
    assert_true(parse_table_schema(text) is Err(_))
  }
}

///|
test "package and standalone parsers share schema semantics" {
  let package_text =
    #|{"resources":[{"name":"products","path":"products.csv","schema":{"fields":[{"name":"id","type":"integer"},{"name":"title"}],"primaryKey":"id","missingValues":["","NA"]}}]}
  let schema_text =
    #|{"fields":[{"name":"id","type":"integer"},{"name":"title"}],"primaryKey":"id","missingValues":["","NA"]}
  let parsed = parse_descriptor(package_text).unwrap()
  let schema = parse_table_schema(schema_text).unwrap()
  let resource = parsed.resources[0]
  assert_eq(schema.fields[0].kind, resource.fields[0].kind)
  assert_eq(schema.fields[1].kind, resource.fields[1].kind)
  assert_eq(schema.missing_values, resource.missing_values)
  assert_eq(schema.primary_key, resource.primary_key)
  assert_true(
    validate_table_schema("t", schema, ["id", "title"], [["1", "NA"]]).valid(),
  )
}
