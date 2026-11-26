///|
fn ascii_alpha(c : Char) -> Bool {
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
}

///|
fn ascii_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn ascii_alnum(c : Char) -> Bool {
  ascii_alpha(c) || ascii_digit(c)
}

///|
fn ascii_hex(c : Char) -> Bool {
  ascii_digit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

///|
fn uri_characters(value : StringView, accept : (Char) -> Bool) -> Bool {
  let mut escape_digits = 0
  for c in value {
    if escape_digits > 0 {
      if !ascii_hex(c) {
        return false
      }
      escape_digits -= 1
    } else if c == '%' {
      escape_digits = 2
    } else if !accept(c) {
      return false
    }
  }
  escape_digits == 0
}

///|
fn uri_subdelimiter(c : Char) -> Bool {
  "!$&'()*+,;=".contains(c.to_string())
}

///|
fn uri_name_char(c : Char) -> Bool {
  ascii_alnum(c) || ['-', '.', '_', '~'].contains(c) || uri_subdelimiter(c)
}

///|
fn ipv4_address(raw : StringView) -> Bool {
  let parts = raw.split(".").collect()
  parts.length() == 4 &&
  parts.all(part => {
    if part.is_empty() ||
      part.length() > 3 ||
      (part.length() > 1 && part.has_prefix("0")) ||
      !part.iter().all(ascii_digit) {
      return false
    }
    let n = @string.parse_int(part.to_owned()) catch { _ => return false }
    n <= 255
  })
}

///|
fn ipv6_address(raw : StringView) -> Bool {
  let (before, after, compressed) = match raw.split_once("::") {
    Some((before, after)) => (before, after, true)
    None => (raw, ""[:], false)
  }
  let head = if before.is_empty() { [] } else { before.split(":").collect() }
  let tail = if after.is_empty() { [] } else { after.split(":").collect() }
  let parts = head + tail
  let mut groups = 0
  for index, part in parts {
    if part.contains(".") {
      if index != parts.length() - 1 ||
        (compressed && tail.is_empty()) ||
        !ipv4_address(part) {
        return false
      }
      groups += 2
    } else {
      if part.is_empty() || part.length() > 4 || !part.iter().all(ascii_hex) {
        return false
      }
      groups += 1
    }
  }
  if compressed {
    groups < 8
  } else {
    groups == 8
  }
}

///|
fn ip_literal(raw : StringView) -> Bool {
  if raw.has_prefix("v") || raw.has_prefix("V") {
    guard raw[1:].split_once(".") is Some((version, address)) else {
      return false
    }
    !version.is_empty() &&
    version.iter().all(ascii_hex) &&
    !address.is_empty() &&
    address.iter().all(c => uri_name_char(c) || c == ':')
  } else {
    ipv6_address(raw)
  }
}

///|
fn uri_authority(authority : StringView, needs_host : Bool) -> Bool {
  let host_port = match authority.split_once("@") {
    Some((user, host)) => {
      if !uri_characters(user, c => uri_name_char(c) || c == ':') {
        return false
      }
      host
    }
    None => authority
  }
  if host_port.has_prefix("[") {
    guard host_port[1:].split_once("]") is Some((address, suffix)) &&
      ip_literal(address) else {
      return false
    }
    return suffix.is_empty() ||
      (suffix.has_prefix(":") && suffix[1:].iter().all(ascii_digit))
  }
  let (host, port) = host_port.split_once(":").unwrap_or((host_port, ""[:]))
  (!needs_host || !host.is_empty()) &&
  uri_characters(host, uri_name_char) &&
  port.iter().all(ascii_digit)
}

///|
fn valid_uri(raw : String) -> Bool {
  guard raw.split_once(":") is Some((scheme, remainder)) &&
    scheme.iter().next() is Some(first) &&
    ascii_alpha(first) &&
    scheme.iter().all(c => ascii_alnum(c) || ['+', '-', '.'].contains(c)) else {
    return false
  }
  let protocol = scheme.to_lower()
  let needs_host = protocol == "http" || protocol == "https"
  let (hier_query, fragment) = remainder
    .split_once("#")
    .unwrap_or((remainder, ""[:]))
  let (hier, query) = hier_query.split_once("?").unwrap_or((hier_query, ""[:]))
  fn path_character(c : Char) -> Bool {
    uri_name_char(c) || ['/', ':', '@'].contains(c)
  }
  fn query_character(c : Char) -> Bool {
    path_character(c) || c == '?'
  }
  if !uri_characters(fragment, query_character) ||
    !uri_characters(query, query_character) {
    return false
  }
  if hier.has_prefix("//") {
    let (authority, path) = hier[2:]
      .split_once("/")
      .unwrap_or((hier[2:], ""[:]))
    uri_authority(authority, needs_host) && uri_characters(path, path_character)
  } else {
    !needs_host && uri_characters(hier, path_character)
  }
}

///|
fn email_local_part(local_part : StringView) -> Bool {
  if local_part.has_prefix("\"") &&
    local_part.has_suffix("\"") &&
    local_part.length() >= 2 {
    let mut escaped = false
    for c in local_part[1:local_part.length() - 1] {
      if c < ' ' || c > '~' || (!escaped && c == '"') {
        return false
      }
      escaped = c == '\\' && !escaped
    }
    return !escaped
  }
  let punctuation = "!#$%&'*+-/=?^_`{|}~"
  local_part
  .split(".")
  .all(token => {
    !token.is_empty() &&
    token.iter().all(c => ascii_alnum(c) || punctuation.contains(c.to_string()))
  })
}

///|
fn valid_email(raw : String) -> Bool {
  guard raw.rev_split_once("@") is Some((local_part, domain)) &&
    !local_part.is_empty() &&
    local_part.length() <= 64 &&
    !domain.is_empty() &&
    domain.length() <= 255 &&
    raw.length() <= 254 &&
    email_local_part(local_part) else {
    return false
  }
  if domain.has_prefix("[") && domain.has_suffix("]") {
    let address = domain[1:domain.length() - 1]
    if address.to_lower().has_prefix("ipv6:") {
      ipv6_address(address[5:])
    } else {
      ipv4_address(address)
    }
  } else {
    domain
    .split(".")
    .all(label => {
      !label.is_empty() &&
      label.length() <= 63 &&
      !label.has_prefix("-") &&
      !label.has_suffix("-") &&
      label.iter().all(c => ascii_alnum(c) || c == '-')
    })
  }
}

///|
fn valid_base64(raw : String) -> Bool {
  if re"^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$".execute(
      raw[:],
    )
    is None {
    return false
  }
  let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  if raw.has_suffix("==") {
    alphabet
    .find(raw.exact_view(start=raw.length() - 3, end=raw.length() - 2))
    .unwrap_or(1) %
    16 ==
    0
  } else if raw.has_suffix("=") {
    alphabet
    .find(raw.exact_view(start=raw.length() - 2, end=raw.length() - 1))
    .unwrap_or(1) %
    4 ==
    0
  } else {
    true
  }
}
