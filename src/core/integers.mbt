///|
fn cast_integer(raw : String) -> Result[Cell, String] {
  let signed = raw.has_prefix("-") || raw.has_prefix("+")
  let start = if signed { 1 } else { 0 }
  if !ascii_digits(raw, start) {
    return Err("Expected a decimal integer")
  }
  let cleaned = if raw.has_prefix("+") { raw[1:].to_owned() } else { raw }
  let value = @string.parse_int64(cleaned) catch {
    _ => return Ok(BigIntegerValue(@bigint.BigInt::from_string(cleaned)))
  }
  Ok(IntegerValue(value))
}

///|
fn logical_integer(cell : Cell) -> @bigint.BigInt? {
  match cell {
    IntegerValue(value) => Some(@bigint.BigInt::from_int64(value))
    BigIntegerValue(value) => Some(value)
    _ => None
  }
}

///|
fn big_integer_json(value : @bigint.BigInt) -> Json {
  // The formatter reads repr before the binary64 placeholder.
  Json::number(0.0, repr=value.to_string())
}

///|
fn integer_bound(
  constraints : Json,
  key : String,
  resource : String,
  name : String,
  errors : Array[Diagnostic],
) -> @bigint.BigInt? {
  let value = prop(constraints, key)
  if value is Null {
    return None
  }
  if cast_json_cell(value, Integer, []) is Ok(cell) &&
    logical_integer(cell) is Some(value) {
    Some(value)
  } else {
    errors.push(
      issue("descriptor", resource, 0, name, key + " must be an integer"),
    )
    None
  }
}

///|
fn cast_json_integer_text(raw : String) -> Result[Cell, String] {
  if cast_integer(raw) is Ok(value) {
    return Ok(value)
  }
  if !decimal_syntax(raw) {
    return Err("JSON number is not an integer")
  }
  let exact = decimal_value(raw)
  if exact.exponent.compare_int(0) < 0 {
    return Err("JSON number is not an integer")
  }
  if exact.exponent.compare_int(1000000) > 0 {
    return Err("JSON integer expands beyond the supported literal size")
  }
  let prefix = if exact.negative { "-" } else { "" }
  cast_integer(prefix + exact.digits + "0".repeat(exact.exponent.to_int()))
}
