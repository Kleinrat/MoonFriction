# JSON batch input consumer

This example validates JSON rows against a standalone Table Schema without
creating a Data Package. It shows array rows, object rows with a different key
order, and the explicit `extra-property` diagnostic.

`scripts/test_embedding.py` compiles this example as a separate MoonBit
consumer together with `examples/standalone-consumer`.

> Mooncakes 当前公开版 0.1.2 尚未包含新增 API；在 0.2.0 发布前，请通过本仓库的
> workspace 依赖编译（`scripts/test_embedding.py` 就是这样做的），不要直接依赖已发布版本。
