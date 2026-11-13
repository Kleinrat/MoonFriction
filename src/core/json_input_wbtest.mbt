///|
fn json_fields() -> Array[Field] {
  [
    field("id", Integer),
    field("title", Text),
    field("qty", Number),
    field("active", Boolean),
  ]
}

///|
test "JSON array rows and CSV rows produce the same logical table" {
  let fields = json_fields()
  let csv = validate_table("t", fields, ["id", "title", "qty", "active"], [
    ["1", "A", "1.5", "true"],
    ["2", "B", "2", "false"],
  ])
  let rows_text =
    #|[[1,"A",1.5,true],[2,"B",2,false]]
  let json_input = input_from_json("t", rows_text).unwrap()
  let json = validate_json_table("t", fields, json_input)
  assert_true(csv.valid())
  assert_true(json.valid())
  assert_eq(json.table.rows, csv.table.rows)
}

///|
test "JSON null and missing properties become Missing like CSV empty cells" {
  let fields = [
    { ..field("id", Integer), required: true, },
    field("note", Text),
  ]
  let csv = validate_table("t", fields, ["id", "note"], [["", ""]])
  let array_text =
    #|[[null,""]]
  let object_text =
    #|[{"note":""}]
  let array = validate_json_table(
    "t",
    fields,
    input_from_json("t", array_text).unwrap(),
  )
  let object = validate_json_table(
    "t",
    fields,
    input_from_json("t", object_text).unwrap(),
  )
  let csv_codes = csv.errors.map(e => e.code)
  assert_eq(array.errors.map(e => e.code), csv_codes)
  assert_eq(object.errors.map(e => e.code), csv_codes)
  assert_eq(csv_codes, ["required"])
}

///|
test "JSON object field order follows the schema and extra properties fail" {
  let fields = [field("id", Integer), field("title", Text)]
  let ordered_text =
    #|[{"title":"A","id":1}]
  let ordered = input_from_json("t", ordered_text).unwrap()
  let report = validate_json_table("t", fields, ordered)
  assert_true(report.valid())
  assert_eq(report.table.rows, [[IntegerValue(1), TextValue("A")]])
  let extra_text =
    #|[{"id":1,"title":"A","extra":true}]
  let extra = input_from_json("t", extra_text).unwrap()
  let bad = validate_json_table("t", fields, extra)
  assert_false(bad.valid())
  assert_eq(bad.errors[0].code, "extra-property")
  assert_eq(bad.errors[0].field, "extra")
}

///|
test "JSON values are not silently stringified into other field kinds" {
  let number_text =
    #|[[1]]
  let text_report = validate_json_table(
    "t",
    [field("v", Text)],
    input_from_json("t", number_text).unwrap(),
  )
  assert_eq(text_report.errors[0].code, "type")
  let bool_report = validate_json_table(
    "t",
    [field("v", Boolean)],
    input_from_json("t", number_text).unwrap(),
  )
  assert_eq(bool_report.errors[0].code, "type")
  let fraction_text =
    #|[[1.5]]
  let integer_report = validate_json_table(
    "t",
    [field("v", Integer)],
    input_from_json("t", fraction_text).unwrap(),
  )
  assert_eq(integer_report.errors[0].code, "type")
}

///|
test "JSON integers keep exact 64-bit values and reject ambiguous fractions" {
  let exact_text =
    #|[[9007199254740993]]
  let exact = validate_json_table(
    "t",
    [field("n", Integer)],
    input_from_json("t", exact_text).unwrap(),
  )
  assert_true(exact.valid())
  assert_eq(exact.table.rows, [[IntegerValue(9007199254740993L)]])
  let fraction_text =
    #|[[9007199254740992.5]]
  let fraction = validate_json_table(
    "t",
    [field("n", Integer)],
    input_from_json("t", fraction_text).unwrap(),
  )
  assert_eq(fraction.errors[0].code, "type")
}

///|
test "JSON strings use the same strict lexical rules as CSV" {
  let fields = [field("n", Number), field("b", Boolean)]
  let good_text =
    #|[["1.5","TRUE"]]
  let good = validate_json_table(
    "t",
    fields,
    input_from_json("t", good_text).unwrap(),
  )
  assert_true(good.valid())
  assert_eq(good.table.rows, [[NumberValue(1.5), BooleanValue(true)]])
  let bad_text =
    #|[["1,000","yes"]]
  let bad = validate_json_table(
    "t",
    fields,
    input_from_json("t", bad_text).unwrap(),
  )
  assert_eq(bad.errors.length(), 2)
  assert_eq(bad.errors[0].code, "type")
  assert_eq(bad.errors[1].code, "type")
}

///|
test "JSON row shape errors are explicit" {
  let object_text =
    #|{"rows":[]}
  assert_true(input_from_json("t", object_text) is Err(_))
  let scalar_text =
    #|[1,2]
  assert_true(input_from_json("t", scalar_text) is Err(_))
  let mixed_text =
    #|[[1],{"id":1}]
  assert_true(input_from_json("t", mixed_text) is Err(_))
  let width_text =
    #|[[1,2]]
  let width = validate_json_table(
    "t",
    [field("id", Integer)],
    input_from_json("t", width_text).unwrap(),
  )
  assert_eq(width.errors[0].code, "row-width")
}

///|
test "JSON single-table validation reuses primary key and scope rules" {
  let schema_text =
    #|{"fields":[{"name":"id","type":"integer"},{"name":"parent","type":"integer"}],"primaryKey":"id","foreignKeys":[{"fields":"parent","reference":{"resource":"","fields":"id"}}]}
  let schema = parse_table_schema(schema_text).unwrap()
  let good_text =
    #|[[1,null],[2,1]]
  let good = schema.validate_json(
    "nodes",
    input_from_json("t", good_text).unwrap(),
  )
  assert_true(good.valid())
  let dup_text =
    #|[[1,null],[1,2]]
  let dup = schema.validate_json(
    "nodes",
    input_from_json("t", dup_text).unwrap(),
  )
  assert_eq(dup.errors[0].code, "primary-key-duplicate")
  let external_text =
    #|{"fields":[{"name":"pid","type":"integer"}],"foreignKeys":[{"fields":"pid","reference":{"resource":"products","fields":"id"}}]}
  let external = parse_table_schema(external_text).unwrap()
  let rows_text =
    #|[[1]]
  let scoped = external.validate_json(
    "orders",
    input_from_json("t", rows_text).unwrap(),
  )
  assert_eq(scoped.errors[0].code, "foreign-key-scope")
}
