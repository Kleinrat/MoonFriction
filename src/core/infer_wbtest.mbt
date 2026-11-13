///|
test "inference preserves leading-zero identifiers as text" {
  let rows = [["001", "1.5", "true"], ["002", "2", "false"]]
  let inferred = infer_table_schema(["id", "price", "active"], rows)
  assert_eq(inferred.schema.fields[0].kind, Text)
  assert_eq(inferred.schema.fields[1].kind, Number)
  assert_eq(inferred.schema.fields[2].kind, Boolean)
  assert_true(inferred.hints.any(h => h.message.contains("前导零")))
}

///|
test "inference falls back to text on mixed columns" {
  let rows = [["1", "true"], ["x", "1"], ["2", "false"]]
  let inferred = infer_table_schema(["mixed", "flag_or_number"], rows)
  assert_eq(inferred.schema.fields[0].kind, Text)
  assert_eq(inferred.schema.fields[1].kind, Text)
  assert_true(inferred.hints.any(h => h.field == "mixed"))
  assert_true(inferred.hints.any(h => h.field == "flag_or_number"))
}

///|
test "inference keeps only 0/1 as integer with an ambiguity hint" {
  let inferred = infer_table_schema(["flag"], [["0"], ["1"]])
  assert_eq(inferred.schema.fields[0].kind, Integer)
  assert_true(inferred.hints.any(h => h.message.contains("0/1")))
}

///|
test "empty and header-only samples fall back to string without guessing keys" {
  let inferred = infer_table_schema(["id", "note"], [])
  assert_eq(inferred.schema.fields.map(f => f.kind), [Text, Text])
  assert_eq(inferred.schema.primary_key, [])
  assert_eq(inferred.schema.foreign_keys.length(), 0)
  assert_true(inferred.hints.any(h => h.message.contains("样本为空")))
}

///|
test "inference reports sampling range and skips malformed sample rows" {
  let rows = [["1", "a"], ["2", "b"], ["3"]]
  let inferred = infer_table_schema(["id", "name"], rows, sample_limit=2)
  assert_eq(inferred.sampled_rows, 2)
  assert_eq(inferred.total_rows, 3)
  assert_true(inferred.hints.any(h => h.message.contains("仅采样前 2 条")))
  let inferred2 = infer_table_schema(["id", "name"], [["1", "a"], ["2"]])
  assert_true(
    inferred2.hints.any(h => h.message.contains("列数与表头不一致")),
  )
}
