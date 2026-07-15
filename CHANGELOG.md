# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]

### Added

- `IN_PRIOR_PREG` metadata can now set optional `start_look_back`/`end_look_back` columns (NA by default, so existing metadata is unaffected) to restrict which prior pregnancies are eligible at all: only episodes overlapping the anchor-relative range `[T0 + start_look_back, T0 + end_look_back]` are considered (a selection filter on the episode, same overlap rule as `OUTSIDE_ALL_PREG`'s search range). A prior pregnancy entirely outside that range is dropped from consideration before any window is built; one that overlaps is kept and its window is still computed from `start_offset`/`end_offset` exactly as before, unclipped. Kept as separate columns from `start_offset`/`end_offset` (which already shift the episode's own start/end and can be positive) rather than reusing them, since a positive `start_offset` would otherwise push the anchor-relative bound past `T0`, which a by-definition-prior episode could never satisfy.
- `anchor_by_selector()`: runs `anchor()` once per unique `selector` value in `metadata`, so a single query covers every variable sharing that selector regardless of `chunk_size`. Cheaper in `concepts` scans than `anchor_by_variable()`; every `variable_id` it touches is safely replaced (see the `OVERWRITE_OR_IGNORE` fix below), it just doesn't bound the blast radius per query the way `anchor_by_variable()`'s `chunk_size` does every variable sharing a selector is recomputed together.
- `anchor_by_variable()` gains `staging_mode` (`"memory"`, default, or `"disk"`) and `publish` (`"once"`, default, or `"per_chunk"`) arguments controlling how chunk output is held before it reaches `anchor_hive_path`, and when. `staging_mode = "memory"` accumulates every chunk's rows into one DuckDB table (via new internal `add_table_accumulation()`), which DuckDB spills to `staging_dir` on its own if it outgrows RAM, then writes to `anchor_hive_path` with a single `COPY`; `staging_mode = "disk"` keeps the previous behavior of staging each chunk to a local parquet hive under `staging_dir` before moving it into place. `publish = "once"` (default) only writes to `anchor_hive_path` after every chunk in the call has succeeded, discarding everything and leaving `anchor_hive_path` completely unchanged if any chunk fails; `publish = "per_chunk"` writes (and keeps) each chunk's results as soon as that chunk finishes, even if a later chunk in the same call fails.
- `anchor_by_variable()` gains a `staging_dir` argument (default `tempdir()`) for the local scratch space used for DuckDB's `temp_directory` and, in `staging_mode = "disk"`, the local staging hive -- lets both be pointed at fast local disk independently of `anchor_hive_path`.

### Changed

- `anchor_by_variable()` now opens one DuckDB connection and loads `concepts` once for the whole call instead of once per `variable_id`, and reuses the already-validated `population` table across variables instead of re-validating/re-copying it each time. Cuts redundant concepts scans and connection overhead for metadata with many standard-window variables.
- `anchor_by_variable()` now processes `variable_id`s in chunks (new `chunk_size` argument, default 20) instead of strictly one at a time, so a single selector query can cover several variables' `concepts` join at once. Each chunk still stages to a temporary hive and swaps in one `variable_id` partition at a time, so partial reruns remain isolated to the requested variables. Pass `chunk_size = 1` for the previous behavior. Variables are also now ordered by selector before being sliced into chunks, so a chunk is as selector-homogeneous as `chunk_size` allows instead of following raw metadata row order.
- `load_concepts_table()` now accepts an optional `concept_ids` filter, applied by `anchor()`/`anchor_by_variable()` as `unique(metadata$concept_id)` for the metadata being processed in that call. For an in-memory `concepts` table this filters before the copy into DuckDB, so irrelevant rows are never materialized; for parquet/DuckDB sources it adds a `WHERE concept_id IN (...)` to the view, giving DuckDB's reader an explicit predicate to prune files/row-groups on (e.g. full hive partition pruning if `concepts` happens to be partitioned by `concept_id`) instead of depending on the query planner's runtime join-filter pushdown to prune it implicitly.
- `inst/sql/latest.sql`/`earliest.sql` now pick the record with `arg_max`/`arg_min` aggregation instead of `ROW_NUMBER() OVER (... ORDER BY ...)`, avoiding an unnecessary sort of every candidate match per person/variable/window. Output (including the same-date tie-break on the larger value) is unchanged; `count.sql`/`count_more_than_1.sql`/`range_count.sql`/`all.sql` already used sort-free aggregation and were left as is.
- `anchor_by_variable()`'s chunk loop no longer writes each chunk directly into (or immediately moves it into) `anchor_hive_path` as that chunk finishes. All per-chunk read/write traffic, and any DuckDB out-of-core spilling, now stays off `anchor_hive_path` until the `staging_mode`/`publish`-controlled publish step described above -- this matters when `anchor_hive_path` is slow or network-backed storage, where the previous per-chunk staging hive lived next to `anchor_hive_path` specifically so `move_anchor_partition()`'s single-filesystem rename could succeed; once staging moved to `tempdir()` (a different filesystem from most network mounts) that rename can no longer succeed and every partition move silently degraded to a full copy-and-delete.
- **Behavior change (new default):** with `publish`'s default now `"once"`, a chunk failure leaves `anchor_hive_path` completely untouched instead of keeping whatever chunks had already completed before the failure, which is what `anchor_by_variable()` used to do. Pass `publish = "per_chunk"` to keep the old per-chunk-durable behavior.

### Removed

- **Breaking:** `start_look_back`/`end_look_back` are no longer accepted as alternate names for `start_offset`/`end_offset`. `normalize_metadata()` used to rename whichever of the two you supplied; that rename is gone. `start_offset`/`end_offset` must now be supplied directly under those exact names for every constructor, including `GENERIC`. This frees up `start_look_back`/`end_look_back` to mean the new, unrelated `IN_PRIOR_PREG` lookback-filter columns described above. **Any existing metadata (including BRIDGE-derived `study_variables.csv` files, per `Input_metadata.md`) that supplies offsets as `start_look_back`/ `end_look_back` must rename those columns to `start_offset`/`end_offset` before calling `anchor()`/`anchor_by_variable()`/`anchor_by_selector()`, or those rows will error with "object 'start_offset' not found".**

### Fixed

- `get_anchor_result()`'s "`population` contains multiple rows for the same `person_id` and `T0`" error now names the conflicting column(s) (e.g. `match_id`) instead of leaving the caller to hunt for which column made the key non-unique.
- `anchor()`/`anchor_by_variable()`/`anchor_by_selector()` write their parquet output with `OVERWRITE_OR_IGNORE` instead of `APPEND`. Previously, `anchor()` (and anything writing directly to `anchor_hive_path`) appended a new file on every call, so rerunning it for a `variable_id` already present at `anchor_hive_path` silently duplicated rows -- the docs' workaround was "use a fresh `anchor_hive_path` per run". `OVERWRITE_OR_IGNORE` instead replaces only the `variable_id` partition(s) a call actually produces and leaves every other partition untouched; verified (empirically, against DuckDB 1.5.4) to be precise per-partition across multiple variables and separate connections, and to leave existing data untouched if the query itself fails partway through.
- Clarified `Tutorial_pregnancy_windows.md` and `examples/Pregnancy Window Worked Example.md`: `start_look_back`/`end_look_back` (episode eligibility filter, `IN_PRIOR_PREG` only) and `OUTSIDE_ALL_PREG`'s own `start_offset`/`end_offset` (its anchor-relative search range) are two different mechanisms that happen to both express "an anchor-relative range" -- setting `start_look_back`/`end_look_back` on an `OUTSIDE_ALL_PREG` row has no effect, a case that came up in practice.
- `anchor()`/`anchor_by_variable()`/`anchor_by_selector()` write their parquet output with `OVERWRITE_OR_IGNORE` instead of `APPEND`. Previously, `anchor()` (and anything writing directly to `anchor_hive_path`) appended a new file on every call, so rerunning it for a `variable_id` already present at `anchor_hive_path` silently duplicated rows -- the docs' workaround was "use a fresh `anchor_hive_path` per run". `OVERWRITE_OR_IGNORE` instead replaces only the `variable_id` partition(s) a call actually produces and leaves every other partition untouched; verified (empirically, against DuckDB 1.5.4) to be precise per-partition across multiple variables and separate connections, and to leave existing data untouched if the query itself fails partway through.

### Future Work

## [v1.4]

### Added

- `R/pregnancy_window.R` with four constructore for multi-events entryes.
- `documentation` Folder containing a more procise and extend documentation.

# List of releases
- unreleased: https://github.com/UMC-Utrecht-RWE/anchoR@main
- v1.4 https://github.com/UMC-Utrecht-RWE/anchoR@1.4
