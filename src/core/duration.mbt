///|
fn cast_duration(raw : String) -> Result[Cell, String] {
  let pattern = re"^(-)?P(?:([0-9]+)Y)?(?:([0-9]+)M)?(?:([0-9]+)D)?(?:T(?:([0-9]+)H)?(?:([0-9]+)M)?(?:([0-9]+)(?:\.([0-9]+))?S)?)?$"
  guard pattern.execute(raw[:]) is Some(matched) &&
    raw != "P" &&
    raw != "-P" &&
    !raw.has_suffix("T") else {
    return Err("Expected an XML Schema duration")
  }
  fn component(index : Int32) -> @bigint.BigInt {
    match matched.group(index) {
      Some(value) => @bigint.BigInt::from_string(value.to_owned())
      None => @bigint.BigInt::from_int(0)
    }
  }
  let months = component(2) * @bigint.BigInt::from_int(12) + component(3)
  let seconds = component(4) * @bigint.BigInt::from_int(86400) +
    component(5) * @bigint.BigInt::from_int(3600) +
    component(6) * @bigint.BigInt::from_int(60) +
    component(7)
  let fraction = match matched.group(8) {
    Some(value) => value.trim_end(chars="0").to_owned()
    None => ""
  }
  if months.is_zero() && seconds.is_zero() && fraction == "" {
    return Ok(TemporalValue("PT0S"))
  }
  let prefix = if raw.has_prefix("-") { "-P" } else { "P" }
  let month_part = if months.is_zero() { "" } else { months.to_string() + "M" }
  let decimal_part = if fraction == "" { "" } else { "." + fraction }
  let time_part = if seconds.is_zero() && fraction == "" {
    ""
  } else {
    "T" + seconds.to_string() + decimal_part + "S"
  }
  Ok(TemporalValue(prefix + month_part + time_part))
}
