///|
test "general data package reads all locator forms in declaration order" {
  let descriptor =
    #|{"name":"mixed","x-custom":{"id":9007199254740993},"resources":[{"name":"parts","path":["a.bin","b.bin"],"schema":"schemas/record.json"},{"name":"outside","path":["https://example.org/a","http://example.org/b"]},{"name":"inside","data":{"id":9007199254740993}},{"name":"label","data":"hello","mediatype":"text/plain"}]}
  let data = parse_data_package(descriptor).unwrap()
  assert_eq(data.original.stringify(), descriptor)
  let read_local = fn(path) {
    match path {
      "a.bin" => Ok(b"ab")
      "b.bin" => Ok(b"cd")
      _ => Err("unexpected read_local file")
    }
  }
  let remote = fn(path) {
    match path {
      "https://example.org/a" => Ok(b"ef")
      "http://example.org/b" => Ok(b"gh")
      _ => Err("unexpected URL")
    }
  }
  let parts = data.resources[0].read(read_local, remote).unwrap()
  assert_true(parts is FileBytes(b"abcd"))
  assert_true(data.resources[0].read(read_local, remote, max_bytes=3) is Err(_))
  assert_true(
    data.resources[1].read(read_local, remote).unwrap() is FileBytes(b"efgh"),
  )
  assert_true(
    data.resources[2].read(read_local, remote).unwrap()
    is InlineValue(Object(_)),
  )
  assert_true(
    data.resources[3].read(read_local, remote).unwrap()
    is InlineValue(String("hello")),
  )
}

///|
test "general descriptor rejects invalid locators and metadata with context" {
  for
    (suffix, field) in [
      ("\"path\":\"../a\"", "path/data"),
      ("\"path\":\"http:///file\"", "path/data"),
      ("\"path\":[\"a.bin\",\"https://example.org/b\"]", "path/data"),
      ("\"path\":[\"a.bin\",null]", "path/data"),
      ("\"path\":[]", "path/data"),
      ("\"path\":\"a.bin\",\"data\":{}", "path/data"),
      ("\"data\":\"plain\"", "path/data"),
      ("\"data\":42", "path/data"),
      ("\"path\":\"a.bin\",\"schema\":\"/absolute/schema.json\"", "schema"),
      ("\"path\":\"a.bin\",\"bytes\":-2", "bytes"),
      (
        "\"path\":\"a.bin\",\"licenses\":[{\"title\":\"missing identifier\"}]", "licenses",
      ),
    ] {
    let text = "{\"resources\":[{\"name\":\"bad\"," + suffix + "}]}"
    let errors = parse_data_package(text).unwrap_err()
    assert_true(errors.any(e => e.resource == "bad" && e.field == field))
  }
  let empty =
    #|{"resources":[]}
  assert_true(parse_data_package(empty) is Err(_))
  let duplicate =
    #|{"resources":[{"name":"a","path":"a"},{"name":"a","data":[]}]}
  assert_true(parse_data_package(duplicate) is Err(_))
}

///|
test "core resolves referenced schema objects through the matching caller loader" {
  let descriptor =
    #|{"created":"2024-02-29T01:05:00.12+01:00","resources":[{"name":"items","path":"items.csv","schema":"schema.json"},{"name":"remote","path":"https://example.org/items","schema":"https://example.org/schema.json"}]}
  let data = parse_data_package(descriptor).unwrap()
  fn read_local(file : String) -> Result[Bytes, String] {
    if file == "schema.json" {
      Ok(b"{\"fields\":[]}")
    } else {
      Err("unexpected file")
    }
  }
  fn read_remote(url : String) -> Result[Bytes, String] {
    if url == "https://example.org/schema.json" {
      Ok(b"[]")
    } else {
      Err("unexpected URL")
    }
  }
  assert_true(
    data.resources[0].resolve_schema(read_local, read_remote).unwrap()
    is Some(Object(_)),
  )
  assert_true(
    data.resources[1].resolve_schema(read_local, read_remote) is Err(_),
  )
  let invalid = descriptor.replace_all(old="2024-02-29", new="2023-02-29")
  assert_true(
    parse_data_package(invalid).unwrap_err().any(e => e.field == "created"),
  )
}

///|
test "Data Package accepts registry license identifiers and license URLs" {
  let package_text =
    #|{"licenses":[{"name":"MIT"},{"name":"ODC-PDDL-1.0"},{"path":"https://example.org/LICENSE"}],"resources":[{"name":"readme","path":"README.md","licenses":[{"name":"CC-BY-4.0"}]}]}
  assert_true(parse_data_package(package_text) is Ok(_))
  let unknown = package_text.replace_all(old="CC-BY-4.0", new="made-up-license")
  let errors = parse_data_package(unknown).unwrap_err()
  assert_true(errors.any(e => e.resource == "readme" && e.field == "licenses"))
}

///|
test "package and resource profiles validate original descriptors and supplied refs" {
  let manifest =
    #|{"profile":"inventory-package","title":"Inventory","resources":[{"name":"items","data":[],"profile":"https://example.org/resource.json","retention":30}]}
  let package_schema = @json.parse(
    (
      #|{"type":"object","required":["title"]}
    ),
  )
  let resource_schema = @json.parse(
    (
      #|{"$schema":"https://json-schema.org/draft/2020-12/schema","properties":{"retention":{"$ref":"days.json"}},"required":["retention"]}
    ),
  )
  let days = @json.parse(
    (
      #|{"type":"integer","minimum":1}
    ),
  )
  let profile_docs = Map([
    ("inventory-package", package_schema),
    ("https://example.org/resource.json", resource_schema),
    ("https://example.org/days.json", days),
  ])
  let data = parse_data_package(manifest).unwrap()
  assert_eq(data.custom_profiles().length(), 2)
  assert_true(data.validate_profiles(profile_docs).is_empty())
  let invalid = parse_data_package(
    manifest.replace_all(old="\"retention\":30", new="\"retention\":0"),
  ).unwrap()
  let errors = invalid.validate_profiles(profile_docs)
  assert_eq(errors.length(), 1)
  assert_eq(errors[0].resource, "items")
  assert_true(errors[0].field.has_prefix("profile"))
  assert_true(data.validate_profiles(Map([])).all(e => e.code == "unsupported"))
  profile_docs.remove("https://example.org/days.json")
  assert_true(
    data.validate_profiles(profile_docs).any(e => e.resource == "items"),
  )
}

///|
test "created follows the RFC 3339 examples and validates leap-second days" {
  for
    (stamp, expected) in [
      ("1985-04-12T23:20:50.52Z", true),
      ("0001-01-01T00:00:00+01:00", true),
      ("9999-12-31T23:59:59-01:00", true),
      ("1990-12-31T15:59:60-08:00", true),
      ("1990-12-31t23:59:60z", true),
      ("1991-01-01T05:59:60+06:00", true),
      ("1990-12-31T23:59:60+06:00", false),
      ("1991-12-31T23:59:60Z", false),
      ("1990-12-31T24:00:00Z", false),
      ("2024-11-26T12:00:00+01:02:03", false),
    ] {
    let descriptor = "{\"created\":\"" +
      stamp +
      "\",\"resources\":[{\"name\":\"items\",\"data\":[]}]}"
    match parse_data_package(descriptor) {
      Ok(_) => assert_true(expected)
      Err(errors) => {
        assert_false(expected)
        assert_eq(errors.map(e => e.field), ["created"])
      }
    }
  }
}

///|
test "built-in tabular profiles enforce resource profile, schema and storage shape" {
  let csv_package =
    #|{"profile":"tabular-data-package","resources":[{"name":"items","profile":"tabular-data-resource","path":"items.csv","schema":{"fields":[{"name":"id","type":"integer"}]}}]}
  let inline = csv_package.replace_all(
    old="\"path\":\"items.csv\"",
    new="\"data\":[{\"id\":1}]",
  )
  for
    valid in [
      csv_package,
      inline,
      csv_package.replace_all(
        old="{\"fields\":[{\"name\":\"id\",\"type\":\"integer\"}]}",
        new="\"schema.json\"",
      ),
    ] {
    assert_true(parse_data_package(valid) is Ok(_))
  }
  for
    (before, after, field) in [
      ("\"profile\":\"tabular-data-resource\",", "", "profile"),
      (
        ",\"schema\":{\"fields\":[{\"name\":\"id\",\"type\":\"integer\"}]}", "",
        "schema",
      ),
      ("\"path\":\"items.csv\"", "\"path\":\"items.json\"", "format"),
      ("\"path\":\"items.csv\"", "\"data\":[1]", "data"),
      (
        "\"path\":\"items.csv\"", "\"data\":\"id\\n1\",\"format\":\"csv\"", "data",
      ),
    ] {
    let errors = parse_data_package(
      csv_package.replace_all(old=before, new=after),
    ).unwrap_err()
    assert_true(errors.any(e => e.resource == "items" && e.field == field))
  }
  let generic =
    #|{"resources":[{"name":"items","format":"csv","data":"id\n1"}]}
  assert_true(parse_data_package(generic) is Ok(_))
}
