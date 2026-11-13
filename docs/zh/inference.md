# 从 CSV 生成 Table Schema 草稿

`scripts/infer.mjs` 读取 CSV 表头和样本，生成一个**可编辑的** `datapackage.json` 草稿。它不会修改原 CSV，也不会覆盖已有的描述文件。

```sh
tmp=$(mktemp -d)
cp examples/shop/products.csv "$tmp/"
node scripts/infer.mjs "$tmp/products.csv" --out "$tmp/datapackage.json"
```

生成的描述文件里 `path` 只写文件名，因此请把 CSV 和描述文件放在同一目录；如果输出到别处，需要手工调整 `path` 或复制 CSV。命令把采样范围、类型歧义和保守回退原因打印到标准错误，描述文件本身写到标准输出或 `--out`。

## 推断策略

- 默认只采样前 100 条；超过时提示“仅采样前 N 条”，不会假装检查了全部数据。
- 只推断当前支持的 `string`、`integer`、`number`、`boolean`。
- 空样本回退 `string`；列内类型混合回退 `string`，并给出原因。
- 前导零编号（如 `001`）按文本保留，避免把编号变成数字。
- 只有 `true/false` 这类默认布尔词推断为 boolean；仅含 `0/1` 时按 integer 推断并提示歧义。
- 不猜测 `required`、`unique` 或主键；这些需要人工编辑。

## 闭环

```sh
node scripts/infer.mjs data/items.csv --out data/datapackage.json
# 人工编辑 data/datapackage.json（例如加 required 或主键）
node scripts/cli.mjs validate data/datapackage.json
node scripts/cli.mjs export data/datapackage.json /tmp/items-export
```

`scripts/test_infer.mjs` 自动验证“生成→人工改约束→校验→导出→源 CSV 不变”；`scripts/test_reference.py` 还会让 Frictionless Framework 读取生成的描述文件。
