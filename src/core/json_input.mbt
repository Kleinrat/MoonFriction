///|
#derive(Debug)
pub(all) enum JsonRowMode {
  ArrayRows
  ObjectRows
}

///|
/// Batch JSON input for one table.
///
/// The top-level JSON value is an array. Every element must be either an array
/// of values in schema field order, or an object keyed by field name. Mixed
/// arrays and objects are rejected at input parsing time.
#derive(Debug)
pub(all) struct JsonInputTable {
  name : String
  mode : JsonRowMode
  rows : Array[Json]
}

///|
/// Parse a JSON array of rows without converting values to strings.
pub fn input_from_json(
  name : String,
  text : String,
) -> Result[JsonInputTable, String] {
  let value = @json.parse(text) catch {
    _ => return Err("Invalid JSON row data")
  }
  let items = match value {
    Array(items) => items
    _ => return Err("JSON rows must be a top-level array")
  }
  if items.is_empty() {
    return Ok({ name, mode: ArrayRows, rows: [], })
  }
  let mode = match items[0] {
    Object(_) => ObjectRows
    Array(_) => ArrayRows
    _ => return Err("JSON rows must contain only objects or only arrays")
  }
  for item in items {
    let matches = match (mode, item) {
      (ObjectRows, Object(_)) => true
      (ArrayRows, Array(_)) => true
      _ => false
    }
    if !matches {
      return Err("JSON rows must contain only objects or only arrays")
    }
  }
  Ok({ name, mode, rows: items, })
}

///|
fn json_exact_integer(number : Double, repr : String?) -> Result[Int64, String] {
  match repr {
    Some(raw) => {
      let start = if raw.has_prefix("-") || raw.has_prefix("+") { 1 } else { 0 }
      if !ascii_digits(raw, start) {
        return Err("JSON number is not an integer")
      }
      let value = @string.parse_int64(raw) catch {
        _ => return Err("JSON integer exceeds signed 64-bit range")
      }
      Ok(value)
    }
    None =>
      if !number.is_finite() || number != number.trunc() {
        Err("JSON number is not an integer")
      } else if number > 9007199254740991.0 || number < -9007199254740991.0 {
        Err("JSON integer is outside the exact 64-bit range")
      } else {
        Ok(number.to_int64())
      }
  }
}

///|
/// Convert one JSON value without stringifying it first.
///
/// Policy:
/// - JSON null is Missing.
/// - For string fields only JSON strings are accepted.
/// - For integer/number/boolean fields, a JSON string uses the same strict
///   physical lexical rules as CSV; native numbers/booleans must match the
///   field kind. Arrays and objects are never accepted as scalar values.
/// - A native JSON number for an integer field must have an exact 64-bit
///   integral value; `1.0` is accepted as 1, `9007199254740993` keeps its exact
///   representation via the JSON parser's `repr`.
pub fn cast_json_cell(
  value : Json,
  kind : FieldType,
  missing_values : Array[String],
) -> Result[Cell, String] {
  match value {
    Null => Ok(Missing)
    String(text) => cast_cell(text, kind, missing_values)
    Number(number, repr~) =>
      match kind {
        Integer =>
          match json_exact_integer(number, repr) {
            Ok(value) => Ok(IntegerValue(value))
            Err(message) => Err(message)
          }
        Number =>
          if number.is_finite() {
            Ok(NumberValue(number))
          } else {
            Err("Non-finite JSON numbers are outside the supported subset")
          }
        Text =>
          Err(
            "JSON number cannot be used for a string field without a declared conversion",
          )
        Boolean => Err("JSON number cannot be used for a boolean field")
      }
    True | False =>
      match kind {
        Boolean => Ok(BooleanValue(value is True))
        Text =>
          Err(
            "JSON boolean cannot be used for a string field without a declared conversion",
          )
        Integer | Number =>
          Err("JSON boolean cannot be used for a numeric field")
      }
    Array(_) | Object(_) =>
      Err("JSON arrays and objects are not scalar cell values")
  }
}

///|
/// Validate a batch JSON table against the same fields and constraints used by
/// CSV input. Input is fully materialized; this API makes no streaming or fixed
/// memory promise.
pub fn validate_json_table(
  name : String,
  fields : Array[Field],
  input : JsonInputTable,
  missing_values~ : Array[String] = [""],
) -> TableReport {
  let errors : Array[Diagnostic] = []
  let output : Array[Array[Cell]] = []
  check_field_definitions(name, fields, errors)
  if !errors.is_empty() {
    return { table: { name, fields, rows: output, }, errors, }
  }
  let field_names = fields.map(f => f.name)
  for index, item in input.rows {
    let number = index + 1
    let values : Array[Json] = match input.mode {
      ArrayRows =>
        match item {
          Array(values) => values
          _ => {
            errors.push(
              issue(
                "json-rows", name, number, "", "JSON row is not an array in array-row mode",
              ),
            )
            continue
          }
        }
      ObjectRows =>
        match item {
          Object(values) => {
            for key, _ in values {
              if !field_names.contains(key) {
                errors.push(
                  issue(
                    "extra-property", name, number, key, "JSON object row contains an unknown property",
                  ),
                )
              }
            }
            fields.map(f => values.get(f.name).unwrap_or(Json::null()))
          }
          _ => {
            errors.push(
              issue(
                "json-rows", name, number, "", "JSON row is not an object in object-row mode",
              ),
            )
            continue
          }
        }
    }
    if values.length() != fields.length() {
      errors.push(
        issue(
          "row-width", name, number, "", "JSON row width differs from schema",
        ),
      )
      continue
    }
    let logical : Array[Cell] = []
    for column, f in fields {
      let cell = match cast_json_cell(values[column], f.kind, missing_values) {
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
