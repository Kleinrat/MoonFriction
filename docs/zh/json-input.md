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

## 同时检查多张 JSON 表（0.3.0 起）

按描述文件中的资源名调用 `input_from_json`，每个资源提供一批行，然后调用 `validate_json_package(descriptor, inputs)`。输入顺序可以不同。报告会指出重复主键、找不到目标的外键，以及缺少或多传的表。外键两端均通过字段校验后才检查该关系。

例如，商品表只有编号 1，订单却引用 42，报告会在订单表第一条记录给出 `foreign-key`。从仓库根目录运行 `python3 scripts/test_embedding.py` 可编译并验证这个用例。该接口使用内存中的行，描述文件沿用已有的 CSV 资源格式，CLI 加载文件的方式不变。

### 用命令行检查商品和订单

从仓库根目录运行以下命令。每个参数的等号左边是描述文件中的资源名，右边是相对于当前目录的 JSON 文件路径。

```sh
sh scripts/build.sh
node scripts/cli.mjs validate-json examples/shop/datapackage.json products=examples/shop/products.json orders=examples/shop/orders.json
```

示例会返回 `ok: true`，两张表各有一行。复制订单文件，把其中的 `product_id` 改为 `42`，再将命令中的订单路径指向副本，就能看到 `orders` 第一行的 `foreign-key` 错误。该命令只读取显式指定的文件。退出码 0 表示通过，1 表示数据或描述文件无效，2 表示参数或文件读取错误。每张表限 16 MiB。
