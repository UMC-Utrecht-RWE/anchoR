# anchoR
Tools to organise and standardise epidemiologic anchoring.

The package now provides a small reusable API:

- `derive_t0()` derives an index date from concept records.
- `define_window()` builds anchoring windows from metadata.
- `anchor()` applies SQL-backed selector rules such as `LATEST`, `EARLIEST`, `COUNT`, and `RANGE_COUNT`.

Bundled selector templates live under `inst/sql/`. The original study-specific reference scripts are preserved under `inst/examples/legacy/`.
