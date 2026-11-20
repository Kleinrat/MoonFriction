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
    TextValue(s) => Json::string(s)
    IntegerValue(i) => Json::number(i.to_double(), repr=i.to_string())
    NumberValue(n) => Json::number(n)
    BooleanValue(b) => @json.to_json(b)
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
fn kind_label(kind : FieldType) -> String {
  match kind {
    Text => "string"
    Integer => "integer"
    Number => "number"
    Boolean => "boolean"
  }
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
      continue
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
    diff_enum(out, a, b)
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
    review(
      "",
      "primaryKey",
      @json.to_json(old.primary_key),
      @json.to_json(current.primary_key),
    )
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
