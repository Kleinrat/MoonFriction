# Sources and third-party notices

- Original project implementation: MIT, see LICENSE. AI-assisted development and review use Codex and DeepSeek Harness (DeepSeek-V4.1-Flash 1017). The maintainer is responsible for reviewing behavior and scope.
- CSV parsing reuses moonbit-community/NyaCSV 0.3.4 (Apache-2.0): https://github.com/moonbit-community/NyaCSV . Dependency source is not vendored. The Apache-2.0 license is retained in third_party/NyaCSV-APACHE-2.0.txt for bundled distributions. Our strict quote-framing guard is a separate implementation, not a replacement parser.
- Implementation targets an explicit subset of the Frictionless Data Package v1 and Table Schema v1 specifications at https://specs.frictionlessdata.io/ . It is not a port of the Python Framework and is not endorsed by Frictionless.
- Frictionless Framework 5.21.0 is used only as an optional independent test oracle. It is not a runtime dependency of the library or CLI.
