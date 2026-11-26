///|
fn enum_member_matches(cell : Cell, kind : FieldType) -> Bool {
  match (cell, kind) {
    (TextValue(_), Text | Any)
    | (IntegerValue(_) | BigIntegerValue(_), Integer)
    | (BooleanValue(_), Boolean) => true
    (NumberValue(n), Number) => n.is_finite()
    (ExactNumberValue(_), Number) => true
    (SpecialNumber(token), Number) => ["NaN", "INF", "-INF"].contains(token)
    (TemporalValue(raw), Date | Time | DateTime | Year | YearMonth) =>
      normalize_temporal(kind_label(kind), raw) == Ok(raw)
    (TemporalValue(raw), Duration) => cast_duration(raw) is Ok(_)
    (StructuredValue(raw), GeoPoint) => {
      let value = @json.parse(raw) catch { _ => return false }
      geopoint_json(value, "array") is Ok(_)
    }
    (StructuredValue(raw), GeoJson) => {
      let value = @json.parse(raw) catch { _ => return false }
      geojson_cell(value) is Ok(_) || topojson_cell(value) is Ok(_)
    }
    (StructuredValue(raw), ObjectValueType | ArrayValueType) =>
      cast_cell(raw, kind, []) is Ok(_)
    _ => false
  }
}

///|
fn parse_enum(
  value : Json,
  field : Field,
  resource : String,
  errors : Array[Diagnostic],
) -> Array[Cell]? {
  if value is Null {
    return None
  }
  if value is Array(items) && !items.is_empty() {
    let result = []
    for item in items {
      if cast_field_json(item, field, []) is Ok(cell) &&
        enum_member_matches(cell, field.kind) {
        result.push(cell)
        continue
      }
      errors.push(
        issue(
          "descriptor",
          resource,
          0,
          field.name,
          "enum entry must match the field type",
        ),
      )
      return None
    }
    return Some(result)
  }
  errors.push(
    issue(
      "descriptor",
      resource,
      0,
      field.name,
      "enum requires a nonempty array",
    ),
  )
  None
}
