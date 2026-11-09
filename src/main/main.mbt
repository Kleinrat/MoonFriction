///|
fn main {
  let fields = [
    @core.field("id", @core.Integer),
    @core.field("title", @core.Text),
  ]
  let report = @core.validate_table("books", fields, ["id", "title"], [
    ["1", "MoonBit"],
  ])
  println("Table valid: \{report.valid()}")
  println(
    "Primary key errors: \{@core.validate_primary_key(report.table, ["id"]).length()}",
  )
}
