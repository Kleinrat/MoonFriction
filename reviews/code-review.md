# MoonFriction 代码审查（第二轮）

- 审查人：DeepSeek Harness（独立规范 / 代码审查）
- 日期：2026-11-09
- 范围：`src/core`、`src/api`、`scripts/cli.mjs`，只读
- 依据：沿用第一轮规范审查结论（Table Schema v1 / Data Package v1，链接见文末），**本轮未重新下载规范全文**
- 环境限制：审查环境没有 `moon` / `node`，未执行 23 项测试与 host 集成；下文的“实际”均为**静态推导**，请主代理在真实工具链上复跑。文中不宣称完整标准兼容。

## 1. 结论

整体分层是正确的：descriptor 解析 → `validate_table` → PK/FK 校验，诊断带 `code/row/field`，unsupported 与 descriptor 错误分开，路径与资源名校验也基本到位。测试覆盖了 missingValues、类型词法、required/null、PK/FK 基础场景。

发现 **5 项实质问题**，其中 3 项会把应判无效的输入判为有效：

| # | 严重度 | 问题 | 风险 |
|---|---|---|---|
| 1 | P1 | 显式 JSON `null` 被当作“缺省”，`required` / `primaryKey` / `foreignKeys` / `missingValues` 等可被静默关闭 | 无效 descriptor 通过；必填数据被放过 |
| 2 | P1 | integer 的 `minimum`/`maximum` 经 `Double` 中转，2^53 以上整数约束失效 | 越界整数被判定有效 |
| 3 | P1 | `resources: []` 被接受为有效 Data Package | 空包被判定有效 |
| 4 | P1/P2 | CSV `skip_empty_lines: true` 静默丢弃空行 | 单列表的 required 空值行消失；行号偏移 |
| 5 | P2 | FK 检查被“全局无错误”门控；null / 跨类型外键策略未固化 | 外键诊断丢失；有效包被过严拒绝或语义未声明 |

未发现 PK 比较本身的 P1 错误：PK 用 `Array[Cell]` 逻辑值比较，`1` / `01` 等重复能被捕获（`src/core/core_wbtest.mbt:69-75`）。其余为策略与诊断完整性问题。

## 2. 问题清单

### 问题 1（P1）显式 JSON `null` 被当作缺省，约束可被静默关闭

**证据**

- `src/core/descriptor.mbt:28-33` 的 `prop` 用 `Json::null()` 同时表示“键不存在”和“键存在但值为 null”，后续无法区分。
- `flag`（`descriptor.mbt:88-98`）对 `Null` 直接返回 `false`，不报错。
- `bound`（`descriptor.mbt:109-127`）对 `Null` 直接返回 `None`，不报错。
- `missingValues`（`descriptor.mbt:354-376`）、`primaryKey`（`descriptor.mbt:377-394`）、`foreignKeys`（`descriptor.mbt:396-445`）、`type`（`descriptor.mbt:247-258`）同样把显式 null 当作缺省。

按 Table Schema v1 配套 JSON Schema：`constraints.required` 类型是 boolean，`missingValues` 是 string 数组，`primaryKey` 是 string/array，`foreignKeys` 是 array，字段 `type` 是 string enum。**显式 null 是非法值，不是“未提供”**。例如 `"required": null` 会让必填约束变成 `required=false`，`"foreignKeys": null` 会让外键校验整体消失。

**最小复现（API / 测试级）**

```json
{"descriptor":{"resources":[{"name":"r","path":"r.csv","schema":{"fields":[{"name":"id","type":"integer","constraints":{"required":null}}]}}]},"resources":[{"name":"r","csv":"id\n\"\"\n"}]}
```

- 实际：`validate_json(...)` 返回 `ok: true`（required 被当成 false；默认 `missingValues:[""]` 把空串变成 Missing，但不报 required）。
- 预期：`ok: false`，descriptor 错误，例如 `required must be boolean`。

更简单：`inspect_json('{"resources":[{"name":"r","path":"r.csv","schema":{"fields":[{"name":"id","type":"integer","constraints":{"required":null}}]}}]}')` 实际返回 `ok: true`，预期 `ok: false`。

同类：`"missingValues": null`、`"primaryKey": null`、`"foreignKeys": null`、`"type": null`、`"format": null` 都应被拒绝，而不是按缺省继续。

**修复建议**

- 不要用 `Json::null()` 当 sentinel；用 `Object.get` 的 `Option` 区分 absent 与 present-null。
- 若键存在且值为 `Null`：`constraints.required/unique` → descriptor 错误；`missingValues` → 必须是 string 数组；`primaryKey` → 必须是 string/array；`foreignKeys` → 必须是 array；`type` → 必须是 string。
- 补测试：`required:null`、`missingValues:null`、`primaryKey:null`、`foreignKeys:null` 全部 `is Err(_)`。

### 问题 2（P1）integer 约束经 Double 中转，2^53 以上精度丢失

**证据**

- `Field.minimum` / `Field.maximum` 类型是 `Double?`（`src/core/model.mbt:27-28`）。
- `bound` 把 JSON number 一律转 `Double`（`src/core/descriptor.mbt:102-127`）；JSON 数字解析本身也走 Double。
- `cell_number` 把 `IntegerValue(Int64)` 转 `n.to_double()` 再比较（`src/core/validate.mbt:13-19`、`98-107`）。

这会让 `Int64` 可精确表示的整数在边界附近被舍入后再比较。

**最小复现**

A. 最大值：

```json
{"descriptor":{"resources":[{"name":"r","path":"r.csv","schema":{"fields":[{"name":"n","type":"integer","constraints":{"maximum":9007199254740992}}]}}]},"resources":[{"name":"r","csv":"n\n9007199254740993\n"}]}
```

- 实际：`ok: true`。`9007199254740993` 是合法 Int64，但 `to_double()` 舍入为 `9007199254740992.0`，`value > maximum` 为 false。
- 预期：`ok: false`，code `maximum`。

B. 最小值：

```json
{"descriptor":{"resources":[{"name":"r","path":"r.csv","schema":{"fields":[{"name":"n","type":"integer","constraints":{"minimum":9007199254740993}}]}}]},"resources":[{"name":"r","csv":"n\n9007199254740992\n"}]}
```

- 实际：`ok: true`（bound 解析为 `9007199254740992.0`，数据也舍入为同一 Double，`<` 不成立）。
- 预期：`ok: false`，code `minimum`。

C. 边界更大时同理：`maximum: 9223372036854775806` + 数据 `9223372036854775807` 会被舍入为同一个 Double 而通过。

**修复建议**

- integer 字段的 bound 用 `Int64`（或独立的 `Bound = Integer(Int64) | Decimal(Double)`），从 JSON 原始数字文本精确解析；不要经 `Double`。
- `validate_table` 对 `IntegerValue` 用 `Int64` 比较；对 integer 字段声明非整数/超出 Int64 的 bound 时，明确报 descriptor 错误。
- 用 2^53 ± 1、Int64 max 附近各写一条测试；同时在 README 的兼容子集里说明 integer 的 64 位边界。

### 问题 3（P1）空 `resources` 数组被当作有效 Data Package

**证据**

- `src/core/descriptor.mbt:165-169` 只检查 `resources` 是数组，没有检查 `items.is_empty()`。
- `src/core/package.mbt:43-77` 在 `descriptor.resources` 为空、`inputs` 也为空时循环不执行，`errors` 为空。

Data Package v1 的 Resource Information 明确 “The resources property is required, with at least one resource”；`data-package.json` 的 `resources` 也有 `minItems: 1`。

**最小复现**

```text
inspect_json('{"resources":[]}')
```

- 实际：`{"ok":true,"resources":[]}`。
- 预期：`ok: false`，descriptor 错误，例如 `resources must contain at least one resource`。

同理：

```json
{"descriptor":{"resources":[]},"resources":[]}
```

- 实际：`validate_json(...)` 返回 `ok: true`。
- 预期：`ok: false`。

**修复建议**

- `parse_descriptor` 在 `items` 为空时 push descriptor 错误并返回 `Err`。
- `validate_package` 对空 `descriptor.resources` 也应有防御性检查（不能依赖调用方一定先 parse）。
- 补测试：`{"resources":[]}` 必须 `is Err(_)`；空包 `validate_json` 必须 `ok:false`。

### 问题 4（P1/P2）CSV 空行被静默丢弃；required 行可能消失、行号偏移

**证据**

- `src/core/csv.mbt:40-46` 向 NyaCSV 传入 `skip_empty_lines: true`。
- 前置的严格引号状态机只做引号框定，不统计行；`validate_table` 的行号是逻辑数据索引 +1（`src/core/validate.mbt:67-80`），不是物理 CSV 行号。
- 单列表 CSV 中，“空单元格”的物理表示就是空行。被跳过意味着这一数据行从未进入校验。

**最小复现**

```json
{"descriptor":{"resources":[{"name":"r","path":"r.csv","schema":{"fields":[{"name":"id","type":"integer","constraints":{"required":true}}]}}]},"resources":[{"name":"r","csv":"id\n\n1\n"}]}
```

- 实际（若 NyaCSV 按 `skip_empty_lines` 语义丢弃空行）：数据行只有 `["1"]`，返回 `ok: true`。
- 预期：空行是 1 列、值为 `""` 的数据行；默认 `missingValues:[""]` → Missing → `required` 错误（第 2 行）；`ok: false`。
- 若项目有意把“跳过空行”作为子集约定，则必须在 README 声明，并保证 `Diagnostic.row` 指向物理行号；否则错误行号会偏移，用户按行号定位会错位。

补充一致性问题：`"id\n\"\"\n"`（引号空字段）会保留为空数据行，而 `"id\n\n"`（裸空行）会被丢弃，二者在 CSV 物理层都表示空值，行为不一致。另外，CLI 的 `TextDecoder` 默认会去除 BOM，而直接调用 `input_from_csv` 的 API 路径不会，带 BOM 的 CSV 会得到 `"\ufeffid"` 表头并报 header mismatch；建议在子集边界文档中明确 BOM 处理。

**修复建议**

- 默认改为 `skip_empty_lines: false`，在 README 中说明 CSV dialect 只支持默认逗号/双引号、不跳过空行。
- 或者在 `InputTable` 中同时保留物理行号，错误 `row` 用物理行号；并为“空行被跳过”提供显式开关。
- 补测试：单列 required + 空行；空行在中间和末尾；引号空字段与裸空行的一致性；BOM 表头。

### 问题 5（P2）主外键比较语义：FK 被全局错误门控，null / 跨类型策略未固化

**证据**

- `src/core/package.mbt:77-94` 只有 `errors.is_empty()` 时才执行 FK 数据校验。只要包内任何表/任何资源出现其它错误，FK 诊断就整体消失。
- `src/core/keys.mbt:111-123` 要求 FK 两端的 `FieldType` 完全相等，否则报 `foreign-key-schema`。Table Schema v1 并没有规定外键两端必须同类型；它只描述“values ... connect to values”。integer → number 在逻辑值层可以比较，当前实现会直接拒绝 descriptor。
- `src/core/keys.mbt:138-148` 对含 `Missing` 的源键直接跳过（视为无引用）。这是合理的 SQL 式策略，但 Table Schema 规范未规定；SCOPE 也明确 “empty/null foreign keys need reference semantics”，需要写进 README 并有测试。

**最小复现 A：FK 诊断被其它错误掩盖**

descriptor：`products(id integer, primaryKey id)`、`orders(product_id integer, foreignKeys product_id → products.id)`、`meta(k text, required true)`。

输入：`products=[["1"]]`、`orders=[["2"]]`（悬空引用）、`meta=[[""]]`（required 缺失）。

- 实际：错误只有 `meta` 的 `required`；`orders` 的悬空引用没有 `foreign-key` 诊断。
- 预期：同时报告 `required` 和 `foreign-key`（orders 第 1 行，product_id=2 无匹配）。两表本身都是逻辑有效的，FK 检查不应被第三个表的错误阻断。

**最小复现 B：跨类型外键被过严拒绝**

`products.id` 为 `number`，`orders.product_id` 为 `integer`，FK 指向 `products.id`：

- 实际：`parse_descriptor` 返回 Err，消息 “Foreign key field types differ”。
- 预期：要么按逻辑数值比较并接受（`1L` 与 `1.0` 等价，按项目策略转换），要么明确归类为 `unsupported` 并在 README 声明；不要作为普通 schema 错误。

**最小复现 C：null 外键静默通过**

`orders.product_id` 为空串（未标 required）：默认 `missingValues` → Missing → FK 跳过，包判有效。

- 预期：这是允许的，但应在 README/测试中固定“Missing 源键 = 无引用”；如果业务上要求外键非空，应由字段 `required: true` 表达。

**修复建议**

- 把 FK 阶段从 `errors.is_empty()` 移到“源表与目标表各自 `report.valid()`”的条件：无效表不生成 FK 噪声，但其它表的错误不应阻断有效表之间的 FK 检查。
- 明确并测试 null FK 语义；跨类型先决定“比较/拒绝/unsupported”，不要用笼统的 schema 错误。
- PK 部分未发现同类 P1：`validate_primary_key` 对 typed cell 元组比较、null 检测、重复字段检测都符合上一轮结论；可补充多资源场景下 PK 错误与 FK 错误同时出现的测试，确认诊断不互相吞掉。

## 3. 验证边界与未覆盖项

本轮是静态审查，以下需要主代理在 host 环境实测：

1. **未执行 23 项测试 / host 集成**：环境无 `moon`、`node`。问题 1-5 的“实际”均为读代码推导，尤其是问题 4 依赖 NyaCSV 的 `skip_empty_lines` 对 `"\n"` 与 `",,,"` 的具体行为。
2. **已读测试的覆盖盲区**：现有 23 个测试未覆盖 `resources: []`、显式 null、2^53 边界、CSV 空行、FK + 其它错误并存、跨类型/null FK 策略。建议按上述最小复现各补 1 条 wbtest。
3. **未验证的依赖细节**：`@json.parse` 对超出 2^53 数字的舍入/原始文本保留方式（问题 2 即使保留原始文本也仍因 `bound` 转 Double 而成立）；`@string.parse_int64` / `parse_double` 是否接受 `"+"` 前缀（当前 `cast.mbt:83` 允许 `+`，若 `parse_int64` 拒绝，`"+42"` 会落到 “Integer exceeds signed 64-bit range” 的误导性错误消息）。
4. **CLI 入口风险（未计入 5 项，需 host 实测）**：`scripts/cli.mjs:39` 用 `new URL(import.meta.url).pathname` 与 `path.resolve(process.argv[1])` 比较。当前工作区路径含中文，URL pathname 会 percent-encode，二者大概率不相等，导致 CLI 主分支不执行、静默 `exit 0`。请执行 `node scripts/cli.mjs inspect examples/shop/datapackage.json` 验证；若确认，改用 `fileURLToPath(import.meta.url)`。
5. **未纳入范围**：`scripts/build.sh`、`scripts/test_host.mjs`、`examples/`、依赖源码；未修改 `src/`、`scripts/`、`moon.mod`，未发布任何内容。

### 规范依据（沿用第一轮）

- Table Schema v1：https://specs.frictionlessdata.io/table-schema/ （Missing Values / Constraints / Primary Key / Foreign Keys / Types and Formats）
- Data Package v1：https://specs.frictionlessdata.io/data-package/ （Resource Information：resources 至少一个）
- Data Resource v1：https://specs.frictionlessdata.io/data-resource/
- 机读 schema：https://specs.frictionlessdata.io/schemas/table-schema.json 、https://specs.frictionlessdata.io/schemas/data-package.json

本轮只新增 `reviews/code-review.md`；未读取无关个人文件，未修改 `src/core`、`src/api`、`scripts/cli.mjs`、`moon.mod`，未创建仓库、未发布包，未切换模型。
