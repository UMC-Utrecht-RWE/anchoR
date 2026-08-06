# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased]
## [v1.5]

### Removed (Breaking)
- The entire old pregnancy/episode API is gone: the `IN_PRIOR_PREG`, `SINCE_START_CURRENT_PREG`, and `ANYTIME_CURRENT_PREG` constructors, the population `event_col` list-column a caller had to pre-nest themselves, and the `end_cap_offset`/`start_look_back`/`end_look_back` metadata columns. None of these names resolve to anything anymore. Existing episode metadata must be rewritten against the new constructors/columns below before calling `anchor()`; there is no compatibility alias.

### Added
- New `episodes` input table (`person_id`, `start_episode`, `end_episode`), passed as its own argument to `define_window()`/`anchor()`/`anchor_by_variable()`/`anchor_by_selector()`. anchoR now nests it onto `population` internally (`nest_episodes_onto_population()`); the caller no longer builds or manages the nested list-column by hand.
- Four episode-based constructors replacing the removed ones: `in_current_pregnancy`, `in_prior_pregnancy`, `in_current_and_prior` (new the union of the other two), `outside_all_pregnancy`. All four share one engine, `pregnancy_window_engine()`.
- `classify_episodes()`: labels each of a person's episodes `"current"`/`"prior"`/`"future"` relative to the anchor date. Prior/future are relative to the current episode's own bounds when one exists; when there is no current episode, they fall back to being relative to the anchor date directly instead.
- `episode_windows()`: the new border-offset formula for turning a selected episode into one or more windows. Six new metadata columns replace everything the removed columns used to do: `anchor_start_offset`/`anchor_end_offset` (see `clip_to_anchor_bounds()` below) and two offset pairs, `before_start_episode_offset`/`after_start_episode_offset` and `before_end_episode_offset`/`after_end_episode_offset`, each relative to the selected episode's own start/end. `before_start_episode_offset` and `after_end_episode_offset` are the "outer" sides (pointing away from the episode); `after_start_episode_offset` and `before_end_episode_offset` are the "inner" sides (pointing into it). A pair with both sides set is always its own self-contained region, `[edge + before_offset, edge + after_offset]` (an inverted pair, `before_*_offset` later than `after_*_offset`, is an error); otherwise, if either pair's outer side is set alone, the whole computation becomes one shared window, with the other pair contributing whichever single value it has (or the unshifted edge, if empty) as a plain point; otherwise any pair with only its inner side set forms its own region instead (missing side defaulting to `0`), and a pair with nothing set contributes nothing. Neither pair set at all falls back to the episode's own unshifted span. See `documentation/definitions/Episode-Based Window Engine.md` for the complete rule and worked examples.
- `clip_to_anchor_bounds()`: `anchor_start_offset`/`anchor_end_offset` are a hard boundary, `[anchor_start_col + anchor_start_offset, anchor_end_col + anchor_end_offset]`, applied to **every** episode-based constructor's output, not just `outside_all_pregnancy`'s search range. Each side clips independently and only when not `NA`: a set `anchor_start_offset` raises a window's start up to the boundary's lower edge, a set `anchor_end_offset` lowers its end down to the boundary's upper edge. A window entirely outside the boundary comes out invalid, the same as any other empty window, rather than erroring. For `outside_all_pregnancy` this clip is a no-op (its search range already is that boundary); for the other three constructors it's a new, independent mechanism on top of the border-offset formula above e.g. "no episode-based window may extend outside `[T0 - 1, T0 + 1]`," regardless of what the border offsets would otherwise produce.
- `make_selector()`: define a custom `selector` (a SQL `SELECT` statement) from your own script, resolved by naming convention (`<NAME>` metadata value → `<name>_selector` object) exactly the way `make_constructor()` already resolved custom constructors. Supporting internals: `selector_object_name()`, `selector_is_resolvable()`, `resolve_selector_sql()`, `selector_sql_exists()`, `read_builtin_selector_sql()`. `read_selector_sql_query()`/`run_selector_query()`/`run_selector_queries()` gain a `selector_env` argument (default `globalenv()`) so a selector name can resolve to either a bundled `inst/sql/*.sql` template or a caller-defined `make_selector()` object.
- `vignettes/custom-selectors.Rmd`: worked example for `make_selector()`, alongside the existing `custom-constructors` vignette.
- `documentation/Quickstart.md`: a zero-jargon quickstart assuming no prior familiarity with R or the epidemiology vocabulary anchoR uses (T0, window, concept, selector, constructor), linked from both this README and `documentation/README.md`.
- `CONTRIBUTING.md`: dev setup, the local inner loop, what each of the four CI workflows (`testthat`, `r_cmd_check`, `code_quality`, `test_coverage`) actually checks, and how to add a built-in constructor or selector to the package itself.
- `documentation/definitions/Episodes.md`, `IN_CURRENT_PREG.md`, `IN_CURRENT_AND_PRIOR.md`: new definitions pages for the new table and constructors.

### Changed
- Every episode-window documentation page (`Tutorial_pregnancy_windows.md`, `examples/Pregnancy_window_worked_example.md`, `vignettes/episode-windows.Rmd`, and the four constructor definitions pages) rewritten end-to-end against the new engine, with every worked-example number re-verified by actually running it through `define_window()`. `documentation/definitions/Episode-Based Window Engine.md` is now the single canonical description of the border-offset formula; the other pages summarize and link back to it instead of each re-describing it, so it no longer drifts out of sync across pages the way the old formula's documentation had.
- `Constructor.md`, `Metadata.md`, `Population.md`, `Input_population.md`, `Input_metadata.md` updated for the new constructor names and offset columns; `Constructor.md`'s links to the two removed constructor pages fixed.
- `tests/testthat/helper-fixtures-preg.R`'s `pregnancy_metadata_simple()`/`pregnancy_metadata_complex()` illustrative fixtures re-verified against both the `anchor_start_offset`/`anchor_end_offset` clip and the final `episode_windows()` outer/inner rule above; their comments now note where a fixture's own `anchor_start_offset = anchor_end_offset = 0` (previously inert, since only `outside_all_pregnancy` read them) now clips a window down to nothing. `complex_current`'s `before_start_episode_offset`/`before_end_episode_offset` values were also corrected from `30`/`60` to `-30`/`-60`: under the old (pre-region-pairs) engine a lone offset's sign never mattered, so this had been masking an inverted-pair mistake that the new validation now catches. Left otherwise as-is to illustrate real engine behavior rather than changed, since these fixtures aren't asserted against in any test.

### Removed
- `documentation/definitions/End Cap Offset.md`, `SINCE_START_CURRENT_PREG.md`, `ANYTIME_CURRENT_PREG.md`: deleted along with the mechanism/constructors they described.

### Fixed
- `looks_like_glob()` (used by `normalize_parquet_sources()` to decide whether a nonexistent-looking path might still be a glob pattern DuckDB can resolve) used a bracket-expression regex (`[\\*\\?\\[]`) written as if `\\*`/`\\?`/`\\[` were escaped literals inside the class; a bracket expression doesn't treat backslash as an escape character, so it actually matched a literal backslash instead, making it return `TRUE` for *any* Windows-style path (backslash path separators) whether or not it contained a real glob character. On Windows this silently let a nonexistent parquet path through instead of raising anchoR's "Concept parquet source does not exist" error. Rewritten as `[*?[]`, which matches only actual `*`/`?`/`[` glob characters.

## [v1.4.5]
### Fixed
- `R/duckdb_helpers.R::load_concepts_table()` no longer errors when called a second time on the same DuckDB connection. It now checks PRAGMA `database_list` and skips the ATTACH if concepts_db is already attached, instead of unconditionally re-attaching (which DuckDB rejects).
- `R/anchor.R::anchor_by_selector()` and `load_concepts_table()` moved from once-before-the-loop (filtering on all metadata's concept_ids) to inside the per-selector loop (filtering on just that selector's concept_ids), shrinking the filtered set per selector. This is what made above fix necessary, since the table now gets loaded multiple times per connection.
- `inst/sql/range_count.sql`'s match-counting query switched from `INNER JOIN + COUNT(*)` to `LEFT JOIN + COUNT(c.person_id)`, so a person with zero matching concepts rows in the window gets a true raw_count = 0 instead of being dropped entirely (which was pushing them into a generic "missing" fallback with the wrong bucket value).

## Added
- `R/get_anchor_result.R`: boolean-variable imputation restored in `imputing_missing()` the missing boolean values are now stamped `FALSE` (this logic had been lost in an earlier PR) and the column is coerced back to logical.

## [v1.4.4]

### Removed
- The original `RANGE_COUNT` (filtered raw `concept.value` against metadata `range_min`/`range_max` bounds) has been removed because not confirm with requests and specifications. All connected functionalities are also removed.

### Added
- `RANGE_COUNT` reintroduced with new, unrelated semantics (developed under the working names `MASK_COUNT`/`COUNT_CATEGORY`/`COUNT_RANGE` before settling back on this name) in `range_count.sql`: counts matching `concepts` rows per person/window like `COUNT` does, then looks up that count in a user-supplied `concept_ranges` table and returns a bucketed `new_value` instead of the raw count. Note this reuses the exact name of the selector removed above; the two are unrelated, and old metadata still using the pre-removal `RANGE_COUNT` bounds-filter behavior will now silently run under this new logic instead of erroring.
- `anchor()`, `anchor_by_variable()`, and `anchor_by_selector()` gain a `prepare_con` argument: an optional function called once, on the same DuckDB connection, right after `concepts` is loaded and before any selector query runs. Lets a caller load extra tables a selector needs (e.g. the new `RANGE_COUNT`'s `concept_ranges`) with plain `DBI` calls, without the package needing to know about them; connection lifecycle (opening/closing) stays owned by the package.
- Update `get_anchor_result` by adding imputation of boolean variables. When value is missing, then `value = FALS`E. We lost this logic on previous PR

### Fixed
- `range_count.sql` (the new selector described above) no longer wraps its bucketing `CASE` inside `COUNT(...)` (which just counted rows, identical to `COUNT(*)`, since every branch was non-`NULL`) and no longer references `w.value`, a column that doesn't exist on `population_windows`. It's now a two-step query: count matches, then join the count against `concept_ranges`. Also casts the looked-up bucket value through `BIGINT` before `VARCHAR` so it renders as `"2"` instead of `"2.0"` when `concept_ranges$new_value` is a double (the common case when read from a CSV).
- `range_count.sql` counted matches via `INNER JOIN concepts` + `COUNT(*)`, so a person with zero matching `concepts` rows in the window produced no row at all instead of a count of `0` making the bucket whose `lower_range`/`upper_range` covers 0 structurally unreachable, and pushing those subjects into `get_anchor_result(impute_missing = TRUE)`'s generic "missing" fallback (which stamps categorical values with a literal `0`, not the correct bucket `new_value`). Downstream, this showed up as a real category vanishing from `RANGE_COUNT`-derived table rows while an unlabeled `0` appeared instead. Switched to `LEFT JOIN` + `COUNT(c.person_id)` so zero-match subjects get a true `raw_count = 0` row and are bucketed against `concept_ranges` like everyone else.
- `vignettes/selector-cookbook.Rmd` excludes the new `RANGE_COUNT` from its "every bundled selector" demo (it needs a `concept_ranges` table the vignette's single-`concepts`-table example doesn't provide) and no longer references the removed (original) `RANGE_COUNT` selector.
- `load_concepts_table()` is now inside the per selector loop, so the filtering is much smaller again (each selector only filters on its own concept_ids). The connection itself is still opened just once, that part didn't change.


## [v1.4.3]

### Fixed

- `get_anchor_result(result_shape = "wide")` no longer collapses `population` rows that share the same `person_id`/`T0` key but differ on other columns. Every such row used to be silently dropped down to one (with a warning) because the anchored results were joined onto the deduplicated key set; the join direction is now reversed so the full `population` drives the output, and the anchored results are left-joined onto it instead.
- `add_parquet_export()` now takes in input the `selector` name and uses it as name for for the files within in the partion name. Prior to that if a `variable_id` had two selectors connected to it, it would overwrite the results.
- `anchor_by_selector()` had a bug in which it'd overwrite a partition if a second selector is present in the metadata. Now, `anchor_by_selector()` goes directly to `anchor_impl()` skipping `anchor()`. It creates its own connection and deletes folder if it finds them. `anchor_impl(`) has now `clear_existing_partitions` to still ensure it delete folders in other functions.
- Validation and improved test coverage for RANGE_COUNT rows in metadata, ensuring that missing `range_min` or `range_max` values generate warnings rather than failing silently. Also updated test fixtures and expectations to include these new columns.

## [v1.4.2]

### Added

- `clear_anchor_partitions` to avoid the duplications of row while using `anchor()` and `anchor_by_selector()` by `OVERWRITE_OR_IGNORE`.
- File `define_selector.R` that contains the functionality to let the user insert their own selector DuckDB/SQL queries. The main fuction responsable for this is `make_selector()`, that mirrors `make_constructor()` original idea of a factory function as vehicle for user inserted selectors.

### Removed

- `anchor_row_id` no longer appears in the parquet hive written by `anchor()`/`anchor_by_variable()`/`anchor_by_selector()`. It was always a synthetic id scoped to a single internal query call (not comparable across different `chunk_size` values or between `anchor_by_selector()`/`anchor_by_variable()`), so reading it from the raw hive and using it to join/diff two runs could silently misalign rows despite matching content. It remains an internal join key inside the selector SQL templates and `population_windows`; `get_anchor_result()` now orders its output by `variable_id, person_id, T0, window_name` instead.

## [v1.4.1.1]

### Changed
- `duplicate_rows` in `R/get_anchor_result.R` had an error message now replaced with a wanring message. The decision is in line with what done previously in the same file. For now we keep this results and we will the decision if these are to be kept or not to a futere discussion with analysis team.

## [v1.4.1]

### Added

- `IN_PRIOR_PREG` metadata can now set optional `start_look_back`/`end_look_back` columns (NA by default, so existing metadata is unaffected) to restrict which prior pregnancies are eligible at all: only episodes overlapping the anchor-relative range `[T0 + start_look_back, T0 + end_look_back]` are considered (a selection filter on the episode, same overlap rule as `OUTSIDE_ALL_PREG`'s search range). A prior pregnancy entirely outside that range is dropped from consideration before any window is built; one that overlaps is kept and its window is still computed from `start_offset`/`end_offset` exactly as before, unclipped. Kept as separate columns from `start_offset`/`end_offset` (which already shift the episode's own start/end and can be positive) rather than reusing them, since a positive `start_offset` would otherwise push the anchor-relative bound past `T0`, which a by-definition-prior episode could never satisfy.
- `anchor_by_selector()`: runs `anchor()` once per unique `selector` value in `metadata`, so a single query covers every variable sharing that selector regardless of `chunk_size`. Cheaper in `concepts` scans than `anchor_by_variable()`; every `variable_id` it touches is safely replaced (see the `OVERWRITE_OR_IGNORE` fix below), it just doesn't bound the blast radius per query the way `anchor_by_variable()`'s `chunk_size` does every variable sharing a selector is recomputed together.
- `anchor_by_variable()` gains `staging_mode` (`"memory"`, default, or `"disk"`) and `publish` (`"once"`, default, or `"per_chunk"`) arguments controlling how chunk output is held before it reaches `anchor_hive_path`, and when. `staging_mode = "memory"` accumulates every chunk's rows into one DuckDB table (via new internal `add_table_accumulation()`), which DuckDB spills to `staging_dir` on its own if it outgrows RAM, then writes to `anchor_hive_path` with a single `COPY`; `staging_mode = "disk"` keeps the previous behavior of staging each chunk to a local parquet hive under `staging_dir` before moving it into place. `publish = "once"` (default) only writes to `anchor_hive_path` after every chunk in the call has succeeded, discarding everything and leaving `anchor_hive_path` completely unchanged if any chunk fails; `publish = "per_chunk"` writes (and keeps) each chunk's results as soon as that chunk finishes, even if a later chunk in the same call fails.
- `anchor_by_variable()` gains a `staging_dir` argument (default `tempdir()`) for the local scratch space used for DuckDB's `temp_directory` and, in `staging_mode = "disk"`, the local staging hive, lets both be pointed at fast local disk independently of `anchor_hive_path`.

### Changed

- `anchor_by_variable()` now opens one DuckDB connection and loads `concepts` once for the whole call instead of once per `variable_id`, and reuses the already-validated `population` table across variables instead of re-validating/re-copying it each time. Cuts redundant concepts scans and connection overhead for metadata with many standard-window variables.
- `anchor_by_variable()` now processes `variable_id`s in chunks (new `chunk_size` argument, default 20) instead of strictly one at a time, so a single selector query can cover several variables' `concepts` join at once. Each chunk still stages to a temporary hive and swaps in one `variable_id` partition at a time, so partial reruns remain isolated to the requested variables. Pass `chunk_size = 1` for the previous behavior. Variables are also now ordered by selector before being sliced into chunks, so a chunk is as selector-homogeneous as `chunk_size` allows instead of following raw metadata row order.
- `load_concepts_table()` now accepts an optional `concept_ids` filter, applied by `anchor()`/`anchor_by_variable()` as `unique(metadata$concept_id)` for the metadata being processed in that call. For an in-memory `concepts` table this filters before the copy into DuckDB, so irrelevant rows are never materialized; for parquet/DuckDB sources it adds a `WHERE concept_id IN (...)` to the view, giving DuckDB's reader an explicit predicate to prune files/row-groups on (e.g. full hive partition pruning if `concepts` happens to be partitioned by `concept_id`) instead of depending on the query planner's runtime join-filter pushdown to prune it implicitly.
- `inst/sql/latest.sql`/`earliest.sql` now pick the record with `arg_max`/`arg_min` aggregation instead of `ROW_NUMBER() OVER (... ORDER BY ...)`, avoiding an unnecessary sort of every candidate match per person/variable/window. Output (including the same-date tie-break on the larger value) is unchanged; `count.sql`/`count_more_than_1.sql`/`range_count.sql`/`all.sql` already used sort-free aggregation and were left as is.
- `anchor_by_variable()`'s chunk loop no longer writes each chunk directly into (or immediately moves it into) `anchor_hive_path` as that chunk finishes. All per-chunk read/write traffic, and any DuckDB out-of-core spilling, now stays off `anchor_hive_path` until the `staging_mode`/`publish`-controlled publish step described above, this matters when `anchor_hive_path` is slow or network-backed storage, where the previous per-chunk staging hive lived next to `anchor_hive_path` specifically so `move_anchor_partition()`'s single-filesystem rename could succeed; once staging moved to `tempdir()` (a different filesystem from most network mounts) that rename can no longer succeed and every partition move silently degraded to a full copy-and-delete.
- **Behavior change (new default):** with `publish`'s default now `"once"`, a chunk failure leaves `anchor_hive_path` completely untouched instead of keeping whatever chunks had already completed before the failure, which is what `anchor_by_variable()` used to do. Pass `publish = "per_chunk"` to keep the old per-chunk-durable behavior.

### Removed

- **Breaking:** `start_look_back`/`end_look_back` are no longer accepted as alternate names for `start_offset`/`end_offset`. `normalize_metadata()` used to rename whichever of the two you supplied; that rename is gone. `start_offset`/`end_offset` must now be supplied directly under those exact names for every constructor, including `GENERIC`. This frees up `start_look_back`/`end_look_back` to mean the new, unrelated `IN_PRIOR_PREG` lookback-filter columns described above. **Any existing metadata (including BRIDGE-derived `study_variables.csv` files, per `Input_metadata.md`) that supplies offsets as `start_look_back`/ `end_look_back` must rename those columns to `start_offset`/`end_offset` before calling `anchor()`/`anchor_by_variable()`/`anchor_by_selector()`, or those rows will error with "object 'start_offset' not found".**

### Fixed

- `get_anchor_result()`'s "`population` contains multiple rows for the same `person_id` and `T0`" error now names the conflicting column(s) (e.g. `match_id`) instead of leaving the caller to hunt for which column made the key non-unique.
- Clarified `Tutorial_pregnancy_windows.md` and `examples/Pregnancy Window Worked Example.md`: `start_look_back`/`end_look_back` (episode eligibility filter, `IN_PRIOR_PREG` only) and `OUTSIDE_ALL_PREG`'s own `start_offset`/`end_offset` (its anchor-relative search range) are two different mechanisms that happen to both express "an anchor-relative range", setting `start_look_back`/`end_look_back` on an `OUTSIDE_ALL_PREG` row has no effect, a case that came up in practice.
- `anchor()`/`anchor_by_variable()`/`anchor_by_selector()` write their parquet output with `OVERWRITE_OR_IGNORE` instead of `APPEND`. Previously, `anchor()` (and anything writing directly to `anchor_hive_path`) appended a new file on every call. `OVERWRITE_OR_IGNORE` instead replaces only the `variable_id` partition(s) a call actually produces and leaves every other partition untouched; verified (empirically, against DuckDB 1.5.4) to be precise per-partition across multiple variables and separate connections, and to leave existing data untouched if the query itself fails partway through.

### Future Work

## [v1.4]

### Added

- `R/pregnancy_window.R` with four constructore for multi-events entryes.
- `documentation` Folder containing a more procise and extend documentation.

# List of releases
- unreleased: https://github.com/UMC-Utrecht-RWE/anchoR@main
- v1.5 https://github.com/UMC-Utrecht-RWE/anchoR/releases/tag/v1.5
- v1.4.5 https://github.com/UMC-Utrecht-RWE/anchoR/releases/tag/v1.4.5
- v1.4.4 https://github.com/UMC-Utrecht-RWE/anchoR/releases/tag/v1.4.4
- v1.4.3 https://github.com/UMC-Utrecht-RWE/anchoR/releases/tag/v1.4.3
- v1.4.2 https://github.com/UMC-Utrecht-RWE/anchoR/releases/tag/v1.4.2
- v1.4.1.1 https://github.com/UMC-Utrecht-RWE/anchoR/releases/tag/v1.4.1.1
- v1.4.1 https://github.com/UMC-Utrecht-RWE/anchoR/releases/tag/v1.4.1
- v1.4 https://github.com/UMC-Utrecht-RWE/anchoR/releases/tag/v1.4
