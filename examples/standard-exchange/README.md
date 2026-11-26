# 用标准字段交换仓库发货数据

`datapackage.json` 描述商品与发货两张 CSV 表。发货日期采用标准的 `date` 类型并有最早允许日期。发货数量是整数且至少为 1，`packed` 使用 `yes` 和 `no`，`details` 是 JSON 对象。主键标识各表记录，`shipments.sku` 必须引用商品表中的 SKU。

在仓库根目录运行下面的命令。临时目录用于导出。

```sh
sh scripts/build.sh
example=examples/standard-exchange
out=$(mktemp -d)
node scripts/cli.mjs validate "$example/datapackage.json"
node scripts/cli.mjs export "$example/datapackage.json" "$out/tabular"
node scripts/cli.mjs validate "$out/tabular/datapackage.json"
node scripts/cli.mjs validate "$example/multipart.json"
node scripts/cli.mjs inspect-package "$example/mixed.json"
node scripts/cli.mjs export-package "$example/mixed.json" "$out/mixed"
```

前三条 CLI 命令应返回 `ok: true`，两张表各有两条记录。校验 `multipart.json` 时，商品表从两个 CSV 文件合并出三条数据，发货表从内嵌 JSON 读出两条数据，其中一条引用第二个分片里的商品。最后两条命令应列出 `local`、`inline`、`remote` 三种资源。通用导出会复制两个商品 CSV 分片，远程 URL 和内嵌 JSON 保存在导出的描述符中。

## 用参考工具交叉验证

在已安装 Frictionless Framework 5.21.0 的环境中运行 `python scripts/test_reference.py`。脚本把案例复制到临时目录，分别构造日期早于下限、非法闰日、商品引用不存在、数量为 0 和布尔标记无效五种错误。两种工具都须拒绝这五种输入，MoonFriction 还须报告资源、逻辑记录号和字段。恢复数据后，参考工具应能验证 MoonFriction 导出的包。另有独立检查用参考工具读取通用导出的内嵌数据和远程引用。远程示例是占位地址，测试期间无需访问它。

两份规范及其边界见 [兼容范围与验证状态](../../docs/COMPATIBILITY.md)。
