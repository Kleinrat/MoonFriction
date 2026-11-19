# 0.2.0 — 2026-11-19

安装模块：`Kleinrat/frictionless@0.2.0`。纯 MoonBit 公共 API 位于 `Kleinrat/frictionless/src/core`。

## 新增功能

- 独立 Table Schema 解析及单表校验，不必构造 Data Package。
- 类型化 JSON 批量行输入：保留数字、布尔、文本和空值语义，并明确缺失/额外属性策略。
- 保守 CSV 规则草稿推断和 CLI，包含样本范围、歧义提示、拒绝覆盖及编辑后校验/导出闭环。

## 发布检查

功能基线：`5bae98503cef8d7d60e88f984b85e27ae8b32b69`，原远端 [CI 通过](https://github.com/Kleinrat/MoonFriction/actions/runs/43419200296)。

发布时运行格式检查、check/build、50项 MoonBit 测试、3个独立调用项目、host/beginner/infer/诊断/教程检查及 Frictionless Framework 5.21.0 对照。公开安装检查在发布后用源工作区外的独立项目进行，包括旧包 API 和新增 schema/JSON/inference API。

## 边界

JSON 输入为批量处理；独立 schema 中的跨表引用明确报错；推断默认只采样前100条，不猜必填/唯一/主键，空样本、前导零和混合类型保守回退文本。推断结果是待人工确认的草稿。未实现流式、远程资源或完整标准兼容，不宣称真实用户采用。

已有0.1.2包不被覆盖。历史测试记录描述当时未发布状态；新版是否可下载以 Mooncakes 对应版本为准。
