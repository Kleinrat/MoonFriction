# Sources and third-party notices

- Original project implementation: MIT, see LICENSE. AI-assisted development and review use Codex and DeepSeek Harness (DeepSeek-V4.1-Flash 1017). The maintainer is responsible for reviewing behavior and scope.
- CSV parsing reuses moonbit-community/NyaCSV 0.3.4 (Apache-2.0): https://github.com/moonbit-community/NyaCSV . Dependency source is not vendored. The Apache-2.0 license is retained in third_party/NyaCSV-APACHE-2.0.txt for bundled distributions. Our strict quote-framing guard is a separate implementation, not a replacement parser.
- Custom profile checks reuse [moonbitstack/moonschema 0.2.0](https://github.com/moonbitstack/moonschema) (Apache-2.0) as a registry dependency.
- Implementation targets an explicit subset of the Frictionless Data Package v1 and Table Schema v1 specifications at https://specs.frictionlessdata.io/ . It is not a port of the Python Framework and is not endorsed by Frictionless.
- Frictionless Framework 5.21.0 is used only as an optional independent test oracle. It is not a runtime dependency of the library or CLI.

- The historical UTC leap-second dates are derived from the public-domain [IANA tzdb leapseconds file](https://data.iana.org/time-zones/tzdb/leapseconds).

- The example CSV in examples/iana-tzdb is derived from the public-domain zone1970.tab in IANA tzdata2025b. It preserves the data records and changes the column order, header and delimited-file encoding. See the example README for upstream attribution, license, hashes and reproduction.

- XML Schema regular expressions use data derived from Unicode Character Database 16.0.0. See [Unicode license](third_party/unicode/LICENSE) and [regeneration instructions](third_party/unicode/README.md).

- Data Package license identifiers are sourced from the [Open Definition license registry](https://github.com/okfn/licenses/tree/086d0bfabce15ad0d587c7e0449c695dc0f66fcf/licenses). The project retains the identifiers only.
