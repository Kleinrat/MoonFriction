///|
#derive(ToJson, Debug)
pub(all) struct InferenceHint {
  field : String
  message : String
}

///|
/// Result of a conservative CSV sample inference. The schema is only a draft:
/// it never contains required/unique/primary-key guesses and never rewrites the
/// source data.
#derive(Debug)
pub(all) struct SchemaInference {
  schema : TableSchema
  sampled_rows : Int32
  total_rows : Int32
  hints : Array[InferenceHint]
}

///|
fn infer_hint(field : String, message : String) -> InferenceHint {
  { field, message, }
}

///|
fn canonical_integer(text : String) -> Bool {
  let start = if text.has_prefix("-") { 1 } else { 0 }
  if start == text.length() {
    return false
  }
  let first = text.code_unit_at(start).to_int()
  if first == 48 {
    return text.length() == start + 1
  }
  if first < 49 || first > 57 {
    return false
  }
  ascii_digits(text, start)
}

///|
fn leading_zero_integer(text : String) -> Bool {
  let start = if text.has_prefix("-") || text.has_prefix("+") { 1 } else { 0 }
  if start >= text.length() || text.code_unit_at(start).to_int() != 48 {
    return false
  }
  if start + 1 >= text.length() {
    return false
  }
  let next = text.code_unit_at(start + 1).to_int()
  next >= 48 && next <= 57
}

///|
fn boolean_word(text : String) -> Bool {
  text == "true" ||
  text == "True" ||
  text == "TRUE" ||
  text == "false" ||
  text == "False" ||
  text == "FALSE"
}

///|
fn one_or_zero(text : String) -> Bool {
  text == "0" || text == "1"
}

///|
/// Infer a draft Table Schema from the first `sample_limit` rows.
///
/// The inference is deliberately conservative:
/// - an empty sample, or a column whose non-missing values conflict, falls back
///   to string;
/// - integer-looking identifiers with leading zeroes fall back to string;
/// - only the default true/false words become boolean; 0/1 stays integer with a
///   hint because the intent is ambiguous;
/// - no required/unique/primary-key constraint is guessed.
pub fn infer_table_schema(
  header : Array[String],
  rows : Array[Array[String]],
  sample_limit~ : Int32 = 100,
  missing_values~ : Array[String] = [""],
) -> SchemaInference {
  let hints : Array[InferenceHint] = []
  if header.is_empty() {
    hints.push(infer_hint("", "CSV 表头为空，无法生成字段"))
  }
  let names_seen : Array[String] = []
  for name in header {
    if name == "" || names_seen.contains(name) {
      hints.push(
        infer_hint(
          name, "表头存在空名或重复名，请先修正 CSV 表头",
        ),
      )
    }
    names_seen.push(name)
  }
  let limit = if sample_limit < 0 { 0 } else { sample_limit }
  let sampled = if rows.length() < limit { rows.length() } else { limit }
  if sampled < rows.length() {
    hints.push(
      infer_hint(
        "",
        "仅采样前 \{sampled} 条（共 \{rows.length()} 条），请复核推断类型",
      ),
    )
  }
  if sampled == 0 {
    hints.push(infer_hint("", "样本为空，所有字段暂定为 string"))
  }
  let mut skipped = 0
  let valid_rows : Array[Array[String]] = []
  for i in 0..<sampled {
    if rows[i].length() == header.length() {
      valid_rows.push(rows[i])
    } else {
      skipped += 1
    }
  }
  let fields : Array[Field] = []
  for column, name in header {
    let values : Array[String] = []
    for row in valid_rows {
      let text = row[column]
      if !missing_values.contains(text) {
        values.push(text)
      }
    }
    let mut saw_integer = false
    let mut saw_number = false
    let mut saw_boolean = false
    let mut saw_text = false
    let mut saw_leading_zero = false
    let mut saw_one_zero = false
    for text in values {
      if canonical_integer(text) {
        saw_integer = true
        if one_or_zero(text) {
          saw_one_zero = true
        }
      } else if leading_zero_integer(text) {
        saw_leading_zero = true
        saw_text = true
      } else if decimal_syntax(text) {
        saw_number = true
      } else if boolean_word(text) {
        saw_boolean = true
      } else {
        saw_text = true
      }
    }
    let kind = if values.is_empty() {
      hints.push(
        infer_hint(name, "该列没有非缺失样本，暂定为 string"),
      )
      Text
    } else if saw_text {
      if saw_integer || saw_number || saw_boolean {
        hints.push(
          infer_hint(name, "样本包含多种类型，回退为 string"),
        )
      }
      Text
    } else if saw_boolean && (saw_integer || saw_number) {
      hints.push(
        infer_hint(name, "布尔值与数字混合，回退为 string"),
      )
      Text
    } else if saw_boolean {
      Boolean
    } else if saw_number {
      Number
    } else if saw_integer {
      if saw_one_zero {
        hints.push(
          infer_hint(
            name, "样本只有 0/1，暂按 integer 推断；若表示布尔请手工修改",
          ),
        )
      }
      Integer
    } else {
      Text
    }
    if saw_leading_zero {
      hints.push(
        infer_hint(name, "检测到前导零，按 string 保留编号"),
      )
    }
    fields.push(field(name, kind))
  }
  if skipped > 0 {
    hints.push(
      infer_hint(
        "",
        "有 \{skipped} 条样本列数与表头不一致，已跳过",
      ),
    )
  }
  {
    schema: { fields, missing_values, primary_key: [], foreign_keys: [], },
    sampled_rows: sampled,
    total_rows: rows.length(),
    hints,
  }
}
