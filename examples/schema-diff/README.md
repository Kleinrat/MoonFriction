# 在脚本中使用 schema diff

在仓库根目录构建，然后逐条运行下面的命令。每条命令后都可以运行 `echo $?` 查看退出码。

```sh
sh scripts/build.sh
d=examples/schema-diff
node scripts/cli.mjs schema diff "$d/old.json" "$d/revised.json"
node scripts/cli.mjs schema diff "$d/old.json" "$d/old.json"
node scripts/cli.mjs schema diff "$d/old.json" "$d/invalid.json"
node scripts/cli.mjs schema diff "$d/old.json" "$d/absent.json"
node scripts/cli.mjs schema diff "$d/old.json"
```

| 上述输入 | 退出码 | 有内容的输出流 | 预期内容 |
|---|---|---|---|
| 更新订单状态枚举 | 0 | stdout，JSON | 两条变更。[完整输出](expected/revised.json) |
| 比较相同的订单规则 | 0 | stdout，JSON | `{"ok":true,"changes":[]}` |
| 新规则使用未知类型 | 1 | stdout，JSON | `ok: false`、`schema: "new"` 和诊断数组。[完整输出](expected/invalid.json) |
| 新规则文件缺失 | 2 | stderr，JSON | 如 `{"ok":false,"error":"ENOENT: no such file or directory, open 'examples/schema-diff/absent.json'"}`。错误描述随系统和路径而异。 |
| 少给一个文件参数 | 2 | stderr，文本 | 以 `Usage:` 开头的用法说明 |

每种情况的另一条输出流均为空。自动化脚本应先检查退出码，分别读取 stdout 和 stderr。退出码 0 表示完成比较，是否发现变化由 `changes` 决定。

### 如何读取变化

每条记录的 `field` 是字段名，空字符串表示整张表。`rule` 标识规则，`before` 和 `after` 是两版规则的值。`impact` 可取 `tightened`（收紧）、`relaxed`（放宽）、`review`（需要复核）或 `orderOnly`（复合主键仅重排）。影响按单条规则解释。

在第一个例子中，订单状态删去 `draft` 并新增 `shipped`。两条记录有相同的完整枚举 `before` 和 `after`。收紧记录的 `members` 是移除的值，放宽记录的 `members` 是新增的值。`members` 是可选字段。双方都设有枚举时用它表示成员差异，整条枚举约束新增或取消时则省略。

### 如何读取错误

两个文件都成功读入后，按 old、new 顺序检查规则。JSON 语法错误和无效的字段规则都会返回退出码 1。`schema` 标出先失败的一侧，`errors` 里的每条诊断包含代码 `code`、资源名 `resource`、记录号 `row`、字段 `field` 与说明 `message`。示例中的 `row: 0` 表示错误发生在规则定义中。

文件访问或 UTF-8 解码失败时返回退出码 2，stderr 的 JSON 只提供 `ok` 和错误描述 `error`。参数数量错误时同样返回 2，stderr 是用法文本。脚本应保留这段文本供排查。

在仓库根目录运行 `node scripts/test_schema_diff.mjs` 可检查这些结果及其输出位置。
