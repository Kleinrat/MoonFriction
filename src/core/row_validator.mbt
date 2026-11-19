///|
pub(all) struct RowSummary {
  rows : Int32
  error_count : Int64
  errors : Array[Diagnostic]
}

///|
struct ErrorSample {
  limit : Int32
  mut count : Int64
  errors : Array[Diagnostic]
}

///|
fn ErrorSample::record(self : ErrorSample, error : Diagnostic) -> Unit {
  self.count += 1
  if self.errors.length() < self.limit {
    self.errors.push(error)
  }
}

///|
pub struct RowValidator {
  priv name : String
  priv fields : Array[Field]
  priv header : Array[String]
  priv missing : Array[String]
  priv positions : Array[Int32]
  priv unique_seen : Array[@hashset.HashSet[Cell]?]
  priv keys : @hashset.HashSet[Array[Cell]]
  priv field_errors : ErrorSample
  priv key_errors : ErrorSample
  priv mut rows : Int32
  priv mut json_mode : JsonRowMode?
}

///|
/// Accepts decoded records. All foreign keys require batch validation.
pub fn RowValidator::new(
  name : String,
  schema : TableSchema,
  header : Array[String],
  max_errors~ : Int32 = 100,
) -> Result[RowValidator, Array[Diagnostic]] {
  let errors = []
  check_field_definitions(name, schema.fields, errors)
  if header != schema.fields.map(f => f.name) {
    errors.push(
      issue("header", name, 0, "", "Header must match schema fields in order"),
    )
  }
  if max_errors < 0 {
    errors.push(issue("input", name, 0, "", "max_errors must be nonnegative"))
  }
  if !schema.foreign_keys.is_empty() {
    errors.push(
      issue(
        "foreign-key-scope", name, 0, "", "Row validation requires batch mode for foreign keys",
      ),
    )
  }
  let positions = if schema.primary_key.is_empty() {
    []
  } else {
    match
      field_positions(
        { name, fields: schema.fields, rows: [], },
        schema.primary_key,
      ) {
      Ok(indexes) => indexes
      Err(message) => {
        errors.push(issue("primary-key-schema", name, 0, "", message))
        []
      }
    }
  }
  if !errors.is_empty() {
    return Err(errors)
  }
  let fields = schema.fields.map(f => {
    ..f,
    enum_values: f.enum_values.map(v => v.copy()),
  })
  Ok({
    name,
    fields,
    header: header.copy(),
    missing: schema.missing_values.copy(),
    positions,
    unique_seen: fields.map(f => {
      if f.unique {
        Some(@hashset.HashSet([]))
      } else {
        None
      }
    }),
    keys: @hashset.HashSet([]),
    field_errors: { limit: max_errors, count: 0, errors: [], },
    key_errors: { limit: max_errors, count: 0, errors: [], },
    rows: 0,
    json_mode: None,
  })
}

///|
pub fn RowValidator::feed(self : RowValidator, row : Array[String]) -> Unit {
  self.rows += 1
  self.consume(row.length(), "Row width differs from schema", (i, f) => {
    cast_cell(row[i], f.kind, self.missing)
  })
}

///|
pub fn RowValidator::feed_json(self : RowValidator, row : Json) -> Unit {
  self.rows += 1
  let mode = match self.json_mode {
    Some(mode) => mode
    None => {
      let mode : JsonRowMode = match row {
        Array(_) => ArrayRows
        Object(_) => ObjectRows
        _ => {
          self.field_errors.record(
            issue(
              "json-rows",
              self.name,
              self.rows,
              "",
              "Expected a JSON array or object row",
            ),
          )
          return
        }
      }
      self.json_mode = Some(mode)
      mode
    }
  }
  let errors = []
  let values = json_row_values(
    row,
    mode,
    self.header,
    self.name,
    self.rows,
    errors,
  )
  for e in errors {
    self.field_errors.record(e)
  }
  if values is Some(v) {
    self.consume(v.length(), "JSON row width differs from schema", (i, f) => {
      cast_json_cell(v[i], f.kind, self.missing)
    })
  }
}

///|
fn RowValidator::consume(
  self : RowValidator,
  width : Int32,
  width_message : String,
  cast : (Int32, Field) -> Result[Cell, String],
) -> Unit {
  if width != self.fields.length() {
    self.field_errors.record(
      issue("row-width", self.name, self.rows, "", width_message),
    )
    return
  }
  let cells = []
  let errors = []
  for i, f in self.fields {
    match cast(i, f) {
      Err(message) => {
        errors.push(issue("type", self.name, self.rows, f.name, message))
        cells.push(Missing)
      }
      Ok(value) => {
        let cell = match value {
          NumberValue(n) if n == 0.0 => NumberValue(0.0)
          _ => value
        }
        let duplicate = if self.unique_seen[i] is Some(seen) && cell != Missing {
          !seen.add_and_check(cell)
        } else {
          false
        }
        check_logical_cell(self.name, f, cell, self.rows, duplicate, errors)
        cells.push(cell)
      }
    }
  }
  for error in errors {
    self.field_errors.record(error)
  }
  // Match batch semantics: key diagnostics apply only if every row passed field validation.
  if self.field_errors.count == 0 && !self.positions.is_empty() {
    let key = self.positions.map(i => cells[i])
    if key.contains(Missing) {
      self.key_errors.record(
        issue(
          "primary-key-null",
          self.name,
          self.rows,
          "",
          "Primary key contains a missing value",
        ),
      )
    } else if !self.keys.add_and_check(key) {
      self.key_errors.record(
        issue(
          "primary-key-duplicate",
          self.name,
          self.rows,
          "",
          "Duplicate primary key",
        ),
      )
    }
  }
}

///|
/// A detached snapshot. Repeated calls do not consume or reset validation state.
pub fn RowValidator::finish(self : RowValidator) -> RowSummary {
  let sample = if self.field_errors.count > 0 {
    self.field_errors
  } else {
    self.key_errors
  }
  { rows: self.rows, error_count: sample.count, errors: sample.errors.copy(), }
}
