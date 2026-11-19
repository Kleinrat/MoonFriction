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
  let description = #|{"resources":[{"name":"products","path":"products.csv","schema":{"fields":[{"name":"id","type":"integer"}],"primaryKey":"id"}},{"name":"orders","path":"orders.csv","schema":{"fields":[{"name":"product","type":"integer"}],"foreignKeys":[{"fields":"product","reference":{"resource":"products","fields":"id"}}]}}]}
  let descriptor = @core.parse_descriptor(description).unwrap()
  let products = @core.input_from_json("products", "[[1]]").unwrap()
  let orders = @core.input_from_json("orders", "[[42]]").unwrap()
  let package_report = @core.validate_json_package(descriptor, [products, orders])
  println("Missing product: \{package_report.errors[0].code}")
}
