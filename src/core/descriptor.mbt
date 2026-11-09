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
  let original = @json.parse(text) catch {
    _ => return Err([issue("json", "", 0, "", "Invalid JSON descriptor")])
  }
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
  if profile != Json::null() &&
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
    if !safe_resource_path(path) || prop(item, "data") != Json::null() {
      errors.push(
        issue(
          "unsupported", name, 0, "", "Only one safe local resource path is supported, without inline data",
        ),
      )
    }
    for key in ["dialect", "compression"] {
      if prop(item, key) != Json::null() {
        errors.push(
          issue(
            "unsupported",
            name,
            0,
            "",
            "Resource feature not yet supported: " + key,
          ),
        )
      }
    }
    if prop(item, "encoding") != Json::null() &&
      prop(item, "encoding") != Json::string("utf-8") {
      errors.push(
        issue("unsupported", name, 0, "", "Only utf-8 encoding is supported"),
      )
    }
    if prop(item, "format") != Json::null() &&
      prop(item, "format") != Json::string("csv") {
      errors.push(
        issue(
          "unsupported", name, 0, "", "Only CSV resource format is supported",
        ),
      )
    }
    if prop(item, "profile") != Json::null() &&
      prop(item, "profile") != Json::string("tabular-data-resource") {
      errors.push(
        issue(
          "unsupported", name, 0, "", "Only tabular-data-resource profiles are supported",
        ),
      )
    }
    let schema = prop(item, "schema")
    reject_nulls(
      schema,
      ["fields", "missingValues", "primaryKey", "foreignKeys"],
      name,
      "",
      errors,
    )
    let entries = match prop(schema, "fields") {
      Array(a) => a
      _ => {
        errors.push(
          issue(
            "descriptor", name, 0, "", "An inline schema with fields is required",
          ),
        )
        []
      }
    }
    let fields : Array[Field] = []
    for entry in entries {
      let fname = json_text(prop(entry, "name")).unwrap_or("")
      reject_nulls(
        entry,
        [
          "name", "type", "format", "constraints", "bareNumber", "decimalChar", "groupChar",
          "trueValues", "falseValues",
        ],
        name,
        fname,
        errors,
      )
      let kind = match prop(entry, "type") {
        Null | String("string") => Text
        String("integer") => Integer
        String("number") => Number
        String("boolean") => Boolean
        _ => {
          errors.push(
            issue("unsupported", name, 0, fname, "Unsupported field type"),
          )
          Text
        }
      }
      if fname == "" || fields.any(f => f.name == fname) {
        errors.push(
          issue(
            "descriptor", name, 0, fname, "Field names must be nonempty and unique",
          ),
        )
      }
      for
        key in [
          "bareNumber", "decimalChar", "groupChar", "trueValues", "falseValues",
        ] {
        if prop(entry, key) != Json::null() {
          errors.push(
            issue(
              "unsupported",
              name,
              0,
              fname,
              "Field feature not yet supported: " + key,
            ),
          )
        }
      }
      if prop(entry, "format") != Json::null() &&
        prop(entry, "format") != Json::string("default") {
        errors.push(
          issue(
            "unsupported", name, 0, fname, "Only default field formats are supported",
          ),
        )
      }
      let constraints = prop(entry, "constraints")
      reject_nulls(
        constraints,
        ["required", "unique", "minimum", "maximum", "minLength", "maxLength"],
        name,
        fname,
        errors,
      )
      if constraints != Json::null() && !(constraints is Object(_)) {
        errors.push(
          issue("descriptor", name, 0, fname, "constraints must be an object"),
        )
      }
      if constraints is Object(values) {
        for key, _ in values {
          if ![
              "required", "unique", "minimum", "maximum", "minLength", "maxLength",
            ].contains(key) {
            errors.push(
              issue(
                "unsupported",
                name,
                0,
                fname,
                "Unsupported constraint: " + key,
              ),
            )
          }
        }
      }
      let minimum = bound(constraints, "minimum", name, fname, errors)
      let maximum = bound(constraints, "maximum", name, fname, errors)
      let min_length = length_bound(
        constraints, "minLength", name, fname, errors,
      )
      let max_length = length_bound(
        constraints, "maxLength", name, fname, errors,
      )
      if (minimum is Some(lo) && maximum is Some(hi) && lo > hi) ||
        (min_length is Some(lo) && max_length is Some(hi) && lo > hi) {
        errors.push(
          issue("descriptor", name, 0, fname, "Contradictory constraint bounds"),
        )
      }
      if (
          (kind == Text || kind == Boolean) &&
          (minimum != None || maximum != None)
        ) ||
        (kind != Text && (min_length != None || max_length != None)) {
        errors.push(
          issue(
            "descriptor", name, 0, fname, "Constraint is not applicable to field type",
          ),
        )
      }
      fields.push({
        name: fname,
        kind,
        required: flag(constraints, "required", name, fname, errors),
        unique: flag(constraints, "unique", name, fname, errors),
        minimum,
        maximum,
        min_length,
        max_length,
      })
    }
    if fields.is_empty() {
      errors.push(
        issue("descriptor", name, 0, "", "Schema fields cannot be empty"),
      )
    }
    let missing_values = match prop(schema, "missingValues") {
      Null => [""]
      Array(a) => {
        let markers = strings(Json::array(a))
        match markers {
          Some(values) => values
          None => {
            errors.push(
              issue(
                "descriptor", name, 0, "", "missingValues must be an array of strings",
              ),
            )
            []
          }
        }
      }
      _ => {
        errors.push(
          issue("descriptor", name, 0, "", "missingValues must be an array"),
        )
        []
      }
    }
    let primary_key = if prop(schema, "primaryKey") == Json::null() {
      []
    } else {
      match strings(prop(schema, "primaryKey")) {
        Some(names) => {
          if names.is_empty() {
            errors.push(
              issue("descriptor", name, 0, "", "primaryKey cannot be empty"),
            )
          }
          names
        }
        None => {
          errors.push(issue("descriptor", name, 0, "", "Invalid primaryKey"))
          []
        }
      }
    }
    let foreign_keys : Array[ForeignKey] = []
    match prop(schema, "foreignKeys") {
      Null => ()
      Array(keys) =>
        for key in keys {
          let reference = prop(key, "reference")
          let source_fields = prop(key, "fields")
          let target_fields = prop(reference, "fields")
          if (source_fields is String(_) && !(target_fields is String(_))) ||
            (source_fields is Array(_) && !(target_fields is Array(_))) {
            errors.push(
              issue(
                "descriptor", name, 0, "", "Foreign key field forms must match",
              ),
            )
          }
          let from = strings(source_fields)
          let to = strings(prop(reference, "fields"))
          let target = json_text(prop(reference, "resource"))
          match (from, to, target) {
            (Some(a), Some(b), Some(target)) => {
              if a.is_empty() || a.length() != b.length() {
                errors.push(
                  issue(
                    "descriptor", name, 0, "", "Foreign key needs equally sized nonempty fields",
                  ),
                )
              }
              foreign_keys.push({
                fields: a,
                resource: if target == "" {
                  name
                } else {
                  target
                },
                reference_fields: b,
              })
            }
            _ =>
              errors.push(
                issue(
                  "descriptor", name, 0, "", "Invalid foreign key descriptor",
                ),
              )
          }
        }
      _ =>
        errors.push(
          issue("descriptor", name, 0, "", "foreignKeys must be an array"),
        )
    }
    resources.push({
      name,
      path,
      fields,
      missing_values,
      primary_key,
      foreign_keys,
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
