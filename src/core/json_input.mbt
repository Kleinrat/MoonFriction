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
  let value = @json.parse(text, preserve_number_repr=true) catch {
    _ => return Err("Invalid JSON row data")
  }
  json_input_value(name, value)
}

///|
fn json_input_value(
  name : String,
  value : Json,
) -> Result[JsonInputTable, String] {
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
/// Convert a JSON value using the default format for the declared type.
/// Native structures are accepted for object, array and GeoJSON fields.
/// Numbers retain their exact source literals when the JSON parser provides them.
/// Null and configured string markers are matched before type conversion.
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
          match repr {
            Some(raw) => cast_json_integer_text(raw)
            None =>
              if !number.is_finite() || number != number.trunc() {
                Err("JSON number is not an integer")
              } else if number < -9007199254740991.0 ||
                number > 9007199254740991.0 {
                Err(
                  "JSON integer requires an exact literal above the safe integer range",
                )
              } else {
                Ok(IntegerValue(number.to_int64()))
              }
          }
        Number => cast_decimal(repr.unwrap_or(value.stringify()))
        Text =>
          Err(
            "JSON number cannot be used for a string field without a declared conversion",
          )
        Year => cast_cell(value.stringify(), kind, missing_values)
        Any => Ok(TextValue(value.stringify()))
        _ => Err("JSON number does not match the field type")
      }
    True | False =>
      match kind {
        Boolean => Ok(BooleanValue(value is True))
        Text =>
          Err(
            "JSON boolean cannot be used for a string field without a declared conversion",
          )
        Any => Ok(TextValue(value.stringify()))
        _ => Err("JSON boolean does not match the field type")
      }
    Array(_) | Object(_) =>
      match kind {
        Any => Ok(TextValue(canonical_json(value).stringify()))
        GeoJson => geojson_cell(value)
        _ => cast_structured(value, kind)
      }
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
    let values : Array[Json] = match
      json_row_values(item, input.mode, field_names, name, number, errors) {
      Some(values) => values
      None => continue
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
      let cell = match cast_field_json(values[column], f, missing_values) {
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

///|
fn json_row_values(
  item : Json,
  mode : JsonRowMode,
  field_names : Array[String],
  name : String,
  number : Int32,
  errors : Array[Diagnostic],
) -> Array[Json]? {
  Some(
    match mode {
      ArrayRows =>
        match item {
          Array(values) => values
          _ => {
            errors.push(
              issue(
                "json-rows", name, number, "", "JSON row is not an array in array-row mode",
              ),
            )
            return None
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
            field_names.map(name => values.get(name).unwrap_or(Json::null()))
          }
          _ => {
            errors.push(
              issue(
                "json-rows", name, number, "", "JSON row is not an object in object-row mode",
              ),
            )
            return None
          }
        }
    },
  )
}
