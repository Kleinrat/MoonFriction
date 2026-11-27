///|
#derive(Debug)
pub(all) enum ResourceLocation {
  LocalPaths(Array[String])
  RemoteUrls(Array[String])
  InlineData(Json)
}

///|
#derive(Debug)
pub(all) struct DataResource {
  name : String
  location : ResourceLocation
  metadata : Json
}

///|
/// General Data Package descriptor, independent of the tabular validation API.
/// Original descriptors retain extension properties and exact JSON number literals.
#derive(Debug)
pub(all) struct DataPackage {
  original : Json
  resources : Array[DataResource]
}

///|
fn http_resource_url(value : String) -> Bool {
  let lower = value.to_lower()
  (lower.has_prefix("https://") || lower.has_prefix("http://")) &&
  valid_uri(value)
}

///|
fn data_locator(value : Json) -> Bool {
  value is String(s) && (safe_resource_path(s) || http_resource_url(s))
}

///|
fn data_location(
  fields : Map[String, Json],
) -> Result[ResourceLocation, String] {
  match (fields.get("path"), fields.get("data")) {
    (Some(path), None) =>
      match strings(path) {
        Some(paths) if !paths.is_empty() && paths.all(safe_resource_path) =>
          Ok(LocalPaths(paths))
        Some(paths) if !paths.is_empty() && paths.all(http_resource_url) =>
          Ok(RemoteUrls(paths))
        _ =>
          Err(
            "path must contain relative POSIX paths or HTTP(S) URLs of one kind",
          )
      }
    (None, Some(Array(_) | Object(_) as data)) => Ok(InlineData(data))
    (None, Some(String(_) as data)) =>
      if (fields.get("format") is Some(String(s)) && s != "") ||
        (fields.get("mediatype") is Some(String(s)) && s != "") {
        Ok(InlineData(data))
      } else {
        Err("Inline string data requires format or mediatype")
      }
    (None, Some(_)) => Err("Inline data must be an array, object or string")
    _ => Err("Expected exactly one of path and data")
  }
}

///|
fn check_package_metadata(
  fields : Map[String, Json],
  owner : String,
  is_resource : Bool,
  errors : Array[Diagnostic],
) -> Unit {
  let common = ["profile", "title", "description"]
  let text = if is_resource {
    ["format", "mediatype", "encoding", "hash"]
  } else {
    ["id", "version"]
  }
  for key in common + text {
    if fields.get(key) is Some(value) && !(value is String(_)) {
      errors.push(issue("descriptor", owner, 0, key, "Expected a string"))
    }
  }
  for key in ["licenses", "sources", "contributors"] {
    if is_resource && key == "contributors" {
      continue
    }
    if fields.get(key) is Some(value) {
      let entries = match value {
        Array(entries) => entries
        _ => {
          errors.push(issue("descriptor", owner, 0, key, "Expected an array"))
          continue
        }
      }
      for entry in entries {
        let valid = match entry {
          Object(item) => {
            let name = item.get("name")
            let title = item.get("title")
            let path = item.get("path")
            let required = if key == "licenses" {
              match name {
                None => path is Some(_)
                Some(String(identifier)) => known_package_license(identifier)
                _ => false
              }
            } else {
              title is Some(String(_))
            }
            let valid_path = match path {
              None => true
              Some(v) if key == "contributors" =>
                v is String(url) && http_resource_url(url)
              Some(v) => data_locator(v)
            }
            let optional_text = if key == "contributors" {
              ["email", "role", "organization"]
            } else if key == "sources" {
              ["email"]
            } else {
              ["name", "title"]
            }
            required &&
            valid_path &&
            optional_text.all(k => {
              match item.get(k) {
                None | Some(String(_)) => true
                _ => false
              }
            })
          }
          _ => false
        }
        if !valid {
          errors.push(
            issue("descriptor", owner, 0, key, "Invalid metadata entry"),
          )
        }
      }
    }
  }
}

///|
fn created_timestamp(value : Json) -> Bool {
  guard value is String(raw) else { return false }
  // RFC 3339 permits lowercase T and Z. Ordinary timestamps only need
  // lexical validation here because the descriptor retains the local year.
  let timestamp = raw.to_upper()
  guard expect_char(timestamp, 10, 'T') &&
    parse_date_at(timestamp, 0) is Ok(_) &&
    parse_time_at(timestamp, 11, allow_leap_second=true)
    is Ok((_, _, second, _, end)) &&
    parse_offset_at(timestamp, end) is Ok(_) else {
    return false
  }
  second != 60 || normalize_temporal("datetime", timestamp) is Ok(_)
}

///|
fn check_tabular_profile(
  resource : Json,
  name : String,
  package_is_tabular : Bool,
  errors : Array[Diagnostic],
) -> Unit {
  if !(prop(resource, "profile") is String("tabular-data-resource")) {
    if package_is_tabular {
      errors.push(
        issue(
          "descriptor", name, 0, "profile", "Expected tabular-data-resource in a tabular-data-package",
        ),
      )
    }
    return
  }
  match prop(resource, "schema") {
    Object(_) as schema =>
      parse_schema_value(schema, name, true, errors) |> ignore
    String(_) => () // The general locator check and the caller handle references.
    Null =>
      errors.push(
        issue(
          "descriptor", name, 0, "schema", "A tabular-data-resource requires a Table Schema",
        ),
      )
    _ => () // Already reported by the general schema check.
  }
  match prop(resource, "data") {
    Null =>
      if tabular_format(resource) != "csv" {
        errors.push(
          issue(
            "descriptor", name, 0, "format", "External tabular-data-resource data must be CSV",
          ),
        )
      }
    Array(rows) if rows.all(row => row is (Array(_) | Object(_))) => ()
    _ =>
      errors.push(
        issue(
          "descriptor", name, 0, "data", "Inline tabular-data-resource data must be an array of JSON rows",
        ),
      )
  }
}

///|
/// Parse the general v1 descriptor and classify each locator without loading it.
pub fn parse_data_package(
  text : String,
) -> Result[DataPackage, Array[Diagnostic]] {
  let original = @json.parse(text, preserve_number_repr=true) catch {
    _ => return Err([issue("json", "", 0, "", "Invalid JSON descriptor")])
  }
  guard original is Object(package_fields) else {
    return Err([issue("descriptor", "", 0, "", "Expected a package object")])
  }
  guard package_fields.get("resources") is Some(Array(items)) &&
    !items.is_empty() else {
    return Err([
      issue(
        "descriptor", "", 0, "resources", "Expected a nonempty resource array",
      ),
    ])
  }
  let errors = []
  let resources = []
  let names : Map[String, Bool] = Map([])
  let package_is_tabular = prop(original, "profile")
    is String("tabular-data-package")
  check_package_metadata(package_fields, "", false, errors)
  if package_fields.get("name") is Some(value) &&
    !(value is String(name) && valid_resource_name(name)) {
    errors.push(
      issue("descriptor", "", 0, "name", "Invalid package identifier"),
    )
  }
  if package_fields.get("keywords") is Some(value) &&
    !(value is Array(words) && words.all(word => word is String(_))) {
    errors.push(
      issue("descriptor", "", 0, "keywords", "Expected an array of strings"),
    )
  }
  if package_fields.get("homepage") is Some(value) &&
    !(value is String(url) && http_resource_url(url)) {
    errors.push(
      issue("descriptor", "", 0, "homepage", "Expected an HTTP(S) URL"),
    )
  }
  if package_fields.get("image") is Some(value) && !data_locator(value) {
    errors.push(issue("descriptor", "", 0, "image", "Invalid image locator"))
  }
  if package_fields.get("created") is Some(value) && !created_timestamp(value) {
    errors.push(
      issue("descriptor", "", 0, "created", "Expected an RFC 3339 timestamp"),
    )
  }
  for item in items {
    guard item is Object(fields) else {
      errors.push(
        issue("descriptor", "", 0, "resources", "Expected a resource object"),
      )
      continue
    }
    let name = json_text(prop(item, "name")).unwrap_or("")
    if !valid_resource_name(name) || names.contains(name) {
      errors.push(
        issue(
          "descriptor", name, 0, "name", "Invalid or duplicate resource name",
        ),
      )
    }
    names[name] = true
    check_package_metadata(fields, name, true, errors)
    if fields.get("schema") is Some(value) &&
      !(value is Object(_) || data_locator(value)) {
      errors.push(
        issue(
          "descriptor", name, 0, "schema", "Expected a schema object or locator",
        ),
      )
    }
    if fields.get("bytes") is Some(value) &&
      !(value is Number(n, ..) && n.is_finite() && n >= 0.0 && n == n.trunc()) {
      errors.push(
        issue("descriptor", name, 0, "bytes", "Expected a nonnegative integer"),
      )
    }
    check_tabular_profile(item, name, package_is_tabular, errors)
    match data_location(fields) {
      Ok(location) => resources.push({ name, location, metadata: item, })
      Err(message) =>
        errors.push(issue("descriptor", name, 0, "path/data", message))
    }
  }
  if errors.is_empty() {
    Ok({ original, resources, })
  } else {
    Err(errors)
  }
}

///|
#derive(Debug)
pub(all) enum ResourceContent {
  FileBytes(Bytes)
  InlineValue(Json)
}

///|
/// Resolve a resource with caller-supplied I/O. The host provides the package
/// root for local paths and decides which URLs it trusts. File parts are read
/// in descriptor order and returned as one byte sequence.
pub fn DataResource::read(
  self : DataResource,
  read_local : (String) -> Result[Bytes, String],
  read_remote : (String) -> Result[Bytes, String],
  max_bytes~ : Int32 = 16777216,
) -> Result[ResourceContent, String] {
  let (paths, read) = match self.location {
    LocalPaths(paths) => (paths, read_local)
    RemoteUrls(urls) => (urls, read_remote)
    InlineData(value) => return Ok(InlineValue(value))
  }
  let parts = []
  let mut length = 0
  for path in paths {
    let bytes = match read(path) {
      Ok(bytes) => bytes
      Err(message) => return Err(path + ": " + message)
    }
    if max_bytes < length || bytes.length() > max_bytes - length {
      return Err("Resource exceeds byte limit")
    }
    length += bytes.length()
    parts.push(bytes)
  }
  Ok(FileBytes(Bytes::from_iter(parts.iter().flat_map(bytes => bytes.iter()))))
}

///|
/// Resolve the optional schema using the same host-controlled I/O as resources.
pub fn DataResource::resolve_schema(
  self : DataResource,
  read_local : (String) -> Result[Bytes, String],
  read_remote : (String) -> Result[Bytes, String],
) -> Result[Json?, String] {
  let value = prop(self.metadata, "schema")
  match value {
    Null => Ok(None)
    Object(_) => Ok(Some(value))
    String(location) => {
      let read = if http_resource_url(location) {
        read_remote
      } else {
        read_local
      }
      let bytes = match read(location) {
        Ok(bytes) => bytes
        Err(message) => return Err(location + ": " + message)
      }
      let schema = @json.parse(
        @utf8.decode(bytes[:]),
        preserve_number_repr=true,
      ) catch {
        _ => return Err("Referenced schema must be a JSON object")
      }
      if schema is Object(_) {
        Ok(Some(schema))
      } else {
        Err("Referenced schema must be a JSON object")
      }
    }
    _ => Err("Expected an inline schema or schema locator")
  }
}
