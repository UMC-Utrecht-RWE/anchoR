# Metadata input

`metadata` describes what to find, when to look for it, and how to reduce matching records. Its unit of observation is one `variable_id × window_name` specification. A variable may therefore appear on several rows when it has several windows.

## Required columns

| column | type | meaning |
| --- | --- | --- |
| `variable_id` | character | Output variable identifier. |
| `concept_id` | character | Value matched directly to `concepts$concept_id`. |
| `constructor` | character | Window rule, usually `GENERIC`; see [constructors](definitions/Constructor.md). |
| `selector` | character | Reduction rule such as `LATEST`, `COUNT`, or `ALL`; see [selectors](definitions/Selector.md). |
| `start_offset` | integer-like | Inclusive window-start offset in days. |
| `end_offset` | integer-like | Inclusive window-end offset in days. |

`start_offset` and `end_offset` are converted with `as.integer()`. Fractional values are truncated toward zero, so validate or round them before calling anchoR if fractions have scientific meaning.

## Optional columns and defaults

| column | default | meaning |
| --- | --- | --- |
| `window_name` | `NA_character_` | Distinguishes multiple windows for one variable. |
| `anchor_start_col` | `anchor_col` | Population column used as the start anchor. Alias: `anchor_date_start`. |
| `anchor_end_col` | `anchor_col` | Population column used as the end anchor. Alias: `anchor_date_end`. |
| `range_min`, `range_max` | `NA_real_` | Inclusive numeric bounds used by `RANGE_COUNT`. |
| `event_col` | `NA_character_` | Population list-column containing episodes for episode-based constructors. |
| `end_cap_offset` | `NA_real_` | Optional end cap for `IN_PRIOR_PREG`. |
| `start_look_back`, `end_look_back` | `NA_real_` | Optional episode-eligibility range used only by `IN_PRIOR_PREG`. |

`date_extraction_func` is accepted as a legacy alias for `selector`. The literal value `"T0"` in either anchor-column field is treated as a placeholder for the `anchor_col` argument.

No aliases exist for `start_offset`, `end_offset`, `window_name`, or `constructor`. In particular, `start`, `end`, `window_start_offset`, `window_end_offset`, and `window_definition` must be renamed before use.

## Canonical example

```r
metadata <- data.table::data.table(
  variable_id = c("recent_flu_vaccine", "recent_flu_vaccine"),
  concept_id = "FLU_VAX",
  constructor = "GENERIC",
  selector = c("LATEST", "EARLIEST"),
  window_name = c("one_year", "ten_years"),
  start_offset = c(-365L, -3650L),
  end_offset = 0L
)
```

This requests two independently labelled windows for the same variable. `anchor()` preserves both definitions in the hive through `window_name`.

## Legacy metadata migration

Older BRIDGE-derived files may use names such as these:

| legacy name | canonical anchoR name |
| --- | --- |
| `date_extraction_func` | `selector` (automatic alias) |
| `anchor_date_start` | `anchor_start_col` (automatic alias) |
| `anchor_date_end` | `anchor_end_col` (automatic alias) |
| `window` | `window_name` (rename explicitly) |
| `start`, `window_start_offset` | `start_offset` (rename explicitly) |
| `end`, `window_end_offset` | `end_offset` (rename explicitly) |
| `window_definition` | `constructor` (rename explicitly) |

For example:

```r
data.table::setnames(
  legacy_metadata,
  old = c("window", "start", "end", "window_definition"),
  new = c("window_name", "start_offset", "end_offset", "constructor"),
  skip_absent = TRUE
)
```

## Validation behavior

- Unsupported or missing selectors cause `anchor()` to stop. Use `filter_supported_metadata()` when deliberately dropping them is appropriate.
- Referenced anchor and episode columns must exist in `population`.
- Anchor columns should be `Date` values (or `YYYY-mm-dd` character values for the primary `anchor_col`).
- Rows with missing `concept_id` cannot match concept records and should normally be removed or handled upstream.
- Additional descriptive columns are allowed, but validation retains only the columns used by anchoR.

See [Tutorial_standard_windows.md](Tutorial_standard_windows.md) for ordinary windows and [Tutorial_pregnancy_windows.md](Tutorial_pregnancy_windows.md) for episode-based metadata.
