# anchoR

`anchoR` is a small R package for anchoring study variables to an index date.

It is built for a common epidemiology workflow:

- define a time window around an anchor date such as `T0`
- find matching concept records for each person inside that window
- reduce those matches to one anchored value using a selector such as `LATEST`, `EARLIEST`, `COUNT`, or `RANGE_COUNT`

The package is intentionally small. It focuses on reusable anchoring logic and leaves study-specific preprocessing to the calling pipeline.

## Core idea

The package works with three inputs:

- `population`: one row per person, including `person_id` and the anchor column
- `metadata`: one row per study variable, including the concept to look for, the selector to use, and the lookback offsets
- `concepts`: the clinical events table, supplied as a data frame, a DuckDB file, or parquet location(s)

From those inputs, `anchoR` builds one person-variable window, queries the concept data, and writes an anchored result you can read back in long or wide format.

## Main functions

- `define_window()`: build one anchoring window per person and per variable
- `anchor()`: compute all requested variables in one pass and replace only their parquet partitions
- `anchor_by_variable()`: process variables in bounded chunks while still replacing each variable's partition independently
- `anchor_by_selector()`: group all variables using the same selector into one query
- `get_anchor_result()`: read the anchored parquet hive back as a long or wide `data.table`
- `make_constructor()`: build a custom window-construction rule without editing anchoR itself
- `filter_supported_metadata()`: drop metadata rows whose selectors are not implemented in the package

## Minimal example

```r
library(anchoR)
library(data.table)

population <- data.table(
  person_id = c("1", "2"),
  T0        = as.Date(c("2024-01-01", "2024-01-01"))
)

metadata <- data.table(
  variable_id  = "flu_vaccine_recent",
  concept_id   = "FLU_VAX",
  constructor  = "GENERIC",
  selector     = "LATEST",
  start_offset = -365L,  # 365 days before T0 ...
  end_offset   = 0L      # ... through T0 itself
)

concepts <- data.table(
  person_id  = "1",
  concept_id = "FLU_VAX",
  date       = as.Date("2023-10-01"),
  value      = "TRUE"
)

hive_path <- tempfile(pattern = "anchor-hive-")
dir.create(hive_path)

anchor(
  population       = population,
  metadata         = metadata,
  concepts         = concepts,
  anchor_hive_path = hive_path
)

get_anchor_result(
  metadata         = metadata,
  anchor_hive_path = hive_path,
  result_shape     = "long"
)
#>    person_id         T0        variable_id window_name       date value
#> 1:         1 2024-01-01 flu_vaccine_recent        <NA> 2023-10-01  TRUE
```

Person 1's window is 365 days before `T0` through `T0` itself, which covers
the 2023-10-01 record; person 2 has no matching record and simply doesn't
appear in the (sparse) result.

## Documentation

- Installed introductory vignettes: `vignette("standard-windows", package = "anchoR")` and `vignette("episode-windows", package = "anchoR")`.
- Practical vignettes: `multiple-windows`, `metadata-migration`, `production-sources`, `troubleshooting`, `selector-cookbook`, `custom-constructors`, and `imputation` (open one with `vignette("<name>", package = "anchoR")`).
- [Standard-window tutorial](documentation/Tutorial_standard_windows.md): selectors, multiple windows, batching, and custom anchors.
- [Episode-window tutorial](documentation/Tutorial_pregnancy_windows.md): recurring start/end episodes and pregnancy-oriented constructors.
- [Result walkthrough](documentation/get_anchor_result_walkthrough.md): long/wide retrieval and imputation internals.
- Canonical schemas: [population](documentation/Input_population.md), [metadata](documentation/Input_metadata.md), [concepts](documentation/Input_concepts.md), and [output](documentation/Output_D4_StudyVariablesAnchored.md).
- [Documentation index](documentation/README.md): choose a guide by task.
