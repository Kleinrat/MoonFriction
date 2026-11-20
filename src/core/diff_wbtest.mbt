///|
test "bound direction reverses under schema exchange" {
  let a = parse_table_schema(
    (
      #|{"fields":[{"name":"qty","type":"integer","constraints":{"maximum":20}},{"name":"s","constraints":{"minLength":2,"maxLength":8}}]}
    ),
  ).unwrap()
  let b = parse_table_schema(
    (
      #|{"fields":[{"name":"qty","type":"integer","constraints":{"minimum":2,"maximum":15,"required":true,"unique":true}},{"name":"s","constraints":{"minLength":1,"maxLength":5}}]}
    ),
  ).unwrap()
  let changes = diff_table_schemas(a, b)
  assert_eq(changes.map(c => c.rule), [
    "required", "unique", "minimum", "maximum", "minLength", "maxLength",
  ])
  assert_eq(changes.map(c => c.impact), [
    "tightened", "tightened", "tightened", "tightened", "relaxed", "tightened",
  ])
  for i, c in diff_table_schemas(b, a) {
    assert_true(c.impact != changes[i].impact)
    assert_eq(c.before, changes[i].after)
    assert_eq(c.after, changes[i].before)
  }
}

///|
test "enum changes split directions and ignore ordering and duplicates" {
  let schema = fn(values) {
    parse_table_schema(
      "{\"fields\":[{\"name\":\"id\",\"type\":\"integer\",\"constraints\":{\"enum\":" +
      values +
      "}}]}",
    ).unwrap()
  }
  let a = schema("[1,9007199254740993,1]")
  assert_true(diff_table_schemas(a, schema("[9007199254740993,1]")).is_empty())
  let changes = diff_table_schemas(a, schema("[2,1]"))
  assert_eq(changes.map(c => c.impact), ["tightened", "relaxed"])
  assert_eq(changes[0].members.unwrap()[0].stringify(), "9007199254740993")
  assert_eq(changes[1].members.unwrap()[0].stringify(), "2")
}

///|
test "structural changes request review without inferring renames" {
  let a = parse_table_schema(
    (
      #|{"fields":[{"name":"id"},{"name":"n"},{"name":"old"}],"primaryKey":"id"}
    ),
  ).unwrap()
  let b = parse_table_schema(
    (
      #|{"fields":[{"name":"n","type":"integer"},{"name":"id"},{"name":"new"}],"missingValues":[],"foreignKeys":[{"fields":"id","reference":{"resource":"parent","fields":"id"}}]}
    ),
  ).unwrap()
  let changes = diff_table_schemas(a, b)
  assert_true(changes.all(c => c.impact == "review"))
  assert_eq(changes.map(c => c.rule), [
    "type", "field", "field", "fieldOrder", "primaryKey", "missingValues", "foreignKeys",
  ])
  assert_true(diff_table_schemas(b, b).is_empty())
}

///|
test "diff cautions on rounded integer bounds before checking equality" {
  fn schema(rule : String, n : String) -> TableSchema {
    parse_table_schema(
      "{\"fields\":[{\"name\":\"n\",\"type\":\"integer\",\"constraints\":{\"" +
      rule +
      "\":" +
      n +
      "}}]}",
    ).unwrap()
  }
  for rule in ["minimum", "maximum"] {
    for
      (x, y) in [
        ("9007199254740992", "9007199254740993"),
        ("-9007199254740992", "-9007199254740993"),
        ("9223372036854775806", "9223372036854775807"),
        ("-9223372036854775807", "-9223372036854775808"),
      ] {
      for (old, current) in [(x, y), (y, x), (x, x)] {
        let changes = diff_table_schemas(
          schema(rule, old),
          schema(rule, current),
        )
        assert_eq(changes.length(), 1)
        assert_eq(changes[0].impact, "review")
        assert_eq(changes[0].rule, rule)
        assert_eq(
          changes[0].before.stringify(),
          "{\"precision\":\"outside-safe-integer-range\"}",
        )
      }
    }
    let safe = schema(rule, "9007199254740991")
    assert_true(diff_table_schemas(safe, safe).is_empty())
    let crossing = diff_table_schemas(safe, schema(rule, "9007199254740992"))[0]
    assert_eq(crossing.before.stringify(), "9007199254740991")
    assert_eq(crossing.impact, "review")
  }
}
