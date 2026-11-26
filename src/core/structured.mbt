///|
#derive(Debug)
pub struct FieldPattern {
  source : String
  matcher : @string.Regex
}

///|
pub fn compile_field_pattern(source : String) -> Result[FieldPattern, String] {
  compile_xml_schema_regex(source).map(matcher => { source, matcher, })
}

///|
fn numeric_kind(kind : FieldType) -> Bool {
  kind == Integer || kind == Number
}

///|
fn collection_kind(kind : FieldType) -> Bool {
  kind == Text || kind == ObjectValueType || kind == ArrayValueType
}

///|
/// Normalize object key order for logical equality and hashing. Preserve the
/// exact numeric values so equivalent literals compare without rounding.
fn canonical_json(value : Json) -> Json {
  match value {
    Object(values) => {
      let keys = []
      for k, _ in values {
        keys.push(k)
      }
      keys.sort()
      let sorted = Map([])
      for k in keys {
        sorted[k] = canonical_json(values[k])
      }
      Json::object(sorted)
    }
    Array(items) => Json::array(items.map(canonical_json))
    Number(_, repr~) =>
      if repr is Some(raw) && decimal_syntax(raw) {
        decimal_json(decimal_value(raw))
      } else {
        value
      }
    _ => value
  }
}

///|
fn cast_structured(value : Json, kind : FieldType) -> Result[Cell, String] {
  match (kind, value) {
    (ObjectValueType, Object(_)) | (ArrayValueType, Array(_)) =>
      Ok(StructuredValue(canonical_json(value).stringify()))
    (ObjectValueType, _) => Err("Expected a JSON object")
    (ArrayValueType, _) => Err("Expected a JSON array")
    _ => Err("Structured JSON does not match the field type")
  }
}

///|
fn cell_length(cell : Cell) -> Int32? {
  match cell {
    TextValue(text) => Some(text.iter().count())
    StructuredValue(raw) => {
      let value = @json.parse(raw) catch { _ => return None }
      match value {
        Array(items) => Some(items.length())
        Object(fields) => Some(fields.length())
        _ => None
      }
    }
    _ => None
  }
}
