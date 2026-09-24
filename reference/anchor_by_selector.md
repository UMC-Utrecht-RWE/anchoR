# Anchor study variables, one selector at a time (deprecated)

**Deprecated:** use
[`anchor`](https://umc-utrecht-rwe.github.io/anchoR/reference/anchor.md)`(..., by = "selector")`
instead. This wrapper forwards to it unchanged.

## Usage

``` r
anchor_by_selector(
  population,
  metadata,
  concepts,
  episodes = NULL,
  anchor_col = "T0",
  anchor_hive_path = NULL,
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

- prepare_con:

  Optional function taking a single argument (the open DBI connection
  selector queries run against).

## Value

Invisibly returns the selector values that were processed.
