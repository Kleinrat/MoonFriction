# First-version scope

Target: Frictionless Data Package v1 / Table Schema v1, not Data Package v2. A compatibility subset must be published in the README.

Deliverables: a reusable MoonBit library, a CLI, three realistic local datasets, CI and reference interoperability tests.

Implemented vertical slice: descriptor parsing -> load caller-provided resource rows -> convert string/integer/number/boolean fields -> constraints -> primary/foreign-key checks -> structured diagnostics. CSV I/O and portable export with preserved descriptors are implemented.

Local relative CSV paths only initially. Remote URLs, external schemas, ZIP archives, dialect extensions, regex constraints, and unsupported field types must report unsupported status rather than claim full validation. File access belongs in the host adapter; pure core receives data from callers.

Resolved policy choices (details in COMPATIBILITY.md): missingValues is string matching before casting; required is distinct from empty string; primary and foreign keys use typed values; empty/null foreign keys need reference semantics; duplicate resource/field names are descriptor errors; unsafe paths and symlink escape must be handled by the host.

References:
- https://specs.frictionlessdata.io/data-package/
- https://specs.frictionlessdata.io/table-schema/
- https://specs.frictionlessdata.io/tabular-data-resource/
