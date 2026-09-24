# Completing and imputing wide results

``` r

library(anchoR)
library(data.table)
```

Imputation occurs during wide retrieval, after population keys and
requested result columns have been completed. It does not modify
persisted parquet or long output.

``` r

population <- data.table(
  person_id = c("1", "2"),
  T0 = as.Date(c("2024-01-01", "2024-01-01")),
  group = c("EXPOSED", "CONTROL")
)
metadata <- data.table(
  variable_id = c("diagnosis", "category", "expected_unknown"),
  concept_id = c("DIAGNOSIS", "CATEGORY", "UNKNOWN"),
  constructor = "GENERIC",
  selector = "LATEST",
  window_name = "lookback",
  start_offset = -365L,
  end_offset = 0L,
  is_expected_missing = c(FALSE, FALSE, TRUE),
  variable_type = c("BOOL", "CAT", "BOOL")
)
concepts <- data.table(
  person_id = "1",
  concept_id = "DIAGNOSIS",
  date = as.Date("2023-10-01"),
  value = "TRUE"
)
hive <- tempfile("imputation-hive-")
anchor(population, metadata, concepts, anchor_hive_path = hive)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/RtmpKyF26O/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ## NULL

Without imputation, completed cells are `NA`.

``` r

get_anchor_result(
  metadata, hive, population = population,
  result_shape = "wide"
)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/RtmpKyF26O/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ##    person_id         T0 window_name value_diagnosis date_diagnosis
    ##       <char>     <Date>      <char>          <char>         <Date>
    ## 1:         1 2024-01-01    lookback            TRUE     2023-10-01
    ## 2:         2 2024-01-01    lookback            <NA>           <NA>
    ##    date_category date_expected_unknown value_category value_expected_unknown
    ##           <Date>                <Date>         <char>                 <char>
    ## 1:          <NA>                  <NA>           <NA>                   <NA>
    ## 2:          <NA>                  <NA>           <NA>                   <NA>
    ##      group
    ##     <char>
    ## 1: EXPOSED
    ## 2: CONTROL

``` r

imputed <- get_anchor_result(
  metadata, hive, population = population,
  result_shape = "wide",
  impute_missing = TRUE
)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/RtmpKyF26O/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

``` r

imputed
```

    ##    person_id         T0 window_name value_diagnosis date_diagnosis
    ##       <char>     <Date>      <char>          <lgcl>         <Date>
    ## 1:         1 2024-01-01    lookback            TRUE     2023-10-01
    ## 2:         2 2024-01-01    lookback           FALSE           <NA>
    ##    date_category date_expected_unknown value_category value_expected_unknown
    ##           <Date>                <Date>         <char>                 <char>
    ## 1:          <NA>                  <NA>              0                   <NA>
    ## 2:          <NA>                  <NA>              0                   <NA>
    ##      group
    ##     <char>
    ## 1: EXPOSED
    ## 2: CONTROL

Rules are intentionally narrow:

- `BOOL`, `BOOLEAN`, `LOGICAL`, and `TF` become logical and missing
  cells become `FALSE`.
- `CAT` and `FACTOR` missing cells become `0`.
- `is_expected_missing = TRUE` prevents imputation for that variable.
- Date columns and unsupported variable types remain missing.
- If required imputation metadata is partly supplied, anchoR warns and
  skips imputation.

These defaults encode domain assumptions, not generic missing-data
methodology. Use them only when a missing concept record means false or
the categorical zero level, not just “unknown.” Otherwise keep `NA` and
handle missingness downstream.

Imputation currently targets columns named `value_<variable_id>`. When
`cast_window = TRUE` produces `value_<window_name>_<variable_id>`, those
columns are not matched by the current imputation helper; impute them
downstream or use the default non-window-cast shape.
