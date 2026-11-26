///|
fn ascii_digits(text : String, start : Int32) -> Bool {
  if start == text.length() {
    return false
  }
  for i = start; i < text.length(); i = i + 1 {
    let c = text.code_unit_at(i).to_int()
    if c < 48 || c > 57 {
      return false
    }
  }
  true
}

///|
fn decimal_syntax(text : String) -> Bool {
  let n = text.length()
  if n == 0 {
    return false
  }
  let mut i = if text.has_prefix("-") || text.has_prefix("+") { 1 } else { 0 }
  let start = i
  while i < n &&
        text.code_unit_at(i).to_int() >= 48 &&
        text.code_unit_at(i).to_int() <= 57 {
    i += 1
  }
  if i == start {
    return false
  }
  if i < n && text.code_unit_at(i).to_int() == 46 {
    i += 1
    let fraction = i
    while i < n &&
          text.code_unit_at(i).to_int() >= 48 &&
          text.code_unit_at(i).to_int() <= 57 {
      i += 1
    }
    if i == fraction {
      return false
    }
  }
  if i < n &&
    (
      text.code_unit_at(i).to_int() == 69 ||
      text.code_unit_at(i).to_int() == 101
    ) {
    i += 1
    if i < n &&
      (
        text.code_unit_at(i).to_int() == 43 ||
        text.code_unit_at(i).to_int() == 45
      ) {
      i += 1
    }
    let exponent = i
    while i < n &&
          text.code_unit_at(i).to_int() >= 48 &&
          text.code_unit_at(i).to_int() <= 57 {
      i += 1
    }
    if i == exponent {
      return false
    }
  }
  i == n
}

///|
/// Convert text using the default format for the declared field type.
/// Missing markers are matched exactly, before casting; whitespace is preserved.
pub fn cast_cell(
  raw : String,
  kind : FieldType,
  missing_values : Array[String],
) -> Result[Cell, String] {
  if missing_values.contains(raw) {
    return Ok(Missing)
  }
  match kind {
    Text | Any => Ok(TextValue(raw))
    Duration => cast_duration(raw)
    GeoPoint => geopoint_text(raw)
    GeoJson => {
      let value = @json.parse(raw, preserve_number_repr=true) catch {
        _ => return Err("Expected GeoJSON")
      }
      geojson_cell(value)
    }
    Date | Time | DateTime | Year | YearMonth =>
      normalize_temporal(kind_label(kind), raw).map(value => {
        TemporalValue(value)
      })
    ObjectValueType | ArrayValueType => {
      let value = @json.parse(raw, preserve_number_repr=true) catch {
        _ => return Err("Expected valid JSON data")
      }
      cast_structured(value, kind)
    }
    Integer => cast_integer(raw)
    Number => cast_decimal(raw)
    Boolean =>
      match raw {
        "true" | "True" | "TRUE" | "1" => Ok(BooleanValue(true))
        "false" | "False" | "FALSE" | "0" => Ok(BooleanValue(false))
        _ => Err("Expected a default-format boolean")
      }
  }
}
