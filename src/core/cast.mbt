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
/// Explicit bounded subset: finite numbers and signed 64-bit integers.
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
    Text => Ok(TextValue(raw))
    Integer => {
      let start = if raw.has_prefix("-") || raw.has_prefix("+") { 1 } else { 0 }
      if !ascii_digits(raw, start) {
        return Err("Expected a decimal integer")
      }
      let value = @string.parse_int64(raw) catch {
        _ => return Err("Integer exceeds signed 64-bit range")
      }
      Ok(IntegerValue(value))
    }
    Number => {
      if !decimal_syntax(raw) {
        return Err("Expected a finite decimal number")
      }
      let value = @string.parse_double(raw) catch {
        _ => return Err("Number cannot be represented")
      }
      if !value.is_finite() {
        return Err("Non-finite numbers are outside the supported subset")
      }
      Ok(NumberValue(value))
    }
    Boolean =>
      match raw {
        "true" | "True" | "TRUE" | "1" => Ok(BooleanValue(true))
        "false" | "False" | "FALSE" | "0" => Ok(BooleanValue(false))
        _ => Err("Expected a default-format boolean")
      }
  }
}
