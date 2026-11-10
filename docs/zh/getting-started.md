# 第一次使用 MoonFriction

这是给处理 CSV 的开发者使用的数据包检查库。CSV 是表格文本；datapackage.json 是说明各列含义、类型和表间关系的规则文件。检查不会替你改数据。

## 先准备

安装 MoonBit 和 Node.js 22+，下载本仓库，在仓库目录执行：

```sh
moon update
sh scripts/build.sh
node scripts/cli.mjs inspect examples/shop/datapackage.json
node scripts/explain.mjs examples/shop/datapackage.json
```

shop 中 products 是商品表，id 是唯一编号；orders 是订单表，product_id 必须引用存在的商品，quantity 是至少为1的整数。inspect 只检查描述文件，不能代替完整数据验证。

检查通过后导出到一个尚不存在的新目录：

```sh
node scripts/cli.mjs export examples/shop/datapackage.json /tmp/my-shop-export
node scripts/explain.mjs /tmp/my-shop-export/datapackage.json
```

如果目标目录已存在，请换一个新名称。导出保留原始数据，不自动修复。

## 看懂失败

按[错误演示](errors-demo.md)依次运行三个坏包。explain 提供中文解释；原有 cli 输出 JSON，便于程序调用。成功退出码0，数据不合格1，参数或文件访问错误2。

| 错误码 | 含义 | 处理方法 |
|---|---|---|
| header | 表头名称或顺序不一致 | 对照字段定义修改 CSV 表头 |
| type | 类型不正确 | 数字列填写数字，不填 two |
| required | 必填值缺失 | 补齐信息 |
| unique | 值重复 | 检查记录或规则 |
| minimum / maximum | 数值超范围 | 核对值及上下限 |
| primary-key-duplicate | 编号重复 | 为记录提供唯一编号 |
| primary-key-null | 编号缺失 | 补全主键 |
| foreign-key | 引用不存在 | 对照目标表检查编号 |
| row-width | 列数不对 | 检查逗号、引号和列数 |

记录号从表头后的第1条数据起算，并非始终等于文本文件行号。其他错误保留原始代码和原因；不支持的功能会拒绝，不算检查通过。

## 你可以参与

复制 shop 到临时目录，用自己的合成数据替换商品名；预测检查结果再运行。记录“输入、期望、实际结果、哪里看不懂”，就是可用于改进项目的反馈。不要填写个人隐私。
