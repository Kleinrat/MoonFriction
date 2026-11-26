///|
fn geo_number(value : Json) -> Bool {
  value is Number(n, ..) && n.is_finite()
}

///|
fn geopoint(lon : Json, lat : Json) -> Result[Cell, String] {
  guard lon is Number(x, ..) &&
    lat is Number(y, ..) &&
    x >= -180.0 &&
    x <= 180.0 &&
    y >= -90.0 &&
    y <= 90.0 else {
    return Err("Expected longitude in [-180, 180] and latitude in [-90, 90]")
  }
  let a = if x == 0.0 { 0.0 } else { x }
  let b = if y == 0.0 { 0.0 } else { y }
  Ok(
    StructuredValue(Json::array([Json::number(a), Json::number(b)]).stringify()),
  )
}

///|
fn geopoint_text(raw : String) -> Result[Cell, String] {
  let parts = raw.split(",").collect()
  guard parts.length() == 2 else { return Err("Expected longitude,latitude") }
  let lon = @string.parse_double(parts[0].trim().to_owned()) catch {
    _ => return Err("Expected a numeric longitude")
  }
  let lat = @string.parse_double(parts[1].trim().to_owned()) catch {
    _ => return Err("Expected a numeric latitude")
  }
  geopoint(Json::number(lon), Json::number(lat))
}

///|
fn geopoint_json(value : Json, format : String) -> Result[Cell, String] {
  match (format, value) {
    ("array", Array(parts)) if parts.length() == 2 =>
      geopoint(parts[0], parts[1])
    ("object", Object(fields)) if fields.length() == 2 =>
      geopoint(prop(value, "lon"), prop(value, "lat"))
    _ => Err("Geopoint does not match its declared format")
  }
}

///|
fn json_items(value : Json, minimum : Int32, check : (Json) -> Bool) -> Bool {
  value is Array(items) && items.length() >= minimum && items.all(check)
}

///|
fn position(value : Json) -> Bool {
  json_items(value, 2, geo_number)
}

///|
fn line(value : Json) -> Bool {
  json_items(value, 2, position)
}

///|
fn ring(value : Json) -> Bool {
  value is Array(items) &&
  items.length() >= 4 &&
  items.all(position) &&
  items[0] == items[items.length() - 1]
}

///|
fn polygon(value : Json) -> Bool {
  json_items(value, 0, ring)
}

///|
fn valid_geo_geometry(value : Json, budget : Int32) -> Bool {
  if budget <= 0 || !geo_bbox(value) {
    return false
  }
  let coords = prop(value, "coordinates")
  match prop(value, "type") {
    String("Point") => position(coords)
    String("MultiPoint") => json_items(coords, 0, position)
    String("LineString") => line(coords)
    String("MultiLineString") => json_items(coords, 0, line)
    String("Polygon") => polygon(coords)
    String("MultiPolygon") => json_items(coords, 0, polygon)
    String("GeometryCollection") =>
      json_items(prop(value, "geometries"), 0, item => {
        valid_geo_geometry(item, budget - 1)
      })
    _ => false
  }
}

///|
fn geo_bbox(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  match fields.get("bbox") {
    None => true
    Some(Array(values)) =>
      values.length() >= 4 && values.length() % 2 == 0 && values.all(geo_number)
    _ => false
  }
}

///|
fn valid_geo_feature(value : Json) -> Bool {
  guard value is Object(fields) && prop(value, "type") is String("Feature") else {
    return false
  }
  let geometry = fields.get("geometry")
  let properties = fields.get("properties")
  let id = fields.get("id")
  geo_bbox(value) &&
  (geometry is Some(Null) || (geometry is Some(g) && valid_geo_geometry(g, 64))) &&
  properties is Some(Null | Object(_)) &&
  (id is None || id is Some(String(_)) || (id is Some(v) && geo_number(v)))
}

///|
fn geojson_cell(value : Json) -> Result[Cell, String] {
  let valid = match prop(value, "type") {
    String("Feature") => valid_geo_feature(value)
    String("FeatureCollection") =>
      geo_bbox(value) &&
      json_items(prop(value, "features"), 0, valid_geo_feature)
    _ => valid_geo_geometry(value, 64)
  }
  if valid {
    Ok(StructuredValue(canonical_json(value).stringify()))
  } else {
    Err("Expected a valid GeoJSON geometry, feature or feature collection")
  }
}

///|
fn topology_integer(value : Json) -> Bool {
  value is Number(n, ..) &&
  n >= -2147483648.0 &&
  n <= 2147483647.0 &&
  n == n.trunc()
}

///|
priv struct TopologyArc {
  first : Array[Double]
  last : Array[Double]
  count : Int32
}

///|
fn topology_arc(value : Json, quantized : Bool) -> TopologyArc {
  // The caller has already verified the positions and their coordinate types.
  let points = match value {
    Array(items) => items
    _ => abort("Invalid validated topology arc")
  }
  fn coordinates(point : Json) -> Array[Double] {
    match point {
      Array(items) =>
        items.map(item => {
          match item {
            Number(coordinate, ..) => coordinate
            _ => abort("Invalid validated topology coordinate")
          }
        })
      _ => abort("Invalid validated topology position")
    }
  }
  let first = coordinates(points[0])
  let last = coordinates(points[points.length() - 1])
  if quantized {
    let mut x = 0L
    let mut y = 0L
    for point in points {
      if point is Array(items) &&
        items[0] is Number(dx, ..) &&
        items[1] is Number(dy, ..) {
        x += dx.to_int64()
        y += dy.to_int64()
      }
    }
    last[0] = x.to_double()
    last[1] = y.to_double()
  }
  { first, last, count: points.length(), }
}

///|
fn topology_line(
  sequence : Json,
  arcs : Array[TopologyArc],
  closed : Bool,
) -> Bool {
  guard sequence is Array(indices) && !indices.is_empty() else { return false }
  let mut first : Array[Double]? = None
  let mut end : Array[Double]? = None
  let mut point_count = 0L
  for value in indices {
    guard value is Number(n, ..) && topology_integer(value) else {
      return false
    }
    let encoded = n.to_int()
    let reversed = encoded < 0
    let index = if reversed { -(encoded + 1) } else { encoded }
    guard arcs.get(index) is Some(arc) else { return false }
    let (start, last) = if reversed {
      (arc.last, arc.first)
    } else {
      (arc.first, arc.last)
    }
    if end is Some(previous) {
      if start != previous {
        return false
      }
      point_count += (arc.count - 1).to_int64()
    } else {
      first = Some(start)
      point_count += arc.count.to_int64()
    }
    end = Some(last)
  }
  !closed || (point_count >= 4L && first == end)
}

///|
fn topology_geometry(
  value : Json,
  arcs : Array[TopologyArc],
  check_position : (Json) -> Bool,
  depth : Int32,
) -> Bool {
  if depth <= 0 || !geo_bbox(value) {
    return false
  }
  if value is Object(fields) &&
    fields.get("properties") is Some(v) &&
    !(v is (Object(_) | Null)) {
    return false
  }
  fn polygon(value : Json) -> Bool {
    json_items(value, 1, ring => topology_line(ring, arcs, true))
  }
  let references = prop(value, "arcs")
  let coords = prop(value, "coordinates")
  match prop(value, "type") {
    String("Point") => check_position(coords)
    String("MultiPoint") => json_items(coords, 0, check_position)
    String("LineString") => topology_line(references, arcs, false)
    String("MultiLineString") =>
      json_items(references, 1, line => topology_line(line, arcs, false))
    String("Polygon") => polygon(references)
    String("MultiPolygon") => json_items(references, 1, polygon)
    String("GeometryCollection") =>
      json_items(prop(value, "geometries"), 0, geometry => {
        topology_geometry(geometry, arcs, check_position, depth - 1)
      })
    _ => false
  }
}

///|
fn topojson_cell(value : Json) -> Result[Cell, String] {
  guard value is Object(map) &&
    prop(value, "type") is String("Topology") &&
    prop(value, "arcs") is Array(arcs) &&
    prop(value, "objects") is Object(objects) &&
    geo_bbox(value) else {
    return Err("Expected TopoJSON Topology with arcs and objects")
  }
  let quantized = match map.get("transform") {
    None => false
    Some(transform) => {
      for name in ["scale", "translate"] {
        guard prop(transform, name) is Array(pair) &&
          pair.length() == 2 &&
          pair.all(geo_number) else {
          return Err("Invalid TopoJSON transform")
        }
      }
      true
    }
  }
  fn check_position(value : Json) -> Bool {
    position(value) &&
    (
      !quantized ||
      (
        value is Array(values) &&
        topology_integer(values[0]) &&
        topology_integer(values[1])
      )
    )
  }
  if !arcs.all(arc => json_items(arc, 2, check_position)) {
    return Err("Invalid TopoJSON arcs")
  }
  let summaries = arcs.map(arc => topology_arc(arc, quantized))
  for _, geometry in objects {
    if !topology_geometry(geometry, summaries, check_position, 64) {
      return Err("Invalid TopoJSON geometry, arc index or arc connectivity")
    }
  }
  Ok(StructuredValue(canonical_json(value).stringify()))
}
