///|
#derive(Debug)
pub(all) struct ForeignKey {
  fields : Array[String]
  resource : String
  reference_fields : Array[String]
}

///|
#derive(Debug)
pub(all) struct Resource {
  name : String
  path : String
  fields : Array[Field]
  missing_values : Array[String]
  primary_key : Array[String]
  foreign_keys : Array[ForeignKey]
}

///|
#derive(Debug)
pub(all) struct Descriptor {
  original : Json
  resources : Array[Resource]
}

///|
fn prop(value : Json, key : String) -> Json {
  match value {
    Object(m) => m.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn strings(value : Json) -> Array[String]? {
  match value {
    String(s) => Some([s])
    Array(items) => {
      let result : Array[String] = []
      for item in items {
        match item {
          String(s) => result.push(s)
          _ => return None
        }
      }
      Some(result)
    }
    _ => None
  }
}

///|
fn valid_resource_name(name : String) -> Bool {
  if name == "" {
    return false
  }
  name
  .iter()
  .all(c => {
    (c >= 'a' && c <= 'z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '-' ||
    c == '.'
  })
}

///|
/// Only portable local relative paths. The I/O adapter must also enforce realpath containment.
pub fn safe_resource_path(path : String) -> Bool {
  path != "" &&
  !path.has_prefix("/") &&
  !path.contains("\\") &&
  !path.contains(":") &&
  !path.contains("\u0000") &&
  path.split("/").all(part => part != ".." && part != "" && part != ".")
}

///|
fn flag(
  value : Json,
  key : String,
  resource : String,
  name : String,
  errors : Array[Diagnostic],
) -> Bool {
  match prop(value, key) {
    Null => false
    True => true
    False => false
    _ => {
      errors.push(
        issue("descriptor", resource, 0, name, key + " must be boolean"),
      )
      false
    }
  }
}

///|
fn bound(
  value : Json,
  key : String,
  resource : String,
  name : String,
  errors : Array[Diagnostic],
) -> Double? {
  match prop(value, key) {
    Null => None
    Number(n, ..) =>
      if n.is_finite() {
        Some(n)
      } else {
        errors.push(
          issue("descriptor", resource, 0, name, key + " must be finite"),
        )
        None
      }
    _ => {
      errors.push(
        issue("descriptor", resource, 0, name, key + " must be numeric"),
      )
      None
    }
  }
}

///|
fn length_bound(
  value : Json,
  key : String,
  resource : String,
  name : String,
  errors : Array[Diagnostic],
) -> Int32? {
  match bound(value, key, resource, name, errors) {
    None => None
    Some(n) =>
      if n < 0.0 || n > 2147483647.0 || n != n.trunc() {
        errors.push(
          issue(
            "descriptor",
            resource,
            0,
            name,
            key + " must be a nonnegative 32-bit integer",
          ),
        )
        None
      } else {
        Some(n.to_int())
      }
  }
}

///|
/// Parse the documented local tabular subset, preserving original metadata for export.
pub fn parse_descriptor(text : String) -> Result[Descriptor, Array[Diagnostic]] {
  let original = @json.parse(text, preserve_number_repr=true) catch {
    _ => return Err([issue("json", "", 0, "", "Invalid JSON descriptor")])
  }
  parse_tabular_descriptor_value(original, mixed=false)
}

///|
/// Parse CSV/JSON tabular rules over a general v1 manifest.
pub fn parse_mixed_descriptor(
  text : String,
) -> Result[Descriptor, Array[Diagnostic]] {
  parse_profiled_mixed_descriptor(text, Map([]), Map([]))
}

///|
/// Validate profile schemas against the original manifest before evaluating
/// Table Schemas and dialects supplied by the host under their locator keys.
pub fn parse_profiled_mixed_descriptor(
  text : String,
  profile_schemas : Map[String, Json],
  resolved_documents : Map[String, Json],
) -> Result[Descriptor, Array[Diagnostic]] {
  match parse_data_package(text) {
    Err(errors) => Err(errors)
    Ok(descriptor) => {
      let errors = descriptor.validate_profiles(profile_schemas)
      if !errors.is_empty() {
        return Err(errors)
      }
      for resource in descriptor.resources {
        guard resource.metadata is Object(fields) else { continue }
        for field in ["schema", "dialect"] {
          if fields.get(field) is Some(String(locator)) &&
            resolved_documents.get(locator) is Some(Object(_) as document) {
            fields[field] = document
          }
        }
      }
      parse_tabular_descriptor_value(descriptor.original, mixed=true)
    }
  }
}

///|
fn parse_tabular_descriptor_value(
  original : Json,
  mixed~ : Bool,
) -> Result[Descriptor, Array[Diagnostic]] {
  let errors : Array[Diagnostic] = []
  let resources : Array[Resource] = []
  let items = match prop(original, "resources") {
    Array(a) => a
    _ =>
      return Err([issue("descriptor", "", 0, "", "resources must be an array")])
  }
  reject_nulls(original, ["name", "profile"], "", "", errors)
  if items.is_empty() {
    errors.push(
      issue(
        "descriptor", "", 0, "", "resources must contain at least one resource",
      ),
    )
  }
  let profile = prop(original, "profile")
  if !mixed &&
    profile != Json::null() &&
    profile != Json::string("data-package") &&
    profile != Json::string("tabular-data-package") {
    errors.push(
      issue(
        "unsupported", "", 0, "", "Only data-package and tabular-data-package profiles are supported",
      ),
    )
  }
  for item in items {
    let name = json_text(prop(item, "name")).unwrap_or("")
    reject_nulls(
      item,
      [
        "name", "path", "profile", "format", "encoding", "schema", "dialect", "compression",
        "data",
      ],
      name,
      "",
      errors,
    )
    if !valid_resource_name(name) || resources.any(r => r.name == name) {
      errors.push(
        issue(
          "descriptor", name, 0, "", "Resource names must be lowercase portable identifiers and unique",
        ),
      )
    }
    let path = json_text(prop(item, "path")).unwrap_or("")
    if !mixed &&
      (!safe_resource_path(path) || prop(item, "data") != Json::null()) {
      errors.push(
        issue(
          "unsupported", name, 0, "", "Only one safe local resource path is supported, without inline data",
        ),
      )
    }
    let dialect = prop(item, "dialect")
    let dialect_check = if mixed {
      parse_tabular_csv_settings(dialect).map(settings => settings.dialect)
    } else {
      parse_csv_dialect(dialect)
    }
    if dialect_check is Err(message) {
      errors.push(issue("unsupported", name, 0, "dialect", message))
    }
    if prop(item, "compression") != Json::null() {
      errors.push(
        issue(
          "unsupported", name, 0, "", "Resource feature not yet supported: compression",
        ),
      )
    }
    if !mixed &&
      prop(item, "encoding") != Json::null() &&
      prop(item, "encoding") != Json::string("utf-8") {
      errors.push(
        issue("unsupported", name, 0, "", "Only utf-8 encoding is supported"),
      )
    }
    if mixed {
      if !["csv", "json"].contains(tabular_format(item)) {
        errors.push(
          issue(
            "unsupported", name, 0, "format", "Expected CSV or tabular JSON",
          ),
        )
      }
    } else if prop(item, "format") != Json::null() &&
      prop(item, "format") != Json::string("csv") {
      errors.push(
        issue(
          "unsupported", name, 0, "", "Only CSV resource format is supported",
        ),
      )
    }
    if !mixed &&
      prop(item, "profile") != Json::null() &&
      prop(item, "profile") != Json::string("tabular-data-resource") {
      errors.push(
        issue(
          "unsupported", name, 0, "", "Only tabular-data-resource profiles are supported",
        ),
      )
    }
    let schema_value = prop(item, "schema")
    let schema = parse_schema_value(schema_value, name, true, errors)
    resources.push({
      name,
      path,
      fields: schema.fields,
      missing_values: schema.missing_values,
      primary_key: schema.primary_key,
      foreign_keys: schema.foreign_keys,
    })
  }
  for r in resources {
    let table : Table = { name: r.name, fields: r.fields, rows: [], }
    if !r.primary_key.is_empty() {
      for e in validate_primary_key(table, r.primary_key) {
        errors.push(e)
      }
    }
    for key in r.foreign_keys {
      let mut target : Resource? = None
      for candidate in resources {
        if candidate.name == key.resource {
          target = Some(candidate)
        }
      }
      match target {
        None =>
          errors.push(
            issue(
              "foreign-key-schema",
              r.name,
              0,
              "",
              "Unknown reference resource: " + key.resource,
            ),
          )
        Some(t) =>
          for
            e in validate_foreign_key(
              table,
              key.fields,
              { name: t.name, fields: t.fields, rows: [], },
              key.reference_fields,
            ) {
            errors.push(e)
          }
      }
    }
  }
  if errors.is_empty() {
    Ok({ original, resources, })
  } else {
    Err(errors)
  }
}

///|
fn json_text(value : Json) -> String? {
  match value {
    String(s) => Some(s)
    _ => None
  }
}

///|
fn reject_nulls(
  value : Json,
  keys : Array[String],
  resource : String,
  field : String,
  errors : Array[Diagnostic],
) -> Unit {
  if value is Object(values) {
    for key in keys {
      if values.get(key) is Some(Null) {
        errors.push(
          issue(
            "descriptor",
            resource,
            0,
            field,
            key + " cannot be explicit null",
          ),
        )
      }
    }
  }
}
