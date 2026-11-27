# MoonFriction

第一次接触？先看[中文入门](docs/zh/getting-started.md)和[四种错误演示](docs/zh/errors-demo.md)。

**使用 MoonBit 校验和交换 Frictionless 数据包及表格规则。**

把 CSV、字段定义和表间关系放在一个标准数据包中：读取描述文件，转换字段类型，检查约束、主键和外键，再导出其他工具能够读取的数据包。

0.11.0 增加秒级和小数秒时区偏移、历史闰秒、无时区的扩展年份，以及内置表格 profile 校验。发布版的规范覆盖情况与后续符合性目标见[兼容性记录](docs/COMPATIBILITY.md)。[Mooncakes 安装入口](https://mooncakes.io/docs/Kleinrat/frictionless@0.11.0)

[持续集成](https://github.com/Kleinrat/MoonFriction/actions) · [测试记录](docs/TESTING-2026-11-13.md) · [版本更新](CHANGELOG.md)

## 能做什么

- 读取带内嵌 schema 的本地 UTF-8 CSV 数据包，保留原始描述信息。
- 转换文本、精确数值、布尔、日期时间、数组和对象和地理数据，区分缺失值、类型错误与约束错误。
- 检查 required、unique、minimum、maximum、minLength、maxLength。
- 检查单字段 / 组合主键、跨表与自引用外键。
- 输出资源名、逻辑记录号、字段名和错误代码。
- 导出新目录，保留描述信息和 CSV 原始内容；拒绝覆盖已有目标。
- 可作为纯 MoonBit 库调用；Node.js CLI 只负责本地文件 I/O 和参数。
- 从 CSV 表头和样本生成保守、可编辑的 Table Schema 草稿，并明确提示采样范围与歧义。

三个合成示例：商品与订单、学生与成绩、传感器与读数。它们用于验证数据交换能力，不代表真实用户采用。

公开数据接入示例使用 IANA tzdb 2025b 的 312 条时区记录，比较两版规则并定位受影响的 34 条记录。[可复现步骤与结果](examples/iana-tzdb/README.md)

## 按标准交换数据

[仓库发货示例](examples/standard-exchange/README.md)演示 Table Schema 的日期、数值、布尔和键规则，并用 Frictionless Framework 独立验证导出结果。该示例还提供通用 Data Package，包含本地文件分片、内嵌 JSON 和 HTTP(S) 引用。`validate` 可把前两种资源放在同一数据包校验跨表外键。要读取可信 HTTP(S) 资源或远程描述符，可在命令后加上 `--allow-remote`。`inspect-package` 和 `export-package` 提供通用包描述符检查及导出。

## 独立业务接入示例

[物资借用检查工具](examples/asset-loans/README.md)是独立 MoonBit 模块，从 Mooncakes 安装0.2.1，不导入本仓库源码。覆盖规则草稿、人工确认、关联数据检查、JSON申请字段检查和导出；属于合成业务演示，尚无真实试用反馈。

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

## 比较两版规则

从仓库根目录运行。唯一一条订单状态为 draft；旧规则允许 draft 和 paid，新规则只允许 paid。

```sh
sh scripts/build.sh
node scripts/cli.mjs schema diff examples/schema-diff/old.json examples/schema-diff/new.json
node scripts/cli.mjs validate-stream examples/schema-diff/old.json examples/schema-diff/orders.csv
node scripts/cli.mjs validate-stream examples/schema-diff/new.json examples/schema-diff/orders.csv
```

比较命令返回字段、规则、旧值、新值及影响。此例返回 `status / enum / tightened`，移除成员为 draft。随后两条校验命令分别通过和报告第 1 条订单的枚举错误。交换规则顺序会得到 relaxed。

MoonBit 接口为 `diff_table_schemas(old, current)`，输入由 `parse_table_schema` 解析。按字段名比较 required、unique、enum、数值及长度上下限；枚举同时增删时分别报告两个方向及对应成员。字段增删、顺序或类型改变、主外键及缺失标记变化标记为 review。类型变化时，原有的 `type` 记录后紧跟同字段的 `fieldConstraints` 记录。`before` 和 `after` 列出两侧生效的全部字段约束，含默认值。例如从必填整数改为可选数值，能直接看到 `required` 从 `true` 变为 `false`。复合主键仅重排时输出 `primaryKeyOrder`，其 `impact` 为 `orderOnly`：同一批行的唯一性判定相同，按位置使用键元组的调用方仍可看到前后顺序。主键成员增删或替换继续输出 `primaryKey / review`。结果仅说明各条规则的潜在影响，元数据不参加比较。从描述符解析的整数和小数界限按精确值比较。直接构造 `Field` 时传入超出安全整数范围的 Double 界限仍会标记为 review。比较成功（含发现差异）退出 0，规则无效退出 1，参数或文件错误退出 2。

脚本集成可按退出码选择输出流，再读取枚举的增删成员。[CLI 输出约定与五个可运行示例](examples/schema-diff/README.md)

## 逐行检查一张表

用 `RowValidator::new("orders", schema, header, max_errors=10)` 创建检查器。向 `feed` 传入一条已分列的文本记录，或向 `feed_json` 传入一个已解析的 JSON 行。JSON 行可采用数组或对象；同一次检查中的 JSON 行使用相同形状。创建时的错误（如表头不匹配）通过 `Err` 返回。

`finish()` 返回独立快照，包含总记录数、错误总数和最前面的错误样本。用 `error_count == 0` 判断通过；`max_errors=0` 可以只计数。默认保留前 100 个诊断。字段校验失败时按批量校验规则仅报告字段错误；全部字段通过后才报告主键错误。

只检查字段时，内存主要取决于规则、当前行和诊断样本。启用精确主键或唯一约束后，还要保留不同键值的索引。自引用和跨表外键请走批量接口。直接检查文件可使用下方命令。[10 万行示例](examples/row-consumer/main.mbt)

### 从命令行检查大 CSV（仓库源码）

从仓库根目录运行，参数依次为独立 Table Schema 和带表头的 UTF-8 CSV 文件：

```sh
sh scripts/build.sh
node scripts/cli.mjs validate-stream examples/shop/products.schema.json examples/shop/products.csv --max-errors 10
```

示例有 2 条数据，输出 `ok: true`、`rows: 2`、`error_count: 0`。命令默认只展示前 10 个数据错误，仍会统计全部错误；设为 0 可以只计数。可选 `--delimiter ';'` 或 `--delimiter tab`，单引号包裹的字段使用 `--quote "'"`。引号内换行算同一条记录。

退出码 0 表示通过，1 表示规则或数据错误，2 表示命令参数、文件读取或 UTF-8 解码错误。表头或引号结构错误会停止解析并返回 `complete: false`；此时 `rows` 是已交给校验器的记录数。命令按块读文件，单条超长记录和大量不同键值仍可能占用较多内存。数据包和外键继续使用 `validate`。

## 限定状态等字段的取值

例如，在字段定义中写入 `{"name":"status","type":"string","constraints":{"enum":["draft","paid"]}}`。订单状态为 `paid` 时通过，为 `void` 时报告 `enum` 及记录号和字段名。CSV 和 JSON 共用这项检查。允许列表须非空，成员按该字段声明的类型和格式转换后再比较。缺失值仍由 `required` 决定。

## 读取分号 CSV 和 Tab 分隔文件（仓库源码）

在 `datapackage.json` 的资源对象中设置方言。例如，数据以分号分列、用单引号包住含分号的文本时，添加：

```json
"dialect": {"delimiter": ";", "quoteChar": "'"}
```

Tab 分隔用 `"delimiter": "\t"`。各资源可以分别配置；省略选项时使用逗号和双引号。校验和导出命令与普通 CSV 相同，导出保留原文件字节及方言声明。嵌入库时可调用 `input_from_csv(name, text, dialect={delimiter: ';', quote_char: '\''})`。无描述文件的草稿推断命令仍按默认 CSV 读取。

## 多个数据包共用一份规则（仓库源码）

把规则保存为 UTF-8 JSON 文件，例如 `schemas/products.json`，内容为 `{"fields":[{"name":"id","type":"integer"}],"primaryKey":"id"}`。在每个需要它的描述文件中，将对应资源的 `schema` 写成 `"schemas/products.json"`。路径相对于该描述文件所在目录，因此同目录的月报描述文件可以共用这份规则。

命令行的 inspect、validate、validate-json、中文 explain 和 export 都支持这种写法。导出会将规则写入新描述文件，移动导出目录后仍能独立校验。引用仅限包目录内的本地文件，每份最多 16 MiB。纯 MoonBit 接口由调用者提供已内嵌的规则。

## JSON 批量行输入

0.3.0 新增 `validate_json_package`，可把多张内存 JSON 表一起检查，例如定位订单引用的商品编号。可用命令行直接检查两份 JSON 文件，见[可复制的命令和错误示例](docs/zh/json-input.md#用命令行检查商品和订单)。中文解释可用 `node scripts/explain.mjs --json 描述文件 资源名=文件 ...`。库调用见[订单与商品示例](examples/json-consumer/main.mbt)。

`input_from_json` 接收顶层 JSON 数组，元素既可以按字段顺序的数组，也可以是按字段名取值的对象；对象键顺序不影响字段顺序。原生 JSON 数字/布尔不再转字符串：

```moonbit
let input = @core.input_from_json("books", #|[[1,"MoonBit"],[2,"数据"]]
).unwrap()
let report = @core.validate_json_table("books", fields, input)
```

规则与 CSV 对等：`null` 和缺失属性都视为 Missing；原生数字只用于 integer/number，原生布尔只用于 boolean，其他标量不会被偷偷字符串化；对象行出现未声明属性会报 `extra-property`。字符串值仍使用与 CSV 相同的严格词法。批量输入完全在内存中处理，不做流式或固定内存承诺。详见[JSON 批量输入](docs/zh/json-input.md)。

## 从 CSV 生成规则草稿

```sh
node scripts/infer.mjs examples/shop/products.csv
```

草稿只包含可推断的字段类型，不会猜主键或 `required`，也不会修改原 CSV；目标描述文件已存在时拒绝覆盖。默认采样前100条，可用 `--sample N` 调整；整个文件仍会读入并解析。前导零编号和不兼容混合类型回退文本，整数与小数混合可推断为 number。生成后请人工编辑，再 `validate` 和 `export`。详见[从 CSV 生成草稿](docs/zh/inference.md)。

## 作为 MoonBit 库使用

在已有 MoonBit 项目中安装：

```sh
moon update
moon add Kleinrat/frictionless@0.11.0
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
| `parse_data_package` / `DataResource::read` | 读取通用包描述符并通过宿主解析资源 |
| `parse_descriptor` | 读取用于表格校验的数据包描述符 |
| `parse_table_schema` / `validate_table_schema` | 不建数据包，直接解析并校验单表的 Table Schema |
| `input_from_csv` | 将默认 CSV 方言转换成表输入 |
| `input_from_json` / `validate_json_table` | 批量 JSON 行输入与类型化校验 |
| `infer_table_schema` | 从表头和样本生成保守的规则草稿 |
| `cast_cell` | 在缺失值匹配之后转换逻辑类型 |
| `validate_table` | 校验字段及行数据 |
| `validate_primary_key` / `validate_foreign_key` | 检查类型转换后的键 |
| `validate_package` | 组合多表与关系校验 |

仅在对应报告 `valid()` 为真后使用逻辑表进行后续处理。独立调用测试在临时 workspace 项目中编译三个消费者（包 API、独立 schema、JSON 行）；0.1.2 发布后的旧 API 消费者验证仍保留在发布记录中。

## 测试与交叉验证

```sh
moon fmt --check
sh scripts/build.sh
moon test --target js
node scripts/test_host.mjs
node scripts/test_beginner.mjs
node scripts/test_infer.mjs
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

CI 运行 MoonBit 单元测试、中文诊断映射检查、教程命令和独立 MoonBit 消费者示例；host 集成测试覆盖导出、内容保留、覆盖拒绝和路径包含检查。使用 Frictionless Framework 5.21.0 核对7个正反用例、另外两个示例，并验证导出包和自动推断草稿能被该工具读取。这些结果仅证明已测场景，不等价于完整规范认证。

## 兼容性与边界

开发目标为完整实现 **Table Schema v1** 与 **Data Package v1**。当前源码的已验证行为和待补规范条目见[兼容范围与验证状态](docs/COMPATIBILITY.md)。

校验声明了自定义 profile 的包时，可以用 `--profile-schemas profiles.json` 提供 profile ID 或 URL 到 JSON Schema 文档的映射。MoonBit 调用方可通过 `DataPackage::validate_profiles` 使用同一套校验。示例命令为 `node scripts/cli.mjs inspect-package datapackage.json --profile-schemas profiles.json`。

缺失值按物理字符串精确匹配后再转换。省略 missingValues 时采用 `[""]`；显式空数组保留空字符串。空 CSV 记录不被跳过，BOM 在 CLI 与库接口中一致处理。记录号是逻辑数据记录号，不是包含表头的物理文件行号。

从文本及 JSON 数字字面量读取的整数和小数可保留精度。超出普通整数或浮点表示时，逻辑值使用 `BigIntegerValue` 或 `ExactNumberValue`。导出保留原始数据。

本地 CLI 在内存中加载资源，每个源文件限制16 MiB；不作为多用户不可信上传服务使用。

## 结构与许可

- `src/core`：MoonBit 数据模型、描述符、转换、约束、键与 CSV 适配。
- `src/api`：供 CLI 调用的 JSON 边界。
- `scripts`：I/O、构建、独立调用和交叉验证。
- `reviews`：规范审查、代码审查和问题修复记录。

原创代码采用 [MIT](LICENSE)。CSV 解析复用 NyaCSV 0.3.4（Apache-2.0），参考 [来源与许可](NOTICE.md)。这是新实现，不是 Python Frictionless Framework 的移植。

