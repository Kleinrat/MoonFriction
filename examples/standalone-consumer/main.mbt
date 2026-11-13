///|
fn main {
  let schema_text = #|{"fields":[{"name":"id","type":"integer"},{"name":"title","type":"string"}],"primaryKey":"id"}
  let schema = match @core.parse_table_schema(schema_text) {
    Ok(schema) => schema
    Err(errors) => {
      println("Schema errors: \{errors.length()}")
      return
    }
  }
  let report = @core.validate_table_schema(
    "books",
    schema,
    ["id", "title"],
    [["1", "MoonBit"], ["1", "duplicate"]],
  )
  println("Standalone valid: \{report.valid()}")
  println("First code: \{report.errors[0].code}")
}
