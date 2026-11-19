///|
fn enum_member_matches(cell : Cell, kind : FieldType) -> Bool {
  match (cell, kind) {
    (TextValue(_), Text)
    | (IntegerValue(_), Integer)
    | (BooleanValue(_), Boolean) => true
    (NumberValue(n), Number) => n.is_finite()
    _ => false
  }
}

///|
fn parse_enum(
  value : Json,
  kind : FieldType,
  resource : String,
  field_name : String,
  errors : Array[Diagnostic],
) -> Array[Cell]? {
  if value is Null {
    return None
  }
  if value is Array(items) && !items.is_empty() {
    let result = []
    for item in items {
      // Schema entries are logical values. CSV-style string coercion applies only to data.
      if !(item is String(_) && kind != Text) {
        if cast_json_cell(item, kind, []) is Ok(cell) &&
          enum_member_matches(cell, kind) {
          result.push(cell)
          continue
        }
      }
      errors.push(
        issue(
          "descriptor", resource, 0, field_name, "enum entry must match the field type",
        ),
      )
      return None
    }
    return Some(result)
  }
  errors.push(
    issue(
      "descriptor", resource, 0, field_name, "enum requires a nonempty array",
    ),
  )
  None
}
