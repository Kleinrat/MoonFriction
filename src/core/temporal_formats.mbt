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
  mut offset : (Int32, Int32)
  mut ordinal : Int32
  mut iso_year : Int32
  mut week : Int32
  mut week_kind : Int32
  mut weekday : Int32
  mut meridiem : Int32
  mut twelve_hour : Bool
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
    offset: (0, 0),
    ordinal: 0,
    iso_year: 0,
    week: -1,
    week_kind: 0,
    weekday: 0,
    meridiem: -1,
    twelve_hour: false,
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
fn fraction_microseconds(fraction : String) -> Int32 {
  let mut micros = 0
  for index in 0..<6 {
    micros *= 10
    if index < fraction.length() {
      micros += fraction.code_unit_at(index).to_int() - 48
    }
  }
  micros
}

///|
fn parse_offset_token(
  raw : String,
  start : Int32,
  extended~ : Bool,
) -> Result[((Int32, Int32), Int32), String] {
  if expect_char(raw, start, 'Z') {
    return Ok(((0, 0), 1))
  }
  guard expect_char(raw, start, '+') || expect_char(raw, start, '-') else {
    return Err("Expected %z as Z or a signed numeric offset")
  }
  let separated = expect_char(raw, start + 3, ':')
  let minute_start = start + (if separated { 4 } else { 3 })
  let hour = match parse_digits(raw, start + 1, 2) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let minute = match parse_digits(raw, minute_start, 2) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  let mut end = minute_start + 2
  let mut second = 0
  let mut micros = 0
  let second_start = if separated { end + 1 } else { end }
  let has_seconds = if separated {
    expect_char(raw, end, ':') && is_ascii_digit(raw, second_start)
  } else {
    is_ascii_digit(raw, second_start) && is_ascii_digit(raw, second_start + 1)
  }
  if extended && has_seconds {
    second = match parse_digits(raw, second_start, 2) {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    end = second_start + 2
    if expect_char(raw, end, '.') && is_ascii_digit(raw, end + 1) {
      let (fraction, consumed) = match parse_fraction_token(raw, end + 1) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      micros = fraction_microseconds(fraction)
      end += consumed + 1
    }
  }
  if hour > 23 || minute > 59 || second > 59 {
    return Err("Invalid %z offset")
  }
  let sign = if expect_char(raw, start, '-') { -1 } else { 1 }
  let seconds = hour * 3600 + minute * 60 + second
  Ok(((sign * seconds, sign * micros), end - start))
}

///|
let temporal_months : Array[String] = [
  "january", "february", "march", "april", "may", "june", "july", "august", "september",
  "october", "november", "december",
]

///|
let temporal_weekdays : Array[String] = [
  "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
]

///|
fn match_temporal_name(
  raw : String,
  start : Int32,
  words : Array[String],
  short : Bool,
) -> Result[(Int32, Int32), String] {
  for index, word in words {
    let length = if short { 3 } else { word.length() }
    if start + length <= raw.length() &&
      raw[start:start + length].to_owned().to_lower() ==
      word[:length].to_owned() {
      return Ok((index + 1, length))
    }
  }
  Err("Expected a date or time name in the C locale")
}

///|
fn temporal_space(code : Int32) -> Bool {
  code == 32 || (code >= 9 && code <= 13)
}

///|
/// Expand C-locale formats without hiding literal %% sequences.
fn expand_temporal_pattern(raw : String) -> String {
  let out = StringBuilder()
  let mut index = 0
  while index < raw.length() {
    if expect_char(raw, index, '%') && index + 1 < raw.length() {
      let expanded = match raw.code_unit_at(index + 1).to_int() {
        99 => "%a %b %d %H:%M:%S %Y" // %c
        120 | 68 => "%m/%d/%y" // %x, %D
        88 | 84 => "%H:%M:%S" // %X, %T
        70 => "%Y-%m-%d" // %F
        82 => "%H:%M" // %R
        114 => "%I:%M:%S %p" // %r
        110 | 116 => " " // %n, %t
        _ => raw[index:index + 2].to_owned()
      }
      out.write_string(expanded)
      index += 2
    } else {
      out.write_string(raw[index:index + 1].to_owned())
      index += 1
    }
  }
  out.to_string()
}

///|
fn parse_with_pattern(
  raw : String,
  format : String,
  extended_offset~ : Bool = true,
) -> Result[ParsedTemporal, String] {
  let parts = empty_parsed_temporal()
  let mut format_index = 0
  let mut raw_index = 0
  while format_index < format.length() {
    let format_code = format.code_unit_at(format_index).to_int()
    if format_code != 37 {
      if raw_index >= raw.length() {
        return Err("Missing input for format")
      }
      if temporal_space(format_code) {
        if !temporal_space(raw.code_unit_at(raw_index).to_int()) {
          return Err("Expected whitespace")
        }
        while raw_index < raw.length() &&
              temporal_space(raw.code_unit_at(raw_index).to_int()) {
          raw_index += 1
        }
        while format_index < format.length() &&
              temporal_space(format.code_unit_at(format_index).to_int()) {
          format_index += 1
        }
      } else {
        if raw.code_unit_at(raw_index).to_int() != format_code {
          return Err("Literal format text does not match input")
        }
        raw_index += 1
        format_index += 1
      }
      continue
    }
    if format_index + 1 >= format.length() {
      return Err("Trailing % in temporal format")
    }
    let directive = format.code_unit_at(format_index + 1).to_int()
    format_index += 2
    match directive {
      37 => { // %%
        if !expect_char(raw, raw_index, '%') {
          return Err("Expected literal %")
        }
        raw_index += 1
      }
      102 => { // %f
        let (fraction, consumed) = match parse_fraction_token(raw, raw_index) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        parts.fraction = fraction
        raw_index += consumed
      }
      122 => { // %z
        let (offset, consumed) = match
          parse_offset_token(raw, raw_index, extended=extended_offset) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        parts.offset = offset
        raw_index += consumed
      }
      90 => { // %Z
        if raw_index + 3 > raw.length() ||
          !["UTC", "GMT"].contains(
            raw[raw_index:raw_index + 3].to_owned().to_upper(),
          ) {
          return Err("Expected UTC or GMT for %Z")
        }
        raw_index += 3
      }
      98 | 66 | 104 | 97 | 65 | 112 => { // %b %B %h %a %A %p
        let words = match directive {
          98 | 66 | 104 => temporal_months
          97 | 65 => temporal_weekdays
          _ => ["am", "pm"]
        }
        let short = directive == 98 || directive == 104 || directive == 97
        let (value, consumed) = match
          match_temporal_name(raw, raw_index, words, short) {
          Ok(parsed) => parsed
          Err(message) => return Err(message)
        }
        match directive {
          98 | 66 | 104 => parts.month = value
          97 | 65 => parts.weekday = value
          _ => parts.meridiem = value - 1
        }
        raw_index += consumed
      }
      _ => {
        let (minimum, maximum) = match directive {
          89 | 71 => (4, 4) // %Y %G
          121 => (2, 2) // %y
          106 => (1, 3) // %j
          117 | 119 => (1, 1) // %u %w
          _ => (1, 2)
        }
        let start = if (directive == 100 || directive == 101) &&
          expect_char(raw, raw_index, ' ') {
          raw_index + 1
        } else {
          raw_index
        }
        let mut end = start
        while end - start < maximum && is_ascii_digit(raw, end) {
          end += 1
        }
        let width = end - start
        if width < minimum {
          return Err("Expected numeric temporal field")
        }
        let value = match parse_digits(raw, start, width) {
          Ok(value) => value
          Err(message) => return Err(message)
        }
        match directive {
          89 => parts.year = value
          121 => parts.year = expand_two_digit_year(value)
          109 => parts.month = value
          100 | 101 => parts.day = value
          72 | 73 => {
            parts.hour = value
            parts.twelve_hour = directive == 73
          }
          77 => parts.minute = value
          83 => parts.second = value
          106 => {
            if value == 0 {
              return Err("Day of year starts at 1")
            }
            parts.ordinal = value
          }
          71 => parts.iso_year = value
          86 | 85 | 87 => {
            parts.week_kind = directive
            parts.week = value
          }
          117 | 119 => {
            if (directive == 117 && (value == 0 || value > 7)) ||
              (directive == 119 && value > 6) {
              return Err("Invalid weekday")
            }
            parts.weekday = if value == 0 { 7 } else { value }
          }
          _ => return Err("Unsupported temporal directive")
        }
        raw_index = end
      }
    }
  }
  if raw_index != raw.length() {
    return Err("Input has trailing characters not covered by format")
  }
  if parts.twelve_hour {
    if parts.hour < 1 || parts.hour > 12 {
      return Err("Invalid 12-hour clock value")
    }
    parts.hour = parts.hour % 12 + 12 * parts.meridiem
  }
  Ok(parts)
}

///|
fn year_length(year : Int32) -> Int32 {
  if is_leap_year(year) {
    366
  } else {
    365
  }
}

///|
fn jan_first_weekday(year : Int32) -> Int32 {
  let previous = year - 1
  (previous + previous / 4 - previous / 100 + previous / 400) % 7 + 1
}

///|
fn date_from_ordinal(year : Int32, ordinal : Int32) -> (Int32, Int32, Int32) {
  let mut year = year
  let mut day = ordinal
  if day < 1 {
    year -= 1
    day += year_length(year)
  } else if day > year_length(year) {
    day -= year_length(year)
    year += 1
  }
  let mut month = 1
  while month < 12 && day > days_in_month(year, month) {
    day -= days_in_month(year, month)
    month += 1
  }
  (year, month, day)
}

///|
fn parsed_calendar_date(
  parts : ParsedTemporal,
) -> Result[(Int32, Int32, Int32), String] {
  let year = if parts.week_kind == 86 { parts.iso_year } else { parts.year }
  if year < 1 || year > 9999 {
    return Err("Invalid calendar year")
  }
  let first = jan_first_weekday(year)
  let (y, m, d) = if parts.week_kind == 86 { // ISO week one contains Jan 4.
    let has_week_53 = first == 4 || (first == 3 && is_leap_year(year))
    if parts.week < 1 || parts.week > (if has_week_53 { 53 } else { 52 }) {
      return Err("Invalid ISO week number")
    }
    let monday = 4 - (first + 2) % 7
    date_from_ordinal(year, monday + (parts.week - 1) * 7 + parts.weekday - 1)
  } else if parts.week_kind != 0 {
    if parts.week > 53 {
      return Err("Invalid week number")
    }
    let start = if parts.week_kind == 85 { 7 } else { 1 }
    let first_start = 1 + (start - first + 7) % 7
    let day_offset = (parts.weekday - start + 7) % 7
    let ordinal = first_start + (parts.week - 1) * 7 + day_offset
    if ordinal < 1 || ordinal > year_length(year) {
      return Err("Week does not contain this weekday in the declared year")
    }
    date_from_ordinal(year, ordinal)
  } else if parts.ordinal != 0 {
    if parts.ordinal > year_length(year) {
      return Err("Invalid day of year")
    }
    date_from_ordinal(year, parts.ordinal)
  } else {
    (year, parts.month, parts.day)
  }
  if !valid_date(y, m, d) {
    return Err("Invalid calendar date")
  }
  // Python treats a weekday written next to a calendar date as descriptive.
  Ok((y, m, d))
}

///|
fn canonical_from_parsed(
  type_name : String,
  parts : ParsedTemporal,
) -> Result[String, String] {
  match type_name {
    "date" =>
      parsed_calendar_date(parts).map(date => {
        format_date(date.0, date.1, date.2)
      })
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
      if parts.hour > 23 || parts.minute > 59 || parts.second > 59 {
        return Err("Invalid clock time")
      }
      let date = match parsed_calendar_date(parts) {
        Ok(date) => date
        Err(message) => return Err(message)
      }
      // Apply the fractional offset in integer microseconds. A negative
      // remainder borrows one second before normalizing the UTC date.
      let (offset_seconds, offset_micros) = parts.offset
      let difference = fraction_microseconds(parts.fraction) - offset_micros
      let mut local_seconds = parts.hour * 3600 +
        parts.minute * 60 +
        parts.second
      let micros = if difference < 0 {
        local_seconds -= 1
        difference + 1000000
      } else if difference >= 1000000 {
        local_seconds += 1
        difference - 1000000
      } else {
        difference
      }
      let digits = (1000000 + micros).to_string()
      datetime_to_utc(
        date,
        local_seconds,
        trim_fraction(digits, 1, 7),
        offset_seconds,
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
  let expanded = expand_temporal_pattern(format)
  let parts = match parse_with_pattern(raw, expanded) {
    Ok(value) => value
    Err(message) if expanded.contains("%z") =>
      // A numeric literal after %z can look like optional offset seconds.
      match parse_with_pattern(raw, expanded, extended_offset=false) {
        Ok(value) => value
        Err(_) => return Err(message)
      }
    Err(message) => return Err(message)
  }
  canonical_from_parsed(type_name, parts)
}

///|
fn supports_pattern(type_name : String, pattern : String) -> Bool {
  let format = expand_temporal_pattern(pattern)
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
        109 | 98 | 66 | 104 => 2 // month
        100 | 101 => 4 // day
        72 => 8 // hour
        77 => 16 // minute
        83 => 32 // second
        122 | 90 => 64 // timezone
        102 => 128 // fractional seconds
        73 => 256 // 12-hour clock
        112 => 512 // AM or PM
        106 => 1024 // ordinal day
        71 => 2048 // ISO week-year
        86 => 4096 // ISO week
        85 | 87 => 8192 // Sunday/Monday-based week
        97 | 65 | 117 | 119 => 16384 // weekday
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
      if !temporal_space(code) && (code < 32 || code > 126) {
        return false
      }
      index = index + 1
    }
  }
  let calendar = seen & (1 | 2 | 4 | 1024 | 2048 | 4096 | 8192)
  let weekday = (seen & 16384) != 0
  let has_date = match calendar {
    7 | 1025 => true
    6144 | 8193 => weekday
    _ => false
  }
  let clock = seen & (8 | 256 | 512)
  let has_time = (clock == 8 || clock == 768) && (seen & 16) != 0
  match type_name {
    "date" => has_date && (seen & (8 | 16 | 32 | 64 | 128 | 256 | 512)) == 0
    "time" => has_time && calendar == 0 && !weekday && (seen & 64) == 0
    "datetime" => has_date && has_time
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
/// Supports calendar, ordinal, week-date, 12/24-hour and timezone patterns.
/// Formats use the C locale and %Z accepts UTC or GMT. Unknown directives,
/// duplicate components and non-ASCII literal text are rejected. `%y` uses the
/// POSIX 69/68 pivot; `%f` accepts one to six fractional digits and trims trailing
/// zeroes. %z accepts seconds and fractional seconds. A datetime pattern
/// without a zone is interpreted as UTC.
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
