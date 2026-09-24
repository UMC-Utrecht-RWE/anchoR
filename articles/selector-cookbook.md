# Selector cookbook

``` r

library(anchoR)
library(data.table)
```

Selectors reduce concept matches after inclusive window filtering. This
example applies every bundled selector to the same person.

``` r

population <- data.table(person_id = "1", T0 = as.Date("2024-01-10"))
# RANGE_COUNT is excluded here: it looks up its output value from a
# user-supplied `concept_ranges` table, which this single-concepts-table demo
# does not provide (see the RANGE_COUNT bullet below).
selectors <- setdiff(available_selectors(), "RANGE_COUNT")
metadata <- data.table(
  variable_id = paste0("example_", tolower(selectors)),
  concept_id = "MEASURE",
  constructor = "GENERIC",
  selector = selectors,
  start_offset = -30L,
  end_offset = 0L,
  range_min = 2,
  range_max = 10
)
concepts <- data.table(
  person_id = "1",
  concept_id = "MEASURE",
  date = as.Date(c("2024-01-01", "2024-01-05", "2024-01-05")),
  value = c("1", "9", "10")
)

hive <- tempfile("selector-hive-")
anchor(population, metadata, concepts, anchor_hive_path = hive)
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmpv5VqEM/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

    ## NULL

``` r

result <- get_anchor_result(metadata, hive, result_shape = "long")
```

    ## duckdb keeps downloaded extensions and secrets in a temporary directory:
    ## ℹ /tmp/Rtmpv5VqEM/duckdb
    ## This is removed when the R session ends.
    ## • Extensions are re-downloaded each session.
    ## • Secrets are lost.
    ## ℹ Run duckdb(shared_home = TRUE) (or create ~/.duckdb) to keep them (suitable for most users).
    ## ℹ Run duckdb(shared_home = FALSE) to accept the temporary directory (and silence this message).
    ## ℹ See ?duckdb_storage for details and alternatives.

``` r

result[, .(variable_id, date, value)]
```

    ##                  variable_id       date  value
    ##                       <char>     <Date> <char>
    ## 1:               example_all 2024-01-01      1
    ## 2:               example_all 2024-01-05      9
    ## 3:               example_all 2024-01-05     10
    ## 4:             example_count 2024-01-05      3
    ## 5: example_count_more_than_1 2024-01-05   TRUE
    ## 6:          example_earliest 2024-01-01      1
    ## 7:            example_latest 2024-01-05      9

Important details:

- `LATEST` and `EARLIEST` return one row. Date ties use the
  lexicographically largest normalized character value, so `"9"` sorts
  after `"10"`.
- `COUNT` persists only when at least one record matches; it does not
  write zero rows.
- `COUNT_MORE_THAN_1` writes `TRUE` only for two or more joined matches.
- `ALL` returns every joined match and normally requires long output.
- `RANGE_COUNT` counts joined matches like `COUNT`, then looks up that
  count in a `concept_ranges` table (matched on `concept_id`, with the
  count falling between `lower_range` and `upper_range`) to return a
  bucketed value instead of the raw count.
- Overlapping candidate windows can join the same concept record
  multiple times.

Selector output `value` is character in persisted/public long results.
Convert it to the type you need after retrieval rather than assuming the
source type survives every SQL selector.

None of these fit your rule? See
[`vignette("custom-selectors")`](https://umc-utrecht-rwe.github.io/anchoR/articles/custom-selectors.md)
for
[`make_selector()`](https://umc-utrecht-rwe.github.io/anchoR/reference/make_selector.md),
which lets you add a selector of your own without editing anchoR.
