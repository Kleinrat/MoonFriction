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
  if budget <= 0 || !(value is Object(_)) {
    return false
  }
  let coords = prop(value, "coordinates")
  let valid = match prop(value, "type") {
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
  valid && valid_geo_bbox(value)
}

///|
priv struct BoundingBox {
  lower : Array[Double]
  upper : Array[Double]
  geographic : Bool
}

///|
fn read_bbox(raw : Json, geographic : Bool) -> BoundingBox? {
  guard raw is Array(values) && values.length() >= 4 && values.length() % 2 == 0 else {
    return None
  }
  let dimension = values.length() / 2
  let lower = []
  let upper = []
  for axis in 0..<dimension {
    guard values[axis] is Number(low, ..) &&
      values[axis + dimension] is Number(high, ..) &&
      low.is_finite() &&
      high.is_finite() else {
      return None
    }
    if geographic && axis < 2 {
      let limit = if axis == 0 { 180.0 } else { 90.0 }
      if low < -limit || low > limit || high < -limit || high > limit {
        return None
      }
    }
    if !(geographic && axis == 0) && low > high {
      return None
    }
    lower.push(low)
    upper.push(high)
  }
  Some({ lower, upper, geographic, })
}

///|
fn BoundingBox::contains(self : BoundingBox, position : Array[Double]) -> Bool {
  guard position.length() == self.lower.length() else { return false }
  for axis, coordinate in position {
    let low = self.lower[axis]
    let high = self.upper[axis]
    if !coordinate.is_finite() {
      return false
    }
    if self.geographic && axis == 0 {
      let within = if low <= high {
        coordinate >= low && coordinate <= high
      } else {
        coordinate >= low || coordinate <= high
      }
      let same_meridian = (coordinate == -180.0 && high == 180.0) ||
        (coordinate == 180.0 && low == -180.0)
      if !within && !same_meridian {
        return false
      }
    } else if coordinate < low || coordinate > high {
      return false
    }
  }
  true
}

///|
fn position_coordinates(value : Json) -> Array[Double] {
  guard value is Array(items) else { abort("Invalid validated position") }
  items.map(item => {
    guard item is Number(coordinate, ..) else {
      abort("Invalid validated coordinate")
    }
    coordinate
  })
}

///|
fn coordinate_array_in_box(coords : Json, box : BoundingBox) -> Bool {
  guard coords is Array(items) else { return false }
  if items.is_empty() {
    return true
  }
  if items[0] is Number(_) {
    box.contains(position_coordinates(coords))
  } else {
    items.all(item => coordinate_array_in_box(item, box))
  }
}

///|
fn geojson_in_box(value : Json, box : BoundingBox) -> Bool {
  match prop(value, "type") {
    String("Feature") => {
      let geometry = prop(value, "geometry")
      geometry is Null || geojson_in_box(geometry, box)
    }
    String("FeatureCollection") =>
      json_items(prop(value, "features"), 0, item => geojson_in_box(item, box))
    String("GeometryCollection") =>
      json_items(prop(value, "geometries"), 0, item => geojson_in_box(item, box))
    _ => coordinate_array_in_box(prop(value, "coordinates"), box)
  }
}

///|
fn valid_geo_bbox(value : Json) -> Bool {
  guard value is Object(fields) else { return false }
  match fields.get("bbox") {
    None => true
    Some(raw) => read_bbox(raw, true) is Some(box) && geojson_in_box(value, box)
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
  (geometry is Some(Null) || (geometry is Some(g) && valid_geo_geometry(g, 64))) &&
  properties is Some(Null | Object(_)) &&
  (id is None || id is Some(String(_)) || (id is Some(v) && geo_number(v))) &&
  valid_geo_bbox(value)
}

///|
fn geojson_cell(value : Json) -> Result[Cell, String] {
  let valid = match prop(value, "type") {
    String("Feature") => valid_geo_feature(value)
    String("FeatureCollection") =>
      json_items(prop(value, "features"), 0, valid_geo_feature) &&
      valid_geo_bbox(value)
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
  let first = position_coordinates(points[0])
  let last = position_coordinates(points[points.length() - 1])
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
  if depth <= 0 || !(value is Object(_)) {
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
    prop(value, "objects") is Object(objects) else {
    return Err("Expected TopoJSON Topology with arcs and objects")
  }
  let transform = match map.get("transform") {
    None => None
    Some(transform) => {
      for name in ["scale", "translate"] {
        guard prop(transform, name) is Array(pair) &&
          pair.length() == 2 &&
          pair.all(geo_number) else {
          return Err("Invalid TopoJSON transform")
        }
      }
      Some(
        (
          position_coordinates(prop(transform, "scale")),
          position_coordinates(prop(transform, "translate")),
        ),
      )
    }
  }
  let quantized = transform is Some(_)
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
  if !valid_topology_bboxes(value, arcs, transform) {
    return Err("Invalid TopoJSON bounding box")
  }
  Ok(StructuredValue(canonical_json(value).stringify()))
}

///|
fn valid_topology_bboxes(
  value : Json,
  arcs : Array[Json],
  transform : (Array[Double], Array[Double])?,
) -> Bool {
  fn inside(point : Array[Double], box : BoundingBox) -> Bool {
    if transform is Some((scale, translate)) {
      point[0] = point[0] * scale[0] + translate[0]
      point[1] = point[1] * scale[1] + translate[1]
    }
    box.contains(point)
  }
  fn arc_inside(index : Int32, box : BoundingBox) -> Bool {
    guard arcs[index] is Array(points) else { return false }
    let mut x = 0L
    let mut y = 0L
    for item in points {
      let point = position_coordinates(item)
      if transform is Some(_) {
        x += point[0].to_int64()
        y += point[1].to_int64()
        point[0] = x.to_double()
        point[1] = y.to_double()
      }
      if !inside(point, box) {
        return false
      }
    }
    true
  }
  fn geometry_inside(
    geometry : Json,
    box : BoundingBox,
    checked : Map[Int32, Bool],
  ) -> Bool {
    fn references_inside(refs : Json) -> Bool {
      match refs {
        Array(items) => items.all(references_inside)
        Number(n, ..) => {
          let encoded = n.to_int()
          let index = if encoded < 0 { -(encoded + 1) } else { encoded }
          if checked.contains(index) {
            return true
          }
          if !arc_inside(index, box) {
            return false
          }
          checked[index] = true
          true
        }
        _ => false
      }
    }
    match prop(geometry, "type") {
      String("Point") =>
        inside(position_coordinates(prop(geometry, "coordinates")), box)
      String("MultiPoint") =>
        json_items(prop(geometry, "coordinates"), 0, p => {
          inside(position_coordinates(p), box)
        })
      String("GeometryCollection") =>
        json_items(prop(geometry, "geometries"), 0, g => {
          geometry_inside(g, box, checked)
        })
      _ => references_inside(prop(geometry, "arcs"))
    }
  }
  fn check_geometry(geometry : Json) -> Bool {
    guard geometry is Object(fields) else { return false }
    if fields.get("bbox") is Some(raw) {
      guard read_bbox(raw, false) is Some(box) &&
        geometry_inside(geometry, box, Map([])) else {
        return false
      }
    }
    if prop(geometry, "type") is String("GeometryCollection") {
      json_items(prop(geometry, "geometries"), 0, check_geometry)
    } else {
      true
    }
  }
  guard value is Object(fields) && prop(value, "objects") is Object(objects) else {
    return false
  }
  if fields.get("bbox") is Some(raw) {
    guard read_bbox(raw, false) is Some(box) else { return false }
    let checked = Map([])
    for index in 0..<arcs.length() {
      if !arc_inside(index, box) {
        return false
      }
      checked[index] = true
    }
    for _, geometry in objects {
      if !geometry_inside(geometry, box, checked) {
        return false
      }
    }
  }
  for _, geometry in objects {
    if !check_geometry(geometry) {
      return false
    }
  }
  true
}
