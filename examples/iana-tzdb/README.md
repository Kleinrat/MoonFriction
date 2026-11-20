# IANA 时区表的规则变更演练

假设导入系统准备把国家代码列限制为两个字符。这个案例用 IANA 发布的完整时区表检查这项改动的影响。基础规则和拟议改动由本示例定义；数据来自 2025b，记录顺序与原表一致。[IANA 时区数据库](https://www.iana.org/time-zones)

## 在本地复现

仓库已附转换后的 CSV。以下命令从仓库根目录执行：

```sh
sh scripts/build.sh
d=examples/iana-tzdb
node scripts/cli.mjs validate "$d/datapackage.json"
node scripts/cli.mjs schema diff "$d/schema.json" "$d/single-country.schema.json"
node scripts/cli.mjs validate-stream "$d/single-country.schema.json" "$d/zones.csv" --max-errors 34
```

第一条校验通过全部 312 条记录，包括时区标识主键检查。比较结果显示 country_codes 的 maxLength 从未设置变为 2。最后一条命令完成扫描、报告 34 个 maxLength 错误并退出 1。第 85 条 Europe/Zurich 的原值是 `CH,DE,LI`。源表允许一个时区对应多个国家代码，导入这份数据时应保留完整列表。独立参考工具 Frictionless Framework 5.21.0 给出了相同的 34 条受影响记录；该对照已加入仓库参考测试。

## 来源及转换

归档固定为 tzdata2025b，源文件为 zone1970.tab。文件头声明其属于公有领域。这里只跳过注释和空行，保留每条数据记录，将第三列时区标识移至首列，为缺省的第四列备注补空字符串，并使用标准 CSV 引号保留值中的逗号。坐标保留上游原文。[源表说明](https://github.com/eggert/tz/blob/2025b/zone1970.tab) · [上游许可](https://github.com/eggert/tz/blob/2025b/LICENSE)

需要复核来源时，从仓库根目录运行以下命令。转换脚本校验归档 SHA-256，仅从中读取 zone1970.tab，不解包到磁盘。

```sh
work=$(mktemp -d)
curl -fsSL https://data.iana.org/time-zones/releases/tzdata2025b.tar.gz -o "$work/tzdata2025b.tar.gz"
python3 examples/iana-tzdb/prepare.py "$work/tzdata2025b.tar.gz" > "$work/zones.csv"
cmp "$work/zones.csv" examples/iana-tzdb/zones.csv
```

| 文件 | SHA-256 |
|---|---|
| tzdata2025b.tar.gz | `11810413345fc7805017e27ea9fa4885fd74cd61b2911711ad038f5d28d71474` |
| zones.csv | `245e82d730c1fff286117da6e34241ca70704b57113385d2f282a9c4a631195a` |
