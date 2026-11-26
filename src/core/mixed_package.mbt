///|
/// Text chunks for one CSV or JSON table. Inline data is already in the descriptor.
#derive(Debug, @json.FromJson)
pub(all) struct TabularResourceInput {
  name : String
  parts : Array[String]
}

///|
priv struct TabularCsvSettings {
  dialect : CsvDialect
  header : Bool
  case_sensitive : Bool
}

///|
fn parse_tabular_csv_settings(
  value : Json,
) -> Result[TabularCsvSettings, String] {
  if value is Null {
    return Ok({
      dialect: default_csv_dialect(),
      header: true,
      case_sensitive: true,
    })
  }
  guard value is Object(fields) else {
    return Err("Expected a resolved CSV dialect object")
  }
  let options = Map([])
  let mut header = true
  let mut case_sensitive = true
  for key, setting in fields {
    match (key, setting) {
      ("header", True | False) => header = setting is True
      ("caseSensitiveHeader", True | False) => case_sensitive = setting is True
      ("lineTerminator", String("\n" | "\r\n")) => ()
      ("doubleQuote", True) | ("skipInitialSpace", False) => ()
      ("csvddfVersion", Number(n, ..)) if n == 1.0 || n == 1.1 || n == 1.2 => ()
      ("delimiter" | "quoteChar", _) => options[key] = setting
      _ => return Err("Unsupported CSV dialect option or value: " + key)
    }
  }
  match parse_csv_dialect(Json::object(options)) {
    Ok(dialect) => Ok({ dialect, header, case_sensitive, })
    Err(message) => Err(message)
  }
}

///|
fn tabular_format(item : Json) -> String {
  match prop(item, "format") {
    String(name) => name.to_lower()
    _ => {
      let media = json_text(prop(item, "mediatype")).unwrap_or("")
      let paths = strings(prop(item, "path")).unwrap_or([])
      if prop(item, "data") is Array(_) ||
        media == "application/json" ||
        (!paths.is_empty() && paths.all(p => p.to_lower().has_suffix(".json"))) {
        "json"
      } else {
        "csv"
      }
    }
  }
}

///|
fn csv_table_from_parts(
  name : String,
  parts : Array[String],
  names : Array[String],
  settings : TabularCsvSettings,
) -> Result[InputTable, String] {
  let rows = []
  fn matches(header : Array[String]) -> Bool {
    if settings.case_sensitive {
      header == names
    } else {
      header.map(s => s.to_lower()) == names.map(s => s.to_lower())
    }
  }
  let dialect = settings.dialect
  if parts.is_empty() {
    return Err("At least one CSV part is required")
  }
  for index, text in parts {
    if !settings.header && (text == "" || text == "\uFEFF") {
      continue
    }
    let part = match input_from_csv(name, text, dialect~) {
      Ok(table) => table
      Err(message) =>
        return Err("CSV part " + (index + 1).to_string() + ": " + message)
    }
    if settings.header && !matches(part.header) {
      return Err(
        "CSV part " +
        (index + 1).to_string() +
        ": header must match schema fields in order",
      )
    }
    if !settings.header {
      rows.push(part.header)
    }
    for row in part.rows {
      rows.push(row)
    }
  }
  Ok({ name, header: names, rows, })
}

///|
fn inline_json_table(
  name : String,
  value : Json,
  names : Array[String],
) -> Result[JsonInputTable, String] {
  match json_input_value(name, value) {
    Ok(table) if table.mode is ArrayRows && !table.rows.is_empty() => {
      guard table.rows[0] == @json.to_json(names) else {
        return Err("First inline JSON array must be the schema header")
      }
      Ok({ ..table, rows: table.rows[1:].to_owned(), })
    }
    result => result
  }
}

///|
fn json_table_from_parts(
  name : String,
  parts : Array[String],
) -> Result[JsonInputTable, String] {
  let rows = []
  for index, text in parts {
    let value = @json.parse(text, preserve_number_repr=true) catch {
      _ =>
        return Err(
          "JSON part " + (index + 1).to_string() + ": Invalid JSON row data",
        )
    }
    guard value is Array(part) else {
      return Err(
        "JSON part " + (index + 1).to_string() + ": Expected an array of rows",
      )
    }
    for row in part {
      rows.push(row)
    }
  }
  json_input_value(name, Json::array(rows))
}

///|
/// Validate CSV and JSON resources together, ensuring every constraint and
/// foreign key sees the complete logical table across all parts.
pub fn validate_mixed_package(
  descriptor : Descriptor,
  inputs : Array[TabularResourceInput],
) -> PackageReport {
  let metadata = Map([])
  if prop(descriptor.original, "resources") is Array(resources) {
    for resource in resources {
      if prop(resource, "name") is String(name) {
        metadata[name] = resource
      }
    }
  }
  validate_inputs(descriptor, inputs, input => input.name, (resource, input) => {
    let item = metadata.get(resource.name).unwrap_or(Json::null())
    let table : Table = {
      name: resource.name,
      fields: resource.fields,
      rows: [],
    }
    fn failure(code : String, message : String) -> TableReport {
      {
        table,
        errors: [{ code, resource: resource.name, row: 0, field: "", message, }],
      }
    }
    let inline = prop(item, "data")
    let names = resource.fields.map(field => field.name)
    if tabular_format(item) == "json" {
      let result = if inline is Null {
        json_table_from_parts(input.name, input.parts)
      } else if inline is String(text) {
        let value = @json.parse(text, preserve_number_repr=true) catch {
          _ => return failure("input", "Invalid inline JSON row data")
        }
        inline_json_table(input.name, value, names)
      } else {
        inline_json_table(input.name, inline, names)
      }
      match result {
        Ok(t) =>
          validate_json_table(
            resource.name,
            resource.fields,
            t,
            missing_values=resource.missing_values,
          )
        Err(message) => failure("input", message)
      }
    } else {
      let parts = match inline {
        String(text) => [text]
        Null => input.parts
        _ => return failure("csv", "Inline CSV must be a string")
      }
      let settings = match parse_tabular_csv_settings(prop(item, "dialect")) {
        Ok(settings) => settings
        Err(message) => return failure("csv", message)
      }
      match csv_table_from_parts(resource.name, parts, names, settings) {
        Ok(t) =>
          validate_table(
            resource.name,
            resource.fields,
            t.header,
            t.rows,
            missing_values=resource.missing_values,
          )
        Err(message) =>
          failure(
            if message.contains(": header must match schema") {
              "header"
            } else {
              "csv"
            },
            message,
          )
      }
    }
  })
}
