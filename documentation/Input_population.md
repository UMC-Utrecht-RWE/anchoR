# Population input

`population` identifies the study units and supplies the dates used to construct their windows.

## Required columns

- `person_id`;
- the primary anchor column named by `anchor_col` (`T0` by default); and
- every additional anchor or episode column referenced by metadata.

The primary anchor may be a `Date` or a character vector in strict `YYYY-mm-dd` format. Additional anchor columns should be `Date` values. Missing dates produce invalid windows, which do not reach selector SQL.

## Shape and duplicate keys

The normal shape is one row per `person_id × anchor date`. A person may appear at several anchor dates.

Persisted anchored output is keyed by `person_id` and the normalized output column `T0`; distinctions between population rows sharing the same `person_id/T0` are not preserved by the hive. When `get_anchor_result(population = ...)` receives duplicate keys with conflicting extra columns, it warns and retains the first row for that key.

## Example

```r
population <- data.table::data.table(
  person_id = c("1", "2", "3"),
  T0 = as.Date(c("2024-01-01", "2024-01-01", "2024-06-01")),
  group = c("EXPOSED", "CONTROL", "CONTROL")
)
```

Extra columns are ignored while ordinary windows are constructed. If the same population is passed to `get_anchor_result()`, those columns are reattached to wide output.

## Alternative anchor columns

Metadata can select a different population column for individual rows through `anchor_start_col` and `anchor_end_col` (or legacy aliases `anchor_date_start` and `anchor_date_end`). The value `"T0"` is a symbolic placeholder for the `anchor_col` argument.

```r
population <- data.table::data.table(
  person_id = "1",
  index_date = as.Date("2024-01-01"),
  follow_up_end = as.Date("2024-12-31")
)

metadata <- data.table::data.table(
  variable_id = "follow_up_event",
  concept_id = "EVENT",
  constructor = "GENERIC",
  selector = "EARLIEST",
  start_offset = 0L,
  end_offset = 0L,
  anchor_start_col = "index_date",
  anchor_end_col = "follow_up_end"
)
```

Call `anchor(..., anchor_col = "index_date")`; persisted output still calls the primary anchor field `T0`.

Episode-based constructors additionally require a population list-column named by `metadata$event_col`. Each element must be a table containing `event_start` and `event_end`; see [Tutorial_pregnancy_windows.md](Tutorial_pregnancy_windows.md).
