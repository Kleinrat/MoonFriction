# MoonFriction

**MoonBit 原生的 Frictionless Data Package v1 / Table Schema v1 子集实现。**

把 CSV、字段定义和表间关系放在一个标准数据包中：读取描述文件，转换字段类型，检查约束、主键和外键，再导出其他工具能够读取的数据包。

首版模块名为 `Kleinrat/frictionless`，版本为 `0.1.0`。支持范围是明确子集，不宣称完整标准兼容。

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

## 作为 MoonBit 库使用

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
| `input_from_csv` | 将默认 CSV 方言转换成表输入 |
| `cast_cell` | 在缺失值匹配之后转换逻辑类型 |
| `validate_table` | 校验字段及行数据 |
| `validate_primary_key` / `validate_foreign_key` | 检查类型转换后的键 |
| `validate_package` | 组合多表与关系校验 |

仅在对应报告 `valid()` 为真后使用逻辑表进行后续处理。独立调用测试通过 Moon workspace 本地成员依赖验证公共 API。公开注册表安装情况以发布验证记录为准。

## 测试与交叉验证

```sh
moon fmt --check
sh scripts/build.sh
moon test --target js
node scripts/test_host.mjs
python3 scripts/test_embedding.py
```

可选的官方 Python 工具交叉验证（只用于测试，运行库不需要 Python）：

```sh
python3 -m venv .venv-reference
.venv-reference/bin/python -m pip install -r scripts/requirements-reference.txt
.venv-reference/bin/python scripts/test_reference.py
```

当前32项 MoonBit 测试通过；host集成覆盖导出、内容保留、覆盖拒绝和路径包含检查；独立 MoonBit 调用项目可以编译运行。使用 Frictionless Framework 5.21.0 核对7个正反用例、另外两个示例，并验证导出包能被该工具读取。这些结果仅证明已测场景，不等价于完整规范认证。

## 兼容性与边界

详见 [支持范围](docs/COMPATIBILITY.md)。首版不支持远程资源、外部 schema、压缩包、自定义 CSV 方言、日期类型、正则和 enum 约束等；遇到这些要求会报错，不假称已完成校验。

缺失值按物理字符串精确匹配后再转换。省略 missingValues 时采用 `[""]`；显式空数组保留空字符串。空 CSV 记录不被跳过，BOM 在 CLI 与库接口中一致处理。记录号是逻辑数据记录号，不是包含表头的物理文件行号。

integer 使用有符号64位整数；number 使用有限 binary64。对超出精确 binary64 范围的整数应用数值边界时，报 unsupported-range，避免错误通过。导出保留数据，不自动清洗或修复。

本地 CLI 在内存中加载资源，每个源文件限制16 MiB；不作为多用户不可信上传服务使用。

## 结构与许可

- `src/core`：MoonBit 数据模型、描述符、转换、约束、键与 CSV 适配。
- `src/api`：供 CLI 调用的 JSON 边界。
- `scripts`：I/O、构建、独立调用和交叉验证。
- `reviews`：DeepSeek Harness 的独立规范与代码审查。

原创代码采用 [MIT](LICENSE)。CSV 解析复用 NyaCSV 0.3.4（Apache-2.0），参考 [来源与许可](NOTICE.md)。这是新实现，不是 Python Frictionless Framework 的移植。

Codex 负责实现、修复与集成；DeepSeek Harness 的 DeepSeek-V4.1-Flash（1017）负责独立规范和代码审查。审查发现须由主代理复现并验证，不以模型结论代替测试。
