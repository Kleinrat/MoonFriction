///|
#derive(Debug)
pub(all) struct NumericFormat {
  bare : Bool
  decimal : String
  group : String?
}

///|
#derive(Debug)
pub(all) struct BooleanTokens {
  truthy : Array[String]
  falsy : Array[String]
}

///|
fn boolean_tokens(
  entry : Json,
  kind : FieldType,
  resource : String,
  name : String,
  errors : Array[Diagnostic],
) -> BooleanTokens? {
  let true_values = prop(entry, "trueValues")
  let false_values = prop(entry, "falseValues")
  if true_values is Null && false_values is Null {
    return None
  }
  fn read(value : Json, default : Array[String]) -> Array[String] {
    match value {
      Null => default
      Array(_) =>
        match strings(value) {
          Some(tokens) if !tokens.is_empty() => tokens
          _ => []
        }
      _ => []
    }
  }
  let truthy = read(true_values, ["true", "True", "TRUE", "1"])
  let falsy = read(false_values, ["false", "False", "FALSE", "0"])
  if kind != Boolean ||
    truthy.is_empty() ||
    falsy.is_empty() ||
    truthy.any(value => falsy.contains(value)) {
    errors.push(
      issue(
        "descriptor", resource, 0, name, "Expected disjoint, nonempty boolean token arrays",
      ),
    )
    None
  } else {
    Some({ truthy, falsy, })
  }
}

///|
fn valid_numeric_separator(raw : String) -> Bool {
  raw.iter().count() == 1 &&
  raw
  .iter()
  .all(c => !(c >= '0' && c <= '9') && !['+', '-', 'e', 'E'].contains(c))
}

///|
fn numeric_format(
  entry : Json,
  kind : FieldType,
  resource : String,
  name : String,
  errors : Array[Diagnostic],
) -> NumericFormat? {
  let bare = prop(entry, "bareNumber")
  let decimal = prop(entry, "decimalChar")
  let group = prop(entry, "groupChar")
  if bare is Null && decimal is Null && group is Null {
    return None
  }
  let group_string = json_text(group)
  let decimal_string = json_text(decimal).unwrap_or(".")
  let valid = bare is (Null | True | False) &&
    (decimal is Null || (kind == Number && decimal is String(_))) &&
    (group is Null || (kind == Number && group is String(_))) &&
    numeric_kind(kind) &&
    valid_numeric_separator(decimal_string) &&
    (
      group is Null ||
      (
        group_string is Some(s) &&
        valid_numeric_separator(s) &&
        s != decimal_string
      )
    )
  if !valid {
    errors.push(
      issue("descriptor", resource, 0, name, "Invalid numeric format options"),
    )
    return None
  }
  Some({ bare: !(bare is False), decimal: decimal_string, group: group_string, })
}

///|
fn normalize_physical_number(
  raw : String,
  format : NumericFormat,
) -> Result[String, String] {
  let chars = raw.to_array()
  let decimal = format.decimal.to_array()[0]
  let group = format.group.map(value => value.to_array()[0])
  let mut start = 0
  let mut end = chars.length()
  fn digit(c : Char) -> Bool {
    c >= '0' && c <= '9'
  }
  if !format.bare {
    while start < end &&
          !digit(chars[start]) &&
          !['+', '-', decimal].contains(chars[start]) {
      start += 1
    }
    while end > start && !digit(chars[end - 1]) && chars[end - 1] != decimal {
      end -= 1
    }
  }
  let normalized = StringBuilder()
  let mut integer_part = true
  for index = start; index < end; index = index + 1 {
    let c = chars[index]
    if group == Some(c) {
      if !integer_part ||
        index == start ||
        index + 1 == end ||
        !digit(chars[index - 1]) ||
        !digit(chars[index + 1]) {
        return Err("Invalid numeric grouping")
      }
      continue
    }
    if c == '.' && decimal != '.' {
      return Err("Value uses a different decimal separator")
    }
    if c == decimal || c == 'e' || c == 'E' {
      integer_part = false
    }
    normalized.write_char(if c == decimal { '.' } else { c })
  }
  Ok(normalized.to_string())
}

///|
fn supported_field_format(kind : FieldType, format : String) -> Bool {
  format == "default" ||
  kind == Any ||
  (temporal_kind(kind) && supports_temporal_format(kind_label(kind), format)) ||
  (kind == GeoJson && format == "topojson") ||
  (kind == GeoPoint && ["array", "object"].contains(format)) ||
  (kind == Text && ["email", "uri", "binary", "uuid"].contains(format))
}

///|
fn text_format_matches(raw : String, format : String) -> Bool {
  match format {
    "default" => true
    "uuid" =>
      re"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$".execute(
        raw[:],
      )
      is Some(_)
    "binary" => valid_base64(raw)
    "email" => valid_email(raw)
    "uri" => valid_uri(raw)
    _ => false
  }
}

///|
fn cast_field_text(
  raw : String,
  f : Field,
  missing : Array[String],
) -> Result[Cell, String] {
  if missing.contains(raw) {
    return Ok(Missing)
  }
  if temporal_kind(f.kind) && f.format != "default" {
    return normalize_temporal_format(kind_label(f.kind), raw, f.format).map(value => {
      TemporalValue(value)
    })
  }
  if f.kind == GeoJson && f.format == "topojson" {
    let value = @json.parse(raw, preserve_number_repr=true) catch {
      _ => return Err("Expected TopoJSON")
    }
    return topojson_cell(value)
  }
  if f.kind == GeoPoint && f.format != "default" {
    let value = @json.parse(raw, preserve_number_repr=true) catch {
      _ => return Err("Expected geopoint JSON")
    }
    return geopoint_json(value, f.format)
  }
  if f.kind == Text && !text_format_matches(raw, f.format) {
    return Err("Value does not match string format " + f.format)
  }
  if f.boolean_tokens is Some(tokens) {
    if tokens.truthy.contains(raw) {
      return Ok(BooleanValue(true))
    }
    if tokens.falsy.contains(raw) {
      return Ok(BooleanValue(false))
    }
    return Err("Expected a declared boolean token")
  }
  match f.numeric_format {
    Some(format) =>
      match normalize_physical_number(raw, format) {
        Ok(value) => cast_cell(value, f.kind, [])
        Err(message) => Err(message)
      }
    None => cast_cell(raw, f.kind, [])
  }
}

///|
fn cast_field_json(
  value : Json,
  f : Field,
  missing : Array[String],
) -> Result[Cell, String] {
  match value {
    String(raw) => cast_field_text(raw, f, missing)
    Object(_) if f.kind == GeoJson && f.format == "topojson" =>
      topojson_cell(value)
    Array(_) | Object(_) if f.kind == GeoPoint => geopoint_json(value, f.format)
    _ => cast_json_cell(value, f.kind, missing)
  }
}
