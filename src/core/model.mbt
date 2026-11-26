///|
#derive(Eq, Debug)
pub(all) enum FieldType {
  Text
  Integer
  Number
  Boolean
  ObjectValueType
  ArrayValueType
  Any
  Date
  Time
  DateTime
  Year
  YearMonth
  Duration
  GeoPoint
  GeoJson
}

///|
#derive(Eq, Hash, Debug)
pub(all) enum Cell {
  Missing
  TextValue(String)
  IntegerValue(Int64)
  BigIntegerValue(@bigint.BigInt)
  NumberValue(Double)
  ExactNumberValue(ExactDecimal)
  SpecialNumber(String)
  BooleanValue(Bool)
  StructuredValue(String)
  TemporalValue(String)
}

///|
#derive(Debug)
pub(all) struct Field {
  name : String
  kind : FieldType
  format : String
  boolean_tokens : BooleanTokens?
  numeric_format : NumericFormat?
  required : Bool
  enum_values : Array[Cell]?
  unique : Bool
  minimum : Double?
  maximum : Double?
  min_length : Int32?
  max_length : Int32?
  pattern : FieldPattern?
  decimal_minimum : ExactDecimal?
  decimal_maximum : ExactDecimal?
  exact_minimum : @bigint.BigInt?
  exact_maximum : @bigint.BigInt?
  temporal_minimum : String?
  temporal_maximum : String?
}

///|
pub fn field(name : String, kind : FieldType) -> Field {
  {
    name,
    kind,
    format: "default",
    boolean_tokens: None,
    numeric_format: None,
    required: false,
    enum_values: None,
    unique: false,
    minimum: None,
    maximum: None,
    min_length: None,
    max_length: None,
    pattern: None,
    decimal_minimum: None,
    decimal_maximum: None,
    exact_minimum: None,
    exact_maximum: None,
    temporal_minimum: None,
    temporal_maximum: None,
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
