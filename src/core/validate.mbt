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
    if !supported_field_format(f.kind, f.format) {
      errors.push(issue("schema", name, 0, f.name, "Unsupported field format"))
    }
    if f.boolean_tokens is Some(t) &&
      (
        f.kind != Boolean ||
        t.truthy.is_empty() ||
        t.falsy.is_empty() ||
        t.truthy.any(v => t.falsy.contains(v))
      ) {
      errors.push(
        issue("schema", name, 0, f.name, "Invalid boolean token definitions"),
      )
    }
    if f.numeric_format is Some(n) &&
      (
        !numeric_kind(f.kind) ||
        !valid_numeric_separator(n.decimal) ||
        (n.group is Some(g) && (!valid_numeric_separator(g) || g == n.decimal))
      ) {
      errors.push(
        issue("schema", name, 0, f.name, "Invalid numeric format definitions"),
      )
    }
    names.push(f.name)
    if f.enum_values is Some(values) &&
      (values.is_empty() || !values.all(v => enum_member_matches(v, f.kind))) {
      errors.push(
        issue(
          "schema",
          name,
          0,
          f.name,
          "enum requires a nonempty array of values matching the field type",
        ),
      )
    }
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
    if (!numeric_kind(f.kind) && (f.minimum != None || f.maximum != None)) ||
      (
        !collection_kind(f.kind) &&
        (f.min_length != None || f.max_length != None)
      ) ||
      (f.kind != Text && f.pattern is Some(_)) {
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
    if (
        f.kind != Integer &&
        (f.exact_minimum is Some(_) || f.exact_maximum is Some(_))
      ) ||
      (f.exact_minimum is Some(lo) && f.exact_maximum is Some(hi) && lo > hi) {
      errors.push(
        issue("schema", name, 0, f.name, "Invalid exact integer bounds"),
      )
    }
    if (
        f.kind != Number &&
        (f.decimal_minimum is Some(_) || f.decimal_maximum is Some(_))
      ) ||
      (
        f.decimal_minimum is Some(lo) &&
        f.decimal_maximum is Some(hi) &&
        compare_decimal(lo, hi) > 0
      ) {
      errors.push(
        issue("schema", name, 0, f.name, "Invalid exact decimal bounds"),
      )
    }
    if f.temporal_minimum is Some(lo) &&
      f.temporal_maximum is Some(hi) &&
      compare_temporal(kind_label(f.kind), lo, hi) > 0 {
      errors.push(issue("schema", name, 0, f.name, "minimum exceeds maximum"))
    }
    for temporal_bound in [f.temporal_minimum, f.temporal_maximum] {
      if temporal_bound is Some(raw) &&
        (
          !temporal_kind(f.kind) ||
          normalize_temporal(kind_label(f.kind), raw) != Ok(raw)
        ) {
        errors.push(
          issue(
            "schema",
            name,
            0,
            f.name,
            "Temporal bounds must be canonical values of the field type",
          ),
        )
      }
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
  duplicate : Bool,
  errors : Array[Diagnostic],
) -> Unit {
  if cell == Missing {
    if f.required {
      errors.push(
        issue("required", name, number, f.name, "Missing required value"),
      )
    }
  } else {
    if f.enum_values is Some(values) && !values.contains(cell) {
      errors.push(
        issue("enum", name, number, f.name, "Value is outside the allowed set"),
      )
    }
    if duplicate {
      errors.push(
        issue("unique", name, number, f.name, "Duplicate logical value"),
      )
    }
    if (f.exact_minimum is Some(_) || f.exact_maximum is Some(_)) &&
      logical_integer(cell) is Some(value) {
      if f.exact_minimum is Some(lo) && value < lo {
        errors.push(
          issue("minimum", name, number, f.name, "Value is below minimum"),
        )
      }
      if f.exact_maximum is Some(hi) && value > hi {
        errors.push(
          issue("maximum", name, number, f.name, "Value is above maximum"),
        )
      }
    }
    if f.kind == Number {
      let minimum = if f.decimal_minimum is Some(_) {
        f.decimal_minimum
      } else {
        f.minimum.map(decimal_from_double)
      }
      let maximum = if f.decimal_maximum is Some(_) {
        f.decimal_maximum
      } else {
        f.maximum.map(decimal_from_double)
      }
      if minimum is Some(_) || maximum is Some(_) {
        let value = logical_decimal(cell)
        if minimum is Some(lo) &&
          (
            cell == SpecialNumber("-INF") ||
            cell == SpecialNumber("NaN") ||
            (value is Some(x) && compare_decimal(x, lo) < 0)
          ) {
          errors.push(
            issue(
              "minimum",
              name,
              number,
              f.name,
              "Value is below or incomparable to minimum",
            ),
          )
        }
        if maximum is Some(hi) &&
          (
            cell == SpecialNumber("INF") ||
            cell == SpecialNumber("NaN") ||
            (value is Some(x) && compare_decimal(x, hi) > 0)
          ) {
          errors.push(
            issue(
              "maximum",
              name,
              number,
              f.name,
              "Value is above or incomparable to maximum",
            ),
          )
        }
      }
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
    if cell is BigIntegerValue(_) && (f.minimum != None || f.maximum != None) {
      errors.push(
        issue(
          "unsupported-range",
          name,
          number,
          f.name,
          "Use exact_minimum or exact_maximum for integer bounds",
        ),
      )
    }
    if f.kind == Integer && cell_number(cell) is Some(value) {
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
    if cell is TemporalValue(value) {
      let kind = kind_label(f.kind)
      if f.temporal_minimum is Some(lo) && compare_temporal(kind, value, lo) < 0 {
        errors.push(
          issue("minimum", name, number, f.name, "Value is below minimum"),
        )
      }
      if f.temporal_maximum is Some(hi) && compare_temporal(kind, value, hi) > 0 {
        errors.push(
          issue("maximum", name, number, f.name, "Value is above maximum"),
        )
      }
    }
    if cell is TextValue(text) &&
      f.pattern is Some(pattern) &&
      pattern.matcher.execute(text[:]) is None {
      errors.push(
        issue("pattern", name, number, f.name, "Value does not match pattern"),
      )
    }
    if (f.min_length is Some(_) || f.max_length is Some(_)) &&
      cell_length(cell) is Some(length) {
      if f.min_length is Some(n) && length < n {
        errors.push(
          issue(
            "minLength",
            name,
            number,
            f.name,
            "Value has fewer items than minLength",
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
            "Value has more items than maxLength",
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
      let cell = match cast_field_text(row[column], f, missing_values) {
        Ok(value) => value
        Err(message) => {
          errors.push(issue("type", name, number, f.name, message))
          logical.push(Missing)
          continue
        }
      }
      check_logical_cell(
        name,
        f,
        cell,
        number,
        f.unique &&
        cell != Missing &&
        output.any(prior => prior[column] == cell),
        errors,
      )
      logical.push(cell)
    }
    output.push(logical)
  }
  { table: { name, fields, rows: output, }, errors, }
}
