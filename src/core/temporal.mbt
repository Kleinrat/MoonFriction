///|
/// Strict, dependency-free Table Schema v1 temporal normalization.
///
/// Supported default formats:
/// - date:      YYYY-MM-DD
/// - time:      hh:mm:ss with an optional fractional-second suffix
/// - datetime:  YYYY-MM-DDThh:mm:ss with an optional fractional-second suffix,
///              followed by Z or a ±HH:MM offset
/// - year:      YYYY
/// - yearmonth: YYYY-MM
///
/// Datetime values with a numeric offset are converted to UTC and rendered with
/// Z. Fractions are arbitrary-length digit strings with trailing zeroes removed.
/// `compare_temporal` compares the fixed-width second prefix separately from the
/// optional fraction, so values with and without fractions order correctly.
fn is_ascii_digit(raw : String, index : Int32) -> Bool {
  if index < 0 || index >= raw.length() {
    false
  } else {
    let code = raw.code_unit_at(index).to_int()
    code >= 48 && code <= 57
  }
}

///|
fn parse_digits(
  raw : String,
  start : Int32,
  count : Int32,
) -> Result[Int32, String] {
  if start < 0 || count <= 0 || start + count > raw.length() {
    return Err("Expected exactly " + count.to_string() + " digits")
  }
  let mut value = 0
  for index in start..<(start + count) {
    if !is_ascii_digit(raw, index) {
      return Err("Expected exactly " + count.to_string() + " ASCII digits")
    }
    value = value * 10 + (raw.code_unit_at(index).to_int() - 48)
  }
  Ok(value)
}

///|
fn expect_char(raw : String, index : Int32, expected : Char) -> Bool {
  index >= 0 &&
  index < raw.length() &&
  raw.code_unit_at(index).to_int() == expected.to_int()
}

///|
fn is_leap_year(year : Int32) -> Bool {
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
}

///|
fn days_in_month(year : Int32, month : Int32) -> Int32 {
  match month {
    1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
    4 | 6 | 9 | 11 => 30
    2 => if is_leap_year(year) { 29 } else { 28 }
    _ => 0
  }
}

///|
fn valid_date(year : Int32, month : Int32, day : Int32) -> Bool {
  year >= 1 &&
  year <= 9999 &&
  month >= 1 &&
  month <= 12 &&
  day >= 1 &&
  day <= days_in_month(year, month)
}

///|
fn parse_date_at(
  raw : String,
  start : Int32,
) -> Result[(Int32, Int32, Int32), String] {
  if start < 0 || start + 10 > raw.length() {
    return Err("Expected date as YYYY-MM-DD")
  }
  if !expect_char(raw, start + 4, '-') || !expect_char(raw, start + 7, '-') {
    return Err("Expected date as YYYY-MM-DD")
  }
  let year = match parse_digits(raw, start, 4) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let month = match parse_digits(raw, start + 5, 2) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let day = match parse_digits(raw, start + 8, 2) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if !valid_date(year, month, day) {
    return Err("Invalid calendar date")
  }
  Ok((year, month, day))
}

///|
fn trim_fraction(raw : String, start : Int32, end : Int32) -> String {
  let mut last = end
  while last > start && raw.code_unit_at(last - 1).to_int() == 48 {
    last = last - 1
  }
  if last == start {
    ""
  } else {
    raw[start:last].to_owned()
  }
}

///|
fn parse_time_at(
  raw : String,
  start : Int32,
) -> Result[(Int32, Int32, Int32, String, Int32), String] {
  if start < 0 || start + 8 > raw.length() {
    return Err("Expected time as hh:mm:ss")
  }
  if !expect_char(raw, start + 2, ':') || !expect_char(raw, start + 5, ':') {
    return Err("Expected time as hh:mm:ss")
  }
  let hour = match parse_digits(raw, start, 2) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let minute = match parse_digits(raw, start + 3, 2) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let second = match parse_digits(raw, start + 6, 2) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if hour > 23 || minute > 59 || second > 59 {
    return Err("Invalid clock time")
  }
  let mut end = start + 8
  let mut fraction = ""
  if end < raw.length() && raw.code_unit_at(end).to_int() == 46 { // .
    let fraction_start = end + 1
    let mut fraction_end = fraction_start
    while fraction_end < raw.length() && is_ascii_digit(raw, fraction_end) {
      fraction_end = fraction_end + 1
    }
    if fraction_end == fraction_start {
      return Err("Expected fractional digits after .")
    }
    fraction = trim_fraction(raw, fraction_start, fraction_end)
    end = fraction_end
  }
  Ok((hour, minute, second, fraction, end))
}

///|
fn pad2(value : Int32) -> String {
  if value < 10 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn pad4(value : Int32) -> String {
  if value < 10 {
    "000" + value.to_string()
  } else if value < 100 {
    "00" + value.to_string()
  } else if value < 1000 {
    "0" + value.to_string()
  } else {
    value.to_string()
  }
}

///|
fn format_date(year : Int32, month : Int32, day : Int32) -> String {
  pad4(year) + "-" + pad2(month) + "-" + pad2(day)
}

///|
fn format_time(hour : Int32, minute : Int32, second : Int32) -> String {
  pad2(hour) + ":" + pad2(minute) + ":" + pad2(second)
}

///|
fn format_time_fraction(
  hour : Int32,
  minute : Int32,
  second : Int32,
  fraction : String,
) -> String {
  if fraction == "" {
    format_time(hour, minute, second)
  } else {
    format_time(hour, minute, second) + "." + fraction
  }
}

///|
fn shift_date(
  year : Int32,
  month : Int32,
  day : Int32,
  delta : Int32,
) -> Result[(Int32, Int32, Int32), String] {
  let mut year = year
  let mut month = month
  let mut day = day
  if delta == -1 {
    if day > 1 {
      day = day - 1
    } else if month == 1 {
      year = year - 1
      month = 12
      day = 31
    } else {
      month = month - 1
      day = days_in_month(year, month)
    }
  } else if delta == 1 {
    if day < days_in_month(year, month) {
      day = day + 1
    } else if month == 12 {
      year = year + 1
      month = 1
      day = 1
    } else {
      month = month + 1
      day = 1
    }
  } else {
    return Err("Internal date shift supports one day only")
  }
  if year < 1 || year > 9999 {
    return Err("Datetime normalization leaves the supported year range")
  }
  Ok((year, month, day))
}

///|
fn parse_offset_at(raw : String, start : Int32) -> Result[Int32, String] {
  if start >= raw.length() {
    return Err("Expected timezone designator Z or ±HH:MM")
  }
  let code = raw.code_unit_at(start).to_int()
  if code == 90 { // Z
    if start + 1 != raw.length() {
      return Err("Unexpected characters after Z")
    }
    return Ok(0)
  }
  if code != 43 && code != 45 { // + or -
    return Err("Expected timezone designator Z or ±HH:MM")
  }
  if start + 6 != raw.length() || !expect_char(raw, start + 3, ':') {
    return Err("Expected numeric offset as ±HH:MM")
  }
  let hour = match parse_digits(raw, start + 1, 2) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let minute = match parse_digits(raw, start + 4, 2) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  if hour > 23 || minute > 59 {
    return Err("Invalid timezone offset")
  }
  let seconds = hour * 3600 + minute * 60
  if code == 45 {
    Ok(-seconds)
  } else {
    Ok(seconds)
  }
}

///|
/// Normalize one Table Schema v1 default-format temporal value.
/// Returns Err for unsupported type names, malformed formats, impossible
/// calendar dates/clocks and out-of-range results of offset normalization.
pub fn normalize_temporal(
  type_name : String,
  raw : String,
) -> Result[String, String] {
  match type_name {
    "date" => {
      if raw.length() != 10 {
        return Err("Expected date as YYYY-MM-DD")
      }
      let (year, month, day) = match parse_date_at(raw, 0) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      Ok(format_date(year, month, day))
    }
    "time" => {
      let (hour, minute, second, fraction, end) = match parse_time_at(raw, 0) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      if end != raw.length() {
        return Err("Unexpected characters after time")
      }
      Ok(format_time_fraction(hour, minute, second, fraction))
    }
    "datetime" => {
      if raw.length() < 20 || !expect_char(raw, 10, 'T') {
        return Err("Expected datetime as YYYY-MM-DDThh:mm:ssZ or ±HH:MM")
      }
      let (year, month, day) = match parse_date_at(raw, 0) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      let (hour, minute, second, fraction, time_end) = match
        parse_time_at(raw, 11) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      let offset = match parse_offset_at(raw, time_end) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      let mut total = hour * 3600 + minute * 60 + second - offset
      let mut date = (year, month, day)
      while total < 0 {
        total = total + 86400
        date = match shift_date(date.0, date.1, date.2, -1) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
      }
      while total >= 86400 {
        total = total - 86400
        date = match shift_date(date.0, date.1, date.2, 1) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
      }
      let hour = total / 3600
      let minute = total % 3600 / 60
      let second = total % 60
      Ok(
        format_date(date.0, date.1, date.2) +
        "T" +
        format_time_fraction(hour, minute, second, fraction) +
        "Z",
      )
    }
    "year" => {
      if raw.length() != 4 {
        return Err("Expected year as YYYY")
      }
      let year = match parse_digits(raw, 0, 4) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      if year < 1 {
        return Err("Year 0000 is outside the supported calendar")
      }
      Ok(pad4(year))
    }
    "yearmonth" => {
      if raw.length() != 7 || !expect_char(raw, 4, '-') {
        return Err("Expected year-month as YYYY-MM")
      }
      let year = match parse_digits(raw, 0, 4) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      let month = match parse_digits(raw, 5, 2) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      if year < 1 || month < 1 || month > 12 {
        return Err("Invalid year-month")
      }
      Ok(pad4(year) + "-" + pad2(month))
    }
    _ => Err("Unsupported temporal type: " + type_name)
  }
}

///|
fn compare_prefix(left : String, right : String, limit : Int32) -> Int32 {
  let mut index = 0
  while index < limit {
    let a = left.code_unit_at(index).to_int()
    let b = right.code_unit_at(index).to_int()
    if a < b {
      return -1
    }
    if a > b {
      return 1
    }
    index = index + 1
  }
  0
}

///|
fn fraction_at(value : String, base_length : Int32, end : Int32) -> String {
  if value.length() > base_length &&
    value.code_unit_at(base_length).to_int() == 46 {
    value[base_length + 1:end].to_owned()
  } else {
    ""
  }
}

///|
fn compare_fraction(left : String, right : String) -> Int32 {
  if left == right {
    0
  } else if left == "" {
    -1
  } else if right == "" {
    1
  } else {
    compare_strings(left, right)
  }
}

///|
fn compare_with_fraction(
  left : String,
  right : String,
  base_length : Int32,
  left_end : Int32,
  right_end : Int32,
) -> Int32 {
  let base = compare_prefix(left, right, base_length)
  if base != 0 {
    base
  } else {
    compare_fraction(
      fraction_at(left, base_length, left_end),
      fraction_at(right, base_length, right_end),
    )
  }
}

///|
fn compare_strings(left : String, right : String) -> Int32 {
  let limit = if left.length() < right.length() {
    left.length()
  } else {
    right.length()
  }
  let mut index = 0
  while index < limit {
    let a = left.code_unit_at(index).to_int()
    let b = right.code_unit_at(index).to_int()
    if a < b {
      return -1
    }
    if a > b {
      return 1
    }
    index = index + 1
  }
  if left.length() < right.length() {
    -1
  } else if left.length() > right.length() {
    1
  } else {
    0
  }
}

///|
/// Compare two values that were already returned by `normalize_temporal`.
/// Date/year/yearmonth use fixed-width lexicographic order; time/datetime compare
/// their fixed-width second prefix first and then the optional fraction.
pub fn compare_temporal(
  type_name : String,
  left : String,
  right : String,
) -> Int32 {
  match type_name {
    "time" =>
      compare_with_fraction(left, right, 8, left.length(), right.length())
    "datetime" =>
      compare_with_fraction(
        left,
        right,
        19,
        left.length() - 1,
        right.length() - 1,
      )
    "date" | "year" | "yearmonth" => compare_strings(left, right)
    _ => compare_strings(left, right)
  }
}

///|
fn temporal_kind(kind : FieldType) -> Bool {
  kind is (Date | Time | DateTime | Year | YearMonth)
}

///|
fn temporal_bound(
  constraints : Json,
  key : String,
  kind : FieldType,
  format : String,
  resource : String,
  field_name : String,
  errors : Array[Diagnostic],
) -> String? {
  let value = prop(constraints, key)
  if value is Null {
    return None
  }
  let parsed = match value {
    String(raw) =>
      // Standard bound literals use the same format as data. Also accept
      // canonical literals so a descriptor can change its wire format safely.
      match normalize_temporal_format(kind_label(kind), raw, format) {
        Ok(value) => Ok(TemporalValue(value))
        Err(_) => cast_json_cell(value, kind, [])
      }
    _ => cast_json_cell(value, kind, [])
  }
  if parsed is Ok(TemporalValue(normalized)) {
    Some(normalized)
  } else {
    errors.push(
      issue("descriptor", resource, 0, field_name, "Invalid temporal " + key),
    )
    None
  }
}
