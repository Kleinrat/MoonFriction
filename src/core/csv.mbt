///|
/// Strict quote framing in front of the reusable CSV parser, which otherwise accepts malformed quotes.
/// UTF-8 decoding is the host's responsibility. Default comma/double-quote dialect only.
pub fn input_from_csv(
  name : String,
  text : String,
) -> Result[InputTable, String] {
  let text = if text.has_prefix("\uFEFF") { text[1:].to_owned() } else { text }
  let mut state = 0 // 0=field start; 1=unquoted; 2=quoted; 3=after closing quote
  let mut i = 0
  while i < text.length() {
    let c = text.code_unit_at(i).to_int()
    if state == 2 {
      if c == 34 {
        if i + 1 < text.length() && text.code_unit_at(i + 1).to_int() == 34 {
          i += 1
        } else {
          state = 3
        }
      }
    } else if c == 44 {
      state = 0
    } else if c == 10 || c == 13 {
      state = 0
    } else if c == 34 {
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
    delimiter: ',',
    allow_newlines_in_quotes: true,
    quote_char: '"',
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
