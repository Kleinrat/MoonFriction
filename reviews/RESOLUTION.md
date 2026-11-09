# Review resolutions — 2026-11-09

DeepSeek Harness / DeepSeek-V4.1-Flash (1017) independently reviewed the specification and the 23-test source snapshot. Its second-round report was static analysis, not executed verification. Codex owns the fixes and the tests below.

| Finding | Resolution | Evidence |
|---|---|---|
| Explicit JSON null conflated with omission | Present-null semantic properties rejected while omitted defaults remain supported | descriptor whitebox regression |
| Wide integer bounds round through binary64 | Comparisons outside exact binary64 integer range return unsupported-range; full exact decimal bounds remain unsupported | 2^53-boundary regression |
| Empty resource arrays accepted | Rejected both by descriptor reader and typed package validator | empty package regression |
| Blank CSV rows discarded; BOM differs | Empty records preserved; embedded API strips BOM consistently | blank required row and BOM regressions |
| Unrelated errors hide FK diagnostics | Relationships checked whenever the relevant source and target tables are available | three-resource regression |
| Cross-type/null FK policies unclear | Cross-type comparisons explicitly unsupported; Missing keys skipped, as documented | typed FK and null FK regressions |
| CLI compares URL pathname to filesystem path | Uses fileURLToPath plus realpath for entry detection | Chinese-path and symlinked-temp-root host test |

As of the final local run: 32 MoonBit tests pass; host integration, independent consumer and selected Framework comparisons pass. This does not imply complete standards conformance or real-world user adoption.
