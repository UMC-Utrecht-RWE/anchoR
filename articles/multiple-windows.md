# Designing multiple windows

``` r

library(anchoR)
library(data.table)
```

A variable can have several clinically meaningful windows. Repeat
`variable_id`, assign a unique `window_name`, and choose offsets and
selectors independently.

``` r

population <- data.table(
  person_id = c("1", "2"),
  T0 = as.Date(c("2024-01-01", "2024-01-01"))
)
metadata <- data.table(
  variable_id = "outcome",
  concept_id = "OUTCOME",
  constructor = "GENERIC",
  selector = "EARLIEST",
  window_name = c("lookback", "index", "risk", "control"),
  start_offset = c(-365L, 0L, 1L, 43L),
  end_offset = c(-1L, 0L, 42L, 84L)
)
concepts <- data.table(
  person_id = c("1", "1", "1", "1"),
  concept_id = "OUTCOME",
  date = as.Date(c("2023-12-20", "2024-01-01", "2024-01-20", "2024-03-01")),
  value = "TRUE"
)
```

Inspecting windows makes gaps and boundary choices explicit.

``` r

define_window(population, metadata)[
  person_id == "1",
  .(window_name, window_start, window_end)
]
```

    ##    window_name window_start window_end
    ##         <char>       <Date>     <Date>
    ## 1:    lookback   2023-01-01 2023-12-31
    ## 2:       index   2024-01-01 2024-01-01
    ## 3:        risk   2024-01-02 2024-02-12
    ## 4:     control   2024-02-13 2024-03-25

``` r

hive <- tempfile("window-hive-")
anchor(population, metadata, concepts, anchor_hive_path = hive)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmp5zXnsw/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ## NULL

``` r

get_anchor_result(metadata, hive, result_shape = "long")
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmp5zXnsw/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ##    person_id         T0 variable_id window_name       date  value
    ##       <char>     <Date>      <char>      <char>     <Date> <char>
    ## 1:         1 2024-01-01     outcome     control 2024-03-01   TRUE
    ## 2:         1 2024-01-01     outcome       index 2024-01-01   TRUE
    ## 3:         1 2024-01-01     outcome    lookback 2023-12-20   TRUE
    ## 4:         1 2024-01-01     outcome        risk 2024-01-20   TRUE

``` r

get_anchor_result(
  metadata, hive, population = population,
  result_shape = "wide"
)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmp5zXnsw/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ##    person_id         T0 window_name value_outcome date_outcome
    ##       <char>     <Date>      <char>        <char>       <Date>
    ## 1:         1 2024-01-01     control          TRUE   2024-03-01
    ## 2:         1 2024-01-01       index          TRUE   2024-01-01
    ## 3:         1 2024-01-01    lookback          TRUE   2023-12-20
    ## 4:         1 2024-01-01        risk          TRUE   2024-01-20
    ## 5:         2 2024-01-01    lookback          <NA>         <NA>
    ## 6:         2 2024-01-01       index          <NA>         <NA>
    ## 7:         2 2024-01-01        risk          <NA>         <NA>
    ## 8:         2 2024-01-01     control          <NA>         <NA>

``` r

get_anchor_result(
  metadata, hive, population = population,
  result_shape = "wide", cast_window = TRUE
)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmp5zXnsw/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ##    person_id         T0 value_control_outcome value_index_outcome
    ##       <char>     <Date>                <char>              <char>
    ## 1:         1 2024-01-01                  TRUE                TRUE
    ## 2:         2 2024-01-01                  <NA>                <NA>
    ##    value_lookback_outcome value_risk_outcome date_control_outcome
    ##                    <char>             <char>               <Date>
    ## 1:                   TRUE               TRUE           2024-03-01
    ## 2:                   <NA>               <NA>                 <NA>
    ##    date_index_outcome date_lookback_outcome date_risk_outcome
    ##                <Date>                <Date>            <Date>
    ## 1:         2024-01-01            2023-12-20        2024-01-20
    ## 2:               <NA>                  <NA>              <NA>

Metadata can request a subset after anchoring. Supplying one explicit
`window_name` restricts retrieval to that variable/window pair; an `NA`
window name acts as a wildcard for that variable.

``` r

get_anchor_result(
  metadata[window_name == "risk"],
  hive,
  result_shape = "long"
)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmp5zXnsw/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ##    person_id         T0 variable_id window_name       date  value
    ##       <char>     <Date>      <char>      <char>     <Date> <char>
    ## 1:         1 2024-01-01     outcome        risk 2024-01-20   TRUE

Use the default wide form when windows are naturally rows and
`cast_window = TRUE` when downstream modeling requires one row per
population key.
