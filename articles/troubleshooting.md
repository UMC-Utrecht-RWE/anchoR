# Troubleshooting and validation

``` r

library(anchoR)
library(data.table)
```

## Inspect windows before anchoring

Most problems are easier to diagnose before concepts and DuckDB are
involved. Start with
[`validate_anchor_inputs()`](https://umc-utrecht-rwe.github.io/anchoR/reference/validate_anchor_inputs.md)
and
[`define_window()`](https://umc-utrecht-rwe.github.io/anchoR/reference/define_window.md).

``` r

population <- data.table(
  person_id = c("1", "2"),
  T0 = as.Date(c("2024-01-01", NA))
)
metadata <- data.table(
  variable_id = "recent_event",
  concept_id = "EVENT",
  constructor = "GENERIC",
  selector = "LATEST",
  start_offset = -30L,
  end_offset = 0L
)

validated <- validate_anchor_inputs(population, metadata)
windows <- define_window(population, metadata)
windows[, .(person_id, window_start, window_end, window_valid)]
```

    ##    person_id window_start window_end window_valid
    ##       <char>       <Date>     <Date>       <lgcl>
    ## 1:         1   2023-12-02 2024-01-01         TRUE
    ## 2:         2         <NA>       <NA>        FALSE

A missing anchor creates an invalid window.
[`anchor()`](https://umc-utrecht-rwe.github.io/anchoR/reference/anchor.md)
sends only valid windows to selector SQL.

## Frequent failures

| symptom | likely cause | resolution |
|----|----|----|
| Missing anchor-column error | Metadata references a population field that is absent | Correct `anchor_start_col`/`anchor_end_col` or add the field |
| Date-format error | Primary anchor is not `Date` or strict `YYYY-mm-dd` text | Parse with [`as.Date()`](https://rdrr.io/r/base/as.Date.html) before anchoring |
| Unsupported selector | Typo, missing selector, or no bundled SQL template | Check [`available_selectors()`](https://umc-utrecht-rwe.github.io/anchoR/reference/available_selectors.md); optionally use [`filter_supported_metadata()`](https://umc-utrecht-rwe.github.io/anchoR/reference/filter_supported_metadata.md) |
| Window function does not exist | Custom constructor name does not resolve to `<name>_window` | Define it in `constructor_env` and use the required name |
| No parquet files found | Empty/wrong concepts directory | Check the path and produce at least one parquet file |
| Wide output is ambiguous | More than one result occupies a wide cell, commonly from `ALL` | Request long output or reduce events upstream |
| Duplicate population warning | Rows share `person_id/T0` but disagree on extra fields | Choose a stable unique population key upstream; anchoR keeps the first row |
| Empty-hive DuckDB error | No variable produced a parquet partition | Detect an empty hive before calling [`get_anchor_result()`](https://umc-utrecht-rwe.github.io/anchoR/reference/get_anchor_result.md) |

## Unsupported metadata

[`anchor()`](https://umc-utrecht-rwe.github.io/anchoR/reference/anchor.md)
stops rather than silently dropping study variables. Inspect deliberate
filtering separately:

``` r

candidate_metadata <- rbind(
  metadata,
  copy(metadata)[, `:=`(variable_id = "bad", selector = "NOT_IMPLEMENTED")]
)

available_selectors()
```

    ## [1] "ALL"               "COUNT_MORE_THAN_1" "COUNT"            
    ## [4] "EARLIEST"          "LATEST"            "RANGE_COUNT"

``` r

supported_metadata <- suppressWarnings(
  filter_supported_metadata(candidate_metadata)
)
```

    ## WARN [2026-09-24 12:46:22] Dropped 1 metadata row(s) with missing or unsupported selectors. Dropped selector value(s): NOT_IMPLEMENTED. Available selectors in package `anchoR`: ALL, COUNT_MORE_THAN_1, COUNT, EARLIEST, LATEST, RANGE_COUNT. Affected variable_id value(s): bad.

``` r

supported_metadata[, .(variable_id, selector)]
```

    ##     variable_id selector
    ##          <char>   <char>
    ## 1: recent_event   LATEST

## Episode checks

The `episodes` table must contain `person_id`, `start_episode`, and
`end_episode`. Invalid or overlapping periods should be corrected
upstream (episode classification assumes a person’s own episodes don’t
overlap). Multiple candidate windows are joined independently;
overlapping windows can cause one concept event to contribute more than
once to `COUNT` or `ALL`.

## A useful diagnostic sequence

1.  Confirm canonical metadata names and supported selectors.
2.  Run
    [`validate_anchor_inputs()`](https://umc-utrecht-rwe.github.io/anchoR/reference/validate_anchor_inputs.md)
    without concepts.
3.  Inspect invalid and unexpectedly expanded rows from
    [`define_window()`](https://umc-utrecht-rwe.github.io/anchoR/reference/define_window.md).
4.  Test one variable against a small in-memory concept subset.
5.  Run the production parquet or DuckDB source.
6.  Read long output first; reshape to wide only after confirming result
    cardinality.
