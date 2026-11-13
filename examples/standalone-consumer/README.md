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
