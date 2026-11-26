///|
/// Parsed components for one custom temporal format. The parser only runs
/// after supports_temporal_format, so required components are known present.
priv struct ParsedTemporal {
  mut year : Int32
  mut month : Int32
  mut day : Int32
  mut hour : Int32
  mut minute : Int32
  mut second : Int32
  mut fraction : String
  mut offset : String?
}

///|
fn empty_parsed_temporal() -> ParsedTemporal {
  {
    year: 0,
    month: 0,
    day: 0,
    hour: 0,
    minute: 0,
    second: 0,
    fraction: "",
    offset: None,
  }
}

///|
fn expand_two_digit_year(year : Int32) -> Int32 {
  // POSIX strptime %y convention: 69..99 -> 1969..1999, 00..68 -> 2000..2068.
  if year >= 69 {
    1900 + year
  } else {
    2000 + year
  }
}

///|
fn parse_fraction_token(
  raw : String,
  start : Int32,
) -> Result[(String, Int32), String] {
  if start >= raw.length() || !is_ascii_digit(raw, start) {
    return Err("Expected 1-6 fractional digits for %f")
  }
  let mut end = start
  while end < raw.length() && end - start < 6 && is_ascii_digit(raw, end) {
    end = end + 1
  }
  Ok((trim_fraction(raw, start, end), end - start))
}

///|
fn parse_offset_token(
  raw : String,
  start : Int32,
) -> Result[(String, Int32), String] {
  if start >= raw.length() {
    return Err("Expected %z offset")
  }
  let code = raw.code_unit_at(start).to_int()
  if code == 90 { // Z
    return Ok(("Z", 1))
  }
  if code != 43 && code != 45 {
    return Err("Expected %z as Z, ±HH:MM or ±HHMM")
  }
  let mut consumed = 0
  let mut hour = 0
  let mut minute = 0
  if start + 6 <= raw.length() && expect_char(raw, start + 3, ':') {
    hour = match parse_digits(raw, start + 1, 2) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    minute = match parse_digits(raw, start + 4, 2) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    consumed = 6
  } else if start + 5 <= raw.length() {
    hour = match parse_digits(raw, start + 1, 2) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    minute = match parse_digits(raw, start + 3, 2) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    consumed = 5
  } else {
    return Err("Expected %z as Z, ±HH:MM or ±HHMM")
  }
  if hour > 23 || minute > 59 {
    return Err("Invalid %z offset")
  }
  let sign = if code == 45 { "-" } else { "+" }
  Ok((sign + pad2(hour) + ":" + pad2(minute), consumed))
}

///|
fn parse_with_pattern(
  raw : String,
  format : String,
) -> Result[ParsedTemporal, String] {
  let parts = empty_parsed_temporal()
  let mut format_index = 0
  let mut raw_index = 0
  while format_index < format.length() {
    let format_code = format.code_unit_at(format_index).to_int()
    if format_code == 37 { // %
      if format_index + 1 >= format.length() {
        return Err("Trailing % in temporal format")
      }
      let directive = format.code_unit_at(format_index + 1).to_int()
      format_index = format_index + 2
      match directive {
        89 => { // %Y
          if raw_index + 4 > raw.length() {
            return Err("Expected four-digit year for %Y")
          }
          parts.year = match parse_digits(raw, raw_index, 4) {
            Ok(value) => value
            Err(message) => return Err(message)
          }
          raw_index = raw_index + 4
        }
        121 => { // %y
          if raw_index + 2 > raw.length() {
            return Err("Expected two-digit year for %y")
          }
          let short = match parse_digits(raw, raw_index, 2) {
            Ok(value) => value
            Err(message) => return Err(message)
          }
          parts.year = expand_two_digit_year(short)
          raw_index = raw_index + 2
        }
        109 => { // %m
          parts.month = match parse_digits(raw, raw_index, 2) {
            Ok(value) => value
            Err(message) => return Err(message)
          }
          raw_index = raw_index + 2
        }
        100 => { // %d
          parts.day = match parse_digits(raw, raw_index, 2) {
            Ok(value) => value
            Err(message) => return Err(message)
          }
          raw_index = raw_index + 2
        }
        72 => { // %H
          parts.hour = match parse_digits(raw, raw_index, 2) {
            Ok(value) => value
            Err(message) => return Err(message)
          }
          raw_index = raw_index + 2
        }
        77 => { // %M
          parts.minute = match parse_digits(raw, raw_index, 2) {
            Ok(value) => value
            Err(message) => return Err(message)
          }
          raw_index = raw_index + 2
        }
        83 => { // %S
          parts.second = match parse_digits(raw, raw_index, 2) {
            Ok(value) => value
            Err(message) => return Err(message)
          }
          raw_index = raw_index + 2
        }
        102 => { // %f
          let parsed = match parse_fraction_token(raw, raw_index) {
            Ok(value) => value
            Err(message) => return Err(message)
          }
          parts.fraction = parsed.0
          raw_index = raw_index + parsed.1
        }
        122 => { // %z
          let parsed = match parse_offset_token(raw, raw_index) {
            Ok(value) => value
            Err(message) => return Err(message)
          }
          parts.offset = Some(parsed.0)
          raw_index = raw_index + parsed.1
        }
        37 => { // %%
          if raw_index >= raw.length() ||
            raw.code_unit_at(raw_index).to_int() != 37 {
            return Err("Expected literal %")
          }
          raw_index = raw_index + 1
        }
        _ => return Err("Unsupported temporal directive")
      }
    } else {
      if raw_index >= raw.length() ||
        raw.code_unit_at(raw_index).to_int() != format_code {
        return Err("Literal format text does not match input")
      }
      raw_index = raw_index + 1
      format_index = format_index + 1
    }
  }
  if raw_index != raw.length() {
    return Err("Input has trailing characters not covered by format")
  }
  Ok(parts)
}

///|
fn canonical_from_parsed(
  type_name : String,
  parts : ParsedTemporal,
) -> Result[String, String] {
  match type_name {
    "date" =>
      normalize_temporal(
        "date",
        format_date(parts.year, parts.month, parts.day),
      )
    "time" =>
      normalize_temporal(
        "time",
        format_time_fraction(
          parts.hour,
          parts.minute,
          parts.second,
          parts.fraction,
        ),
      )
    "datetime" => {
      // A datetime pattern without %z is interpreted as UTC. This is our
      // explicit policy for otherwise timezone-less custom formats.
      let offset = match parts.offset {
        Some(value) => value
        None => "Z"
      }
      normalize_temporal(
        "datetime",
        format_date(parts.year, parts.month, parts.day) +
        "T" +
        format_time_fraction(
          parts.hour,
          parts.minute,
          parts.second,
          parts.fraction,
        ) +
        offset,
      )
    }
    _ => Err("Unsupported temporal type: " + type_name)
  }
}

///|
fn normalize_pattern(
  type_name : String,
  raw : String,
  format : String,
) -> Result[String, String] {
  let parts = match parse_with_pattern(raw, format) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  canonical_from_parsed(type_name, parts)
}

///|
fn supports_pattern(type_name : String, format : String) -> Bool {
  if format.length() == 0 {
    return false
  }
  let mut seen = 0
  let mut index = 0
  while index < format.length() {
    let code = format.code_unit_at(index).to_int()
    if code == 37 { // %
      if index + 1 >= format.length() {
        return false
      }
      let directive = format.code_unit_at(index + 1).to_int()
      let flag = match directive {
        89 | 121 => 1 // year: %Y or %y
        109 => 2 // month
        100 => 4 // day
        72 => 8 // hour
        77 => 16 // minute
        83 => 32 // second
        122 => 64 // timezone
        102 => 128 // fractional seconds
        37 => 0 // literal percent
        _ => return false
      }
      if flag != 0 {
        if flag == 128 && (seen & 32) == 0 {
          // Python %f belongs after the seconds component.
          return false
        }
        if (seen & flag) != 0 {
          return false
        }
        seen = seen | flag
      }
      index = index + 2
    } else {
      // Literal separators must be printable ASCII; non-ASCII literal text is
      // deliberately outside this small, predictable format subset.
      if code < 32 || code > 126 {
        return false
      }
      index = index + 1
    }
  }
  let has_date = (seen & 1) != 0 && (seen & 2) != 0 && (seen & 4) != 0
  let has_time = (seen & 8) != 0 && (seen & 16) != 0 && (seen & 32) != 0
  match type_name {
    "date" => has_date && (seen & (8 | 16 | 32 | 64 | 128)) == 0
    "time" => has_time && (seen & (1 | 2 | 4 | 64)) == 0
    "datetime" => has_date && has_time
    "year" | "yearmonth" => false
    _ => false
  }
}

///|
/// Whether a Table Schema temporal type supports a format in this module.
/// `default` is supported for all five types; `any` and strptime patterns are
/// supported only for date/time/datetime. year/yearmonth have no format options
/// in Table Schema v1.
pub fn supports_temporal_format(type_name : String, format : String) -> Bool {
  if format == "default" {
    match type_name {
      "date" | "time" | "datetime" | "year" | "yearmonth" => true
      _ => false
    }
  } else if format == "any" {
    match type_name {
      "date" | "time" | "datetime" => true
      _ => false
    }
  } else {
    supports_pattern(type_name, format)
  }
}

///|
fn normalize_any(type_name : String, raw : String) -> Result[String, String] {
  match type_name {
    "date" =>
      match normalize_temporal("date", raw) {
        Ok(value) => Ok(value)
        Err(_) => {
          for pattern in ["%Y/%m/%d", "%Y.%m.%d"] {
            match normalize_pattern("date", raw, pattern) {
              Ok(value) => return Ok(value)
              Err(_) => ()
            }
          }
          Err("No unambiguous supported date form matched")
        }
      }
    "time" => normalize_temporal("time", raw)
    "datetime" =>
      match normalize_temporal("datetime", raw) {
        Ok(value) => Ok(value)
        Err(_) =>
          // Space-separated ISO datetime is common; date-first forms only.
          match normalize_pattern("datetime", raw, "%Y-%m-%d %H:%M:%S.%f%z") {
            Ok(value) => Ok(value)
            Err(_) => normalize_pattern("datetime", raw, "%Y-%m-%d %H:%M:%S%z")
          }
      }
    _ => Err("Unsupported temporal type for any: " + type_name)
  }
}

///|
/// Normalize one Table Schema v1 temporal value with a supported format.
///
/// Supported strptime directives: %Y %y %m %d %H %M %S %f %z %%.
/// Literal printable ASCII separators are matched exactly. Unknown directives,
/// duplicate components and non-ASCII literal text are rejected. `%y` uses the
/// POSIX 69/68 pivot; `%f` accepts one to six fractional digits and trims trailing
/// zeroes. A datetime pattern without %z is interpreted as UTC.
/// `any` accepts only a small documented unambiguous set, never a guessed
/// day/month order.
pub fn normalize_temporal_format(
  type_name : String,
  raw : String,
  format : String,
) -> Result[String, String] {
  if !supports_temporal_format(type_name, format) {
    return Err("Unsupported temporal format: " + type_name + " / " + format)
  }
  if format == "default" {
    normalize_temporal(type_name, raw)
  } else if format == "any" {
    normalize_any(type_name, raw)
  } else {
    normalize_pattern(type_name, raw, format)
  }
}
