# Supported subset and policy choices

This is a developing Data Package v1 / Table Schema v1 subset. It is not a full conformance claim or a Data Package v2 implementation.

## Supported

- Inline schemas for named local UTF-8 CSV resources, with default comma/double-quote dialect. Blank lines are preserved as empty records; data whitespace is not trimmed.
- Standalone Table Schema descriptors (`parse_table_schema` / `validate_table_schema`) using the same field, constraint, missing-value and primary-key semantics as inline resource schemas. Cross-table foreign keys are structurally accepted but single-table validation reports `foreign-key-scope` rather than resolving them.
- string (default type), integer (signed 64-bit), number (finite binary64), boolean with default exact physical representations.
- required, unique, minimum, maximum, minLength, maxLength; inapplicable constraints are descriptor errors.
- Explicit missingValues arrays, including an empty array; omitted missingValues means [""]. Markers match before type conversion. Explicit null descriptor properties are not treated as omission.
- Single and composite primary keys; named-resource and self-reference foreign keys. Typed comparisons happen after casting.
- Original descriptor metadata and original CSV bytes retained on export.

## Explicit policies / numeric limitations

- A required field rejects Missing; with missingValues=[] a string empty value remains a valid string.
- Nulls are ignored for unique checks. Primary keys reject any Missing component. Foreign keys with any Missing component are skipped; all nonmissing keys must resolve. These are explicit local validation policies where the prose specification does not fully prescribe behavior.
- Field names are case-sensitive. Key comparison requires the same declared field type on both sides. Foreign key string-vs-array descriptor forms must match.
- Integer lexical subset: optional sign and ASCII digits, including leading zeros. Number lexical subset: optional sign, digits, optional fraction with at least one digit, optional e/E exponent. No whitespace, grouping, currency stripping, NaN or infinities. This is deliberately narrower than every form discussed by the standard.
- Integers retain signed 64-bit values. Numeric bounds are binary64; applying numeric bounds to integers outside ±(2^53−1) returns unsupported-range instead of silently rounding a passing comparison.
- Text length is counted in Unicode scalar values, not bytes or UTF-16 code units.
- Schema error positions use row=0. Data row numbers are logical 1-based data records, not physical line numbers (quoted CSV can span lines).

## Rejected for now

Remote URLs, resource path arrays, inline data, external schema references, custom profiles, compressed resources, non-UTF-8 encoding, custom dialect objects, non-default field formats, other field types, enum and pattern constraints, custom trueValues/falseValues, bareNumber, decimalChar and groupChar. Adding a feature requires reference and regression tests first.

The host enforces realpath containment and refuses overwriting export destinations. This local CLI is not designed as a multi-user untrusted-upload service. BOM stripping is consistent for the CSV API and CLI. It loads resources in memory; each source resource is limited to 16 MiB. Export preserves data; it does not silently clean or repair it.

## Independent validation

scripts/test_reference.py compares selected supported positive/negative cases with Frictionless Framework 5.21.0 and checks that the Framework can import a package exported by this implementation. This proves those scenarios only, not whole-standard equivalence.

## Specification references

- Data Package v1: https://specs.frictionlessdata.io/data-package/ (page updated 2017-05-02)
- Table Schema v1: https://specs.frictionlessdata.io/table-schema/ (page updated 2021-10-05)
- Tabular Data Resource: https://specs.frictionlessdata.io/tabular-data-resource/

The independent DeepSeek review found prose/JSON-Schema discrepancies. See reviews/deepseek-spec-review.txt; review suggestions are evidence to inspect, not automatically accepted normative requirements.
