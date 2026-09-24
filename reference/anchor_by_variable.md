# Anchor study variables in batches (deprecated)

**Deprecated:** use
[`anchor`](https://umc-utrecht-rwe.github.io/anchoR/reference/anchor.md)`(..., by = "variable")`
instead. This wrapper forwards to it unchanged.

## Usage

``` r
anchor_by_variable(
  population,
  metadata,
  concepts,
  episodes = NULL,
  anchor_col = "T0",
  anchor_hive_path = NULL,
  chunk_size = 20L,
  staging_dir = NULL,
  staging_mode = c("memory", "disk"),
  publish = c("once", "per_chunk"),
  prepare_con = NULL
)
```

## Arguments

- population:

  A data frame containing the study population. Must include a
  `person_id` column and the anchor date column specified by
  `anchor_col`.

- metadata:

  A data frame describing the variables to anchor. Must contain the
  columns required by
  [`validate_anchor_inputs()`](https://umc-utrecht-rwe.github.io/anchoR/reference/validate_anchor_inputs.md).

- concepts:

  A concept table as a data frame, a DuckDB file path whose
  `concept_table` contains `person_id`, `concept_id`, and `date`, or
  parquet file location(s).

- episodes:

  Optional data frame with `person_id`, `start_episode`, `end_episode`
  columns. Required when `metadata` uses an episode-based constructor
  (`in_current_pregnancy`, `in_prior_pregnancy`, `in_current_and_prior`,
  `outside_all_pregnancy`); see `R/pregnancy_window.R`.

- anchor_col:

  Character. Name of the column in `population` to use as the index date
  when metadata does not specify an anchor column. Defaults to `"T0"`.

- anchor_hive_path:

  Character. Path to an existing (or creatable) directory where selector
  query results are written as a partitioned parquet hive. Must not be
  `NULL`.

- chunk_size:

  Only used when `by = "variable"`. How many variables to process per
  batch. Bigger batches mean fewer (and cheaper) scans of `concepts`,
  but (with `publish = "once"`) also throw away more work if a batch
  fails partway through, since nothing is saved until the whole call
  succeeds. Use `1` to process one variable at a time. Variables are
  sorted by selector before being split into batches, so each batch
  groups same-selector variables together as much as `chunk_size`
  allows.

- staging_dir:

  Only used when `by = "variable"`. Folder to use for DuckDB's own
  temporary files, and (only when `staging_mode = "disk"`) for the local
  scratch hive every batch writes into. Defaults to
  [`tempdir()`](https://rdrr.io/r/base/tempfile.html). Only change this
  if your machine's default temporary folder is itself slow or on a
  network drive.

- staging_mode:

  Only used when `by = "variable"`. Where each batch's results are held
  before being published: `"memory"` (default) accumulates them in one
  DuckDB table; `"disk"` writes them to a local scratch parquet hive
  instead. See Details.

- publish:

  Only used when `by = "variable"`. When to write results to
  `anchor_hive_path`: `"once"` (default) after the whole call succeeds,
  all together; `"per_chunk"` after each batch, incrementally. See
  Details.

- prepare_con:

  Optional function taking a single argument (the open DBI connection
  selector queries run against).

## Value

Invisibly returns the variable ids that were processed.
