# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

### Added

- `anchor_by_selector()`: runs `anchor()` once per unique `selector` value in
  `metadata`, so a single query covers every variable sharing that selector
  regardless of `chunk_size`. Cheaper in `concepts` scans than
  `anchor_by_variable()`; every `variable_id` it touches is safely replaced
  (see the `OVERWRITE_OR_IGNORE` fix below), it just doesn't bound the blast
  radius per query the way `anchor_by_variable()`'s `chunk_size` does --
  every variable sharing a selector is recomputed together.

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
- `load_concepts_table()` now accepts an optional `concept_ids` filter,
  applied by `anchor()`/`anchor_by_variable()` as `unique(metadata$concept_id)`
  for the metadata being processed in that call. For an in-memory `concepts`
  table this filters before the copy into DuckDB, so irrelevant rows are
  never materialized; for parquet/DuckDB sources it adds a `WHERE concept_id
  IN (...)` to the view, giving DuckDB's reader an explicit predicate to
  prune files/row-groups on (e.g. full hive partition pruning if `concepts`
  happens to be partitioned by `concept_id`) instead of depending on the
  query planner's runtime join-filter pushdown to prune it implicitly.
- `inst/sql/latest.sql`/`earliest.sql` now pick the record with
  `arg_max`/`arg_min` aggregation instead of `ROW_NUMBER() OVER (... ORDER BY
  ...)`, avoiding an unnecessary sort of every candidate match per
  person/variable/window. Output (including the same-date tie-break on the
  larger value) is unchanged; `count.sql`/`count_more_than_1.sql`/
  `range_count.sql`/`all.sql` already used sort-free aggregation and were
  left as is.

### Removed

### Fixed

- `get_anchor_result()`'s "`population` contains multiple rows for the same
  `person_id` and `T0`" error now names the conflicting column(s) (e.g.
  `match_id`) instead of leaving the caller to hunt for which column made the
  key non-unique.
- `anchor()`/`anchor_by_variable()`/`anchor_by_selector()` write their parquet
  output with `OVERWRITE_OR_IGNORE` instead of `APPEND`. Previously,
  `anchor()` (and anything writing directly to `anchor_hive_path`) appended a
  new file on every call, so rerunning it for a `variable_id` already present
  at `anchor_hive_path` silently duplicated rows -- the docs' workaround was
  "use a fresh `anchor_hive_path` per run". `OVERWRITE_OR_IGNORE` instead
  replaces only the `variable_id` partition(s) a call actually produces and
  leaves every other partition untouched; verified (empirically, against
  DuckDB 1.5.4) to be precise per-partition across multiple variables and
  separate connections, and to leave existing data untouched if the query
  itself fails partway through.

### Future Work

## [v1.4]

### Added

- `R/pregnancy_window.R` with four constructore for multi-events entryes.
- `documentation` Folder containing a more procise and extend documentation.

# List of releases
- unreleased: https://github.com/UMC-Utrecht-RWE/anchoR@main
- v1.4 https://github.com/UMC-Utrecht-RWE/anchoR@1.4
