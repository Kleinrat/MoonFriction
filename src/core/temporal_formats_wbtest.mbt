///|
test "format support covers default, any and supported strptime directives" {
  for type_name in ["date", "time", "datetime", "year", "yearmonth"] {
    assert_true(supports_temporal_format(type_name, "default"))
  }
  assert_true(supports_temporal_format("date", "any"))
  assert_true(supports_temporal_format("time", "any"))
  assert_true(supports_temporal_format("datetime", "any"))
  assert_false(supports_temporal_format("year", "any"))
  assert_false(supports_temporal_format("yearmonth", "%Y-%m"))

  assert_true(supports_temporal_format("date", "%Y-%m-%d"))
  assert_true(supports_temporal_format("date", "%d/%m/%Y"))
  assert_true(supports_temporal_format("date", "%Y%m%d"))
  assert_true(supports_temporal_format("time", "%H:%M:%S"))
  assert_true(supports_temporal_format("datetime", "%Y-%m-%dT%H:%M:%S%z"))
  assert_true(supports_temporal_format("datetime", "%Y-%m-%d %H:%M:%S"))
  assert_true(supports_temporal_format("date", "%Y-%m-%d%%"))
  assert_true(supports_temporal_format("time", "%H:%M:%S.%f"))
  assert_true(supports_temporal_format("datetime", "%Y-%m-%dT%H:%M:%S.%f%z"))
}

///|
test "format support rejects unknown, duplicate, misplaced and non-ASCII patterns" {
  for
    format in [
      "%b", "%j", "%Y-%m-%d%", "%Y-%m-%d %H:%M", "%Y-%Y-%m-%d", "%Y-%m-%dT%H:%M:%S%z%z",
      "%Y-%m-%d%Q",
    ] {
    assert_false(supports_temporal_format("date", format))
  }
  assert_false(supports_temporal_format("date", "%Y-%m-%dT%H:%M:%S"))
  assert_false(supports_temporal_format("time", "%Y-%m-%d"))
  assert_false(supports_temporal_format("date", "%Y-%m-%d %z"))
  assert_false(supports_temporal_format("datetime", "%Y年%m月%d日"))
  assert_false(supports_temporal_format("date", ""))
  assert_false(supports_temporal_format("date", "%"))
  assert_false(supports_temporal_format("date", "%Y-%m-%d.%f"))
  assert_false(supports_temporal_format("time", "%f%H:%M:%S"))
  assert_false(supports_temporal_format("time", "%H:%M:%S.%f.%f"))
}

///|
test "custom date formats normalize through the default normalizer" {
  assert_eq(
    normalize_temporal_format("date", "31/12/2024", "%d/%m/%Y"),
    Ok("2024-12-31"),
  )
  assert_eq(
    normalize_temporal_format("date", "20241231", "%Y%m%d"),
    Ok("2024-12-31"),
  )
  assert_eq(
    normalize_temporal_format("date", "24-12-31", "%y-%m-%d"),
    Ok("2024-12-31"),
  )
  assert_eq(
    normalize_temporal_format("date", "2024-01-01%", "%Y-%m-%d%%"),
    Ok("2024-01-01"),
  )
  assert_true(
    normalize_temporal_format("date", "31/02/2024", "%d/%m/%Y") is Err(_),
  )
  assert_true(
    normalize_temporal_format("date", "2024-01-01", "%d/%m/%Y") is Err(_),
  )
}

///|
test "two-digit year uses the POSIX 69/68 pivot" {
  assert_eq(
    normalize_temporal_format("date", "69-01-01", "%y-%m-%d"),
    Ok("1969-01-01"),
  )
  assert_eq(
    normalize_temporal_format("date", "68-12-31", "%y-%m-%d"),
    Ok("2068-12-31"),
  )
}

///|
test "custom time formats are strict and reject seconds outside clock" {
  assert_eq(
    normalize_temporal_format("time", "23-59-58", "%H-%M-%S"),
    Ok("23:59:58"),
  )
  assert_true(
    normalize_temporal_format("time", "24:00:00", "%H:%M:%S") is Err(_),
  )
  assert_true(normalize_temporal_format("time", "12:00", "%H:%M:%S") is Err(_))
}

///|
test "custom datetime offset formats normalize to UTC" {
  assert_eq(
    normalize_temporal_format(
      "datetime", "2024-01-01 01:30:00+01:30", "%Y-%m-%d %H:%M:%S%z",
    ),
    Ok("2024-01-01T00:00:00Z"),
  )
  assert_eq(
    normalize_temporal_format(
      "datetime", "2024-01-01T01:30:00+0130", "%Y-%m-%dT%H:%M:%S%z",
    ),
    Ok("2024-01-01T00:00:00Z"),
  )
  assert_eq(
    normalize_temporal_format(
      "datetime", "2024-01-01T00:00:00Z", "%Y-%m-%dT%H:%M:%S%z",
    ),
    Ok("2024-01-01T00:00:00Z"),
  )
  assert_eq(
    normalize_temporal_format(
      "datetime", "2024-01-01T00:00:00+0000", "%Y-%m-%dT%H:%M:%S%z",
    ),
    Ok("2024-01-01T00:00:00Z"),
  )
  assert_eq(
    normalize_temporal_format(
      "datetime", "2024-01-01 00:30:00-01:00", "%Y-%m-%d %H:%M:%S%z",
    ),
    Ok("2024-01-01T01:30:00Z"),
  )
  assert_eq(
    normalize_temporal_format(
      "datetime", "2024-03-01T00:30:00+01:00", "%Y-%m-%dT%H:%M:%S%z",
    ),
    Ok("2024-02-29T23:30:00Z"),
  )
  assert_eq(
    normalize_temporal_format(
      "datetime", "2024-01-01 00:00:00", "%Y-%m-%d %H:%M:%S",
    ),
    Ok("2024-01-01T00:00:00Z"),
  )
  assert_true(
    normalize_temporal_format(
      "datetime", "2024-01-01 00:00:00", "%Y-%m-%dT%H:%M:%S%z",
    )
    is Err(_),
  )
  assert_true(
    normalize_temporal_format(
      "datetime", "2024-01-01T00:00:00+24:00", "%Y-%m-%dT%H:%M:%S%z",
    )
    is Err(_),
  )
}

///|
test "strptime %f supports one to six digits with Python-style truncation" {
  assert_eq(
    normalize_temporal_format("time", "12:00:00.5", "%H:%M:%S.%f"),
    Ok("12:00:00.5"),
  )
  assert_eq(
    normalize_temporal_format("time", "12:00:00.500000", "%H:%M:%S.%f"),
    Ok("12:00:00.5"),
  )
  assert_eq(
    normalize_temporal_format("time", "12:00:00.000000", "%H:%M:%S.%f"),
    Ok("12:00:00"),
  )
  assert_eq(
    normalize_temporal_format("time", "12:00:00.000001", "%H:%M:%S.%f"),
    Ok("12:00:00.000001"),
  )
  assert_eq(
    normalize_temporal_format(
      "datetime", "2024-01-01T00:00:00.250000+01:00", "%Y-%m-%dT%H:%M:%S.%f%z",
    ),
    Ok("2023-12-31T23:00:00.25Z"),
  )
  assert_true(
    normalize_temporal_format("time", "12:00:00.1234567", "%H:%M:%S.%f")
    is Err(_),
  )
  assert_true(
    normalize_temporal_format("time", "12:00:00.", "%H:%M:%S.%f") is Err(_),
  )
  assert_true(
    normalize_temporal_format("time", "12:00:00.a", "%H:%M:%S.%f") is Err(_),
  )
}

///|
test "any accepts only documented unambiguous forms" {
  assert_eq(
    normalize_temporal_format("date", "2024-12-31", "any"),
    Ok("2024-12-31"),
  )
  assert_eq(
    normalize_temporal_format("date", "2024/12/31", "any"),
    Ok("2024-12-31"),
  )
  assert_eq(
    normalize_temporal_format("date", "2024.12.31", "any"),
    Ok("2024-12-31"),
  )
  assert_true(normalize_temporal_format("date", "31/12/2024", "any") is Err(_))
  assert_eq(
    normalize_temporal_format("time", "12:34:56", "any"),
    Ok("12:34:56"),
  )
  assert_eq(
    normalize_temporal_format("datetime", "2024-01-01 01:30:00+01:00", "any"),
    Ok("2024-01-01T00:30:00Z"),
  )
  assert_eq(
    normalize_temporal_format("datetime", "2024-01-01 01:30:00.25+01:00", "any"),
    Ok("2024-01-01T00:30:00.25Z"),
  )
}

///|
test "unsupported type and format combinations fail explicitly" {
  assert_true(normalize_temporal_format("year", "2024", "any") is Err(_))
  assert_true(normalize_temporal_format("date", "2024-01-01", "%b") is Err(_))
  assert_true(
    normalize_temporal_format("duration", "2024-01-01", "default") is Err(_),
  )
  assert_eq(normalize_temporal_format("year", "2024", "default"), Ok("2024"))
  assert_eq(
    normalize_temporal_format("yearmonth", "2024-01", "default"),
    Ok("2024-01"),
  )
}
