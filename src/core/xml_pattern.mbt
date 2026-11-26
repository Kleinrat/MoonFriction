///|
priv struct XmlPatternParser {
  chars : Array[Char]
  mut index : Int32
}

///|
priv struct XmlCharacterSet {
  ranges : Array[(Int32, Int32)]
  scalar : Int32?
}

///|
fn XmlPatternParser::peek(
  self : XmlPatternParser,
  offset~ : Int32 = 0,
) -> Char? {
  self.chars.get(self.index + offset)
}

///|
fn normalize_ranges(ranges : Array[(Int32, Int32)]) -> Array[(Int32, Int32)] {
  ranges.sort_by((a, b) => a.0.compare(b.0))
  let result = []
  for (lo, hi) in ranges {
    if result.last() is Some((start, end)) && lo <= end + 1 {
      result[result.length() - 1] = (start, end.max(hi))
    } else {
      result.push((lo, hi))
    }
  }
  result
}

///|
fn subtract_ranges(
  base : Array[(Int32, Int32)],
  excluded : Array[(Int32, Int32)],
) -> Array[(Int32, Int32)] {
  let result = []
  let mut first = 0
  for (lo, hi) in base {
    while first < excluded.length() && excluded[first].1 < lo {
      first += 1
    }
    let mut position = lo
    for index = first; index < excluded.length(); index = index + 1 {
      let (below, above) = excluded[index]
      if below > hi {
        break
      }
      if below > position {
        result.push((position, below - 1))
      }
      position = position.max(above + 1)
      if position > hi {
        break
      }
    }
    if position <= hi {
      result.push((position, hi))
    }
  }
  result
}

///|
let unicode_scalar_ranges : Array[(Int32, Int32)] = [
  (0, 0xD7FF),
  (0xE000, 0x10FFFF),
]

///|
let xml_name_start : Array[(Int32, Int32)] = [
  (0x3A, 0x3A),
  (0x41, 0x5A),
  (0x5F, 0x5F),
  (0x61, 0x7A),
  (0xC0, 0xD6),
  (0xD8, 0xF6),
  (0xF8, 0x2FF),
  (0x370, 0x37D),
  (0x37F, 0x1FFF),
  (0x200C, 0x200D),
  (0x2070, 0x218F),
  (0x2C00, 0x2FEF),
  (0x3001, 0xD7FF),
  (0xF900, 0xFDCF),
  (0xFDF0, 0xFFFD),
  (0x10000, 0xEFFFF),
]

///|
fn decode_ranges(encoded : String, result : Array[(Int32, Int32)]) -> Unit {
  for entry in encoded.split(" ") {
    let endpoints = entry.split("-").collect()
    let left = @string.parse_int(endpoints[0].to_owned(), base=16) catch {
      _ => abort("Invalid generated Unicode range")
    }
    let right = if endpoints.length() == 1 {
      left
    } else {
      @string.parse_int(endpoints[1].to_owned(), base=16) catch {
        _ => abort("Invalid generated Unicode range")
      }
    }
    result.push((left, right))
  }
}

///|
fn unicode_property(name : String) -> Result[Array[(Int32, Int32)], String] {
  let ranges = []
  if name.has_prefix("Is") {
    let key = String::from_iter(
      name[2:].iter().filter(c => ![' ', '_', '-'].contains(c)),
    ).to_lower()
    guard unicode_blocks.get(key) is Some(encoded) else {
      return Err("Unknown Unicode block: " + name)
    }
    decode_ranges(encoded, ranges)
  } else if name.length() == 1 &&
    ["L", "M", "N", "P", "Z", "S", "C"].contains(name) {
    for category, encoded in unicode_categories {
      if category.has_prefix(name) {
        decode_ranges(encoded, ranges)
      }
    }
  } else {
    guard unicode_categories.get(name) is Some(encoded) else {
      return Err("Unknown Unicode category: " + name)
    }
    decode_ranges(encoded, ranges)
  }
  Ok(subtract_ranges(normalize_ranges(ranges), [(0xD800, 0xDFFF)]))
}

///|
fn xml_scalar(character : Char) -> XmlCharacterSet {
  let code = character.to_int()
  { ranges: [(code, code)], scalar: Some(code), }
}

///|
fn XmlPatternParser::escape(
  self : XmlPatternParser,
) -> Result[XmlCharacterSet, String] {
  guard self.peek() is Some(character) else {
    return Err("Incomplete pattern escape")
  }
  self.index += 1
  if [
      '\\', '|', '.', '-', '^', '$', '?', '*', '+', '{', '}', '(', ')', '[', ']',
    ].contains(character) {
    return Ok(xml_scalar(character))
  }
  match character {
    'n' => return Ok(xml_scalar('\n'))
    'r' => return Ok(xml_scalar('\r'))
    't' => return Ok(xml_scalar('\t'))
    _ => ()
  }
  let ranges = match character {
    'i' | 'I' => xml_name_start
    'c' | 'C' =>
      normalize_ranges(
        xml_name_start +
        [
          (0x2D, 0x2E),
          (0x30, 0x39),
          (0xB7, 0xB7),
          (0x300, 0x36F),
          (0x203F, 0x2040),
        ],
      )
    's' | 'S' => [(9, 10), (13, 13), (32, 32)]
    'd' | 'D' =>
      match unicode_property("Nd") {
        Ok(ranges) => ranges
        Err(message) => return Err(message)
      }
    'w' | 'W' => {
      let exclusions = []
      for category, encoded in unicode_categories {
        if category.has_prefix("P") ||
          category.has_prefix("Z") ||
          category.has_prefix("C") {
          decode_ranges(encoded, exclusions)
        }
      }
      subtract_ranges(unicode_scalar_ranges, normalize_ranges(exclusions))
    }
    'p' | 'P' => {
      if self.peek() != Some('{') {
        return Err("Unicode properties need braces")
      }
      self.index += 1
      let property = StringBuilder()
      while self.peek() is Some(c) && c != '}' {
        property.write_char(c)
        self.index += 1
      }
      if self.peek() != Some('}') {
        return Err("Unclosed Unicode property")
      }
      self.index += 1
      match unicode_property(property.to_string()) {
        Ok(ranges) => ranges
        Err(message) => return Err(message)
      }
    }
    _ => return Err("Unsupported XML Schema pattern escape")
  }
  let negated = ['I', 'C', 'S', 'D', 'W', 'P'].contains(character)
  Ok({
    ranges: if negated {
      subtract_ranges(unicode_scalar_ranges, ranges)
    } else {
      ranges
    },
    scalar: None,
  })
}

///|
fn XmlPatternParser::class_atom(
  self : XmlPatternParser,
) -> Result[XmlCharacterSet, String] {
  guard self.peek() is Some(character) else {
    return Err("Unclosed character class")
  }
  self.index += 1
  match character {
    '\\' => self.escape()
    '[' | ']' => Err("Unescaped bracket in character class")
    _ => Ok(xml_scalar(character))
  }
}

///|
fn XmlPatternParser::character_class(
  self : XmlPatternParser,
  depth : Int32,
) -> Result[Array[(Int32, Int32)], String] {
  if depth == 64 {
    return Err("Character class nesting exceeds 64")
  }
  let negated = self.peek() == Some('^')
  if negated {
    self.index += 1
  }
  let ranges = []
  let mut saw_atom = false
  while self.peek() is Some(character) && character != ']' {
    if character == '-' && self.peek(offset=1) == Some('[') {
      if !saw_atom {
        return Err("Character class subtraction needs a base set")
      }
      self.index += 2
      let excluded = match self.character_class(depth + 1) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      if self.peek() != Some(']') {
        return Err("Subtraction must be the last part of a character class")
      }
      self.index += 1
      let base = normalize_ranges(ranges)
      return Ok(
        subtract_ranges(
          if negated {
            subtract_ranges(unicode_scalar_ranges, base)
          } else {
            base
          },
          excluded,
        ),
      )
    }
    saw_atom = true
    let first = match self.class_atom() {
      Ok(value) => value
      Err(message) => return Err(message)
    }
    if self.peek() == Some('-') &&
      self.peek(offset=1) != Some(']') &&
      self.peek(offset=1) != Some('[') {
      self.index += 1
      let second = match self.class_atom() {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      guard first.scalar is Some(low) &&
        second.scalar is Some(high) &&
        low <= high else {
        return Err("Invalid character range")
      }
      ranges.push((low, high))
    } else {
      for interval in first.ranges {
        ranges.push(interval)
      }
    }
  }
  if self.peek() != Some(']') || !saw_atom {
    return Err("Empty or unclosed character class")
  }
  self.index += 1
  let base = normalize_ranges(ranges)
  Ok(if negated { subtract_ranges(unicode_scalar_ranges, base) } else { base })
}

///|
fn write_regex_point(output : StringBuilder, code : Int32) -> Unit {
  output.write_string("\\u{")
  output.write_string(code.to_string(radix=16))
  output.write_char('}')
}

///|
fn write_regex_set(
  output : StringBuilder,
  ranges : Array[(Int32, Int32)],
) -> Unit {
  if ranges.is_empty() {
    // Empty sets cannot be written as an empty character class in this backend.
    output.write_string("(?:\\b\\B)")
    return
  }
  output.write_char('[')
  for (lo, hi) in ranges {
    write_regex_point(output, lo)
    if lo != hi {
      output.write_char('-')
      write_regex_point(output, hi)
    }
  }
  output.write_char(']')
}

///|
fn compile_xml_schema_regex(source : String) -> Result[@string.Regex, String] {
  let chars = source.to_array()
  let parser : XmlPatternParser = { chars, index: 0, }
  let output = StringBuilder()
  output.write_string("^(?:")
  // Preserve conventional outer anchors used in existing Frictionless files.
  if parser.peek() == Some('^') {
    parser.index += 1
  }
  while parser.peek() is Some(character) {
    parser.index += 1
    match character {
      '[' =>
        match parser.character_class(0) {
          Ok(ranges) => write_regex_set(output, ranges)
          Err(message) => return Err(message)
        }
      '\\' =>
        match parser.escape() {
          Ok(chars) => write_regex_set(output, chars.ranges)
          Err(message) => return Err(message)
        }
      '.' =>
        write_regex_set(
          output,
          subtract_ranges(unicode_scalar_ranges, [(10, 10), (13, 13)]),
        )
      '(' if parser.peek() == Some('?') =>
        return Err("Unsupported XML Schema group syntax")
      '$' if parser.index == chars.length() => ()
      '^' | '$' => write_regex_point(output, character.to_int())
      _ => output.write_char(character)
    }
  }
  output.write_string(")$")
  let expression = output.to_string()
  let regex = @string.Regex(expression[:]) catch {
    _ => return Err("Invalid or unsupported XML Schema pattern")
  }
  Ok(regex)
}
