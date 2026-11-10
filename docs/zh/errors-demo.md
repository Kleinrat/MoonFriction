# 三个可以复现的错误

先完成[准备步骤](getting-started.md)。以下故意无效的数据包只用于演示；命令退出码1是预期结果。

```sh
node scripts/explain.mjs examples/broken-type/datapackage.json
node scripts/explain.mjs examples/broken-primary-key/datapackage.json
node scripts/explain.mjs examples/broken-foreign-key/datapackage.json
```

1. broken-type：orders.csv 第1条数据的 quantity 填了 two。应出现 type；复制到临时目录后改为2，再检查。
2. broken-primary-key：products.csv 两条记录的 id 都为1。应出现 primary-key-duplicate，且订单引用2也不存在，可能同时出现 foreign-key。把第2条商品编号改为2，再检查。
3. broken-foreign-key：orders.csv 第1条数据引用商品999，商品表只有1和2。应出现 foreign-key；将999改为1，再检查。

修改请在临时副本中进行，保留仓库中的坏包作为回归样例。修正后应退出0并显示检查通过。自动验证：`node scripts/test_beginner.mjs`，CI 同时检查 JSON 诊断码和中文入口退出码。
