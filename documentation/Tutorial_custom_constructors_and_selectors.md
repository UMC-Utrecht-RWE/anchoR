# Custom Constructors and Selectors

anchoR ships a fixed set of window 'shapes' (`constructor` values like `GENERIC`, see [Tutorial_standard_windows](Tutorial_standard_windows.md), or `IN_PRIOR_PREG`/`SINCE_START_CURRENT_PREG`/etc., see [Tutorial_pregnancy_windows](Tutorial_pregnancy_windows.md)) and a fixed set of window-reduction rules (`selector` values like `LATEST`, `COUNT`, `RANGE_COUNT`, compared in the `selector-cookbook` vignette). Most study variables fit one of those.

When one doesn't, you don't need to edit anchoR itself. `make_constructor()` and `make_selector()` let you define your own `constructor`/`selector` value from your own script, and `anchor()` picks it up automatically, the same way it resolves a built-in one.

## The shared idea: metadata points at a name, anchoR resolves it

Every row in `metadata` names a `constructor` and a `selector`. anchoR resolves each name in two steps, always in the same order:

1. Look for a built-in with that name (`GENERIC`, `LATEST`, ... shipped inside the package).
2. If none exists, look for something *you* defined, by a fixed naming convention, in your R session's global environment.
3. If neither exists, fail immediately, before touching the database, with an error naming exactly what it looked for.

This is why nothing needs to be registered or passed as an extra argument to `anchor()`: define the function/object under the right name at the top level of your script, and it's visible the moment `anchor()` runs.

The two mechanisms differ in one important way, because a constructor and a selector do fundamentally different jobs:

|                   | constructor                                                                                         | selector                                                                   |
| ----------------- | --------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| what it is        | a plain R function over a `data.table`                                                              | a SQL `SELECT` statement                                                   |
| where it runs     | in R, before any database work                                                                      | inside anchoR's DuckDB connection                                          |
| input             | one row per person-variable-window, with metadata columns (`anchor_start_col`, `start_offset`, ...) | `population_windows` (aliased `w`) joined against `concepts` (aliased `c`) |
| must produce      | the same rows back, plus `window_start`/`window_end`                                                | `person_id`, `T0`, `variable_id`, `window_name`, `value`, `date`, `n`      |
| naming convention | `<CONSTRUCTOR>` metadata value &rarr; `<constructor>_window` function                               | `<SELECTOR>` metadata value &rarr; `<selector>_selector` object            |
| built with        | `make_constructor()`                                                                                | `make_selector()`                                                          |

## Custom constructors: `make_constructor()`

A constructor decides *where a window starts and ends*. Use one when the built-in `GENERIC` (fixed offset around an anchor date) and the pregnancy-episode constructors don't describe your boundary.

`make_constructor()` takes the function that does the actual work (`transform_fn`), the metadata columns it needs (`required_cols`), and an optional extra validation function (`check_fn`). It returns a function that checks `required_cols` are present, then calls `transform_fn`.

```r
FUN <- make_constructor(
  transform_fn  = function(window_dt) { ... },  # must return window_dt with window_start/window_end added
  required_cols = c("anchor_start_col", "anchor_end_col", "start_offset", "end_offset"),
  check_fn      = NULL   # optional extra validation, run before required_cols is checked
)
```

### Worked example: follow-up capped at 180 days

Say a variable should start at `T0` and end at the earlier of a person's recorded follow-up date or 180 days after `T0`, whichever comes first. Metadata value `CAPPED_FOLLOWUP` needs to resolve to a function named `capped_followup_window`:

```r
library(data.table)

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

`window_dt` arrives with anchoR's canonical metadata columns already attached, use them (`anchor_start_col`, `start_offset`, ...) instead of inventing new ones, since normalization only keeps anchoR's known metadata fields (see the caveat at the end of this page).

```r
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

define_window(population, metadata, constructor_env = environment())[
  , .(person_id, window_start, window_end, window_valid)
]
#>    person_id window_start window_end window_valid
#> 1:         1   2024-01-01 2024-03-01         TRUE
#> 2:         2   2024-01-01 2024-06-29         TRUE
```

Person 1 is capped by their recorded `follow_up_end` (`2024-03-01`, earlier than `T0 + 180`); person 2's `follow_up_end` is far in the future, so they're capped at `T0 + 180 = 2024-06-29` instead. `define_window(..., constructor_env = environment())` is a good way to check boundaries like this before running concepts through them, `constructor_env` only matters for this kind of isolated check; `anchor()` always resolves from the global environment (see below).

```r
concepts <- data.table(
  person_id = c("1", "2", "2"),
  concept_id = "EVENT",
  date = as.Date(c("2024-02-01", "2024-05-01", "2024-08-01")),
  value = "TRUE"
)
hive <- tempfile("custom-hive-")

anchor(population, metadata, concepts, anchor_hive_path = hive)
get_anchor_result(metadata, hive, result_shape = "long")
#>    person_id         T0            variable_id window_name       date  value
#> 1:         1 2024-01-01 first_follow_up_event        <NA> 2024-02-01   TRUE
#> 2:         2 2024-01-01 first_follow_up_event        <NA> 2024-05-01   TRUE
```

Person 2's `2024-08-01` event falls outside their capped window (`2024-06-29`), so `EARLIEST` matches their in-window `2024-05-01` event instead. No extra step was needed to make `anchor()` find `capped_followup_window`, it just has to exist in the global environment (the top level of your script) when `anchor()` runs.

## Custom selectors: `make_selector()`

A selector decides *which concept rows inside a window become the anchored value*. Use one when none of `LATEST`, `EARLIEST`, `COUNT`, `COUNT_MORE_THAN_1`, `RANGE_COUNT`, or `ALL` reduce a window's matches the way you need (see the `selector-cookbook` vignette for what those do).

A selector is not an R function, it's a SQL `SELECT` statement, run directly inside the DuckDB connection `anchor()` opens. Inside that query, `population_windows` (aliased `w`) and `concepts` (aliased `c`) are already loaded. Your query must:

- Project exactly these columns: `person_id`, `T0`, `variable_id`, `window_name`, `value`, `date`, `n`.
- Filter on `w.selector = '<NAME>'`, so it only claims the metadata rows routed to it.
- Join `concepts AS c` to `population_windows AS w` on `person_id`, `concept_id`, and `c.date BETWEEN w.window_start AND w.window_end`, the same join every built-in selector template uses.

`make_selector()` checks `selector_query` is a non-empty string that selects every required column by name; it can't check the SQL itself, since `population_windows`/`concepts` only exist once `anchor()` actually opens a connection. A typo surfaces as a database error the first time the selector runs, not when you define it.

```r
FUN <- make_selector(selector_query)  # a single SQL SELECT statement, as a string
```

### Worked example: highest value in the window

Say a lab variable should report the *highest* numeric value recorded in the window, not the latest or a count. Metadata value `MAX_VALUE` needs to resolve to an object named `max_value_selector`:

```r
max_value_selector <- make_selector("
  SELECT
      w.person_id,
      w.T0,
      w.variable_id,
      w.window_name,
      CAST(MAX(TRY_CAST(c.value AS DOUBLE)) AS VARCHAR) AS value,
      MAX(c.date) AS date,
      COUNT(*) AS n
  FROM population_windows AS w
  INNER JOIN concepts AS c
      ON c.person_id = w.person_id
     AND c.concept_id = w.concept_id
     AND c.date BETWEEN w.window_start AND w.window_end
  WHERE w.selector = 'MAX_VALUE'
  GROUP BY w.person_id, w.T0, w.variable_id, w.window_name
")

population <- data.table(
  person_id = c("1", "2", "3"),
  T0 = as.Date(c("2024-01-01", "2024-01-15", "2024-02-01"))
)
metadata <- data.table(
  variable_id = "highest_lab_value",
  concept_id = "LAB_X",
  constructor = "GENERIC",
  selector = "MAX_VALUE",
  start_offset = -90L,
  end_offset = 0L
)
concepts <- data.table(
  person_id = c("1", "1", "2"),
  concept_id = "LAB_X",
  date = as.Date(c("2023-11-01", "2023-12-15", "2023-12-20")),
  value = c("4.2", "7.8", "3.1")
)

hive <- tempfile("selector-hive-")
anchor(population, metadata, concepts, anchor_hive_path = hive)
get_anchor_result(metadata, hive, result_shape = "long")[, .(person_id, T0, value, date)]
#>    person_id         T0  value       date
#> 1:         1 2024-01-01    7.8 2023-12-15
#> 2:         2 2024-01-15    3.1 2023-12-20
```

Person 1 has two `LAB_X` records in their window (`4.2` and `7.8`), and gets the higher one; person 2 has one match; person 3 has none, so they produce no row at all rather than a row with a missing value, the same "silent gap, not an error" behavior every selector has when nothing matches (see the `selector-cookbook` vignette).

### If the name doesn't resolve to anything

Metadata referencing a `selector` (or `constructor`) that's neither built in nor defined where anchoR looks fails fast, before any SQL runs:

```r
metadata[, selector := "TOTALLY_MADE_UP"]
anchor(population, metadata, concepts, anchor_hive_path = hive)
#> Error: Unsupported selector(s) in `metadata`: TOTALLY_MADE_UP Available
#> selectors in package `anchoR`: ALL, COUNT, COUNT_MORE_THAN_1, EARLIEST,
#> LATEST, RANGE_COUNT. Use `filter_supported_metadata()` if you want to drop
#> unsupported rows before calling `anchor()`.
```

That message only lists the *built-in* selectors by name, a custom one is still accepted, this is just where the error tells you what it already checked before giving up.

## Caveats that apply to both

- **Built-in and custom rows can coexist** in one `metadata` table. Nothing forces every variable to use the same kind of constructor or selector.
- **Definitions must be visible from the global environment** when `anchor()` runs, define them at the top level of your script (not inside a function, unless you explicitly export them to `globalenv()`).
- **Metadata normalization only keeps anchoR's canonical fields.** If your constructor needs extra per-variable configuration beyond `start_offset`/`end_offset`/`anchor_start_col`/etc., encode it using those canonical columns or handle it in preprocessing before calling `anchor()`, arbitrary extra metadata columns don't survive validation.
- **A selector's SQL is only checked at run time.** Test a new selector against a small `population`/`metadata`/`concepts` example, the way both worked examples above do, before pointing it at a real dataset.

## See also

- `vignette("custom-constructors", package = "anchoR")` and `vignette("custom-selectors", package = "anchoR")`, the installed-package versions of the two worked examples above.
- `vignette("selector-cookbook", package = "anchoR")` for what the built-in selectors do, useful for checking whether you actually need a custom one.
- [Tutorial_standard_windows](Tutorial_standard_windows.md) and [Tutorial_pregnancy_windows](Tutorial_pregnancy_windows.md) for the built-in constructors.
