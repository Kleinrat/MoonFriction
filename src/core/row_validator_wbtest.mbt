///|
test "stream primary keys match batch including composite typed and missing keys" {
  let text =
    #|{"fields":[{"name":"id","type":"integer"},{"name":"group"}],"primaryKey":["id","group"]}
  let schema = parse_table_schema(text).unwrap()
  let rows = [["01", "a"], ["1", "b"], ["1", "a"], ["", "b"]]
  let header = ["id", "group"]
  let v = RowValidator::new("t", schema, header).unwrap()
  for row in rows {
    v.feed(row)
  }
  let report = v.finish()
  assert_eq(report.rows, 4)
  assert_eq(report.error_count, 2L)
  assert_eq(report.errors, schema.validate("t", header, rows).errors)
  v.feed(["bad", "c"])
  rows.push(["bad", "c"])
  assert_eq(v.finish().errors, schema.validate("t", header, rows).errors)
  assert_eq(report.errors.length(), 2)
}

///|
test "JSON stream matches batch fields and exact unique checking" {
  let text =
    #|{"fields":[{"name":"id","type":"integer","constraints":{"unique":true}},{"name":"qty","type":"number","constraints":{"unique":true,"minimum":0}},{"name":"flag","type":"boolean","constraints":{"required":true}}]}
  let schema = parse_table_schema(text).unwrap()
  let data =
    #|[{"id":9007199254740993,"qty":-0.0,"flag":true},{"id":9007199254740992,"qty":0,"flag":false},{"id":9007199254740993,"qty":-3,"extra":1}]
  let input = input_from_json("t", data).unwrap()
  let v = RowValidator::new("t", schema, ["id", "qty", "flag"]).unwrap()
  for row in input.rows {
    v.feed_json(row)
  }
  let expected = schema.validate_json("t", input).errors
  assert_eq(expected.length(), 5)
  assert_eq(v.finish().errors, expected)
  v.feed_json(Json::array([]))
  assert_eq(v.finish().errors.last().unwrap().code, "json-rows")
}

///|
test "row validator caps diagnostics and retains no unindexed row history" {
  let text =
    #|{"fields":[{"name":"n","type":"integer","constraints":{"minimum":0}}]}
  let schema = parse_table_schema(text).unwrap()
  let v = RowValidator::new("t", schema, ["n"], max_errors=2).unwrap()
  for i = 0; i < 100000; i = i + 1 {
    v.feed([(-i).to_string()])
  }
  let summary = v.finish()
  assert_eq(summary.rows, 100000)
  assert_eq(summary.error_count, 99999L)
  assert_eq(summary.errors.map(e => e.row), [2, 3])
  assert_eq(v.keys.length(), 0)
  assert_true(v.unique_seen[0] is None)
  let zero = RowValidator::new("t", schema, ["n"], max_errors=0).unwrap()
  zero.feed([])
  assert_eq(zero.finish().error_count, 1L)
  assert_true(zero.finish().errors.is_empty())
}

///|
test "row setup rejects foreign keys invalid headers and invalid limits" {
  let text =
    #|{"fields":[{"name":"id"}],"foreignKeys":[{"fields":"id","reference":{"resource":"","fields":"id"}}]}
  let schema = parse_table_schema(text).unwrap()
  match RowValidator::new("t", schema, ["wrong"], max_errors=-1) {
    Err(errors) =>
      assert_eq(errors.map(e => e.code), [
        "header", "input", "foreign-key-scope",
      ])
    Ok(_) => fail("invalid stream settings accepted")
  }
}

///|
test "large exact indexes retain distinct keys only and cap primary key samples" {
  let text =
    #|{"fields":[{"name":"id","type":"integer"},{"name":"alias","constraints":{"unique":true}}],"primaryKey":"id"}
  let schema = parse_table_schema(text).unwrap()
  let v = RowValidator::new("rows", schema, ["id", "alias"], max_errors=1).unwrap()
  for i = 0; i < 100000; i = i + 1 {
    v.feed([(i % 1000).to_string(), i.to_string()])
  }
  let result = v.finish()
  assert_eq(result.error_count, 99000L)
  assert_eq(result.errors.length(), 1)
  assert_eq(result.errors[0].row, 1001)
  assert_eq(v.keys.length(), 1000)
  assert_eq(v.unique_seen[1].unwrap().length(), 100000)
}
