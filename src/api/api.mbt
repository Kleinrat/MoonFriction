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
    let parsed = match d.csv_dialect(r.name) {
      Ok(dialect) => @core.input_from_csv(r.name, r.csv, dialect~)
      // Package validation reports unexpected input names.
      Err(_) => @core.input_from_csv(r.name, r.csv)
    }
    match parsed {
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
  package_result(@core.validate_package(d, tables))
}

///|
fn package_result(report : @core.PackageReport) -> String {
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

///|
#derive(@json.FromJson)
priv struct JsonBatch {
  name : String
  text : String
}

///|
pub fn validate_json_files(descriptor : String, batches : String) -> String {
  let d = match @core.parse_descriptor(descriptor) {
    Err(errors) =>
      return ({ "ok": false, "errors": @json.to_json(errors) } : Json).stringify()
    Ok(d) => d
  }
  let files : Array[JsonBatch] = @json.from_json(@json.parse(batches)) catch {
    _ =>
      return (
        {
          "ok": false,
          "errors": [
            { "code": "input", "message": "Expected named JSON batches" },
          ],
        } : Json).stringify()
  }
  let tables = []
  for file in files {
    match @core.input_from_json(file.name, file.text) {
      Ok(t) => tables.push(t)
      Err(message) =>
        return (
          {
            "ok": false,
            "errors": [
              { "code": "input", "resource": file.name, "message": message },
            ],
          } : Json).stringify()
    }
  }
  package_result(@core.validate_json_package(d, tables))
}

///|
#derive(@json.FromJson)
priv struct InferInput {
  package_name : String
  resource_name : String
  path : String
  csv : String
  sample_limit : Int32
}

///|
fn field_type_json_name(kind : @core.FieldType) -> String {
  match kind {
    Text => "string"
    Integer => "integer"
    Number => "number"
    Boolean => "boolean"
  }
}

///|
/// Infer a draft descriptor from CSV text and return it as JSON.
///
/// This is a thin boundary: all inference happens in MoonBit core. The caller
/// receives a descriptor plus explicit sampling/ambiguity hints. The input CSV
/// is never modified, and this function does not write files.
pub fn infer_json(text : String) -> String {
  let input : InferInput = @json.from_json(@json.parse(text)) catch {
    _ =>
      return (
        {
          "ok": false,
          "error": "Expected package_name, resource_name, path, csv and sample_limit",
        } : Json).stringify()
  }
  let table = match @core.input_from_csv(input.resource_name, input.csv) {
    Ok(table) => table
    Err(message) =>
      return (
        {
          "ok": false,
          "errors": [
            {
              "code": "csv",
              "resource": input.resource_name,
              "message": message,
            },
          ],
        } : Json).stringify()
  }
  let inference = @core.infer_table_schema(
    table.header,
    table.rows,
    sample_limit=input.sample_limit,
  )
  let field_jsons = inference.schema.fields.map(f => {
    ({ "name": f.name, "type": field_type_json_name(f.kind) } : Json)
  })
  let schema_json : Json = ({ "fields": @json.to_json(field_jsons) } : Json)
  let descriptor : Json = (
    {
      "name": input.package_name,
      "resources": [
        {
          "name": input.resource_name,
          "path": input.path,
          "format": "csv",
          "schema": schema_json,
        },
      ],
    } : Json)
  match @core.parse_descriptor(descriptor.stringify()) {
    Err(errors) =>
      (
        {
          "ok": false,
          "errors": @json.to_json(errors),
          "hints": @json.to_json(inference.hints),
        } : Json).stringify()
    Ok(_) =>
      (
        {
          "ok": true,
          "descriptor": descriptor,
          "hints": @json.to_json(inference.hints),
          "sampled_rows": inference.sampled_rows,
          "total_rows": inference.total_rows,
        } : Json).stringify()
  }
}

///|
pub fn schema_diff_json(old_text : String, new_text : String) -> String {
  let schemas = []
  for (side, text) in [("old", old_text), ("new", new_text)] {
    match @core.parse_table_schema(text) {
      Err(errors) =>
        return (
          { "ok": false, "schema": side, "errors": @json.to_json(errors) } :
          Json).stringify()
      Ok(schema) => schemas.push(schema)
    }
  }
  (
    {
      "ok": true,
      "changes": @json.to_json(@core.diff_table_schemas(schemas[0], schemas[1])),
    } : Json).stringify()
}
