# Frictionless v1 兼容范围与验证状态

开发目标是完整实现 **Table Schema v1** 和 **Data Package v1**。本页记录当前源码已验证的行为及后续验收仍需补齐的条目。公开安装版本的范围见相应的 Git 标签。

## Table Schema v1

| 规范条目 | 当前行为和验证 |
|---|---|
| 描述符、字段及元数据 | 解析有序字段与缺失标记。字段名比较区分大小写。检查 `title`、`description` 和 `rdfType` 的形状。 |
| 基本类型及数值精度 | 支持 `string`、`integer`、`number`、`boolean` 与 `any`。文本数值和 JSON 数字字面量保留精度。整数超出 Int64 时使用 `BigIntegerValue`。超出 binary64 往返能力的小数使用 `ExactNumberValue`。`NaN`、`INF` 和 `-INF` 表示为 `SpecialNumber`。自定义布尔标记和数值分隔符在类型转换时应用。 |
| 文本格式 | 默认格式、UUID、ASCII 邮箱地址（含引号本地部分和 IP 字面量域名）、RFC 3986 的 URI 组件和 IP 字面量、检查填充位的标准 Base64。电子邮件注释、过时语法和 SMTPUTF8 不在已验证范围内。 |
| 集合与时长 | 支持对象、数组与 XML Schema 时长。对象键换序和等值数值字面量归一化后再比较。时长按月份和秒量归一化，例如 `P1D` 和 `PT24H` 等价。 |
| 日期和时间 | 支持 `date`、`time`、`datetime`、`year`、`yearmonth` 的默认格式及日历检查。带数字偏移的 datetime 会转换为 UTC。自定义格式接受英文月份和星期、年内日序、ISO 周日期、按周日或周一起算的周日期、12 小时制以及 C locale 的日期时间简写。`%Z` 识别 UTC 和 GMT。`%f` 采用 1–6 位行为，默认时间保留任意位小数秒。更广的 locale 指令、秒级时区偏移、闰秒及扩展年份仍有限制。 |
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

- [仓库发货案例](../examples/standard-exchange/README.md) 覆盖标准类型、约束、引用关系、错误定位和双工具读回。通用包示例另外覆盖本地分片、内嵌数据和 HTTP(S) 引用描述符。
- `moon test --target js` 覆盖精确数值、时间、集合、约束和资源定位。 `node scripts/test_host.mjs` 检查分片导出、引用 schema、字节数、摘要和路径包含规则。
- `python scripts/test_reference.py` 与 Frictionless Framework 5.21.0 对照分片和内嵌表、月份名、年内日序、ISO 周日期、12 小时制及导出读回。Fiji 跨日期变更线案例验证地理表格数据可交换，Python jsonschema 独立校验 profile 的包级、资源级约束及导出结果。系统装有 `xmllint` 时也会交叉验证 XML Schema 正则。CI 安装该工具。

规范依据为 [Table Schema v1](https://specs.frictionlessdata.io/table-schema/)、[Data Package v1](https://specs.frictionlessdata.io/data-package/)、[Data Resource v1](https://specs.frictionlessdata.io/data-resource/)、[Tabular Data Resource v1](https://specs.frictionlessdata.io/tabular-data-resource/)、[Profiles](https://specs.frictionlessdata.io/profiles/)、[RFC 7946 §5](https://www.rfc-editor.org/rfc/rfc7946#section-5) 及 [TopoJSON §3](https://github.com/topojson/topojson-specification#3-bounding-boxes)。
