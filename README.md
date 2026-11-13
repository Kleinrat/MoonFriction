# MoonFriction

第一次接触？先看[中文入门](docs/zh/getting-started.md)和[四种错误演示](docs/zh/errors-demo.md)。

**MoonBit 原生的 Frictionless Data Package v1 / Table Schema v1 子集实现。**

把 CSV、字段定义和表间关系放在一个标准数据包中：读取描述文件，转换字段类型，检查约束、主键和外键，再导出其他工具能够读取的数据包。

当前版本 [Kleinrat/frictionless@0.1.2](https://mooncakes.io/docs/Kleinrat/frictionless@0.1.2)。支持范围是明确子集，不宣称完整标准兼容。

[持续集成](https://github.com/Kleinrat/MoonFriction/actions) · [测试记录](docs/TESTING-2026-11-09.md) · [发布验证](docs/RELEASE-0.1.2.md)

## 能做什么

- 读取带内嵌 schema 的本地 UTF-8 CSV 数据包，保留原始描述信息。
- 转换 string、integer、number、boolean，区分缺失值、转换错误与约束错误。
- 检查 required、unique、minimum、maximum、minLength、maxLength。
- 检查单字段 / 组合主键、跨表与自引用外键。
- 输出资源名、逻辑记录号、字段名和错误代码。
- 导出新目录，保留描述信息和 CSV 原始内容；拒绝覆盖已有目标。
- 可作为纯 MoonBit 库调用；Node.js CLI 只负责本地文件 I/O 和参数。

三个合成示例：商品与订单、学生与成绩、传感器与读数。它们用于验证数据交换能力，不代表真实用户采用。

## 运行

需要 MoonBit、Node.js 22+。当前验证：`moonc 0.10.20`。CI 检查编译器不低于赛事要求的 0.10.16；并不表示所有旧工具链均已测试。

```sh
moon update
sh scripts/build.sh
node scripts/cli.mjs inspect examples/shop/datapackage.json
node scripts/cli.mjs validate examples/shop/datapackage.json
node scripts/cli.mjs export examples/shop/datapackage.json /tmp/shop-export
```

`export` 目标必须不存在。验证成功退出码为0；数据或描述符无效为1；文件访问、命令参数等错误为2。

另两个示例：

```sh
node scripts/cli.mjs validate examples/school/datapackage.json
node scripts/cli.mjs validate examples/sensors/datapackage.json
```

例如，订单引用不存在的商品时，报告 `foreign-key` 错误，而不是自动删除或改写记录。

## 独立校验一张表（无需 Data Package）

Table Schema 也可以脱离 `datapackage.json` 单独使用。`parse_table_schema` 解析字段、`missingValues`、主键和自引用外键，`validate_table_schema` 只校验这一张表；跨表外键不会假装已经解析，而会返回 `foreign-key-scope`。

```moonbit
let schema = @core.parse_table_schema(
  #|{"fields":[{"name":"id","type":"integer"},{"name":"title"}],"primaryKey":"id"}
).unwrap()
let report = @core.validate_table_schema(
  "books", schema, ["id", "title"], [["1", "MoonBit"], ["1", "重复"]],
)
println(report.valid()) // false：主键重复
```

可运行的全新消费者见 [`examples/standalone-consumer`](examples/standalone-consumer)；`scripts/test_embedding.py` 会把它作为独立项目编译。完整说明见[独立 Table Schema](docs/zh/standalone-schema.md)。

## JSON 批量行输入

`input_from_json` 接收顶层 JSON 数组，元素既可以按字段顺序的数组，也可以是按字段名取值的对象；对象键顺序不影响字段顺序。原生 JSON 数字/布尔不再转字符串：

```moonbit
let input = @core.input_from_json("books", #|[[1,"MoonBit"],[2,"数据"]]
).unwrap()
let report = @core.validate_json_table("books", fields, input)
```

规则与 CSV 对等：`null` 和缺失属性都视为 Missing；原生数字只用于 integer/number，原生布尔只用于 boolean，其他标量不会被偷偷字符串化；对象行出现未声明属性会报 `extra-property`。字符串值仍使用与 CSV 相同的严格词法。批量输入完全在内存中处理，不做流式或固定内存承诺。详见[JSON 批量输入](docs/zh/json-input.md)。

## 作为 MoonBit 库使用

在已有 MoonBit 项目中安装：

```sh
moon update
moon add Kleinrat/frictionless@0.1.2
```

在调用包的 `moon.pkg` 中加入：

```moonbit
import {
  "Kleinrat/frictionless/src/core",
}
```

公共包路径为 `Kleinrat/frictionless/src/core`。文件 I/O 不进入核心库；调用者可以提供从任意来源获得的表头和原始字符串记录。

```moonbit
let fields = [@core.field("id", @core.Integer), @core.field("title", @core.Text)]
let report = @core.validate_table("books", fields, ["id", "title"], [["1", "MoonBit"]])
println(report.valid())
```

上述代码需要在调用包的 `moon.pkg` 中导入公共包，并放在函数中；完整可运行示例见 `src/main`：

```sh
moon run src/main --target js
```

API 主入口：

| 函数 | 用途 |
|---|---|
| `parse_descriptor` | 读取标准描述文件，验证当前支持范围 |
| `parse_table_schema` / `validate_table_schema` | 不建数据包，直接解析并校验单表的 Table Schema |
| `input_from_csv` | 将默认 CSV 方言转换成表输入 |
| `cast_cell` | 在缺失值匹配之后转换逻辑类型 |
| `validate_table` | 校验字段及行数据 |
| `validate_primary_key` / `validate_foreign_key` | 检查类型转换后的键 |
| `validate_package` | 组合多表与关系校验 |

仅在对应报告 `valid()` 为真后使用逻辑表进行后续处理。独立调用测试覆盖本地 workspace 依赖；0.1.0 发布后，另用全新项目从 Mooncakes 下载、编译并运行公共 API 示例，结果通过。

## 测试与交叉验证

```sh
moon fmt --check
sh scripts/build.sh
moon test --target js
node scripts/test_host.mjs
node scripts/test_beginner.mjs
node scripts/check_diagnostics.mjs
node scripts/test_tutorial.mjs
python3 scripts/test_embedding.py
```

可选的官方 Python 工具交叉验证（只用于测试，运行库不需要 Python）：

```sh
python3 -m venv .venv-reference
.venv-reference/bin/python -m pip install -r scripts/requirements-reference.txt
.venv-reference/bin/python scripts/test_reference.py
```

当前32项 MoonBit 测试通过；中文说明覆盖23种已发现的诊断代码，教程19个命令块由自动检查实际执行；host集成覆盖导出、内容保留、覆盖拒绝和路径包含检查；独立 MoonBit 调用项目可以编译运行。使用 Frictionless Framework 5.21.0 核对7个正反用例、另外两个示例，并验证导出包能被该工具读取。这些结果仅证明已测场景，不等价于完整规范认证。

## 兼容性与边界

详见 [支持范围](docs/COMPATIBILITY.md)。首版不支持远程资源、外部 schema、压缩包、自定义 CSV 方言、日期类型、正则和 enum 约束等；遇到这些要求会报错，不假称已完成校验。

缺失值按物理字符串精确匹配后再转换。省略 missingValues 时采用 `[""]`；显式空数组保留空字符串。空 CSV 记录不被跳过，BOM 在 CLI 与库接口中一致处理。记录号是逻辑数据记录号，不是包含表头的物理文件行号。

integer 使用有符号64位整数；number 使用有限 binary64。对超出精确 binary64 范围的整数应用数值边界时，报 unsupported-range，避免错误通过。导出保留数据，不自动清洗或修复。

本地 CLI 在内存中加载资源，每个源文件限制16 MiB；不作为多用户不可信上传服务使用。

## 结构与许可

- `src/core`：MoonBit 数据模型、描述符、转换、约束、键与 CSV 适配。
- `src/api`：供 CLI 调用的 JSON 边界。
- `scripts`：I/O、构建、独立调用和交叉验证。
- `reviews`：规范审查、代码审查和问题修复记录。

原创代码采用 [MIT](LICENSE)。CSV 解析复用 NyaCSV 0.3.4（Apache-2.0），参考 [来源与许可](NOTICE.md)。这是新实现，不是 Python Frictionless Framework 的移植。

