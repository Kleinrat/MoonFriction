///|
#derive(@json.FromJson)
priv struct Bundle {
  descriptor : Json
  assets : String
  loans : String
}

///|
fn failure(message : String) -> String {
  ({ "ok": false, "error": message } : Json).stringify()
}

///|
pub fn check_bundle(text : String) -> String {
  let b : Bundle = @json.from_json(@json.parse(text)) catch {
    _ => return failure("Expected descriptor, assets CSV and loans CSV")
  }
  let d = match @core.parse_descriptor(b.descriptor.stringify()) {
    Ok(d) => d
    Err(errors) =>
      return ({ "ok": false, "errors": @json.to_json(errors) } : Json).stringify()
  }
  let assets = match @core.input_from_csv("assets", b.assets) {
    Ok(t) => t
    Err(m) => return failure(m)
  }
  let loans = match @core.input_from_csv("loans", b.loans) {
    Ok(t) => t
    Err(m) => return failure(m)
  }
  let report = @core.validate_package(d, [assets, loans])
  ({ "ok": report.valid(), "errors": @json.to_json(report.errors) } : Json).stringify()
}

///|
fn resource(name : String, csv : String) -> Result[Json, String] {
  let table = match @core.input_from_csv(name, csv) {
    Ok(t) => t
    Err(m) => return Err(m)
  }
  let inferred = @core.infer_table_schema(table.header, table.rows)
  let fields = inferred.schema.fields.map(f => {
    let kind = match f.kind {
      Text => "string"
      Integer => "integer"
      Number => "number"
      Boolean => "boolean"
    }
    ({ "name": f.name, "type": kind } : Json)
  })
  Ok(
    (
      {
        "name": name,
        "path": name + ".csv",
        "format": "csv",
        "schema": { "fields": @json.to_json(fields) },
        "x-inference": {
          "sampled_rows": inferred.sampled_rows,
          "total_rows": inferred.total_rows,
          "hints": @json.to_json(inferred.hints),
        },
      } : Json),
  )
}

///|
pub fn draft_bundle(text : String) -> String {
  let b : Bundle = @json.from_json(@json.parse(text)) catch {
    _ => return failure("Expected CSV texts")
  }
  let a = match resource("assets", b.assets) {
    Ok(v) => v
    Err(m) => return failure(m)
  }
  let l = match resource("loans", b.loans) {
    Ok(v) => v
    Err(m) => return failure(m)
  }
  (
    {
      "ok": true,
      "descriptor": { "name": "asset-loans", "resources": [a, l] },
      "warning": "Draft only: review types, required fields, keys and quantity constraints before use",
    } : Json).stringify()
}

///|
pub fn check_request(text : String) -> String {
  let schema = @core.parse_table_schema(
    (
      #|{"fields":[{"name":"loan_id","type":"integer","constraints":{"required":true}},{"name":"asset_id","type":"string","constraints":{"required":true}},{"name":"quantity","type":"integer","constraints":{"minimum":1,"required":true}}]}
    ),
  ).unwrap()
  let input = match @core.input_from_json("request", text) {
    Ok(v) => v
    Err(m) =>
      return (
        {
          "ok": false,
          "field_validation": "failed",
          "business_validation": "not-run",
          "scope": "request-fields-only",
          "notice": "只检查申请字段；未检查物资存在、重复借用或可借库存。",
          "error": m,
        } : Json).stringify()
  }
  let report = schema.validate_json("request", input)
  (
    {
      "ok": report.valid(),
      "field_validation": if report.valid() {
        "passed"
      } else {
        "failed"
      },
      "business_validation": "not-run",
      "notice": "只检查申请字段；未检查物资存在、重复借用或可借库存。",
      "scope": "request-fields-only; does not check asset existence, duplicate loans or stock availability",
      "errors": @json.to_json(report.errors),
    } : Json).stringify()
}
