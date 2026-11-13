# 独立 Table Schema：不建数据包也能校验一张表

`datapackage.json` 适合多文件数据包；如果只有一个表、或者字段规则来自别的系统，可以直接使用 Table Schema。

```moonbit
let schema = @core.parse_table_schema(
  #|{"fields":[{"name":"id","type":"integer"},{"name":"title","type":"string"}],"primaryKey":"id"}
).unwrap()
let report = @core.validate_table_schema(
  "books", schema, ["id", "title"], [["1", "MoonBit"], ["1", "重复"]],
)
```

规则来源与数据包内嵌 schema 相同：字段名、类型、`missingValues`、`required`、`unique`、数值/长度约束、主键都会复用；自引用外键也能校验。**跨表外键**（`reference.resource` 指向别的表）在单表接口中无法解析，`validate_table_schema` 会明确返回 `foreign-key-scope`，不会误判为通过。

完整可编译消费者示例在 [`examples/standalone-consumer`](../../examples/standalone-consumer)，由 `python3 scripts/test_embedding.py` 在临时项目中编译运行。
