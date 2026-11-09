///|
test "missing markers are exact and run before conversion" {
  assert_eq(cast_cell("NA", Integer, ["NA"]), Ok(Missing))
  assert_eq(cast_cell("", Text, []), Ok(TextValue("")))
  assert_eq(cast_cell("", Text, [""]), Ok(Missing))
  assert_true(cast_cell(" NA ", Integer, ["NA"]) is Err(_))
}

///|
test "integer lexical rules and signed bounds" {
  assert_eq(cast_cell("001", Integer, []), Ok(IntegerValue(1L)))
  assert_eq(cast_cell("-3", Integer, []), Ok(IntegerValue(-3L)))
  for raw in ["", "1.5", "1e2", " 1", "1 ", "0x10", "9223372036854775808"] {
    assert_true(cast_cell(raw, Integer, []) is Err(_))
  }
}

///|
test "finite decimal values and invalid lexical forms" {
  assert_eq(cast_cell("1.25e2", Number, []), Ok(NumberValue(125.0)))
  for raw in ["NaN", "Infinity", "1e9999", "1,000", " ", "1.2.3", "1e"] {
    assert_true(cast_cell(raw, Number, []) is Err(_))
  }
}

///|
test "default boolean physical representations" {
  for raw in ["true", "True", "TRUE", "1"] {
    assert_eq(cast_cell(raw, Boolean, []), Ok(BooleanValue(true)))
  }
  for raw in ["false", "False", "FALSE", "0"] {
    assert_eq(cast_cell(raw, Boolean, []), Ok(BooleanValue(false)))
  }
  for raw in ["yes", "FALSE ", "2"] {
    assert_true(cast_cell(raw, Boolean, []) is Err(_))
  }
}

///|
test "empty string can be valid required text when not a missing marker" {
  let f = { ..field("name", Text), required: true, }
  assert_true(
    validate_table("t", [f], ["name"], [[""]], missing_values=[]).valid(),
  )
  assert_eq(
    validate_table("t", [f], ["name"], [[""]]).errors[0].code,
    "required",
  )
}

///|
test "header and width errors are distinct from type errors" {
  let fields = [field("id", Integer)]
  assert_eq(
    validate_table("t", fields, ["other"], [["1"]]).errors[0].code,
    "header",
  )
  assert_eq(
    validate_table("t", fields, ["id"], [["1", "2"]]).errors[0].code,
    "row-width",
  )
  assert_eq(
    validate_table("t", fields, ["id"], [["oops"]]).errors[0].code,
    "type",
  )
}

///|
test "uniqueness compares converted values" {
  let f = { ..field("id", Integer), unique: true, }
  let r = validate_table("t", [f], ["id"], [["1"], ["01"], [""], [""]])
  assert_eq(r.errors.length(), 1)
  assert_eq(r.errors[0].code, "unique")
  assert_eq(r.errors[0].row, 2)
}

///|
test "numeric limits and Unicode scalar text length" {
  let fields = [
    { ..field("n", Number), minimum: Some(0.0), maximum: Some(10.0), },
    { ..field("s", Text), max_length: Some(2), },
  ]
  let r = validate_table("t", fields, ["n", "s"], [
    ["-1", "你好🙂"],
    ["11", "好🙂"],
  ])
  assert_eq(r.errors.length(), 3)
  assert_eq(r.errors[0].code, "minimum")
  assert_eq(r.errors[1].code, "maxLength")
  assert_eq(r.errors[2].code, "maximum")
}

///|
test "descriptor-like field errors stop row processing" {
  assert_false(
    validate_table("t", [field("x", Text), field("x", Text)], ["x", "x"], []).valid(),
  )
  assert_false(
    validate_table(
      "t",
      [{ ..field("x", Number), minimum: Some(5.0), maximum: Some(1.0), }],
      ["x"],
      [],
    ).valid(),
  )
}

///|
test "composite primary keys detect typed duplicates and null" {
  let t = validate_table(
      "t",
      [field("a", Integer), field("b", Text)],
      ["a", "b"],
      [["1", "x"], ["01", "x"], ["", "z"]],
    ).table
  let errors = validate_primary_key(t, ["a", "b"])
  assert_eq(errors.length(), 2)
  assert_eq(errors[0].code, "primary-key-duplicate")
  assert_eq(errors[1].code, "primary-key-null")
}

///|
test "foreign key typed joins allow missing keys" {
  let a = validate_table("orders", [field("product", Integer)], ["product"], [
      ["01"],
      ["2"],
      [""],
    ]).table
  let b = validate_table("products", [field("id", Integer)], ["id"], [["1"]]).table
  let errors = validate_foreign_key(a, ["product"], b, ["id"])
  assert_eq(errors.length(), 1)
  assert_eq(errors[0].row, 2)
}

///|
test "key definition errors never become success" {
  let t = validate_table("t", [field("id", Integer)], ["id"], [["1"]]).table
  assert_eq(validate_primary_key(t, ["bad"])[0].code, "primary-key-schema")
  assert_eq(validate_primary_key(t, ["id", "id"])[0].code, "primary-key-schema")
  assert_eq(
    validate_foreign_key(t, ["id"], t, [])[0].code,
    "foreign-key-schema",
  )
}

///|
test "wide integer bounds cannot silently round to a passing Double comparison" {
  let f = { ..field("n", Integer), maximum: Some(9007199254740992.0), }
  let r = validate_table("t", [f], ["n"], [["9007199254740993"]])
  assert_false(r.valid())
  assert_eq(r.errors[0].code, "unsupported-range")
}

///|
test "public typed field API enforces applicable constraints and finite bounds" {
  let f = { ..field("v", Text), minimum: Some(0.0), }
  assert_false(validate_table("t", [f], ["v"], [["a"]]).valid())
  let text = { ..field("v", Text), min_length: Some(4), max_length: Some(1), }
  assert_false(validate_table("t", [text], ["v"], []).valid())
}

///|
test "cross type foreign key comparisons are explicitly unsupported" {
  let a = validate_table("a", [field("id", Integer)], ["id"], [["1"]]).table
  let b = validate_table("b", [field("id", Number)], ["id"], [["1.0"]]).table
  assert_eq(validate_foreign_key(a, ["id"], b, ["id"])[0].code, "unsupported")
}

///|
test "explicit positive signs work in supported numeric lexemes" {
  assert_eq(cast_cell("+42", Integer, []), Ok(IntegerValue(42L)))
  assert_eq(cast_cell("+1.5", Number, []), Ok(NumberValue(1.5)))
}
