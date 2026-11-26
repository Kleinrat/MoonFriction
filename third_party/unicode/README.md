# Unicode 16.0.0 property tables

The MoonBit interval tables in `src/core/unicode_properties.mbt` are generated from these Unicode Character Database files.

- [DerivedGeneralCategory.txt](https://www.unicode.org/Public/16.0.0/ucd/extracted/DerivedGeneralCategory.txt)
- [Blocks.txt](https://www.unicode.org/Public/16.0.0/ucd/Blocks.txt)
- [PropertyValueAliases.txt](https://www.unicode.org/Public/16.0.0/ucd/PropertyValueAliases.txt)

Place the three files in one directory. From the project root, run `python3 scripts/generate_unicode_properties.py DATA_DIRECTORY` and `moon fmt`. The generator verifies the three SHA-256 digests before use. The tables are covered by the [Unicode license](LICENSE).
