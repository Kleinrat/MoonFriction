# Release 0.1.0 — 2026-11-09

- Module: [Kleinrat/frictionless@0.1.0](https://mooncakes.io/docs/Kleinrat/frictionless@0.1.0)
- Repository: https://github.com/Kleinrat/MoonFriction
- Source baseline: `24ea4fd1d2a90233ed7dfe2246699bb94bb23f8f`
- License: MIT; NyaCSV dependency: Apache-2.0.
- [Passing CI](https://github.com/Kleinrat/MoonFriction/actions/runs/42645486579)

`moon publish` checked the source and extracted archive, then returned `Server status: 200 OK`. Registry resource metadata confirms the module name, version, repository, MIT license and NyaCSV 0.3.4 dependency.

Archive SHA-256 (`Kleinrat-frictionless-0.1.0.zip`):

```text
a58e39814afe84b8e31104241546443691facc1abc1bc432cde5b926efa6eec1
```

A clean consumer outside the library workspace installed the published module through `moon add Kleinrat/frictionless@0.1.0`. It imported `Kleinrat/frictionless/src/core`, compiled for JS, and printed:

```text
Table valid: true
Primary key errors: 0
```

The registry archive contains the README at publication time. Later repository documentation records the completed publication and consumer verification; it does not change the immutable 0.1.0 archive.

This release implements the documented subset, not all of Frictionless Data Package / Table Schema. See [compatibility](COMPATIBILITY.md) for explicit exclusions and [test record](TESTING-2026-11-09.md) for validation evidence.
