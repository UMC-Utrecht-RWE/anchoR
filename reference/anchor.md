# Anchor Study Variables to an Index Date

Applies metadata-driven windowing and selector rules to a concept table,
producing one anchored value and event date per person-variable
combination.

## Usage

``` r
anchor(
  population,
  metadata,
  concepts,
  episodes = NULL,
  anchor_col = "T0",
  anchor_hive_path = NULL,
  by = c("whole", "variable", "selector"),
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

- by:

  How `metadata` is worked through:

  `"whole"`

  :   (default) everything in one pass, one query per selector. See
      Details.

  `"variable"`

  :   `metadata` is worked through in batches of `chunk_size` variables,
      so a single failing variable only ever costs its own batch. See
      Details and `chunk_size`, `staging_dir`, `staging_mode`, `publish`
      below.

  `"selector"`

  :   one pass per distinct `selector` value in `metadata`, with no
      `chunk_size` limit; every variable sharing a selector is always
      processed together. See Details.

  With `by = "variable"`, every batch's results are held somewhere other
  than `anchor_hive_path` until they're ready to publish, either in one
  growing DuckDB table (`staging_mode = "memory"`, the default), or in a
  scratch folder on local disk (`staging_mode = "disk"`, under
  `staging_dir`). Either way, this keeps the repeated reading and
  writing that happens while batches are being computed off
  `anchor_hive_path`, which matters when it points at slow or network
  storage. `"memory"` avoids an extra local write-then-read round trip
  that `"disk"` needs, but holds the whole run's output in memory
  (DuckDB spills to local disk on its own if that gets too big);
  `"disk"` bounds memory use to one batch at a time instead.

  `publish` controls when that held output gets written to
  `anchor_hive_path`. With `publish = "once"` (the default), nothing is
  written until every batch has finished successfully, and if any batch
  fails, nothing is written at all, `anchor_hive_path` is left exactly
  as it was before the call, and the error is raised, so you never end
  up with some variables refreshed and others not. With
  `publish = "per_chunk"`, each batch's results are written as soon as
  that batch finishes, so a later batch's failure doesn't discard
  earlier batches' already-published results.

  Whichever combination is used, publishing only ever replaces the
  `variable_id` partitions that were computed and leaves the rest of
  `anchor_hive_path` untouched, so re-running for just a few variables
  is always safe.

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

Invisibly `NULL` when `by = "whole"`; otherwise, invisibly, the
`variable_id` values (`by = "variable"`) or `selector` values
(`by = "selector"`) that were processed. Writes parquet files to
`anchor_hive_path` as a side effect.
