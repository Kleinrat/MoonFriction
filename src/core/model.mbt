///|
#derive(Eq, Debug)
pub(all) enum FieldType {
  Text
  Integer
  Number
  Boolean
}

///|
#derive(Eq, Debug)
pub(all) enum Cell {
  Missing
  TextValue(String)
  IntegerValue(Int64)
  NumberValue(Double)
  BooleanValue(Bool)
}

///|
#derive(Debug)
pub(all) struct Field {
  name : String
  kind : FieldType
  required : Bool
  unique : Bool
  minimum : Double?
  maximum : Double?
  min_length : Int32?
  max_length : Int32?
}

///|
pub fn field(name : String, kind : FieldType) -> Field {
  {
    name,
    kind,
    required: false,
    unique: false,
    minimum: None,
    maximum: None,
    min_length: None,
    max_length: None,
  }
}

///|
#derive(ToJson, Eq, Debug)
pub(all) struct Diagnostic {
  code : String
  resource : String
  row : Int32
  field : String
  message : String
}

///|
#derive(Debug)
pub(all) struct Table {
  name : String
  fields : Array[Field]
  rows : Array[Array[Cell]]
}

///|
#derive(Debug)
pub(all) struct TableReport {
  table : Table
  errors : Array[Diagnostic]
}

///|
pub fn TableReport::valid(self : TableReport) -> Bool {
  self.errors.is_empty()
}
