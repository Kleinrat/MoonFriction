///|
fn main {
  let schema_text = #|{"fields":[{"name":"id","type":"integer"},{"name":"title","type":"string"}],"primaryKey":"id"}
  let schema = @core.parse_table_schema(schema_text).unwrap()
  let good_text = #|[[1,"MoonBit"],[2,"数据"]]
  let good = match @core.input_from_json("books", good_text) {
    Ok(input) => schema.validate_json("books", input)
    Err(message) => {
      println("Input error: \{message}")
      return
    }
  }
  println("JSON array rows valid: \{good.valid()}")
  let object_text = #|[{"title":"数据","id":2}]
  let object = match @core.input_from_json("books", object_text) {
    Ok(input) => schema.validate_json("books", input)
    Err(message) => {
      println("Input error: \{message}")
      return
    }
  }
  println("JSON object rows valid: \{object.valid()}")
  let extra_text = #|[{"id":1,"title":"A","unknown":true}]
  let extra = match @core.input_from_json("books", extra_text) {
    Ok(input) => schema.validate_json("books", input)
    Err(message) => {
      println("Input error: \{message}")
      return
    }
  }
  println("Extra property code: \{extra.errors[0].code}")
}
