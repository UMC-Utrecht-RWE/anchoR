# Running anchoR: `anchor()`, `anchor_by_variable()`, `anchor_by_selector()`

`R/anchor.R` holds the three functions that actually *run* the anchoring pipeline and write results to a parquet hive at `anchor_hive_path`. This page is about **how to call them**, which one to reach for, how they relate to each other, and (for `anchor_by_variable()`) the performance knobs meant for large runs or slow output storage.

This page assumes you already have valid `population`/`metadata`/`concepts` tables. For what a window, selector, or constructor actually *means*, see [Tutorial_standard_windows.md](Tutorial_standard_windows.md) (fixed-offset windows) or [Tutorial_pregnancy_windows.md](Tutorial_pregnancy_windows.md) (recurring-event windows), everything here works identically regardless of which `constructor` your metadata uses.

## The three functions at a glance

| function               | `concepts` scans                                                     | on rerun / on failure                                                                                | best for                                                                      |
| ---------------------- | -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `anchor()`             | one query per distinct selector, always                              | replaces only the `variable_id` partitions it computes; existing data untouched on error             | small metadata, or a first pass over everything                               |
| `anchor_by_variable()` | one query per distinct selector, per chunk of `chunk_size` variables | same partition-safety, plus configurable all-or-nothing behavior (see below)                         | large metadata, partial reruns, or `anchor_hive_path` on slow/network storage |
| `anchor_by_selector()` | one query per distinct selector, total (cheapest)                    | same partition-safety as `anchor()`; every variable sharing a selector is always recomputed together | large metadata where you don't need `anchor_by_variable()`'s chunk-size cap   |

All three share the same core arguments:

```r
FUN(
  population,
  metadata,
  concepts,
  anchor_col       = "T0",   # column in `population` used as the index date
  anchor_hive_path = NULL    # where to write the parquet hive (required)
)
```

See [Input_population.md](Input_population.md), [Input_metadata.md](Input_metadata.md), and [Input_concepts.md](Input_concepts.md) for what each of those three tables needs to contain.

## `anchor()`: everything in one pass

The simplest option: builds every window in `metadata`, runs one query per distinct `selector`, and writes the result straight to `anchor_hive_path`.

```r
library(data.table)

population <- data.table(
  person_id = c("1", "2"),
  T0        = as.Date("2024-01-01")
)
metadata <- data.table(
  variable_id  = c("flu_vaccine_recent", "recent_hosp_count"),
  concept_id   = c("FLU_VAX", "HOSP"),
  constructor  = "GENERIC",
  selector     = c("LATEST", "COUNT"),
  start_offset = -365L,
  end_offset   = 0L
)
concepts <- data.table(
  person_id  = c("1", "2"),
  concept_id = c("FLU_VAX", "HOSP"),
  date       = as.Date(c("2023-10-01", "2023-11-01")),
  value      = c("TRUE", "1")
)

hive_path <- tempfile(pattern = "anchor-hive-")
dir.create(hive_path)

anchor(population, metadata, concepts, anchor_hive_path = hive_path)
```

Calling `anchor()` again writes with `OVERWRITE_OR_IGNORE`, not `APPEND`: it replaces only the `variable_id` partitions the current `metadata` computes, and leaves every other partition already at `anchor_hive_path` exactly as it was. So re-running `anchor()` with a subset of `metadata` is always safe, you just recompute *everything in that subset* in one query per selector, with no smaller unit of work than "the whole call."

## `anchor_by_variable()`: batching for large or partial reruns

`anchor_by_variable()` does the same job as `anchor()`, but works through `metadata` in batches ("chunks") of `chunk_size` `variable_id` values at a time (default 20), instead of all at once.

```r
anchor_by_variable(
  population, metadata, concepts,
  anchor_hive_path = hive_path,
  chunk_size = 1   # one variable per chunk, for illustration
)
read_anchor_hive(hive_path)[, .(variable_id, person_id, value, date)]
#>           variable_id person_id  value       date
#> 1: flu_vaccine_recent         1   TRUE 2023-10-01
#> 2:  recent_hosp_count         2      1 2023-11-01
```

The output is identical to `anchor()`'s, `chunk_size` only changes how much work is batched into one selector query at a time, not what gets computed. Two reasons to reach for it instead of `anchor()`:

- **Partial reruns.** Re-running `anchor_by_variable()` with just one variable's metadata only recomputes and republishes that variable's partition, same as `anchor()`, but because processing happens in bounded chunks, a metadata file with hundreds of variables doesn't need one giant query touching all of them just to refresh a handful.
- **Slow or network-backed `anchor_hive_path`.** This is what the rest of this section is about.

### Where results go before they're published: `staging_mode`

Every chunk's results are held *somewhere other than* `anchor_hive_path` until they're ready to publish. `staging_mode` controls where:

| `staging_mode`       | where chunk output is held                                                    | trade-off                                                                                                                                  |
| -------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `"memory"` (default) | one growing DuckDB table, shared across every chunk in the call               | no local write-then-read round trip; the whole run's output lives in memory (DuckDB spills to `staging_dir` on its own if it gets too big) |
| `"disk"`             | a local scratch parquet hive under `staging_dir`, one chunk's worth at a time | bounds memory to one chunk instead of the whole run; costs a local write + a local read-back per chunk                                     |

Either way, none of this touches `anchor_hive_path` while chunks are being computed, which matters when `anchor_hive_path` points at slow or network-backed storage (a shared drive, a client-managed server, cloud-mounted storage, ...), since every read/write against it pays a network round trip. `staging_dir` (default `tempdir()`) is also where DuckDB's own `temp_directory` points, so any out-of-core spilling during the join/windowing stays on local disk too. Only change `staging_dir` if your machine's default temp folder is itself slow.

### When results actually reach `anchor_hive_path`: `publish`

`publish` controls *when* the held results (from either `staging_mode`) get written to `anchor_hive_path`:

| `publish`          | behavior                                                                                                                                                                                              |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `"once"` (default) | nothing is written until every chunk in the call has succeeded. If any chunk fails, **nothing** is published: `anchor_hive_path` is left exactly as it was before the call, and the error propagates. |
| `"per_chunk"`      | each chunk's results are written as soon as that chunk finishes, so a later chunk's failure doesn't undo earlier chunks' already-published results.                                                   |

This is a real behavioral difference, not just a performance one. Same `metadata` (three variables; the third has a broken window constructor and will fail), run once with each `publish` setting:

```r
metadata <- data.table(
  variable_id  = c("flu_vaccine_recent", "recent_hosp_count", "broken_variable"),
  concept_id   = c("FLU_VAX", "HOSP", "DX"),
  constructor  = c("GENERIC", "GENERIC", "NOPE_CONSTRUCTOR"),  # <- doesn't exist
  selector     = c("LATEST", "COUNT", "LATEST"),
  start_offset = -365L,
  end_offset   = 0L
)

# publish = "once" (default): the failure discards everything.
once_path <- tempfile(pattern = "anchor-hive-")
dir.create(once_path)
anchor_by_variable(population, metadata, concepts, anchor_hive_path = once_path, chunk_size = 1)
#> Error: Window function does not exist: nope_constructor_window. ...
list.files(once_path)
#> character(0)

# publish = "per_chunk": earlier successes survive the later failure.
per_chunk_path <- tempfile(pattern = "anchor-hive-")
dir.create(per_chunk_path)
anchor_by_variable(
  population, metadata, concepts,
  anchor_hive_path = per_chunk_path, chunk_size = 1, publish = "per_chunk"
)
#> Error: Window function does not exist: nope_constructor_window. ...
list.files(per_chunk_path)
#> [1] "variable_id=flu_vaccine_recent" "variable_id=recent_hosp_count"
```

Both runs raise the same error. The difference is only in what's left on disk afterward: `"once"` guarantees you never end up with some variables refreshed and others not (useful when downstream code assumes the hive is internally consistent), while `"per_chunk"` guarantees you never lose work that already succeeded (useful for a large run where re-doing everything after a late failure would be wasteful, and `anchor_hive_path` is fast enough that the extra writes don't matter).

### Picking `staging_mode` / `publish`

- **Default (`memory` + `once`)** is the right starting point for most runs, especially when `anchor_hive_path` is slow or network-backed: minimal traffic against it, and a clean, unambiguous state if something goes wrong.
- Switch to **`publish = "per_chunk"`** if a run is large enough that losing all progress to one bad variable partway through is more costly than the risk of a partially-updated hive.
- Switch to **`staging_mode = "disk"`** if a single run's total output is large enough that you'd rather bound memory per chunk than let DuckDB manage it (at the cost of the local write/read round trip per chunk).

## `anchor_by_selector()`: cheapest in `concepts` scans, no chunk cap

`anchor_by_selector()` groups `metadata` by `selector` and calls `anchor()` once per distinct selector value, so every variable sharing a selector is always covered by one query, however many variables that is, there's no `chunk_size` splitting a selector's variables across more than one query the way `anchor_by_variable()` can.

```r
metadata <- data.table(
  variable_id  = c("flu_vaccine_recent", "flu_vaccine_ever", "recent_hosp_count"),
  concept_id   = c("FLU_VAX", "FLU_VAX", "HOSP"),
  constructor  = "GENERIC",
  selector     = c("LATEST", "EARLIEST", "COUNT"),
  start_offset = c(-365L, -3650L, -365L),
  end_offset   = 0L
)
concepts <- data.table(
  person_id  = c("1", "1", "2"),
  concept_id = c("FLU_VAX", "FLU_VAX", "HOSP"),
  date       = as.Date(c("2023-10-01", "2020-01-01", "2023-11-01")),
  value      = c("TRUE", "TRUE", "1")
)

hive_path <- tempfile(pattern = "anchor-hive-")
dir.create(hive_path)

anchor_by_selector(population, metadata, concepts, anchor_hive_path = hive_path)
read_anchor_hive(hive_path)[, .(variable_id, person_id, value, date)][order(variable_id, person_id)]
#>           variable_id person_id  value       date
#> 1:   flu_vaccine_ever         1   TRUE 2020-01-01
#> 2: flu_vaccine_recent         1   TRUE 2023-10-01
#> 3:  recent_hosp_count         2      1 2023-11-01
```

Here, `LATEST` and `EARLIEST` (two variables, `flu_vaccine_recent` and `flu_vaccine_ever`) each get their own query, and `COUNT` gets one for `recent_hosp_count`, three queries total, the same as `anchor_by_variable()` with `chunk_size` large enough to fit every selector's variables together, but reached without having to pick a `chunk_size` at all. The trade-off is the one `anchor_by_variable()`'s `chunk_size` exists to avoid: if one selector covers hundreds of variables, they're always recomputed as a single unit, with no smaller batch to bound the work.

## Quick decision guide

| situation                                                                | use                                                    |
| ------------------------------------------------------------------------ | ------------------------------------------------------ |
| Small `metadata`, first pass over everything                             | `anchor()`                                             |
| Large `metadata`; expect to rerun individual variables later             | `anchor_by_variable()` (defaults are fine)             |
| `anchor_hive_path` is slow / network / client-managed storage            | `anchor_by_variable()`, keep `staging_mode = "memory"` |
| A large run where losing all progress to one late failure is too costly  | `anchor_by_variable(..., publish = "per_chunk")`       |
| Large `metadata`, but you don't want to reason about `chunk_size` at all | `anchor_by_selector()`                                 |

## Reading the result

None of the three functions return the anchored data directly, they write parquet to `anchor_hive_path`. Use `get_anchor_result()` to read it back in long or wide shape (see [Output_D4_StudyVariablesAnchored.md](Output_D4_StudyVariablesAnchored.md) and the worked examples in [Tutorial_standard_windows.md](Tutorial_standard_windows.md)); `read_anchor_hive()`, used for the small examples above, is a plain DuckDB read of the hive with no reshaping, defined alongside the test suite's fixtures.
