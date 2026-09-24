# Validate Anchoring Inputs

Standardizes the study-variable metadata shape and checks the minimum
structure required by the package.

## Usage

``` r
validate_anchor_inputs(
  population,
  metadata,
  concepts = NULL,
  episodes = NULL,
  anchor_col = "T0"
)
```

## Arguments

- population:

  A data frame containing at least `person_id` and the anchor column
  used for windowing.

- metadata:

  A data frame in the standard study-variable format.

- concepts:

  A concept table as a data frame, a DuckDB file path whose
  `concept_table` contains `person_id`, `concept_id`, and `date`, or
  parquet file location(s).

- episodes:

  Optional data frame with `person_id`, `start_episode`, `end_episode`
  columns, required when `metadata` uses an episode-based constructor.
  See `R/pregnancy_window.R`.

- anchor_col:

  Column to use when metadata does not specify the anchor column.

## Value

Invisibly returns a list with normalized `population`, `metadata`,
`concepts`, and `episodes`.
