# anchoR

The pipeline transforms raw clinical concept data into analysis-ready datasets by  **anchoring medical events relative to each person's T0 date** , then computing whether events occurred within predefined time windows. The starter code you were given is essentially a simplified version of the same pattern.

The functions within the package needs to handle three things:
- **window definition** (lookback offsets from anchor),
- **concept matching** (joining to the events database), and
- **value extraction** (how to summarise matched records).

The package now provides a small reusable API:

- `derive_t0()` derives an index date from concept records.
- `define_window()` builds anchoring windows from metadata.
- `anchor()` applies SQL-backed selector rules such as `LATEST`, `EARLIEST`, `COUNT`, and `RANGE_COUNT`.

Bundled selector templates live under `inst/sql/`. The original study-specific reference scripts are preserved under `inst/examples/legacy/`.
