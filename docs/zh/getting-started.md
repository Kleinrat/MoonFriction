# 第一次使用 MoonFriction

这是给处理 CSV 的开发者使用的数据包检查库。CSV 是表格文本；datapackage.json 是说明各列含义、类型和表间关系的规则文件。检查不会替你改数据。

## 先准备

安装 MoonBit 和 Node.js 22+，下载本仓库，在仓库目录执行：

<!-- test: exit=0 -->
```sh
moon update &&
sh scripts/build.sh &&
node scripts/cli.mjs inspect examples/shop/datapackage.json &&
node scripts/explain.mjs examples/shop/datapackage.json
```

shop 中 products 是商品表，id 是唯一编号；orders 是订单表，product_id 必须引用存在的商品，quantity 是至少为1的整数。inspect 只检查描述文件，不能代替完整数据验证。

检查通过后导出到一个尚不存在的新目录：

<!-- test: exit=0 -->
```sh
export MOONFRICTION_DEMO="${MOONFRICTION_DEMO:-$(mktemp -d)}"
node scripts/cli.mjs export examples/shop/datapackage.json "$MOONFRICTION_DEMO/exported" &&
node scripts/explain.mjs "$MOONFRICTION_DEMO/exported/datapackage.json"
```

如果目标目录已存在，请换一个新名称。导出保留原始数据，不自动修复。

## 看懂失败

按[错误演示](errors-demo.md)依次运行四个坏包。explain 提供中文解释；原有 cli 输出 JSON，便于程序调用。成功退出码0，数据不合格1，参数或文件访问错误2。

<!-- diagnostics:start -->
| 错误码 | 含义 | 处理方法 |
|---|---|---|
| csv | CSV 格式无法读取 | 检查引号是否成对、引号内的转义和分隔符。 |
| descriptor | 数据包规则文件不合法 | 检查 datapackage.json 的属性、字段和资源声明。 |
| foreign-key | 引用的记录不存在 | 对照目标表修正编号，或补充确实存在的目标记录。 |
| foreign-key-schema | 外键规则不合法 | 核对源字段、目标资源、目标字段及字段类型。 |
| foreign-key-scope | 跨表外键需要完整数据包 | 在数据包中使用 validate_package 校验；单表接口不会假装已解析其他资源。 |
| header | 表头与规则不一致 | 按规则的字段名称和顺序修正 CSV 第一条记录。 |
| input | 调用输入不合法 | 提供 descriptor 和每个资源对应的 CSV 字符串。 |
| invalid-table | 传入的逻辑表结构不合法 | 先校验原始记录，再使用有效报告中的逻辑表。 |
| json | JSON 文本无法解析 | 检查逗号、引号、括号和 JSON 语法。 |
| maximum | 数值高于上限 | 核对数值及定义的最大值。 |
| maxLength | 文本长于长度上限 | 核对文本内容及最大长度规则。 |
| minimum | 数值低于下限 | 核对数值及定义的最小值。 |
| minLength | 文本短于长度下限 | 补充文本或核对最小长度规则。 |
| primary-key-duplicate | 记录编号重复 | 让主键或组合主键能够唯一标识记录。 |
| primary-key-null | 记录编号缺失 | 补齐主键的所有组成字段。 |
| primary-key-schema | 主键规则不合法 | 使用已定义字段，检查组合键是否为空或重复。 |
| required | 必填字段缺失 | 补充有效值；不要直接删除记录。 |
| resource-input | 资源输入缺失或重复 | 按描述文件为每个资源提供一次对应输入。 |
| row-width | 记录列数不匹配 | 检查分隔符、引号和缺少或多余的列。 |
| schema | 字段规则不合法 | 检查字段名称、类型及约束是否适用和互相矛盾。 |
| type | 字段类型不正确 | 按字段定义填写数字、文字或布尔值。 |
| unique | 字段值重复 | 检查重复记录或字段的唯一约束。 |
| unsupported | 使用了尚不支持的功能 | 查看兼容范围，调整规则；不要将此结果视为通过。 |
| unsupported-range | 数值边界无法可靠比较 | 查看整数精度限制，调整边界或采用其他校验工具。 |
<!-- diagnostics:end -->

记录号从表头后的第1条数据起算，并非始终等于文本文件行号。其他错误保留原始代码和原因；不支持的功能会拒绝，不算检查通过。

## 你可以参与

复制 shop 到临时目录，用自己的合成数据替换商品名；预测检查结果再运行。记录“输入、期望、实际结果、哪里看不懂”，就是可用于改进项目的反馈。不要填写个人隐私。
