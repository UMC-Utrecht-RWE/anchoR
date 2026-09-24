# Custom window constructors

``` r

library(anchoR)
library(data.table)
```

Use a custom constructor when window boundaries cannot be expressed by
the built-in generic or episode rules. This example starts at an index
date and ends at the earlier of recorded follow-up or 180 days after
index.

Constructor metadata value `CAPPED_FOLLOWUP` resolves to a function
named `capped_followup_window`. The function must return its input rows
with `window_start` and `window_end` columns.

``` r

capped_followup_window <- make_constructor(
  transform_fn = function(window_dt) {
    window_dt[, `:=`(
      window_start = as.Date(NA),
      window_end = as.Date(NA),
      .follow_up_cap = as.Date(NA)
    )]

    for (col in unique(window_dt$anchor_start_col)) {
      window_dt[
        anchor_start_col == col,
        `:=`(
          window_start = as.Date(get(col) + start_offset),
          .follow_up_cap = as.Date(get(col) + 180L)
        )
      ]
    }
    for (col in unique(window_dt$anchor_end_col)) {
      window_dt[
        anchor_end_col == col,
        window_end := as.Date(pmin(get(col) + end_offset, .follow_up_cap))
      ]
    }

    window_dt[, .follow_up_cap := NULL]
    window_dt[]
  },
  required_cols = c(
    "anchor_start_col", "anchor_end_col", "start_offset", "end_offset"
  )
)
```

The constructor uses canonical metadata fields so validation and the
anchoring pipeline retain everything it needs.

``` r

population <- data.table(
  person_id = c("1", "2"),
  T0 = as.Date(c("2024-01-01", "2024-01-01")),
  follow_up_end = as.Date(c("2024-03-01", "2025-01-01"))
)
metadata <- data.table(
  variable_id = "first_follow_up_event",
  concept_id = "EVENT",
  constructor = "CAPPED_FOLLOWUP",
  selector = "EARLIEST",
  start_offset = 0L,
  end_offset = 0L,
  anchor_start_col = "T0",
  anchor_end_col = "follow_up_end"
)

define_window(
  population, metadata,
  constructor_env = environment()
)[
  , .(person_id, window_start, window_end, window_valid)
]
```

    ##    person_id window_start window_end window_valid
    ##       <char>       <Date>     <Date>       <lgcl>
    ## 1:         1   2024-01-01 2024-03-01         TRUE
    ## 2:         2   2024-01-01 2024-06-29         TRUE

Person 1 is capped by recorded follow-up; person 2 is capped at
`T0 + 180`. Test those boundaries with
[`define_window()`](https://umc-utrecht-rwe.github.io/anchoR/reference/define_window.md)
before applying concepts.

``` r

concepts <- data.table(
  person_id = c("1", "2", "2"),
  concept_id = "EVENT",
  date = as.Date(c("2024-02-01", "2024-05-01", "2024-08-01")),
  value = "TRUE"
)
hive <- tempfile("custom-hive-")

# anchor() resolves custom constructors from the global environment.
had_existing_constructor <- exists(
  "capped_followup_window", envir = globalenv(), inherits = FALSE
)
if (had_existing_constructor) {
  existing_constructor <- get(
    "capped_followup_window", envir = globalenv(), inherits = FALSE
  )
}
assign(
  "capped_followup_window", capped_followup_window,
  envir = globalenv()
)
anchor(population, metadata, concepts, anchor_hive_path = hive)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/RtmpuSRiyG/duckdb
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
    ## ℹ /tmp/RtmpuSRiyG/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ##    person_id         T0           variable_id window_name       date  value
    ##       <char>     <Date>                <char>      <char>     <Date> <char>
    ## 1:         1 2024-01-01 first_follow_up_event        <NA> 2024-02-01   TRUE
    ## 2:         2 2024-01-01 first_follow_up_event        <NA> 2024-05-01   TRUE

Custom constructors are discovered in the global environment by the
standard
[`anchor()`](https://umc-utrecht-rwe.github.io/anchoR/reference/anchor.md)
workflow.
[`define_window()`](https://umc-utrecht-rwe.github.io/anchoR/reference/define_window.md)
additionally accepts `constructor_env` for explicit lookup during
isolated testing. Built-in and custom constructor rows may coexist in
one metadata table.

Current normalization retains only anchoR’s canonical metadata fields.
Encode custom boundaries using canonical anchor/offset columns or
implement preprocessing upstream; arbitrary extra metadata columns are
not passed through validation.
