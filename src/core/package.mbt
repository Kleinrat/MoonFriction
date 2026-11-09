///|
#derive(Debug)
pub(all) struct InputTable {
  name : String
  header : Array[String]
  rows : Array[Array[String]]
}

///|
#derive(Debug)
pub(all) struct PackageReport {
  tables : Array[Table]
  errors : Array[Diagnostic]
}

///|
pub fn PackageReport::valid(self : PackageReport) -> Bool {
  self.errors.is_empty()
}

///|
/// No I/O: a host may load local files or supply rows from any trusted source.
pub fn validate_package(
  descriptor : Descriptor,
  inputs : Array[InputTable],
) -> PackageReport {
  let tables : Array[Table] = []
  let errors : Array[Diagnostic] = []
  if descriptor.resources.is_empty() {
    errors.push(issue("descriptor", "", 0, "", "resources cannot be empty"))
  }
  for resource in descriptor.resources {
    if !valid_resource_name(resource.name) ||
      descriptor.resources.filter(r => r.name == resource.name).length() != 1 {
      errors.push(
        issue(
          "descriptor",
          resource.name,
          0,
          "",
          "Resource names must be valid and unique",
        ),
      )
    }
    for key in resource.foreign_keys {
      if !descriptor.resources.any(r => r.name == key.resource) {
        errors.push(
          issue(
            "foreign-key-schema",
            resource.name,
            0,
            "",
            "Unknown reference resource",
          ),
        )
      }
    }
  }
  for input in inputs {
    if !descriptor.resources.any(r => r.name == input.name) ||
      inputs.filter(x => x.name == input.name).length() != 1 {
      errors.push(
        issue(
          "resource-input",
          input.name,
          0,
          "",
          "Unexpected or duplicate resource input",
        ),
      )
    }
  }
  for resource in descriptor.resources {
    let matches = inputs.filter(t => t.name == resource.name)
    if matches.length() != 1 {
      errors.push(
        issue(
          "resource-input",
          resource.name,
          0,
          "",
          "Exactly one input table is required",
        ),
      )
      continue
    }
    let input = matches[0]
    let report = validate_table(
      resource.name,
      resource.fields,
      input.header,
      input.rows,
      missing_values=resource.missing_values,
    )
    for e in report.errors {
      errors.push(e)
    }
    if report.valid() {
      if !resource.primary_key.is_empty() {
        for e in validate_primary_key(report.table, resource.primary_key) {
          errors.push(e)
        }
      }
      tables.push(report.table)
    }
  }
  // Validate each relationship only when its source and target table are usable.
  for resource in descriptor.resources {
    let sources = tables.filter(t => t.name == resource.name)
    if sources.length() != 1 {
      continue
    }
    for key in resource.foreign_keys {
      let targets = tables.filter(t => t.name == key.resource)
      if targets.length() != 1 {
        continue
      }
      for
        e in validate_foreign_key(
          sources[0],
          key.fields,
          targets[0],
          key.reference_fields,
        ) {
        errors.push(e)
      }
    }
  }
  { tables, errors, }
}
