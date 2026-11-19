///|
#derive(Debug, Eq)
pub(all) struct CsvDialect {
  delimiter : Char
  quote_char : Char
}

///|
fn default_csv_dialect() -> CsvDialect {
  { delimiter: ',', quote_char: '"', }
}

///|
fn CsvDialect::supported(self : CsvDialect) -> Bool {
  (self.delimiter == ',' || self.delimiter == ';' || self.delimiter == '\t') &&
  (self.quote_char == '"' || self.quote_char == '\'')
}

///|
fn parse_csv_dialect(value : Json) -> Result[CsvDialect, String] {
  let mut dialect = default_csv_dialect()
  match value {
    Null => Ok(dialect)
    Object(options) => {
      for key, setting in options {
        let char = match setting {
          String(s) if s.length() == 1 => s.iter().next().unwrap()
          _ =>
            return Err("Expected one character for CSV dialect option: " + key)
        }
        match key {
          "delimiter" => dialect = { ..dialect, delimiter: char, }
          "quoteChar" => dialect = { ..dialect, quote_char: char, }
          _ => return Err("Unsupported CSV dialect option: " + key)
        }
      }
      if dialect.supported() {
        Ok(dialect)
      } else {
        Err("Unsupported CSV delimiter or quote character")
      }
    }
    _ => Err("Expected a CSV dialect object")
  }
}

///|
/// Look up the resource's physical CSV format in the original descriptor.
pub fn Descriptor::csv_dialect(
  self : Descriptor,
  name : String,
) -> Result[CsvDialect, String] {
  if prop(self.original, "resources") is Array(items) {
    for item in items {
      if prop(item, "name") == Json::string(name) {
        return parse_csv_dialect(prop(item, "dialect"))
      }
    }
  }
  Err("Unknown CSV resource: " + name)
}
