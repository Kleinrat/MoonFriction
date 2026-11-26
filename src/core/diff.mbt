///|
#derive(Debug, ToJson)
pub(all) struct SchemaChange {
  field : String
  rule : String
  impact : String
  before : Json
  after : Json
  members : Array[Json]?
}

///|
fn direction(tighter : Bool) -> String {
  if tighter {
    "tightened"
  } else {
    "relaxed"
  }
}

///|
fn diff_bound_value(value : Double?, integer : Bool) -> Json {
  match value {
    None => Json::null()
    Some(n) if integer && (n > 9007199254740991.0 || n < -9007199254740991.0) =>
      { "precision": "outside-safe-integer-range" }
    Some(n) => Json::number(n)
  }
}

///|
fn diff_bound(
  out : Array[SchemaChange],
  field : String,
  rule : String,
  old : Double?,
  current : Double?,
  lower : Bool,
  integer~ : Bool = false,
) -> Unit {
  let before = diff_bound_value(old, integer)
  let after = diff_bound_value(current, integer)
  // Parsed bounds are binary64. Equal rounded values cannot establish equality.
  if before is Object(_) || after is Object(_) {
    out.push({ field, rule, impact: "review", before, after, members: None, })
    return
  }
  if old == current {
    return
  }
  let tighter = match (old, current) {
    (_, None) => false
    (None, Some(_)) => true
    (Some(a), Some(b)) => if lower { b > a } else { b < a }
  }
  out.push({
    field,
    rule,
    impact: direction(tighter),
    before,
    after,
    members: None,
  })
}

///|
fn diff_cell(c : Cell) -> Json {
  match c {
    TextValue(s) | TemporalValue(s) => Json::string(s)
    IntegerValue(i) => Json::number(i.to_double(), repr=i.to_string())
    BigIntegerValue(i) => big_integer_json(i)
    NumberValue(n) => Json::number(n)
    ExactNumberValue(n) => decimal_json(n)
    SpecialNumber(s) => Json::string(s)
    BooleanValue(b) => @json.to_json(b)
    StructuredValue(raw) =>
      @json.parse(raw, preserve_number_repr=true) catch {
        _ => Json::string(raw)
      }
    Missing => Json::null()
  }
}

///|
fn enum_json(values : Array[Cell]?) -> Json {
  match values {
    None => Json::null()
    Some(xs) => Json::array(xs.map(diff_cell))
  }
}

///|
fn diff_enum(out : Array[SchemaChange], old : Field, current : Field) -> Unit {
  let a = old.enum_values
  let b = current.enum_values
  fn change(delta : Array[Cell]?, tighter : Bool) -> Unit {
    out.push({
      field: old.name,
      rule: "enum",
      impact: direction(tighter),
      before: enum_json(a),
      after: enum_json(b),
      members: delta.map(xs => xs.map(diff_cell)),
    })
  }
  match (a, b) {
    (Some(xs), Some(ys)) =>
      // Compare as sets; report the removed and added members independently.
      for (source, target, tighter) in [(xs, ys, true), (ys, xs, false)] {
        let delta : Array[Cell] = []
        for x in source {
          if !target.contains(x) && !delta.contains(x) {
            delta.push(x)
          }
        }
        if !delta.is_empty() {
          change(Some(delta), tighter)
        }
      }
    (None, None) => ()
    _ => {
      let values = a.unwrap_or(b.unwrap_or([]))
      if old.kind == Boolean &&
        values.contains(BooleanValue(true)) &&
        values.contains(BooleanValue(false)) {
        return
      }
      change(None, b is Some(_))
    }
  }
}

///|
pub fn kind_label(kind : FieldType) -> String {
  match kind {
    Text => "string"
    Integer => "integer"
    Number => "number"
    Boolean => "boolean"
    ObjectValueType => "object"
    ArrayValueType => "array"
    Any => "any"
    Date => "date"
    Time => "time"
    DateTime => "datetime"
    Year => "year"
    YearMonth => "yearmonth"
    Duration => "duration"
    GeoPoint => "geopoint"
    GeoJson => "geojson"
  }
}

///|
fn field_diff_bound(
  exact : @bigint.BigInt?,
  decimal : ExactDecimal?,
  temporal : String?,
  numeric : Double?,
  integer : Bool,
) -> Json {
  if exact is Some(value) {
    big_integer_json(value)
  } else if decimal is Some(value) {
    decimal_json(value)
  } else if temporal is Some(value) {
    Json::string(value)
  } else {
    diff_bound_value(numeric, integer)
  }
}

///|
fn[T] diff_ordered(
  out : Array[SchemaChange],
  field : String,
  rule : String,
  old : T?,
  current : T?,
  lower : Bool,
  compare : (T, T) -> Int32,
  encode : (T) -> Json,
) -> Unit {
  let tighter = match (old, current) {
    (None, None) => return
    (_, None) => false
    (None, Some(_)) => true
    (Some(x), Some(y)) => {
      let order = compare(y, x)
      if order == 0 {
        return
      }
      if lower {
        order > 0
      } else {
        order < 0
      }
    }
  }
  out.push({
    field,
    rule,
    impact: direction(tighter),
    before: old.map(encode).unwrap_or(Json::null()),
    after: current.map(encode).unwrap_or(Json::null()),
    members: None,
  })
}

///|
fn field_input_options(f : Field) -> Json {
  match f.kind {
    Boolean => {
      let t = f.boolean_tokens.unwrap_or({
        truthy: ["true", "True", "TRUE", "1"],
        falsy: ["false", "False", "FALSE", "0"],
      })
      {
        "trueValues": @json.to_json(t.truthy),
        "falseValues": @json.to_json(t.falsy),
      }
    }
    Integer | Number => {
      let n = f.numeric_format.unwrap_or({
        bare: true,
        decimal: ".",
        group: None,
      })
      {
        "bareNumber": @json.to_json(n.bare),
        "decimalChar": n.decimal,
        "groupChar": @json.to_json(n.group),
      }
    }
    _ => Json::null()
  }
}

///|
fn field_constraints(f : Field) -> Json {
  let rules : Json = {
    "required": @json.to_json(f.required),
    "unique": @json.to_json(f.unique),
    "enum": enum_json(f.enum_values),
    "minimum": field_diff_bound(
      f.exact_minimum,
      f.decimal_minimum,
      f.temporal_minimum,
      f.minimum,
      f.kind == Integer,
    ),
    "maximum": field_diff_bound(
      f.exact_maximum,
      f.decimal_maximum,
      f.temporal_maximum,
      f.maximum,
      f.kind == Integer,
    ),
    "minLength": diff_bound_value(f.min_length.map(n => n.to_double()), false),
    "maxLength": diff_bound_value(f.max_length.map(n => n.to_double()), false),
  }
  if f.pattern is Some(p) && rules is Object(values) {
    values["pattern"] = Json::string(p.source)
  }
  rules
}

///|
fn fk_json(key : ForeignKey) -> Json {
  {
    "fields": @json.to_json(key.fields),
    "reference": {
      "resource": key.resource,
      "fields": @json.to_json(key.reference_fields),
    },
  }
}

///|
/// Compare parsed standalone schemas. Direction is local to an individual rule.
pub fn diff_table_schemas(
  old : TableSchema,
  current : TableSchema,
) -> Array[SchemaChange] {
  let out = []
  fn review(
    field : String,
    rule : String,
    before : Json,
    after : Json,
  ) -> Unit {
    out.push({ field, rule, impact: "review", before, after, members: None, })
  }
  let old_names = old.fields.map(f => f.name)
  let names = current.fields.map(f => f.name)
  let by_name : Map[String, Field] = Map([])
  for f in current.fields {
    by_name[f.name] = f
  }
  for a in old.fields {
    guard by_name.get(a.name) is Some(b) else {
      review(a.name, "field", Json::string(a.name), Json::null())
      continue
    }
    if a.kind != b.kind {
      review(
        a.name,
        "type",
        Json::string(kind_label(a.kind)),
        Json::string(kind_label(b.kind)),
      )
      review(
        a.name,
        "fieldConstraints",
        field_constraints(a),
        field_constraints(b),
      )
      continue
    }
    if a.format != b.format {
      review(a.name, "format", Json::string(a.format), Json::string(b.format))
    }
    let old_options = field_input_options(a)
    let new_options = field_input_options(b)
    if old_options != new_options {
      review(a.name, "inputOptions", old_options, new_options)
    }
    for
      (rule, x, y) in [
        ("required", a.required, b.required),
        ("unique", a.unique, b.unique),
      ] {
      if x != y {
        out.push({
          field: a.name,
          rule,
          impact: direction(y),
          before: @json.to_json(x),
          after: @json.to_json(y),
          members: None,
        })
      }
    }
    diff_bound(
      out,
      a.name,
      "minimum",
      a.minimum,
      b.minimum,
      true,
      integer=a.kind == Integer,
    )
    diff_bound(
      out,
      a.name,
      "maximum",
      a.maximum,
      b.maximum,
      false,
      integer=a.kind == Integer,
    )
    diff_bound(
      out,
      a.name,
      "minLength",
      a.min_length.map(n => n.to_double()),
      b.min_length.map(n => n.to_double()),
      true,
    )
    diff_bound(
      out,
      a.name,
      "maxLength",
      a.max_length.map(n => n.to_double()),
      b.max_length.map(n => n.to_double()),
      false,
    )
    for
      (rule, old, current, lower) in [
        ("minimum", a.exact_minimum, b.exact_minimum, true),
        ("maximum", a.exact_maximum, b.exact_maximum, false),
      ] {
      diff_ordered(
        out,
        a.name,
        rule,
        old,
        current,
        lower,
        (x, y) => x.compare(y),
        big_integer_json,
      )
    }
    for
      (rule, old, current, lower) in [
        ("minimum", a.temporal_minimum, b.temporal_minimum, true),
        ("maximum", a.temporal_maximum, b.temporal_maximum, false),
      ] {
      diff_ordered(
        out,
        a.name,
        rule,
        old,
        current,
        lower,
        (x, y) => compare_temporal(kind_label(a.kind), x, y),
        Json::string,
      )
    }
    for
      (rule, old, current, lower) in [
        ("minimum", a.decimal_minimum, b.decimal_minimum, true),
        ("maximum", a.decimal_maximum, b.decimal_maximum, false),
      ] {
      diff_ordered(
        out,
        a.name,
        rule,
        old,
        current,
        lower,
        compare_decimal,
        decimal_json,
      )
    }
    diff_enum(out, a, b)
    let old_pattern = a.pattern.map(p => p.source)
    let new_pattern = b.pattern.map(p => p.source)
    if old_pattern != new_pattern {
      review(
        a.name,
        "pattern",
        @json.to_json(old_pattern),
        @json.to_json(new_pattern),
      )
    }
  }
  for name in names {
    if !old_names.contains(name) {
      review(name, "field", Json::null(), Json::string(name))
    }
  }
  if old_names.filter(n => names.contains(n)) !=
    names.filter(n => old_names.contains(n)) {
    review("", "fieldOrder", @json.to_json(old_names), @json.to_json(names))
  }
  if old.primary_key != current.primary_key {
    let old_members = old.primary_key.copy()
    let new_members = current.primary_key.copy()
    old_members.sort()
    new_members.sort()
    let before = @json.to_json(old.primary_key)
    let after = @json.to_json(current.primary_key)
    if old_members == new_members {
      out.push({
        field: "",
        rule: "primaryKeyOrder",
        impact: "orderOnly",
        before,
        after,
        members: None,
      })
    } else {
      review("", "primaryKey", before, after)
    }
  }
  if !old.missing_values.all(n => current.missing_values.contains(n)) ||
    !current.missing_values.all(n => old.missing_values.contains(n)) {
    review(
      "",
      "missingValues",
      @json.to_json(old.missing_values),
      @json.to_json(current.missing_values),
    )
  }
  let old_keys = old.foreign_keys.map(fk_json)
  let new_keys = current.foreign_keys.map(fk_json)
  if !old_keys.all(k => new_keys.contains(k)) ||
    !new_keys.all(k => old_keys.contains(k)) {
    review("", "foreignKeys", Json::array(old_keys), Json::array(new_keys))
  }
  out
}
