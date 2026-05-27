# anchoR

`anchoR` is a small R package for anchoring study variables to an index date.

It is built for a common epidemiology workflow:

- define a time window around an anchor date such as `T0`
- find matching concept records for each person inside that window
- reduce those matches to one anchored value using a selector such as `LATEST`, `EARLIEST`, `COUNT`, or `RANGE_COUNT`

The package is intentionally narrow. It focuses on reusable anchoring logic and leaves study-specific preprocessing to the calling pipeline.

## Core idea

The package works with three inputs:

- `population`: one row per person, including `person_id` and the anchor column
- `metadata`: one row per study variable, including the concept to look for, the selector to use, and the lookback offsets
- `concepts`: the clinical events table, supplied as a data frame, a DuckDB file, or parquet location(s)

From those inputs, `anchoR` builds one person-variable window, queries the concept data, and returns a long anchored result.

## Main functions

- `define_window()`: build one anchoring window per person and per variable
- `anchor()`: run the selector SQL and return anchored values
- `filter_supported_metadata()`: drop metadata rows whose selectors are not implemented in the simplified package

## Minimal example

```r
library(anchoR)
library(data.table)

population <- fread(system.file("extdata", "example_population.csv", package = "anchoR"))
metadata <- fread(system.file("extdata", "example_metadata.csv", package = "anchoR"))
concepts <- fread(system.file("extdata", "example_concepts.csv", package = "anchoR"))

population[, c("T0", "lmp_date", "pregnancy_end_date", "candidate_start", "candidate_end") :=
  lapply(.SD, as.Date),
  .SDcols = c("T0", "lmp_date", "pregnancy_end_date", "candidate_start", "candidate_end")
]
concepts[, date := as.Date(date)]

anchor(
  population = population,
  metadata = metadata,
  concepts = concepts
)
```
