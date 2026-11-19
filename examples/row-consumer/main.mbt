///|
fn main {
  let descriptor = #|{"fields":[{"name":"id","type":"integer","constraints":{"minimum":0}}]}
  let schema = @core.parse_table_schema(descriptor).unwrap()
  let validator = @core.RowValidator::new("events", schema, ["id"], max_errors=2).unwrap()
  for i = 0; i < 100000; i = i + 1 {
    validator.feed([i.to_string()])
  }
  validator.feed(["-1"])
  let report = validator.finish()
  println("Rows: \{report.rows}, errors: \{report.error_count}")
  for error in report.errors {
    println("\{error.resource} \{error.row} \{error.field} \{error.code}")
  }
}
