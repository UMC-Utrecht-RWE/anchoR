# Standard anchoring windows

``` r

library(anchoR)
library(data.table)
```

anchoR combines a population, variable metadata, and concept events. A
generic window is an inclusive date range obtained by adding day offsets
to an anchor date.

``` r

population <- data.table(
  person_id = c("1", "2"),
  T0 = as.Date(c("2024-01-01", "2024-01-01")),
  group = c("EXPOSED", "CONTROL")
)

metadata <- data.table(
  variable_id = "recent_flu_vaccine",
  concept_id = "FLU_VAX",
  constructor = "GENERIC",
  selector = "LATEST",
  window_name = "one_year",
  start_offset = -365L,
  end_offset = 0L
)

concepts <- data.table(
  person_id = "1",
  concept_id = "FLU_VAX",
  date = as.Date("2023-10-01"),
  value = "TRUE"
)
```

[`define_window()`](https://umc-utrecht-rwe.github.io/anchoR/reference/define_window.md)
is useful for inspecting the design before reading any concepts.

``` r

define_window(population, metadata)[
  , .(person_id, T0, variable_id, window_name, window_start, window_end)
]
```

    ##    person_id         T0        variable_id window_name window_start window_end
    ##       <char>     <Date>             <char>      <char>       <Date>     <Date>
    ## 1:         1 2024-01-01 recent_flu_vaccine    one_year   2023-01-01 2024-01-01
    ## 2:         2 2024-01-01 recent_flu_vaccine    one_year   2023-01-01 2024-01-01

[`anchor()`](https://umc-utrecht-rwe.github.io/anchoR/reference/anchor.md)
persists sparse matches in a parquet Hive. Long output contains only
matches.

``` r

hive_path <- tempfile("anchor-hive-")
anchor(population, metadata, concepts, anchor_hive_path = hive_path)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmpi3BrZV/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ## NULL

``` r

get_anchor_result(metadata, hive_path, result_shape = "long")
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmpi3BrZV/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ##    person_id         T0        variable_id window_name       date  value
    ##       <char>     <Date>             <char>      <char>     <Date> <char>
    ## 1:         1 2024-01-01 recent_flu_vaccine    one_year 2023-10-01   TRUE

Supplying the population to wide output completes missing population
keys and reattaches its additional columns.

``` r

get_anchor_result(
  metadata,
  hive_path,
  population = population,
  result_shape = "wide"
)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmpi3BrZV/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ##    person_id         T0 window_name value_recent_flu_vaccine
    ##       <char>     <Date>      <char>                   <char>
    ## 1:         1 2024-01-01    one_year                     TRUE
    ## 2:         2 2024-01-01    one_year                     <NA>
    ##    date_recent_flu_vaccine   group
    ##                     <Date>  <char>
    ## 1:              2023-10-01 EXPOSED
    ## 2:                    <NA> CONTROL

For multiple windows, repeat `variable_id` with distinct `window_name`
values. The default wide form retains one row per `person_id`, `T0`, and
`window_name`; `cast_window = TRUE` folds the window into each result
column name. Use long output for `ALL`, which can put several records
into one wide cell. `LATEST` and `EARLIEST` break date ties with the
lexicographically largest normalized character value.

Available selectors are returned by
[`available_selectors()`](https://umc-utrecht-rwe.github.io/anchoR/reference/available_selectors.md).
Their complete semantics, including inclusive boundaries and tie
behavior, are documented in the selector reference on the package
website.
