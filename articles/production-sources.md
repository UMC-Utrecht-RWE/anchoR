# Parquet and DuckDB concept sources

``` r

library(anchoR)
library(data.table)
```

Production concept stores can remain on disk. anchoR queries parquet
directly and attaches DuckDB databases read-only, filtering to metadata
concept IDs before selector execution.

``` r

population <- data.table(
  person_id = c("1", "2"),
  T0 = as.Date(c("2024-01-01", "2024-01-01")),
  group = c("EXPOSED", "CONTROL")
)
metadata <- data.table(
  variable_id = c("recent_vaccine", "hospital_count"),
  concept_id = c("VACCINE", "HOSP"),
  constructor = "GENERIC",
  selector = c("LATEST", "COUNT"),
  start_offset = -365L,
  end_offset = 0L
)
concepts <- data.table(
  person_id = c("1", "2", "2"),
  concept_id = c("VACCINE", "HOSP", "HOSP"),
  date = as.Date(c("2023-10-01", "2023-08-01", "2023-11-01")),
  value = "TRUE"
)
```

## Hive-partitioned parquet

``` r

parquet_dir <- tempfile("concept-parquet-")
dir.create(parquet_dir)
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmp9Ru13j/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

``` r

DBI::dbWriteTable(con, "concept_table", concepts)
quoted_parquet <- as.character(DBI::dbQuoteString(con, parquet_dir))
DBI::dbExecute(
  con,
  sprintf(
    "COPY concept_table TO %s (FORMAT PARQUET, PARTITION_BY (concept_id))",
    quoted_parquet
  )
)
```

    ## [1] 3

``` r

DBI::dbDisconnect(con, shutdown = TRUE)

hive <- tempfile("production-hive-")
anchor(
  population, metadata, parquet_dir,
  anchor_hive_path = hive,
  by = "variable",
  chunk_size = 1L
)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmp9Ru13j/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ## [1] "recent_vaccine" "hospital_count"

``` r

get_anchor_result(
  metadata, hive, population = population,
  result_shape = "wide", cast_window = TRUE
)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmp9Ru13j/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ## Key: <person_id, T0>
    ##    person_id         T0 value_NA_hospital_count value_NA_recent_vaccine
    ##       <char>     <Date>                  <char>                  <char>
    ## 1:         1 2024-01-01                    <NA>                    TRUE
    ## 2:         2 2024-01-01                       2                    <NA>
    ##    date_NA_hospital_count date_NA_recent_vaccine date_NA_NA value_NA_NA   group
    ##                    <Date>                 <Date>     <Date>      <char>  <char>
    ## 1:                   <NA>             2023-10-01       <NA>        <NA> EXPOSED
    ## 2:             2023-11-01                   <NA>       <NA>        <NA> CONTROL

Directories, individual parquet files, vectors of files, and glob
patterns are accepted. Hive partitioning by `concept_id` lets DuckDB
prune irrelevant partitions.

## DuckDB database

The database must contain a table named `concept_table` with
`person_id`, `concept_id`, `date`, and `value`.

``` r

duckdb_path <- tempfile(fileext = ".duckdb")
updated_concepts <- rbind(
  concepts,
  data.table(
    person_id = "1", concept_id = "VACCINE",
    date = as.Date("2023-12-15"), value = "TRUE"
  )
)
con <- DBI::dbConnect(duckdb::duckdb(), dbdir = duckdb_path)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmp9Ru13j/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

``` r

DBI::dbWriteTable(con, "concept_table", updated_concepts)
DBI::dbDisconnect(con, shutdown = TRUE)

anchor(
  population,
  metadata[variable_id == "recent_vaccine"],
  duckdb_path,
  anchor_hive_path = hive,
  by = "variable",
  chunk_size = 1L
)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmp9Ru13j/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ## [1] "recent_vaccine"

``` r

get_anchor_result(metadata, hive, result_shape = "long")
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmp9Ru13j/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ##    person_id         T0    variable_id window_name       date  value
    ##       <char>     <Date>         <char>      <char>     <Date> <char>
    ## 1:         2 2024-01-01 hospital_count        <NA> 2023-11-01      2
    ## 2:         1 2024-01-01 recent_vaccine        <NA> 2023-12-15   TRUE

The second run replaces only `recent_vaccine`; the existing
`hospital_count` partition remains. A recomputed variable with no
matches has its previous partition removed. If that leaves the entire
hive without parquet files, check for the empty directory before
retrieval.

Choose
[`anchor()`](https://umc-utrecht-rwe.github.io/anchoR/reference/anchor.md)’s
`by` argument based on scale:

- `by = "whole"` (default) minimizes orchestration and handles all
  requested variables together.
- `by = "variable"` bounds working-set and replacement scope with
  `chunk_size`.
- `by = "selector"` minimizes selector scans by grouping all variables
  using each selector.
