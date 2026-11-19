# 物资借用记录检查工具

独立 MoonBit 应用，固定从 Mooncakes 安装 `Kleinrat/frictionless@0.2.0`，不引用父仓库源码。可单独复制此目录到其他位置。依赖 MoonBit（验证版本0.10.20）及 Node.js 22+。

这是合成业务场景，不是已上线的库存系统或真实用户试用证据。它检查物资编号、借用编号、数量和跨表引用，不检查当前可借库存、归还、日期、预约冲突或多人操作。JSON 申请只检查字段，不检查物资存在性或业务库存。

## 完整操作

进入本目录后：

```sh
moon update
moon build --target js --release
node app.mjs draft data /tmp/asset-draft
```

目标目录必须不存在，可以换成其他新目录。草稿保留前导零编号，包含采样与歧义提示，但不猜主键、外键、必填和数量约束。

打开 `/tmp/asset-draft/datapackage.json` 人工确认规则。随附的 `reviewed-rules.json` 是本场景明确编写的业务规则示范，可以对照编辑或用它替换草稿规则：

```sh
cp reviewed-rules.json /tmp/asset-draft/datapackage.json
node app.mjs check /tmp/asset-draft
node app.mjs check-request data/request.json
```

两张表的约定固定为 `assets.csv` 和 `loans.csv`。物资编号是 string（`001`不等于`1`），借用编号是 integer；数量是至少为1的整数，借用物资必须存在。库存列仅要求不小于0，不对借用数量之和做库存扣减判断。

试着在临时副本 loans.csv 中把 asset_id 改为999，再检查，应退出1并报告 `foreign-key`；恢复为001后应通过。重复 loan_id 会报 `primary-key-duplicate`，数量0会报 `minimum`。JSON 申请中的数量0也应失败，但该命令的通过只代表字段通过。

确认有效后导出：

```sh
node app.mjs export /tmp/asset-draft /tmp/asset-export
node app.mjs check /tmp/asset-export
```

导出保留描述文件和CSV字节，拒绝覆盖已有目录；无效数据包不导出。退出码0代表本命令范围内通过，1代表数据不合格，2代表参数或文件访问错误。数据完整读入内存；每个文件限制16 MiB，本地工具不用于不可信多人上传服务。

## 验证与反馈

父仓库的 `scripts/test_asset_consumer.py` 会把此目录复制到临时目录，重新通过注册表安装依赖、构建并执行以上闭环；`--reference` 还会用官方 Frictionless Framework 校验导出包。

请让实际使用者按步骤试用，并填写 [反馈表](FEEDBACK.md)。没有实际试用前，不填写耗时、采用人数或“真实需求已验证”。
