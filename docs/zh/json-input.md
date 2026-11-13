# JSON 批量行输入

CSV 之外，也可以把一批行直接交给 MoonBit 库。顶层必须是 JSON 数组，元素有两种写法：

```json
[
  [1, "MoonBit"],
  [2, "数据"]
]
```

```json
[
  {"id": 1, "title": "MoonBit"},
  {"id": 2, "title": "数据"}
]
```

数组元素按 Table Schema 的字段顺序对应；对象元素按字段名取值，键的书写顺序不影响结果。两类元素不能混用。

```moonbit
let input = @core.input_from_json("books", text).unwrap()
let report = @core.validate_json_table("books", fields, input)
```

## 明确策略

- `null` 与对象中缺失的属性都转为 Missing，与 CSV 空单元格使用相同的 required/主键规则。
- 原生 JSON 数字只用于 integer/number 字段；整数必须精确落在有符号 64 位范围内，`9007199254740993` 这类大整数会按 JSON 解析器保留的原文精确处理。
- 原生 JSON 布尔只用于 boolean 字段。
- JSON 字符串仍按 CSV 的严格词法转换（例如 integer 不接受 `"1.0"`），不会把数字/布尔先转成字符串再猜测。
- 对象行出现未声明属性报 `extra-property`；数组行元素个数不符报 `row-width`。
- 输入一次性读入内存，不做流式或固定内存承诺。
