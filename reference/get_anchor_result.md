# Retrieve and Reshape Anchored Variable Results

Reads parquet files from an anchor hive directory via DuckDB, filters to
the requested variables, and pivots the long-format result into a wide
data.table with one column per variable for both value and date.

## Usage

``` r
get_anchor_result(
  metadata,
  anchor_hive_path = NULL,
  population = NULL,
  result_shape = "wide",
  impute_missing = FALSE,
  cast_window = FALSE,
  only_date = FALSE,
  required_population_cols = c("person_id", "T0")
)
```

## Arguments

- metadata:

  A data frame describing the study variables. Must contain at least a
  variable_id column.

- anchor_hive_path:

  A character string giving the path to the directory that contains the
  anchored parquet hive. Must be a valid existing directory.

- population:

  Optional data frame with population rows to be represented in wide
  output. When provided, it must contain person_id and T0 columns.
  Additional population columns are carried into the wide result.
  Multiple rows may legitimately share the same person_id/T0 key while
  disagreeing on other columns; every such row is kept. The anchored
  results are left-joined onto the full population, so result_shape =
  "wide" output always has one row per population row (times the number
  of distinct window_name values when cast_window = FALSE).

- result_shape:

  A character string specifying the desired shape of the output. Must be
  either "wide" or "long".

- impute_missing:

  Logical; when TRUE and result_shape = "wide", missing
  value\_\<variable_id\> cells are imputed using metadata columns
  is_expected_missing and variable_type via imputing_missing().

- cast_window:

  Logical; controls wide reshaping formula. When `FALSE` (default),
  results are cast by `person_id + T0 + window_name ~ variable_id`. When
  `TRUE`, results are cast by
  `person_id + T0 ~ window_name + variable_id`.

- only_date:

  Logical; when `TRUE` and result_shape = "wide", only date columns are
  cast (no `value_<...>` columns). When `FALSE`, both value and date
  columns are cast.

- required_population_cols:

  Character vector of column names that must be present in the
  population data frame when provided. Defaults to
  `c("person_id", "T0")`.

## Value

A data.table with anchored variable results in the specified shape.
