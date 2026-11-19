///|
#derive(Eq)
priv enum CsvPosition {
  Start
  Plain
  Quoted
  AfterQuote
}

///|
/// Opaque JS-host session. Only a partial record and RowValidator state survive a chunk.
pub struct CsvSession {
  priv validator : @core.RowValidator?
  priv header : Array[String]
  priv name : String
  priv delimiter : Char
  priv quote : Char
  priv mut position : CsvPosition
  priv mut field : StringBuilder
  priv mut record : Array[String]
  priv mut saw_header : Bool
  priv mut after_cr : Bool
  priv mut rows : Int32
  priv mut fatal : Array[@core.Diagnostic]
}

///|
pub fn open_csv_stream(
  schema_text : String,
  name : String,
  delimiter : String,
  quote : String,
  limit : Int32,
) -> CsvSession {
  let session = {
    validator: None,
    header: [],
    name,
    delimiter: delimiter.iter().next().unwrap_or(','),
    quote: quote.iter().next().unwrap_or('"'),
    position: Start,
    field: StringBuilder(),
    record: [],
    saw_header: false,
    after_cr: false,
    rows: 0,
    fatal: [],
  }
  if ![",", ";", "\t"].contains(delimiter) || !["\"", "'"].contains(quote) {
    session.fatal.push({
      code: "unsupported",
      resource: name,
      row: 0,
      field: "dialect",
      message: "Unsupported delimiter or quote character",
    })
    return session
  }
  match @core.parse_table_schema(schema_text) {
    Err(errors) => {
      session.fatal = errors
      session
    }
    Ok(schema) => {
      let header = schema.fields.map(f => f.name)
      match @core.RowValidator::new(name, schema, header, max_errors=limit) {
        Ok(v) => { ..session, header, validator: Some(v), }
        Err(errors) => {
          session.fatal = errors
          session
        }
      }
    }
  }
}

///|
fn CsvSession::error(self : CsvSession, message : String) -> Unit {
  self.fatal.push({
    code: "csv",
    resource: self.name,
    row: if self.saw_header {
      self.rows + 1
    } else {
      0
    },
    field: "",
    message,
  })
}

///|
fn CsvSession::end_field(self : CsvSession) -> Unit {
  self.record.push(self.field.to_string())
  self.field = StringBuilder()
  self.position = Start
}

///|
fn CsvSession::end_record(self : CsvSession) -> Unit {
  self.end_field()
  if !self.saw_header {
    if self.record != self.header {
      self.fatal.push({
        code: "header",
        resource: self.name,
        row: 0,
        field: "",
        message: "Header must match schema fields in order",
      })
    }
    self.saw_header = true
  } else {
    self.validator.unwrap().feed(self.record)
    self.rows += 1
  }
  self.record = []
}

///|
/// Text must already be decoded with a stateful UTF-8 decoder.
pub fn push_csv_chunk(session : CsvSession, text : String) -> Bool {
  if !session.fatal.is_empty() {
    return false
  }
  for c in text.iter() {
    if session.after_cr {
      session.after_cr = false
      if c == '\n' {
        continue
      }
    }
    if session.position == Quoted {
      if c == session.quote {
        session.position = AfterQuote
      } else {
        session.field.write_char(c)
      }
    } else if c == session.quote && session.position == AfterQuote {
      session.field.write_char(c)
      session.position = Quoted
    } else if c == session.delimiter {
      session.end_field()
    } else if c == '\n' || c == '\r' {
      session.end_record()
      if !session.fatal.is_empty() {
        return false
      }
      session.after_cr = c == '\r'
    } else if c == session.quote && session.position == Start {
      session.position = Quoted
    } else if c == session.quote || session.position == AfterQuote {
      session.error("Unexpected quote or character after closing quote")
      return false
    } else {
      session.field.write_char(c)
      session.position = Plain
    }
  }
  true
}

///|
pub fn finish_csv_stream(session : CsvSession) -> String {
  if session.fatal.is_empty() {
    if session.position == Quoted {
      session.error("Unterminated quoted field")
    } else if !session.saw_header ||
      session.position != Start ||
      !session.record.is_empty() {
      session.end_record()
    }
  }
  if !session.fatal.is_empty() {
    return (
      {
        "ok": false,
        "complete": false,
        "rows": session.rows,
        "errors": @json.to_json(session.fatal),
      } : Json).stringify()
  }
  let summary = session.validator.unwrap().finish()
  (
    {
      "ok": summary.error_count == 0,
      "complete": true,
      "rows": summary.rows,
      "error_count": Json::number(summary.error_count.to_double()),
      "errors": @json.to_json(summary.errors),
    } : Json).stringify()
}
