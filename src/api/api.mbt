///|
#derive(@json.FromJson)
priv struct CsvInput {
  name : String
  csv : String
}

///|
#derive(@json.FromJson)
priv struct BundleInput {
  descriptor : Json
  resources : Array[CsvInput]
}

///|
pub fn inspect_json(text : String) -> String {
  match @core.parse_descriptor(text) {
    Err(errors) =>
      ({ "ok": false, "errors": @json.to_json(errors) } : Json).stringify()
    Ok(d) =>
      (
        {
          "ok": true,
          "resources": @json.to_json(
            d.resources.map(r => ({ "name": r.name, "path": r.path } : Json)),
          ),
        } : Json).stringify()
  }
}

///|
pub fn validate_json(text : String) -> String {
  let input : BundleInput = @json.from_json(@json.parse(text)) catch {
    _ =>
      return (
        {
          "ok": false,
          "errors": [
            {
              "code": "input",
              "message": "Expected descriptor and resource CSV strings",
            },
          ],
        } : Json).stringify()
  }
  let d = match @core.parse_descriptor(input.descriptor.stringify()) {
    Err(errors) =>
      return ({ "ok": false, "errors": @json.to_json(errors) } : Json).stringify()
    Ok(d) => d
  }
  let tables : Array[@core.InputTable] = []
  for r in input.resources {
    match @core.input_from_csv(r.name, r.csv) {
      Ok(t) => tables.push(t)
      Err(message) =>
        return (
          {
            "ok": false,
            "errors": [
              { "code": "csv", "resource": r.name, "message": message },
            ],
          } : Json).stringify()
    }
  }
  let report = @core.validate_package(d, tables)
  (
    {
      "ok": report.valid(),
      "errors": @json.to_json(report.errors),
      "resources": @json.to_json(
        report.tables.map(t => {
          ({ "name": t.name, "rows": t.rows.length() } : Json)
        }),
      ),
    } : Json).stringify()
}
