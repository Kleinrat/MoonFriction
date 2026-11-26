///|
fn custom_profile(value : Json, resource : Bool) -> String? {
  guard prop(value, "profile") is String(identifier) else { return None }
  let built_in = if resource {
    identifier == "data-resource" || identifier == "tabular-data-resource"
  } else {
    identifier == "data-package" || identifier == "tabular-data-package"
  }
  if built_in {
    None
  } else {
    Some(identifier)
  }
}

///|
/// Return the custom profiles declared by this Data Package and its resources.
/// The strings are profile identifiers or fully qualified schema URLs.
pub fn DataPackage::custom_profiles(self : DataPackage) -> Array[String] {
  let profiles : Map[String, Unit] = Map([])
  if custom_profile(self.original, false) is Some(id) {
    profiles[id] = ()
  }
  for resource in self.resources {
    if custom_profile(resource.metadata, true) is Some(id) {
      profiles[id] = ()
    }
  }
  profiles.keys().collect()
}

///|
fn profile_schema_at(document : Json, url : String) -> Json {
  guard document is Object(fields) && valid_uri(url) else { return document }
  let draft = match fields.get("$schema") {
    Some(String(uri)) => @moonschema.Draft::of(uri[:]).unwrap_or(Draft4)
    _ => Draft4
  }
  let keyword = if draft == Draft4 { "id" } else { "$id" }
  guard fields.get(keyword) is None else { return document }
  let schema = Map([])
  for key, value in fields {
    schema[key] = value
  }
  schema[keyword] = Json::string(url)
  Json::object(schema)
}

///|
/// Validate the original package and resource descriptors against supplied
/// custom JSON Schema documents. Keys are registry identifiers or schema URLs.
/// External references resolve only from the supplied documents. Unavailable
/// profile schemas and invalid descriptors produce scoped diagnostics.
pub fn DataPackage::validate_profiles(
  self : DataPackage,
  schemas : Map[String, Json],
) -> Array[Diagnostic] {
  let errors = []
  let compiled : Map[String, @moonschema.Schema] = Map([])
  for
    (resource, descriptor) in [("", self.original)] +
    self.resources.map(item => (item.name, item.metadata)) {
    guard custom_profile(descriptor, resource != "") is Some(id) else {
      continue
    }
    guard id != "" && (valid_uri(id) || valid_resource_name(id)) else {
      errors.push(
        issue(
          "descriptor", resource, 0, "profile", "Invalid profile identifier",
        ),
      )
      continue
    }
    guard schemas.get(id) is Some(Object(_) | True | False as document) else {
      errors.push(
        issue(
          "unsupported",
          resource,
          0,
          "profile",
          "No JSON Schema supplied for profile " + id,
        ),
      )
      continue
    }
    let schema = match compiled.get(id) {
      Some(schema) => schema
      None => {
        // v1 registry schemas use draft-04. Explicit $schema declarations on
        // custom documents override this default.
        let schema = @moonschema.Schema::new(
          profile_schema_at(document, id),
          draft=Draft4,
          remotes=schemas,
        ) catch {
          error => {
            errors.push(
              issue(
                "descriptor",
                resource,
                0,
                "profile",
                "Cannot load profile " + id + ": " + error.to_string(),
              ),
            )
            continue
          }
        }
        compiled[id] = schema
        schema
      }
    }
    for fault in schema.faults(descriptor) {
      errors.push(
        issue(
          "descriptor",
          resource,
          0,
          "profile" + fault.at,
          id + ": " + fault.message,
        ),
      )
    }
  }
  errors
}
