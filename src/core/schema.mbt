///|
/// A parsed Table Schema that can be used without wrapping it in a Data Package.
/// The field, constraint, primary-key and diagnostics semantics are shared with
/// the package reader: `parse_descriptor` stores the same values on `Resource`.
#derive(Debug)
pub(all) struct TableSchema {
  fields : Array[Field]
  missing_values : Array[String]
  primary_key : Array[String]
  foreign_keys : Array[ForeignKey]
}

///|
/// Parse a standalone Table Schema descriptor.
///
/// This is deliberately the same supported subset as an inline resource schema.
/// Unknown top-level metadata is preserved by the caller if needed, but is not
/// interpreted here. Cross-table foreign keys are accepted structurally; a
/// single-table validation reports them explicitly instead of resolving them.
pub fn parse_table_schema(
  text : String,
) -> Result[TableSchema, Array[Diagnostic]] {
  let original = @json.parse(text, preserve_number_repr=true) catch {
    _ => return Err([issue("json", "", 0, "", "Invalid JSON table schema")])
  }
  if !(original is Object(_)) {
    return Err([
      issue("schema", "", 0, "", "Table Schema must be a JSON object"),
    ])
  }
  let errors : Array[Diagnostic] = []
  let schema = parse_schema_value(original, "", false, errors)
  let table : Table = { name: "", fields: schema.fields, rows: [], }
  if !schema.primary_key.is_empty() {
    for e in validate_primary_key(table, schema.primary_key) {
      errors.push(e)
    }
  }
  for fk in schema.foreign_keys {
    if fk.resource == "" {
      for
        e in validate_foreign_key(table, fk.fields, table, fk.reference_fields) {
        errors.push(e)
      }
    } else {
      // The target table is not available here. Still validate the source side
      // so an unknown source field cannot be mistaken for a valid rule.
      match field_positions(table, fk.fields) {
        Ok(_) => ()
        Err(message) =>
          errors.push(issue("foreign-key-schema", "", 0, "", message))
      }
    }
  }
  if errors.is_empty() {
    Ok(schema)
  } else {
    Err(errors)
  }
}

///|
/// Validate one table against a parsed Table Schema.
///
/// Missing values come from the schema unless the caller explicitly overrides
/// them. Self-referencing foreign keys are checked against this table. Any
/// foreign key that names another resource is reported as
/// `foreign-key-scope`, because a single table alone cannot resolve it.
pub fn validate_table_schema(
  name : String,
  schema : TableSchema,
  header : Array[String],
  rows : Array[Array[String]],
  missing_values~ : Array[String]? = None,
) -> TableReport {
  let effective_missing_values = match missing_values {
    Some(values) => values
    None => schema.missing_values
  }
  let report = validate_table(
    name,
    schema.fields,
    header,
    rows,
    missing_values=effective_missing_values,
  )
  finish_schema_report(name, schema, report)
}

///|
/// Shared table-level completion for CSV and JSON single-table validation:
/// report cross-table foreign keys, then run primary and self-reference keys on
/// a logically valid table.
fn finish_schema_report(
  name : String,
  schema : TableSchema,
  report : TableReport,
) -> TableReport {
  let errors : Array[Diagnostic] = []
  for e in report.errors {
    errors.push(e)
  }
  for fk in schema.foreign_keys {
    if fk.resource != "" {
      errors.push(
        issue(
          "foreign-key-scope",
          name,
          0,
          "",
          "Cross-table foreign key requires data-package validation: " +
          fk.resource,
        ),
      )
    }
  }
  if report.valid() {
    if !schema.primary_key.is_empty() {
      for e in validate_primary_key(report.table, schema.primary_key) {
        errors.push(e)
      }
    }
    for fk in schema.foreign_keys {
      if fk.resource == "" {
        for
          e in validate_foreign_key(
            report.table,
            fk.fields,
            report.table,
            fk.reference_fields,
          ) {
          errors.push(e)
        }
      }
    }
  }
  { table: report.table, errors, }
}

///|
/// Validate a parsed JSON batch against this standalone Table Schema, including
/// primary-key and self-reference rules. Cross-table foreign keys still report
/// `foreign-key-scope`.
pub fn TableSchema::validate_json(
  self : TableSchema,
  name : String,
  input : JsonInputTable,
) -> TableReport {
  let report = validate_json_table(
    name,
    self.fields,
    input,
    missing_values=self.missing_values,
  )
  finish_schema_report(name, self, report)
}

///|
/// Convenience method form for embedding consumers.
pub fn TableSchema::validate(
  self : TableSchema,
  name : String,
  header : Array[String],
  rows : Array[Array[String]],
  missing_values~ : Array[String]? = None,
) -> TableReport {
  validate_table_schema(name, self, header, rows, missing_values~)
}

///|
/// Shared inline-schema parser used by both `parse_table_schema` and the Data
/// Package reader. `normalize_self` controls whether a `resource: ""` foreign
/// key is rewritten to the owning resource name (package semantics); standalone
/// Table Schema keeps it as the explicit self-reference marker.
fn parse_schema_value(
  schema : Json,
  resource : String,
  normalize_self : Bool,
  errors : Array[Diagnostic],
) -> TableSchema {
  reject_nulls(
    schema,
    ["fields", "missingValues", "primaryKey", "foreignKeys"],
    resource,
    "",
    errors,
  )
  let entries = match prop(schema, "fields") {
    Array(a) => a
    _ => {
      errors.push(
        issue(
          "descriptor", resource, 0, "", "An inline schema with fields is required",
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
        "name", "type", "format", "constraints", "bareNumber", "decimalChar", "trueValues",
        "falseValues",
      ],
      resource,
      fname,
      errors,
    )
    if entry is Object(properties) {
      for key in ["title", "description"] {
        if properties.get(key) is Some(value) && !(value is String(_)) {
          errors.push(
            issue("descriptor", resource, 0, fname, key + " must be a string"),
          )
        }
      }
      if properties.get("rdfType") is Some(value) &&
        !(value is String(uri) && text_format_matches(uri, "uri")) {
        errors.push(
          issue(
            "descriptor", resource, 0, fname, "rdfType must be an absolute URI",
          ),
        )
      }
    }
    let kind = match prop(entry, "type") {
      Null | String("string") => Text
      String("integer") => Integer
      String("number") => Number
      String("boolean") => Boolean
      String("object") => ObjectValueType
      String("array") => ArrayValueType
      String("any") => Any
      String("date") => Date
      String("time") => Time
      String("datetime") => DateTime
      String("year") => Year
      String("yearmonth") => YearMonth
      String("duration") => Duration
      String("geopoint") => GeoPoint
      String("geojson") => GeoJson
      _ => {
        errors.push(
          issue("unsupported", resource, 0, fname, "Unsupported field type"),
        )
        Text
      }
    }
    if fname == "" || fields.any(f => f.name == fname) {
      errors.push(
        issue(
          "descriptor", resource, 0, fname, "Field names must be nonempty and unique",
        ),
      )
    }
    let declared_format = prop(entry, "format")
    let format = json_text(declared_format).unwrap_or("default")
    if (!(declared_format is Null) && !(declared_format is String(_))) ||
      !supported_field_format(kind, format) {
      errors.push(
        issue("unsupported", resource, 0, fname, "Unsupported field format"),
      )
    }
    let boolean_tokens = boolean_tokens(entry, kind, resource, fname, errors)
    let numeric_format = numeric_format(entry, kind, resource, fname, errors)
    let constraints = prop(entry, "constraints")
    reject_nulls(
      constraints,
      [
        "required", "unique", "enum", "minimum", "maximum", "minLength", "maxLength",
        "pattern",
      ],
      resource,
      fname,
      errors,
    )
    if constraints != Json::null() && !(constraints is Object(_)) {
      errors.push(
        issue("descriptor", resource, 0, fname, "constraints must be an object"),
      )
    }
    if constraints is Object(values) {
      for key, _ in values {
        if ![
            "required", "unique", "enum", "minimum", "maximum", "minLength", "maxLength",
            "pattern",
          ].contains(key) {
          errors.push(
            issue(
              "unsupported",
              resource,
              0,
              fname,
              "Unsupported constraint: " + key,
            ),
          )
        }
      }
    }
    let temporal = temporal_kind(kind)
    let integer = kind == Integer
    let exact_minimum = if integer {
      integer_bound(constraints, "minimum", resource, fname, errors)
    } else {
      None
    }
    let exact_maximum = if integer {
      integer_bound(constraints, "maximum", resource, fname, errors)
    } else {
      None
    }
    let minimum = if temporal || numeric_kind(kind) {
      None
    } else {
      bound(constraints, "minimum", resource, fname, errors)
    }
    let maximum = if temporal || numeric_kind(kind) {
      None
    } else {
      bound(constraints, "maximum", resource, fname, errors)
    }
    let temporal_minimum = if temporal {
      temporal_bound(
        constraints, "minimum", kind, format, resource, fname, errors,
      )
    } else {
      None
    }
    let temporal_maximum = if temporal {
      temporal_bound(
        constraints, "maximum", kind, format, resource, fname, errors,
      )
    } else {
      None
    }
    let min_length = length_bound(
      constraints, "minLength", resource, fname, errors,
    )
    let max_length = length_bound(
      constraints, "maxLength", resource, fname, errors,
    )
    if (minimum is Some(lo) && maximum is Some(hi) && lo > hi) ||
      (exact_minimum is Some(lo) && exact_maximum is Some(hi) && lo > hi) ||
      (
        temporal_minimum is Some(lo) &&
        temporal_maximum is Some(hi) &&
        compare_temporal(kind_label(kind), lo, hi) > 0
      ) ||
      (min_length is Some(lo) && max_length is Some(hi) && lo > hi) {
      errors.push(
        issue(
          "descriptor", resource, 0, fname, "Contradictory constraint bounds",
        ),
      )
    }
    if (!numeric_kind(kind) && (minimum != None || maximum != None)) ||
      (!collection_kind(kind) && (min_length != None || max_length != None)) {
      errors.push(
        issue(
          "descriptor", resource, 0, fname, "Constraint is not applicable to field type",
        ),
      )
    }
    let pattern = match prop(constraints, "pattern") {
      Null => None
      String(raw) if kind == Text =>
        match compile_field_pattern(raw) {
          Ok(value) => Some(value)
          Err(message) => {
            errors.push(issue("descriptor", resource, 0, fname, message))
            None
          }
        }
      _ => {
        errors.push(
          issue(
            "descriptor", resource, 0, fname, "pattern requires a string field and a regex string",
          ),
        )
        None
      }
    }
    let f = {
      name: fname,
      kind,
      format,
      boolean_tokens,
      numeric_format,
      required: flag(constraints, "required", resource, fname, errors),
      unique: flag(constraints, "unique", resource, fname, errors),
      enum_values: None,
      minimum,
      maximum,
      min_length,
      max_length,
      pattern,
      decimal_minimum: None,
      decimal_maximum: None,
      exact_minimum,
      exact_maximum,
      temporal_minimum,
      temporal_maximum,
    }
    let decimal_minimum = if kind == Number {
      decimal_bound(constraints, "minimum", f, resource, errors)
    } else {
      None
    }
    let decimal_maximum = if kind == Number {
      decimal_bound(constraints, "maximum", f, resource, errors)
    } else {
      None
    }
    if decimal_minimum is Some(lo) &&
      decimal_maximum is Some(hi) &&
      compare_decimal(lo, hi) > 0 {
      errors.push(
        issue(
          "descriptor", resource, 0, fname, "Contradictory constraint bounds",
        ),
      )
    }
    fields.push({
      ..f,
      decimal_minimum,
      decimal_maximum,
      enum_values: parse_enum(prop(constraints, "enum"), f, resource, errors),
    })
  }
  if fields.is_empty() {
    errors.push(
      issue("descriptor", resource, 0, "", "Schema fields cannot be empty"),
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
              "descriptor", resource, 0, "", "missingValues must be an array of strings",
            ),
          )
          []
        }
      }
    }
    _ => {
      errors.push(
        issue("descriptor", resource, 0, "", "missingValues must be an array"),
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
            issue("descriptor", resource, 0, "", "primaryKey cannot be empty"),
          )
        }
        names
      }
      None => {
        errors.push(issue("descriptor", resource, 0, "", "Invalid primaryKey"))
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
              "descriptor", resource, 0, "", "Foreign key field forms must match",
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
                  "descriptor", resource, 0, "", "Foreign key needs equally sized nonempty fields",
                ),
              )
            }
            foreign_keys.push({
              fields: a,
              resource: if normalize_self && target == "" {
                resource
              } else {
                target
              },
              reference_fields: b,
            })
          }
          _ =>
            errors.push(
              issue(
                "descriptor", resource, 0, "", "Invalid foreign key descriptor",
              ),
            )
        }
      }
    _ =>
      errors.push(
        issue("descriptor", resource, 0, "", "foreignKeys must be an array"),
      )
  }
  { fields, missing_values, primary_key, foreign_keys, }
}
