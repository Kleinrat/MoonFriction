///|
fn field_positions(
  table : Table,
  names : Array[String],
) -> Result[Array[Int32], String] {
  if names.is_empty() {
    return Err("Key fields cannot be empty")
  }
  let positions : Array[Int32] = []
  for name in names {
    let mut position = -1
    for i, f in table.fields {
      if f.name == name {
        position = i
      }
    }
    if position < 0 {
      return Err("Unknown key field: " + name)
    }
    if positions.contains(position) {
      return Err("Repeated field in key: " + name)
    }
    positions.push(position)
  }
  Ok(positions)
}

///|
/// Only call on a table whose TableReport is valid. Composite keys compare typed cells.
pub fn validate_primary_key(
  table : Table,
  fields : Array[String],
) -> Array[Diagnostic] {
  let positions = match field_positions(table, fields) {
    Ok(p) => p
    Err(message) =>
      return [issue("primary-key-schema", table.name, 0, "", message)]
  }
  let errors : Array[Diagnostic] = []
  let seen : Array[Array[Cell]] = []
  for i, row in table.rows {
    if row.length() != table.fields.length() {
      errors.push(
        issue(
          "invalid-table",
          table.name,
          i + 1,
          "",
          "Cannot validate keys on a malformed logical table",
        ),
      )
      continue
    }
    let key = positions.map(p => row[p])
    if key.contains(Missing) {
      errors.push(
        issue(
          "primary-key-null",
          table.name,
          i + 1,
          "",
          "Primary key contains a missing value",
        ),
      )
    } else if seen.contains(key) {
      errors.push(
        issue(
          "primary-key-duplicate",
          table.name,
          i + 1,
          "",
          "Duplicate primary key",
        ),
      )
    }
    seen.push(key)
  }
  errors
}

///|
/// Foreign keys are checked after successful table validation. A key containing Missing is not matched.
pub fn validate_foreign_key(
  table : Table,
  fields : Array[String],
  reference : Table,
  reference_fields : Array[String],
) -> Array[Diagnostic] {
  if fields.length() != reference_fields.length() {
    return [
      issue(
        "foreign-key-schema",
        table.name,
        0,
        "",
        "Foreign key arities differ",
      ),
    ]
  }
  let from = match field_positions(table, fields) {
    Ok(p) => p
    Err(message) =>
      return [issue("foreign-key-schema", table.name, 0, "", message)]
  }
  let to = match field_positions(reference, reference_fields) {
    Ok(p) => p
    Err(message) =>
      return [issue("foreign-key-schema", table.name, 0, "", message)]
  }
  let errors : Array[Diagnostic] = []
  for j in 0..<from.length() {
    if table.fields[from[j]].kind != reference.fields[to[j]].kind {
      return [
        issue(
          "unsupported",
          table.name,
          0,
          "",
          "Cross-type foreign keys are outside the supported subset",
        ),
      ]
    }
  }
  if reference.rows.any(row => row.length() != reference.fields.length()) {
    return [
      issue("invalid-table", reference.name, 0, "", "Malformed reference table"),
    ]
  }
  let keys = reference.rows.map(row => to.map(p => row[p]))
  for i, row in table.rows {
    if row.length() != table.fields.length() {
      errors.push(
        issue("invalid-table", table.name, i + 1, "", "Malformed source table"),
      )
      continue
    }
    let key = from.map(p => row[p])
    if !key.contains(Missing) && !keys.contains(key) {
      errors.push(
        issue(
          "foreign-key",
          table.name,
          i + 1,
          "",
          "No matching referenced row",
        ),
      )
    }
  }
  errors
}
