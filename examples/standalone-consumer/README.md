# Standalone Table Schema consumer

This example imports only `Kleinrat/frictionless/src/core` and parses a Table
Schema directly, without creating a Data Package. It is compiled as a separate
workspace consumer by `scripts/test_embedding.py`.

```sh
moon add Kleinrat/frictionless
```

Use `@core.parse_table_schema` and `@core.validate_table_schema`; a schema with a
cross-table foreign key is accepted by the parser but `validate_table_schema`
reports `foreign-key-scope` because one table cannot resolve other resources.

> Mooncakes 当前公开版 0.1.2 尚未包含新增 API；在 0.2.0 发布前，请通过本仓库的
> workspace 依赖编译（`scripts/test_embedding.py` 就是这样做的），不要直接依赖已发布版本。
