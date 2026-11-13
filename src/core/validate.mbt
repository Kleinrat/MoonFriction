///|
fn issue(
  code : String,
  resource : String,
  row : Int32,
  field : String,
  message : String,
) -> Diagnostic {
  { code, resource, row, field, message, }
}

///|
fn cell_number(cell : Cell) -> Double? {
  match cell {
    IntegerValue(n) => Some(n.to_double())
    NumberValue(n) => Some(n)
    _ => None
  }
}

///|
fn check_field_definitions(
  name : String,
  fields : Array[Field],
  errors : Array[Diagnostic],
) -> Unit {
  if fields.is_empty() {
    errors.push(issue("schema", name, 0, "", "At least one field is required"))
  }
  let names : Array[String] = []
  for f in fields {
    if f.name == "" || names.contains(f.name) {
      errors.push(
        issue(
          "schema",
          name,
          0,
          f.name,
          "Field names must be nonempty and unique",
        ),
      )
    }
    names.push(f.name)
    if (f.minimum is Some(n) && !n.is_finite()) ||
      (f.maximum is Some(n) && !n.is_finite()) {
      errors.push(
        issue("schema", name, 0, f.name, "Numeric bounds must be finite"),
      )
    }
    if f.min_length is Some(lo) && f.max_length is Some(hi) && lo > hi {
      errors.push(
        issue("schema", name, 0, f.name, "minLength exceeds maxLength"),
      )
    }
    if (
        (f.kind == Text || f.kind == Boolean) &&
        (f.minimum != None || f.maximum != None)
      ) ||
      (f.kind != Text && (f.min_length != None || f.max_length != None)) {
      errors.push(
        issue(
          "schema",
          name,
          0,
          f.name,
          "Constraint is not applicable to field type",
        ),
      )
    }
    if f.minimum is Some(lo) && f.maximum is Some(hi) && lo > hi {
      errors.push(issue("schema", name, 0, f.name, "minimum exceeds maximum"))
    }
    if (f.min_length is Some(n) && n < 0) || (f.max_length is Some(n) && n < 0) {
      errors.push(
        issue("schema", name, 0, f.name, "Length bounds cannot be negative"),
      )
    }
  }
}

///|
fn check_logical_cell(
  name : String,
  f : Field,
  cell : Cell,
  number : Int32,
  column : Int32,
  output : Array[Array[Cell]],
  errors : Array[Diagnostic],
) -> Unit {
  if cell == Missing {
    if f.required {
      errors.push(
        issue("required", name, number, f.name, "Missing required value"),
      )
    }
  } else {
    if f.unique && output.any(prior => prior[column] == cell) {
      errors.push(
        issue("unique", name, number, f.name, "Duplicate logical value"),
      )
    }
    if cell is IntegerValue(n) &&
      (f.minimum != None || f.maximum != None) &&
      (n > 9007199254740991L || n < -9007199254740991L) {
      errors.push(
        issue(
          "unsupported-range",
          name,
          number,
          f.name,
          "Integer bounds above exact binary64 range require an exact numeric implementation",
        ),
      )
    }
    if cell_number(cell) is Some(value) {
      if f.minimum is Some(lo) && value < lo {
        errors.push(
          issue("minimum", name, number, f.name, "Value is below minimum"),
        )
      }
      if f.maximum is Some(hi) && value > hi {
        errors.push(
          issue("maximum", name, number, f.name, "Value is above maximum"),
        )
      }
    }
    if cell is TextValue(text) {
      let length = text.iter().count()
      if f.min_length is Some(n) && length < n {
        errors.push(
          issue(
            "minLength",
            name,
            number,
            f.name,
            "Text is shorter than minLength",
          ),
        )
      }
      if f.max_length is Some(n) && length > n {
        errors.push(
          issue(
            "maxLength",
            name,
            number,
            f.name,
            "Text is longer than maxLength",
          ),
        )
      }
    }
  }
}

///|
/// Validate caller-provided rows. row=0 denotes schema/header errors; data rows are 1-based.
/// Cells are returned for inspection, but callers must require valid() before using them.
pub fn validate_table(
  name : String,
  fields : Array[Field],
  header : Array[String],
  rows : Array[Array[String]],
  missing_values~ : Array[String] = [""],
) -> TableReport {
  let errors : Array[Diagnostic] = []
  let output : Array[Array[Cell]] = []
  check_field_definitions(name, fields, errors)
  if header != fields.map(f => f.name) {
    errors.push(
      issue("header", name, 0, "", "Header must match schema fields in order"),
    )
  }
  if !errors.is_empty() {
    return { table: { name, fields, rows: output, }, errors, }
  }
  for index, row in rows {
    let logical : Array[Cell] = []
    let number = index + 1
    if row.length() != fields.length() {
      errors.push(
        issue("row-width", name, number, "", "Row width differs from schema"),
      )
      continue
    }
    for column, f in fields {
      let cell = match cast_cell(row[column], f.kind, missing_values) {
        Ok(value) => value
        Err(message) => {
          errors.push(issue("type", name, number, f.name, message))
          logical.push(Missing)
          continue
        }
      }
      check_logical_cell(name, f, cell, number, column, output, errors)
      logical.push(cell)
    }
    output.push(logical)
  }
  { table: { name, fields, rows: output, }, errors, }
}
