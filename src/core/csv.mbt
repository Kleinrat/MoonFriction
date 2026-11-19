///|
/// Strict quote framing in front of the reusable CSV parser, which otherwise accepts malformed quotes.
/// UTF-8 decoding is the host's responsibility.
pub fn input_from_csv(
  name : String,
  text : String,
  dialect~ : CsvDialect = default_csv_dialect(),
) -> Result[InputTable, String] {
  if !dialect.supported() {
    return Err("Unsupported CSV delimiter or quote character")
  }
  let quote = dialect.quote_char.to_int()
  let separator = dialect.delimiter.to_int()
  let text = if text.has_prefix("\uFEFF") { text[1:].to_owned() } else { text }
  let mut state = 0 // 0=field start; 1=unquoted; 2=quoted; 3=after closing quote
  let mut i = 0
  while i < text.length() {
    let c = text.code_unit_at(i).to_int()
    if state == 2 {
      if c == quote {
        if i + 1 < text.length() && text.code_unit_at(i + 1).to_int() == quote {
          i += 1
        } else {
          state = 3
        }
      }
    } else if c == separator {
      state = 0
    } else if c == 10 || c == 13 {
      state = 0
    } else if c == quote {
      if state != 0 {
        return Err("Quote inside an unquoted field")
      }
      state = 2
    } else {
      if state == 3 {
        return Err("Unexpected character after closing quote")
      }
      state = 1
    }
    i += 1
  }
  if state == 2 {
    return Err("Unterminated quoted field")
  }
  let parsed = @csv.CSV::parse_string(text, options={
    delimiter: dialect.delimiter,
    allow_newlines_in_quotes: true,
    quote_char: dialect.quote_char,
    skip_empty_lines: false,
    trim_spaces: false,
  })
  Ok({ name, header: parsed.header(), rows: parsed.data(), })
}

///|
test "reused CSV parser preserves quoted commas newlines and Unicode" {
  let input = input_from_csv(
    "t", "id,title\r\n1,\"你好,🙂\"\r\n2,\"line1\nline2\"\r\n",
  ).unwrap()
  assert_eq(input.header, ["id", "title"])
  assert_eq(input.rows, [["1", "你好,🙂"], ["2", "line1\nline2"]])
}

///|
test "malformed CSV is rejected before lenient dependency parsing" {
  for text in ["id\n\"unterminated", "id\na\"b", "id\n\"value\"oops"] {
    assert_true(input_from_csv("t", text) is Err(_))
  }
}

///|
test "empty CSV records cannot erase required data errors" {
  let input = input_from_csv("t", "id\n\n1\n").unwrap()
  assert_eq(input.rows, [[""], ["1"]])
  let report = validate_table(
    "t",
    [{ ..field("id", Integer), required: true, }],
    input.header,
    input.rows,
  )
  assert_false(report.valid())
  assert_eq(report.errors[0].code, "required")
}

///|
test "BOM is handled consistently in the embedded API" {
  assert_eq(input_from_csv("t", "\uFEFFid\n1\n").unwrap().header, ["id"])
}

///|
test "alternate delimiters and quotes preserve the same logical records" {
  let expected = input_from_csv(
    "t", "id,title\r\n1,\"it's;茶\r\n新\"\r\n2,\r\n",
  ).unwrap()
  for sep in [';', '\t'] {
    let dialect : CsvDialect = { delimiter: sep, quote_char: '\'', }
    let text = "\uFEFFid\{sep}title\r\n1\{sep}'it''s;茶\r\n新'\r\n2\{sep}\r\n"
    let actual = input_from_csv("t", text, dialect~).unwrap()
    assert_eq(actual.header, expected.header)
    assert_eq(actual.rows, expected.rows)
    for bad in ["'oops", "a'b", "'closed'x"] {
      assert_true(input_from_csv("t", bad, dialect~) is Err(_))
    }
  }
}
