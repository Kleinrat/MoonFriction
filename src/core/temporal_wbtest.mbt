///|
test "date normalization validates leap years and calendar boundaries" {
  assert_eq(normalize_temporal("date", "2024-02-29"), Ok("2024-02-29"))
  assert_eq(normalize_temporal("date", "2000-02-29"), Ok("2000-02-29"))
  assert_true(normalize_temporal("date", "1900-02-29") is Err(_))
  assert_true(normalize_temporal("date", "2023-02-29") is Err(_))
  assert_true(normalize_temporal("date", "2024-04-31") is Err(_))
  assert_true(normalize_temporal("date", "2024-13-01") is Err(_))
  assert_true(normalize_temporal("date", "2024-00-01") is Err(_))
  assert_true(normalize_temporal("date", "2024-01-00") is Err(_))
  assert_true(normalize_temporal("date", "0000-01-01") is Err(_))
  assert_eq(normalize_temporal("date", "9999-12-31"), Ok("9999-12-31"))
  assert_eq(normalize_temporal("date", "0001-01-01"), Ok("0001-01-01"))
  assert_eq(normalize_temporal("date", "1900-02-28"), Ok("1900-02-28"))
}

///|
test "date format is strict and not trimmed" {
  for
    raw in [
      "2024-1-01", "2024-01-1", " 2024-01-01", "2024-01-01 ", "2024/01/01", "2024-01-01T00:00:00",
    ] {
    assert_true(normalize_temporal("date", raw) is Err(_))
  }
}

///|
test "time normalization supports fractions and strict 24-hour clock" {
  assert_eq(normalize_temporal("time", "00:00:00"), Ok("00:00:00"))
  assert_eq(normalize_temporal("time", "23:59:59"), Ok("23:59:59"))
  assert_eq(normalize_temporal("time", "12:00:00.0"), Ok("12:00:00"))
  assert_eq(normalize_temporal("time", "12:00:00.00"), Ok("12:00:00"))
  assert_eq(normalize_temporal("time", "12:00:00.500"), Ok("12:00:00.5"))
  assert_eq(normalize_temporal("time", "12:00:00.1200"), Ok("12:00:00.12"))
  assert_eq(
    normalize_temporal("time", "12:00:00.000001"),
    Ok("12:00:00.000001"),
  )
  assert_eq(
    normalize_temporal("time", "12:00:00.12345678901234567890"),
    Ok("12:00:00.1234567890123456789"),
  )
  for
    raw in [
      "24:00:00", "12:60:00", "12:00:60", "1:00:00", "12:0:00", "12:00", "12:00:00Z",
      "12:00:00.", "12:00:00.a", "12:00:00.1.2", " 12:00:00",
    ] {
    assert_true(normalize_temporal("time", raw) is Err(_))
  }
}

///|
test "datetime requires UTC designator or numeric offset and normalizes to UTC" {
  assert_eq(
    normalize_temporal("datetime", "2024-01-01T00:00:00Z"),
    Ok("2024-01-01T00:00:00Z"),
  )
  assert_eq(
    normalize_temporal("datetime", "2024-01-01T01:30:00+01:30"),
    Ok("2024-01-01T00:00:00Z"),
  )
  assert_eq(
    normalize_temporal("datetime", "2024-01-01T00:30:00-01:00"),
    Ok("2024-01-01T01:30:00Z"),
  )
  assert_eq(
    normalize_temporal("datetime", "2023-12-31T23:30:00+00:30"),
    Ok("2023-12-31T23:00:00Z"),
  )
  assert_eq(
    normalize_temporal("datetime", "2024-01-01T00:00:00+14:00"),
    Ok("2023-12-31T10:00:00Z"),
  )
  assert_eq(
    normalize_temporal("datetime", "2024-01-01T00:00:00-12:00"),
    Ok("2024-01-01T12:00:00Z"),
  )
  assert_eq(
    normalize_temporal("datetime", "2024-01-02T00:00:00+23:59"),
    Ok("2024-01-01T00:01:00Z"),
  )
  assert_eq(
    normalize_temporal("datetime", "2024-12-31T23:30:00-01:00"),
    Ok("2025-01-01T00:30:00Z"),
  )
}

///|
test "datetime fractions survive UTC offset normalization and zero trimming" {
  assert_eq(
    normalize_temporal("datetime", "2024-01-01T00:00:00.500Z"),
    Ok("2024-01-01T00:00:00.5Z"),
  )
  assert_eq(
    normalize_temporal("datetime", "2024-01-01T00:00:00.000Z"),
    Ok("2024-01-01T00:00:00Z"),
  )
  assert_eq(
    normalize_temporal("datetime", "2024-01-01T00:00:00.25+01:00"),
    Ok("2023-12-31T23:00:00.25Z"),
  )
  assert_eq(
    normalize_temporal("datetime", "2024-01-01T00:00:00.12345678901234567890Z"),
    Ok("2024-01-01T00:00:00.1234567890123456789Z"),
  )
}

///|
test "datetime offset normalization crosses leap-day and year boundaries" {
  assert_eq(
    normalize_temporal("datetime", "2024-03-01T00:30:00+01:00"),
    Ok("2024-02-29T23:30:00Z"),
  )
  assert_eq(
    normalize_temporal("datetime", "2023-03-01T00:30:00+01:00"),
    Ok("2023-02-28T23:30:00Z"),
  )
  assert_eq(
    normalize_temporal("datetime", "2024-01-01T00:30:00+01:00"),
    Ok("2023-12-31T23:30:00Z"),
  )
  assert_eq(
    normalize_temporal("datetime", "2023-12-31T23:30:00-01:00"),
    Ok("2024-01-01T00:30:00Z"),
  )
}

///|
test "datetime rejects missing zone, bad offsets, bad dates and bad clocks" {
  for
    raw in [
      "2024-01-01T00:00:00", "2024-01-01t00:00:00Z", "2024-01-01T00:00:00z", "2024-01-01T00:00:00+24:00",
      "2024-01-01T00:00:00+01:60", "2024-01-01T00:00:00+0100", "2024-01-01T00:00:00+01",
      "2024-02-30T00:00:00Z", "2024-01-01T24:00:00Z", "2024-01-01T00:00:60Z", "2024-01-01T00:00:00.Z",
      "2024-01-01T00:00:00.aZ",
    ] {
    assert_true(normalize_temporal("datetime", raw) is Err(_))
  }
  assert_true(
    normalize_temporal("datetime", "0001-01-01T00:00:00+01:00") is Err(_),
  )
  assert_true(
    normalize_temporal("datetime", "9999-12-31T23:59:59-01:00") is Err(_),
  )
}

///|
test "year and yearmonth use four-digit years and valid months" {
  assert_eq(normalize_temporal("year", "2024"), Ok("2024"))
  assert_eq(normalize_temporal("year", "9999"), Ok("9999"))
  assert_true(normalize_temporal("year", "0000") is Err(_))
  assert_true(normalize_temporal("year", "24") is Err(_))
  assert_eq(normalize_temporal("yearmonth", "2024-02"), Ok("2024-02"))
  assert_eq(normalize_temporal("yearmonth", "9999-12"), Ok("9999-12"))
  for raw in ["2024-00", "2024-13", "2024-1", "2024-02-01", "0000-01"] {
    assert_true(normalize_temporal("yearmonth", raw) is Err(_))
  }
}

///|
test "normalized datetime values compare chronologically" {
  let a = normalize_temporal("datetime", "2024-01-01T00:30:00+01:00").unwrap()
  let b = normalize_temporal("datetime", "2024-01-01T00:00:00Z").unwrap()
  assert_eq(a, "2023-12-31T23:30:00Z")
  assert_eq(compare_temporal("datetime", a, b), -1)
  assert_eq(compare_temporal("datetime", b, a), 1)
  assert_eq(compare_temporal("datetime", b, b), 0)
}

///|
test "fractional and non-fractional canonical values compare correctly" {
  let no_fraction = normalize_temporal("time", "12:00:00").unwrap()
  let small = normalize_temporal("time", "12:00:00.0001").unwrap()
  let tenth = normalize_temporal("time", "12:00:00.1").unwrap()
  assert_eq(compare_temporal("time", no_fraction, small), -1)
  assert_eq(compare_temporal("time", small, no_fraction), 1)
  assert_eq(
    compare_temporal(
      "time",
      tenth,
      normalize_temporal("time", "12:00:00.09").unwrap(),
    ),
    1,
  )
  assert_eq(compare_temporal("time", small, small), 0)
  let dt0 = normalize_temporal("datetime", "2024-01-01T00:00:00Z").unwrap()
  let dt1 = normalize_temporal("datetime", "2024-01-01T00:00:00.1Z").unwrap()
  assert_eq(compare_temporal("datetime", dt0, dt1), -1)
  assert_eq(compare_temporal("datetime", dt1, dt0), 1)
}

///|
test "compare_temporal works for all five canonical forms" {
  assert_eq(compare_temporal("date", "2024-01-01", "2024-01-02"), -1)
  assert_eq(compare_temporal("date", "2024-02-01", "2024-01-31"), 1)
  assert_eq(compare_temporal("time", "09:00:00", "10:00:00"), -1)
  assert_eq(compare_temporal("year", "1999", "2000"), -1)
  assert_eq(compare_temporal("yearmonth", "2024-02", "2024-10"), -1)
  assert_eq(compare_temporal("yearmonth", "2024-02", "2024-02"), 0)
}

///|
test "unsupported temporal types and unknown formats fail explicitly" {
  assert_true(normalize_temporal("any", "2024-01-01") is Err(_))
  assert_true(normalize_temporal("duration", "P1D") is Err(_))
}

///|
test "default datetime keeps known UTC leap seconds as distinct instants" {
  for
    raw in [
      "1990-12-31T23:59:60Z", "1990-12-31T15:59:60-08:00", "1991-01-01T00:59:60+01:00",
    ] {
    assert_eq(normalize_temporal("datetime", raw), Ok("1990-12-31T23:59:60Z"))
  }
  let late = normalize_temporal("datetime", "2016-12-31T23:59:60.123456789Z").unwrap()
  assert_eq(late, "2016-12-31T23:59:60.123456789Z")
  assert_eq(compare_temporal("datetime", "2016-12-31T23:59:59.999Z", late), -1)
  assert_eq(compare_temporal("datetime", late, "2017-01-01T00:00:00Z"), -1)
  for
    raw in [
      "2015-12-31T23:59:60Z", "2015-06-30T23:58:60Z", "2016-12-31T23:59:60+01:00",
    ] {
    assert_true(normalize_temporal("datetime", raw) is Err(_))
  }
}

///|
test "XML Schema expanded years compare by magnitude without losing digits" {
  let timeline = [
    "-100000000000000000000000", "-10000", "-0002", "-0001", "0001", "9999", "10000",
    "100000000000000000000000",
  ]
  for index, raw in timeline {
    assert_eq(normalize_temporal("year", raw), Ok(raw))
    if index > 0 {
      assert_eq(compare_temporal("year", timeline[index - 1], raw), -1)
    }
  }
  for invalid in ["+10000", "00000", "-0000", "00001", "-01234"] {
    assert_true(normalize_temporal("year", invalid) is Err(_))
  }
  assert_eq(normalize_temporal("yearmonth", "-10000-01"), Ok("-10000-01"))
  assert_eq(compare_temporal("yearmonth", "-0002-12", "-0001-01"), -1)
  assert_eq(compare_temporal("yearmonth", "-0001-01", "-0001-02"), -1)
  assert_eq(compare_temporal("yearmonth", "9999-12", "10000-01"), -1)

  let descriptor =
    #|{"fields":[{"name":"period","type":"yearmonth","constraints":{"minimum":"-0002-02","maximum":"10000-02"}}]}
  let schema = parse_table_schema(descriptor).unwrap()
  let report = validate_table("periods", schema.fields, ["period"], [
    ["-0002-01"],
    ["-0002-02"],
    ["9999-12"],
    ["10000-02"],
    ["10000-03"],
  ])
  assert_eq(report.errors.map(error => (error.row, error.code)), [
    (1, "minimum"),
    (5, "maximum"),
  ])
}
