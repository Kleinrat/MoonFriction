///|
#derive(Eq, Hash, Debug)
pub(all) struct ExactDecimal {
  negative : Bool
  digits : String
  exponent : @bigint.BigInt
}

///|
fn decimal_value(raw : String) -> ExactDecimal {
  let negative = raw.has_prefix("-")
  let start = if raw.has_prefix("-") || raw.has_prefix("+") { 1 } else { 0 }
  let mut dot = raw.length()
  let mut end = raw.length()
  for i = start; i < raw.length(); i = i + 1 {
    match raw.code_unit_at(i).to_int() {
      46 => dot = i
      69 | 101 => {
        end = i
        break
      }
      _ => ()
    }
  }
  let exponent = if end == raw.length() {
    @bigint.BigInt::from_int(0)
  } else {
    let exp_start = if raw.code_unit_at(end + 1).to_int() == 43 {
      end + 2
    } else {
      end + 1
    }
    @bigint.BigInt::from_string(raw.exact_view(start=exp_start).to_owned())
  }
  let fractional = if dot < end { end - dot - 1 } else { 0 }
  let digits = raw
    .exact_view(start~, end~)
    .to_owned()
    .replace_all(old=".", new="")
  let unpadded = digits.trim_start(chars="0").to_owned()
  if unpadded == "" {
    return {
      negative: false,
      digits: "0",
      exponent: @bigint.BigInt::from_int(0),
    }
  }
  let trimmed = unpadded.trim_end(chars="0").to_owned()
  {
    negative,
    digits: trimmed,
    exponent: exponent +
    @bigint.BigInt::from_int(unpadded.length() - trimmed.length() - fractional),
  }
}

///|
fn decimal_json(value : ExactDecimal) -> Json {
  let prefix = if value.negative { "-" } else { "" }
  let repr = if value.exponent.equal_int(0) {
    prefix + value.digits
  } else {
    prefix + value.digits + "e" + value.exponent.to_string()
  }
  let approx = @string.parse_double(repr) catch { _ => 0.0 }
  Json::number(approx, repr~)
}

///|
fn compare_decimal(left : ExactDecimal, right : ExactDecimal) -> Int32 {
  if left == right {
    return 0
  }
  if left.digits == "0" {
    return if right.negative { 1 } else { -1 }
  }
  if right.digits == "0" {
    return if left.negative { -1 } else { 1 }
  }
  if left.negative != right.negative {
    return if left.negative { -1 } else { 1 }
  }
  let a = left.exponent + @bigint.BigInt::from_int(left.digits.length())
  let b = right.exponent + @bigint.BigInt::from_int(right.digits.length())
  let order = if a == b {
    left.digits.compare(right.digits)
  } else {
    a.compare(b)
  }
  if left.negative {
    -order
  } else {
    order
  }
}

///|
fn cast_decimal(raw : String) -> Result[Cell, String] {
  let upper = raw.to_upper()
  if upper == "NAN" {
    return Ok(SpecialNumber("NaN"))
  }
  if upper == "INF" || upper == "+INF" {
    return Ok(SpecialNumber("INF"))
  }
  if upper == "-INF" {
    return Ok(SpecialNumber("-INF"))
  }
  if !decimal_syntax(raw) {
    return Err("Expected a decimal number")
  }
  let exact = decimal_value(raw)
  let number = @string.parse_double(raw) catch {
    _ => return Ok(ExactNumberValue(exact))
  }
  if !number.is_finite() ||
    decimal_value(Json::number(number).stringify()) != exact {
    Ok(ExactNumberValue(exact))
  } else {
    Ok(NumberValue(if number == 0.0 { 0.0 } else { number }))
  }
}

///|
fn decimal_from_double(value : Double) -> ExactDecimal {
  decimal_value(Json::number(value).stringify())
}

///|
fn logical_decimal(cell : Cell) -> ExactDecimal? {
  match cell {
    NumberValue(n) if n.is_finite() => Some(decimal_from_double(n))
    ExactNumberValue(n) => Some(n)
    _ => None
  }
}

///|
fn decimal_bound(
  constraints : Json,
  key : String,
  field : Field,
  resource : String,
  errors : Array[Diagnostic],
) -> ExactDecimal? {
  let value = prop(constraints, key)
  if value is Null {
    return None
  }
  if cast_field_json(value, field, []) is Ok(cell) &&
    logical_decimal(cell) is Some(exact) {
    Some(exact)
  } else {
    errors.push(
      issue(
        "descriptor",
        resource,
        0,
        field.name,
        key + " must be a finite decimal",
      ),
    )
    None
  }
}
