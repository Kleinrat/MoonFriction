# Frictionless v1 兼容范围与验证状态

开发目标是完整实现 **Table Schema v1** 和 **Data Package v1**。本页记录当前源码已验证的行为及后续验收仍需补齐的条目。公开安装版本的范围见相应的 Git 标签。

## Table Schema v1

| 规范条目 | 当前行为和验证 |
|---|---|
| 描述符、字段及元数据 | 解析有序字段与缺失标记。字段名比较区分大小写。检查 `title`、`description` 和 `rdfType` 的形状。 |
| 基本类型及数值精度 | 支持 `string`、`integer`、`number`、`boolean` 与 `any`。文本数值和 JSON 数字字面量保留精度。整数超出 Int64 时使用 `BigIntegerValue`。超出 binary64 往返能力的小数使用 `ExactNumberValue`。`NaN`、`INF` 和 `-INF` 表示为 `SpecialNumber`。自定义布尔标记和数值分隔符在类型转换时应用。 |
| 文本格式 | 默认格式、UUID、ASCII 邮箱地址（含引号本地部分和 IP 字面量域名）、RFC 3986 的 URI 组件和 IP 字面量、检查填充位的标准 Base64。电子邮件注释、过时语法和 SMTPUTF8 不在已验证范围内。 |
| 集合与时长 | 支持对象、数组与 XML Schema 时长。对象键换序和等值数值字面量归一化后再比较。时长按月份和秒量归一化，例如 `P1D` 和 `PT24H` 等价。 |
| 日期和时间 | 支持 `date`、`time`、`datetime`、`year`、`yearmonth` 的默认格式。自定义日期时间支持英文月份、星期、年内日序、周日期、12 小时制与 C locale 简写。`%z` 支持秒及 1–6 位小数秒偏移，按整数微秒转换到 UTC，再用逻辑值校验范围与唯一性。默认 datetime 支持已公布的历史闰秒，`created` 使用相同的 UTC 校验。`year` 和 `yearmonth` 支持 XML Schema 1.0 无时区的负值及扩展年份。 |
| 地理数据 | 支持 `geopoint` 文本、数组和对象。GeoJSON 校验边界框维数、轴顺序、坐标包含关系及跨日期变更线的经度区间。TopoJSON 校验 arc 索引、端点衔接及多边形环闭合，并对解码后的坐标检查拓扑和几何对象各自的边界框。 |
| 约束 | `required`、`unique`、`enum`、数值与日期时间上下限、集合长度，以及 XML Schema 风格的 `pattern`。覆盖全值匹配、字符类减法、XML 名称类和 Unicode 16 类别与区块。首尾 `^`、`$` 也作为已有 Frictionless 描述符常用的锚点写法接受，使用转义表示字面字符。更广的 XML 正则语法和 Unicode 版本兼容仍需用完整测试集核对。 |
| 缺失值及键 | 在类型转换前匹配物理字符串缺失标记，默认 `[""]`。支持单字段与复合主键、自引用与包内外键。单表遇到跨表外键返回 `foreign-key-scope`。外键字段需要相同声明类型，缺失外键按当前策略跳过。 |
| CSV 与 JSON 入口 | 批量校验共享逻辑类型与约束。JSON 表以对象行或数组行输入。逐行接口可限制诊断样本，主键和唯一索引随 distinct 值增加。跨表外键使用批量入口。 |

直接构造 `Field` 的消费者可以使用 `field(name, kind)` 并通过结构体更新设置约束。解析后的整数界限位于 `exact_minimum`、`exact_maximum`，小数界限位于 `decimal_minimum`、`decimal_maximum`，日期时间界限位于 `temporal_minimum`、`temporal_maximum`。原有的 `minimum` 和 `maximum` 仍可用于调用方提供的 Double 界限。

JSON 的原始整数可精确解析。若调用方提供经过浮点解析且没有原始字面量的 JSON 整数，超出安全整数区间时会报错。科学记数法整数的展开限制为一百万个尾零。NaN 在枚举和唯一性中按统一标记比较，在有序范围约束中报告不可比较。

## Data Package v1

| 规范条目 | 当前行为和验证 |
|---|---|
| 描述符与资源 | `parse_data_package` 检查资源数组、唯一资源名、包名、位置和主要元数据的结构。保留原始描述符、扩展字段和精确数值。许可证 ID 对照固定的 Open Definition 登记表，也可使用标准的许可证路径。 |
| 内置表格 profile | 声明 `tabular-data-package` 时，每个资源必须声明 `tabular-data-resource`。声明表格资源时检查 Table Schema、外部 CSV 和内嵌 JSON 行结构。外部 Table Schema 的规则在 `validate` 解析引用后校验。 |
| 自定义 profile | `DataPackage::validate_profiles` 接收按注册 ID 或 URL 编址的 JSON Schema 文档，校验原始包和资源描述符。默认采用 draft-04，识别显式声明的受支持版本。缺 schema、无法解析的引用和约束错误提供带资源位置的诊断。 |
| 文件与内嵌数据 | 支持单一本地 POSIX 相对路径或 HTTP(S) URL，同类路径数组，以及内嵌 JSON 对象、数组和带媒体声明的文本。检查位置互斥、有实质路径、路径类型一致与绝对路径、父目录限制。 |
| 内容与 schema 解析 | `DataResource::read` 使用调用方提供的本地或远程读取函数，按描述符顺序拼接文件分片。 `resolve_schema` 通过对应 I/O 函数读取本地或远程 JSON schema，或返回内嵌对象。纯 MoonBit 核心无需网络。 |
| 通用 CLI 导入导出 | `inspect-package` 检查描述符。`export-package` 复制相对路径资源及本地引用的 schema 和方言，校验资源声明的字节数和摘要，保留内嵌数据及绝对远程引用。命令可以显式启用 `--allow-remote` 读取远程描述符。 |
| 表格验证适配 | `validate`、`export` 可在同一包处理多分片 CSV、内嵌 JSON 和远程表格数据。所有分片合并后检查字段、主键和外键。内嵌对象行直接映射字段，内嵌数组行以第一条为表头。CSV 默认每片含相同表头，方言 `header: false` 可声明每片只有数据。`validate-json` 保留外部 JSON 文件显式映射入口。 |

路径读取和导出使用本地目录包含检查，资源单文件读取限制为 16 MiB。通用资源可以使用任意数据格式。一个通用资源是否具备相应字段格式、编码或 schema 的内容校验，取决于它的消费方。

专用 CSV 入口支持逗号、分号或 Tab、单双引号以及从描述符解析的本地或远程方言。批量包校验按 Node.js TextDecoder 支持的编码解码，流式入口仍为 UTF-8。CSV Dialect 的自定义转义、注释及所有分隔符组合仍需覆盖。行号是从 1 开始的逻辑数据记录号，规则和表头诊断使用 0。

远程读取默认关闭。启用后，CSV、JSON、schema 和方言可通过 HTTP(S) 读取。URL 不带凭据并直接返回内容。响应拒绝重定向，每个文件最大 16 MiB，读取超时为 15 秒。导出时相对路径文件会复制到目标目录，绝对 URL 继续保存在描述符中。

接受的数据包命令为 `inspect-package`、`export-package`、`validate` 和 `export`。使用 `--profile-schemas FILE` 提供 JSON 对象，其键为 profile ID、URL 或引用 URI，其值为 JSON Schema 文档。显式启用 `--allow-remote` 可读取直接声明的 HTTP(S) profile，外部 `$ref` 文档仍由调用方提供。表格入口先校验原始描述符，再展开资源 schema 和方言，保留自定义 profile 对原始字段类型的约束。旧的 `inspect`、`validate-json` 仍采用单路径旧入口。

## 可复验的证据

在源码目录运行 `sh scripts/build.sh` 和 `moon test --target js`。安装 `scripts/requirements-reference.txt` 中的依赖后，运行 `python scripts/test_reference.py`。安装 `xmllint` 可执行 XML Schema 对照。GitHub CI 运行这些步骤和 `node scripts/test_host.mjs`。

| 规范条款 | 可复验输入和结果 |
|---|---|
| Table Schema v1 类型和约束 | [仓库发货](../examples/standard-exchange/README.md)中的 `type`、`minimum`、布尔标记及对象字段。对照 Frictionless 验证有效表、非法日期、数量越界与非法布尔值。 |
| Table Schema v1 自定义日期和逻辑值 | 对照 Python `strptime` 验证秒和小数秒偏移，拒绝混用分隔符和无效秒值。MoonBit 断言跨日期的 UTC 值、范围和同一瞬间的唯一性，导出由 Frictionless 读回。 |
| Table Schema v1 `year`、`yearmonth` | `xmllint` 对照 XML Schema 1.0 的 `gYear` 和 `gYearMonth` 无时区词法。MoonBit 测试覆盖负年、超四位年份、年零及上下限。 |
| Table Schema v1 约束和键 | 对照 XML Schema 正则正反例，检查必填、枚举、单键和复合主键、跨资源外键。用分片末尾的 SKU 验证内嵌 JSON 引用，用重复键和无效引用验证错误位置。 |
| Table Schema v1 地理字段 | 对照 Fiji 跨日期变更线的 GeoJSON 样例，核对边界外坐标的诊断。MoonBit 测试验证 TopoJSON 解码、弧段引用和边界框。 |
| Data Package v1 描述符和 `created` | 以 RFC 3339 §5.8 的两个等价闰秒为正例，配对错误日期和错误偏移。数据包检查出口断言 `created` 错误字段。 |
| Data Resource v1 路径与内嵌数据 | 交叉验证分片、本地文件、内嵌数据、远程引用的原样读回。宿主测试检查字节数、摘要和包目录边界。 |
| Data Package v1 profiles | 用 Frictionless 验证内置表格 profile 的合法数据、缺失资源 profile、缺失 schema 和非法行。自定义 profile 对照 Python jsonschema，覆盖包级和资源级约束及导出。 |

当前已复现的差异包括 `gYear` 和 `gYearMonth` 的带时区词法、XML Schema 正则首尾 `^` 和 `$` 的字面量语义，以及 Data Package `contributors[].email` 的邮箱格式校验。CSV Dialect 的 `|` 分隔符、注释、`skipInitialSpace` 和省略 `caseSensitiveHeader` 时的默认行为也有差异。历史闰秒表随 IERS 公告更新。表中的测试证据按当前实现范围维护。

规范依据为 [Table Schema v1](https://specs.frictionlessdata.io/table-schema/)、[Data Package v1](https://specs.frictionlessdata.io/data-package/)、[Data Resource v1](https://specs.frictionlessdata.io/data-resource/)、[Tabular Data Resource v1](https://specs.frictionlessdata.io/tabular-data-resource/)、[Profiles](https://specs.frictionlessdata.io/profiles/)、[RFC 7946 §5](https://www.rfc-editor.org/rfc/rfc7946#section-5) 及 [TopoJSON §3](https://github.com/topojson/topojson-specification#3-bounding-boxes)。
