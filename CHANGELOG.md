# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

### Added

- `anchor_by_selector()`: runs `anchor()` once per unique `selector` value in
  `metadata`, so a single query covers every variable sharing that selector
  regardless of `chunk_size`. Cheaper in `concepts` scans than
  `anchor_by_variable()`, but (like `anchor()`) appends rather than swapping
  individual `variable_id` partitions, so it's meant for a fresh, one-shot
  `anchor_hive_path` rather than safe per-variable reruns.

### Changed

- `anchor_by_variable()` now opens one DuckDB connection and loads `concepts`
  once for the whole call instead of once per `variable_id`, and reuses the
  already-validated `population` table across variables instead of
  re-validating/re-copying it each time. Cuts redundant concepts scans and
  connection overhead for metadata with many standard-window variables.
- `anchor_by_variable()` now processes `variable_id`s in chunks (new
  `chunk_size` argument, default 20) instead of strictly one at a time, so a
  single selector query can cover several variables' `concepts` join at once.
  Each chunk still stages to a temporary hive and swaps in one
  `variable_id` partition at a time, so partial reruns remain isolated to the
  requested variables. Pass `chunk_size = 1` for the previous behavior.
  Variables are also now ordered by selector before being sliced into
  chunks, so a chunk is as selector-homogeneous as `chunk_size` allows
  instead of following raw metadata row order.
- `inst/sql/latest.sql`/`earliest.sql` now pick the record with
  `arg_max`/`arg_min` aggregation instead of `ROW_NUMBER() OVER (... ORDER BY
  ...)`, avoiding an unnecessary sort of every candidate match per
  person/variable/window. Output (including the same-date tie-break on the
  larger value) is unchanged; `count.sql`/`count_more_than_1.sql`/
  `range_count.sql`/`all.sql` already used sort-free aggregation and were
  left as is.

### Removed

### Fixed

### Future Work

## [v1.4]

### Added

- `R/pregnancy_window.R` with four constructore for multi-events entryes.
- `documentation` Folder containing a more procise and extend documentation.

# List of releases
- unreleased: https://github.com/UMC-Utrecht-RWE/anchoR@main
- v1.4 https://github.com/UMC-Utrecht-RWE/anchoR@1.4
