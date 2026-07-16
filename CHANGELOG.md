# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

## [v1.4.2]

### Added

- `clear_anchor_partitions` to avoid the duplications of row while using `anchor()` and `anchor_by_selector()` by `OVERWRITE_OR_IGNORE`.

### Removed

- `anchor_row_id` no longer appears in the parquet hive written by `anchor()`/`anchor_by_variable()`/`anchor_by_selector()`. It was always a synthetic id scoped to a single internal query call (not comparable across different `chunk_size` values or between `anchor_by_selector()`/`anchor_by_variable()`), so reading it from the raw hive and using it to join/diff two runs could silently misalign rows despite matching content. It remains an internal join key inside the selector SQL templates and `population_windows`; `get_anchor_result()` now orders its output by `variable_id, person_id, T0, window_name` instead.

## [v1.4.1.1]

### Changed
- `duplicate_rows` in `R/get_anchor_result.R` had an error message now replaced with a wanring message. The decision is in line with what done previously in the same file. For now we keep this results and we will the decision if these are to be kept or not to a futere discussion with analysis team.

## [v1.4.1]

### Added

- `IN_PRIOR_PREG` metadata can now set optional `start_look_back`/`end_look_back` columns (NA by default, so existing metadata is unaffected) to restrict which prior pregnancies are eligible at all: only episodes overlapping the anchor-relative range `[T0 + start_look_back, T0 + end_look_back]` are considered (a selection filter on the episode, same overlap rule as `OUTSIDE_ALL_PREG`'s search range). A prior pregnancy entirely outside that range is dropped from consideration before any window is built; one that overlaps is kept and its window is still computed from `start_offset`/`end_offset` exactly as before, unclipped. Kept as separate columns from `start_offset`/`end_offset` (which already shift the episode's own start/end and can be positive) rather than reusing them, since a positive `start_offset` would otherwise push the anchor-relative bound past `T0`, which a by-definition-prior episode could never satisfy.
- `anchor_by_selector()`: runs `anchor()` once per unique `selector` value in `metadata`, so a single query covers every variable sharing that selector regardless of `chunk_size`. Cheaper in `concepts` scans than `anchor_by_variable()`; every `variable_id` it touches is safely replaced (see the `OVERWRITE_OR_IGNORE` fix below), it just doesn't bound the blast radius per query the way `anchor_by_variable()`'s `chunk_size` does every variable sharing a selector is recomputed together.

### Changed

- `anchor_by_variable()` now opens one DuckDB connection and loads `concepts` once for the whole call instead of once per `variable_id`, and reuses the already-validated `population` table across variables instead of re-validating/re-copying it each time. Cuts redundant concepts scans and connection overhead for metadata with many standard-window variables.
- `anchor_by_variable()` now processes `variable_id`s in chunks (new `chunk_size` argument, default 20) instead of strictly one at a time, so a single selector query can cover several variables' `concepts` join at once. Each chunk still stages to a temporary hive and swaps in one `variable_id` partition at a time, so partial reruns remain isolated to the requested variables. Pass `chunk_size = 1` for the previous behavior. Variables are also now ordered by selector before being sliced into chunks, so a chunk is as selector-homogeneous as `chunk_size` allows instead of following raw metadata row order.
- `load_concepts_table()` now accepts an optional `concept_ids` filter, applied by `anchor()`/`anchor_by_variable()` as `unique(metadata$concept_id)` for the metadata being processed in that call. For an in-memory `concepts` table this filters before the copy into DuckDB, so irrelevant rows are never materialized; for parquet/DuckDB sources it adds a `WHERE concept_id IN (...)` to the view, giving DuckDB's reader an explicit predicate to prune files/row-groups on (e.g. full hive partition pruning if `concepts` happens to be partitioned by `concept_id`) instead of depending on the query planner's runtime join-filter pushdown to prune it implicitly.
- `inst/sql/latest.sql`/`earliest.sql` now pick the record with `arg_max`/`arg_min` aggregation instead of `ROW_NUMBER() OVER (... ORDER BY ...)`, avoiding an unnecessary sort of every candidate match per person/variable/window. Output (including the same-date tie-break on the larger value) is unchanged; `count.sql`/`count_more_than_1.sql`/`range_count.sql`/`all.sql` already used sort-free aggregation and were left as is.

### Removed

- **Breaking:** `start_look_back`/`end_look_back` are no longer accepted as alternate names for `start_offset`/`end_offset`. `normalize_metadata()` used to rename whichever of the two you supplied; that rename is gone. `start_offset`/`end_offset` must now be supplied directly under those exact names for every constructor, including `GENERIC`. This frees up `start_look_back`/`end_look_back` to mean the new, unrelated `IN_PRIOR_PREG` lookback-filter columns described above. **Any existing metadata (including BRIDGE-derived `study_variables.csv` files, per `Input_metadata.md`) that supplies offsets as `start_look_back`/ `end_look_back` must rename those columns to `start_offset`/`end_offset` before calling `anchor()`/`anchor_by_variable()`/`anchor_by_selector()`, or those rows will error with "object 'start_offset' not found".**

### Fixed

- `get_anchor_result()`'s "`population` contains multiple rows for the same `person_id` and `T0`" error now names the conflicting column(s) (e.g. `match_id`) instead of leaving the caller to hunt for which column made the key non-unique.
- Clarified `Tutorial_pregnancy_windows.md` and `examples/Pregnancy Window Worked Example.md`: `start_look_back`/`end_look_back` (episode eligibility filter, `IN_PRIOR_PREG` only) and `OUTSIDE_ALL_PREG`'s own `start_offset`/`end_offset` (its anchor-relative search range) are two different mechanisms that happen to both express "an anchor-relative range" -- setting `start_look_back`/`end_look_back` on an `OUTSIDE_ALL_PREG` row has no effect, a case that came up in practice.
- `anchor()`/`anchor_by_variable()`/`anchor_by_selector()` write their parquet output with `OVERWRITE_OR_IGNORE` instead of `APPEND`. Previously, `anchor()` (and anything writing directly to `anchor_hive_path`) appended a new file on every call. `OVERWRITE_OR_IGNORE` instead replaces only the `variable_id` partition(s) a call actually produces and leaves every other partition untouched; verified (empirically, against DuckDB 1.5.4) to be precise per-partition across multiple variables and separate connections, and to leave existing data untouched if the query itself fails partway through.

### Future Work

## [v1.4]

### Added

- `R/pregnancy_window.R` with four constructore for multi-events entryes.
- `documentation` Folder containing a more procise and extend documentation.

# List of releases
- unreleased: https://github.com/UMC-Utrecht-RWE/anchoR@main
- v1.4.2 https://github.com/UMC-Utrecht-RWE/anchoR/releases/tag/v1.4.2
- v1.4.1.1 https://github.com/UMC-Utrecht-RWE/anchoR/releases/tag/v1.4.1.1
- v1.4.1 https://github.com/UMC-Utrecht-RWE/anchoR/releases/tag/v1.4.1
- v1.4 https://github.com/UMC-Utrecht-RWE/anchoR/releases/tag/v1.4
