# Using anchoR for Standard (Single-Anchor) Study Variables

This is the usage guide for anchoR's core workflow: a study variable anchored to one fixed date per person (usually called `T0`), with a window defined as a fixed offset around it. If you need a window that depends on a *recurring* event instead (e.g. pregnancy, or any condition that can start and stop multiple times), see [Tutorial_pregnancy_windows](Tutorial_pregnancy_windows.md), everything on this page is the `GENERIC` special case of that same machinery.

## The three inputs

| input        | shape                                                             | see also                                   |
| ------------ | ----------------------------------------------------------------- | ------------------------------------------ |
| `population` | one row per person (or per `person_id x T0`), with an anchor date | [Input_population.md](Input_population.md) |
| `metadata`   | one row per study variable (or per variable x window)             | [Input_metadata.md](Input_metadata.md)     |
| `concepts`   | one row per raw event: `person_id`, `concept_id`, `date`, `value` | [Input_concepts.md](Input_concepts.md)     |

`anchor()` cross-joins population with metadata, builds a window per person-variable pair, filters `concepts` to whichever records fall in that window, and collapses the matches with the requested selector.

## Step 1: [Population](definitions/Population.md)

```r
library(anchoR)
library(data.table)

population <- data.table(
  person_id = c("1", "2", "3"),
  T0        = as.Date(c("2024-01-01", "2024-01-01", "2024-06-01"))
)
```

Only `person_id` and the anchor column (`T0` by default) are required. Extra columns are fine; the anchoring step itself ignores them.

## Step 2: [Metadata](definitions/Metadata.md)

Each row says: for this `variable_id`, look for `concept_id` in a window built from `start_offset`/`end_offset` days around the anchor, and collapse whatever matches with `selector`.

```r
metadata <- data.table(
  variable_id  = "flu_vaccine_recent",
  concept_id   = "FLU_VAX",
  constructor  = "GENERIC",
  selector     = "LATEST",
  start_offset = -365L,   # 365 days before T0 ...
  end_offset   = 0L       # ... through T0 itself
)
```

`constructor = "GENERIC"` means "a fixed offset around the anchor", it's the only constructor you need for this workflow. (`start_offset`/`end_offset` are not aliased to anything else, `start_look_back`/`end_look_back` are a separate, unrelated pair of columns used only by `IN_PRIOR_PREG`, see [Tutorial_pregnancy_windows](Tutorial_pregnancy_windows.md).)

## Step 3: [Concepts](definitions/Concepts.md)

```r
concepts <- data.table(
  person_id  = "1",
  concept_id = "FLU_VAX",
  date       = as.Date("2023-10-01"),
  value      = "TRUE"
)
```

## Step 4: Anchor and read the result

```r
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

Person 1's window is `[2023-01-02, 2024-01-01]`, which covers the 2023-10-01 record. Persons 2 and 3 have no matching record, so they don't appear; long output is sparse by design.

`anchor()` *replaces* whatever parquet is already at `anchor_hive_path` for each `variable_id` it computes (rather than appending to it), so calling it twice with overlapping `variable_id` values into the same path re-runs cleanly instead of producing duplicate rows. `variable_id`s outside the current `metadata` call are left untouched. See `anchor_by_variable()`/`anchor_by_selector()` (below) if you want to recompute a subset of variables without recomputing everything else in one pass.

## Selector reference

| selector            | returns per window                                                                                                              |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `LATEST`            | the most recent matching record (by `date`)                                                                                     |
| `EARLIEST`          | the oldest matching record                                                                                                      |
| `COUNT`             | how many records matched (`value` is the count, `date` is the latest)                                                           |
| `COUNT_MORE_THAN_1` | `TRUE` only if 2 or more records matched, otherwise no row at all                                                               |
| `RANGE_COUNT`       | how many records had a numeric `value` inside `[range_min, range_max]` (also needs `range_min`/`range_max` columns in metadata) |
| `ALL`               | every matching record, one output row each                                                                                      |

Worked example, one variable per selector:

```r
hive_path <- tempfile(pattern = "anchor-hive-")
dir.create(hive_path)

population <- data.table(
  person_id = c("1", "2", "3"),
  T0        = as.Date(c("2024-01-01", "2024-01-01", "2024-06-01"))
)

metadata <- data.table(
  variable_id = c(
    "flu_vaccine_recent", "flu_vaccine_ever", "hospitalizations_1y",
    "recurrent_hospitalization", "bmi_in_healthy_range", "all_diagnoses"
  ),
  concept_id = c("FLU_VAX", "FLU_VAX", "HOSP", "HOSP", "BMI", "DX"),
  constructor = "GENERIC",
  selector = c(
    "LATEST", "EARLIEST", "COUNT", "COUNT_MORE_THAN_1", "RANGE_COUNT", "ALL"
  ),
  start_offset = c(-365L, -3650L, -365L, -365L, -180L, -365L),
  end_offset   = 0L,
  range_min = c(NA, NA, NA, NA, 18.5, NA),
  range_max = c(NA, NA, NA, NA, 25, NA)
)

concepts <- data.table(
  person_id  = c("1","1","1","1","2","1","2","1","1"),
  concept_id = c(
    "FLU_VAX","FLU_VAX","HOSP","HOSP","HOSP","BMI","BMI","DX","DX"
  ),
  date = as.Date(c(
    "2023-10-01","2020-01-01","2023-06-01","2023-09-01","2023-12-01",
    "2023-11-01","2023-11-01","2023-08-01","2023-09-15"
  )),
  value = c("TRUE","TRUE","TRUE","TRUE","TRUE","22.5","30","TRUE","TRUE")
)

anchor(population, metadata, concepts, anchor_hive_path = hive_path)
result <- get_anchor_result(metadata, hive_path, result_shape = "long")[
  , .(person_id, T0, variable_id, date, value)
]
setorder(result, variable_id, person_id)
result
#>    person_id         T0               variable_id       date value
#> 1:         1 2024-01-01             all_diagnoses  2023-08-01  TRUE
#> 2:         1 2024-01-01             all_diagnoses  2023-09-15  TRUE
#> 3:         1 2024-01-01      bmi_in_healthy_range  2023-11-01     1
#> 4:         1 2024-01-01          flu_vaccine_ever  2020-01-01  TRUE
#> 5:         1 2024-01-01        flu_vaccine_recent  2023-10-01  TRUE
#> 6:         1 2024-01-01       hospitalizations_1y  2023-09-01     2
#> 7:         2 2024-01-01       hospitalizations_1y  2023-12-01     1
#> 8:         1 2024-01-01 recurrent_hospitalization  2023-09-01  TRUE
```

A few things worth noticing:

- Person 2's `BMI` was `30`, outside `[18.5, 25]`, so `bmi_in_healthy_range` has no row for them. `RANGE_COUNT`'s `value` is a *count* of in-range records, not the BMI itself.
- Person 2 has only one `HOSP` record, so `hospitalizations_1y` still reports it (`COUNT` includes everyone with >= 1 match), but `recurrent_hospitalization` (`COUNT_MORE_THAN_1`) correctly excludes them.
- Person 3 has no concept records at all and never appears.

## Multiple windows for the same variable

Repeat `variable_id` with different `window_name`/offsets/selectors to get several windows for one variable, e.g. a "how recent" view and an "ever" view of the same concept:

```r
hive_path <- tempfile(pattern = "anchor-hive-")
dir.create(hive_path)

population <- data.table(
  person_id = c("1", "2"),
  T0        = as.Date(c("2024-01-01", "2024-01-01"))
)
concepts <- data.table(
  person_id  = c("1", "1"),
  concept_id = c("FLU_VAX", "FLU_VAX"),
  date       = as.Date(c("2023-10-01", "2020-01-01")),
  value      = c("TRUE", "TRUE")
)
metadata <- data.table(
  variable_id = c("flu_vaccine", "flu_vaccine"),
  concept_id  = c("FLU_VAX", "FLU_VAX"),
  constructor = "GENERIC",
  window_name = c("recent", "ever"),
  selector    = c("LATEST", "EARLIEST"),
  start_offset = c(-365L, -3650L),
  end_offset   = 0L
)

anchor_by_variable(population, metadata, concepts, anchor_hive_path = hive_path)
get_anchor_result(metadata, hive_path, population = population, result_shape = "wide")
#>    person_id         T0 window_name value_flu_vaccine date_flu_vaccine
#> 1:         1 2024-01-01        ever              TRUE       2020-01-01
#> 2:         1 2024-01-01      recent              TRUE       2023-10-01
#> 3:         2 2024-01-01      recent              <NA>             <NA>
#> 4:         2 2024-01-01        ever              <NA>             <NA>
```

That's one row per `person_id x T0 x window_name` (`cast_window = FALSE`,
the default). Set `cast_window = TRUE` to get one row per `person_id x T0`
instead, with the window folded into the column name:

```r
get_anchor_result(
  metadata, hive_path, population = population,
  result_shape = "wide", cast_window = TRUE
)
#>    person_id         T0 value_ever_flu_vaccine value_recent_flu_vaccine
#> 1:         1 2024-01-01                   TRUE                     TRUE
#> 2:         2 2024-01-01                   <NA>                     <NA>
```

Passing `population` to `get_anchor_result()` also backfills a row for every population key with no match at all (person 2 above), so wide output always has a predictable number of rows.

## `anchor()` vs `anchor_by_variable()`

`anchor()` computes every variable in `metadata` in one pass and writes one parquet hive. `anchor_by_variable()` processes variable IDs in bounded chunks (`chunk_size = 10` by default) and replaces each variable's own partition rather than appending. A call with metadata for one variable therefore touches only that partition. Use it when you want a bounded processing/failure scope or expect to re-run selected variables without recomputing everything else:

```r
hive_path <- tempfile(pattern = "anchor-hive-")
dir.create(hive_path)

population <- data.table(
  person_id = c("1", "2"), T0 = as.Date(c("2024-01-01", "2024-01-01"))
)
metadata <- data.table(
  variable_id = c("flu_vaccine_recent", "recent_hosp_count"),
  concept_id  = c("FLU_VAX", "HOSP"),
  constructor = "GENERIC",
  selector    = c("LATEST", "COUNT"),
  start_offset = -365L,
  end_offset   = 0L
)
concepts <- data.table(
  person_id  = c("1", "2"),
  concept_id = c("FLU_VAX", "HOSP"),
  date       = as.Date(c("2023-10-01", "2023-11-01")),
  value      = c("TRUE", "1")
)

anchor_by_variable(population, metadata, concepts, anchor_hive_path = hive_path)
get_anchor_result(metadata, hive_path, result_shape = "long")[
  , .(variable_id, person_id, value, date)
]
#>           variable_id person_id  value       date
#> 1: flu_vaccine_recent         1   TRUE 2023-10-01
#> 2:  recent_hosp_count         2      1 2023-11-01

# A later, corrected concept source adds a newer FLU_VAX record for person 1.
updated_concepts <- rbindlist(list(
  concepts,
  data.table(
    person_id = "1", concept_id = "FLU_VAX",
    date = as.Date("2023-12-01"), value = "TRUE"
  )
))

anchor_by_variable(
  population       = population,
  metadata         = metadata[variable_id == "flu_vaccine_recent"],
  concepts         = updated_concepts,
  anchor_hive_path = hive_path
)

get_anchor_result(metadata, hive_path, result_shape = "long")[
  , .(variable_id, person_id, value, date)
]
#>           variable_id person_id  value       date
#> 1: flu_vaccine_recent         1   TRUE 2023-12-01
#> 2:  recent_hosp_count         2      1 2023-11-01
```

Only `flu_vaccine_recent`'s partition changed (now reflecting the 2023-12-01 record); `recent_hosp_count`, untouched by the second call, kept its original value.

## A non-default anchor column

If your population's anchor date isn't called `T0`, pass its name via `anchor_col`. The output still reports it as `T0`:

```r
hive_path <- tempfile(pattern = "anchor-hive-")
dir.create(hive_path)

population <- data.table(
  person_id  = c("1", "2"),
  index_date = as.Date(c("2024-01-01", "2024-01-01"))
)
metadata <- data.table(
  variable_id = "flu_vaccine_recent",
  concept_id  = "FLU_VAX",
  constructor = "GENERIC",
  selector    = "LATEST",
  start_offset = -365L,
  end_offset   = 0L
)
concepts <- data.table(
  person_id = "1", concept_id = "FLU_VAX",
  date = as.Date("2023-10-01"), value = "TRUE"
)

anchor(
  population, metadata, concepts,
  anchor_col = "index_date", anchor_hive_path = hive_path
)
get_anchor_result(metadata, hive_path, result_shape = "long")[
  , .(person_id, T0, value, date)
]
#>    person_id         T0  value       date
#> 1:         1 2024-01-01   TRUE 2023-10-01
```

## Extending beyond a fixed offset

`GENERIC` covers "the window is always N days around one anchor date." If a study variable instead needs a window built from a *recurring* event (multiple pregnancies, repeated hospitalizations, ...), that's what the episode-based constructors in [Tutorial_pregnancy_windows.md](Tutorial_pregnancy_windows.md) are for, same `population`/`metadata`/`concepts`/`anchor()` workflow, just a different `constructor` value and one extra population column. For anything else entirely bespoke, `make_constructor()` lets you build and register a new window shape without editing anchoR itself.
