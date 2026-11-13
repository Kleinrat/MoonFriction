# JSON batch input consumer

This example validates JSON rows against a standalone Table Schema without
creating a Data Package. It shows array rows, object rows with a different key
order, and the explicit `extra-property` diagnostic.

`scripts/test_embedding.py` compiles this example as a separate MoonBit
consumer together with `examples/standalone-consumer`.
