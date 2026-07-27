# Concepts input

`concepts` contains the event records queried by anchoR. Each row represents one recorded value for a person, concept, and date.

## Required columns

| column | type | meaning |
| --- | --- | --- |
| `person_id` | character-compatible | Person identifier joined to `population$person_id`. |
| `concept_id` | character-compatible | Identifier matched directly to `metadata$concept_id`. |
| `date` | `Date` or date-compatible | Event date tested against inclusive window boundaries. |
| `value` | any scalar type | Event value returned or interpreted by the selector. It is normalized to character for selector output. |

The source may contain additional columns. anchoR selects only these four fields for selector queries.

## Supported sources

`concepts` may be:

- an in-memory `data.frame` or `data.table`;
- a DuckDB database file containing a table named `concept_table`; or
- one or more parquet files, glob patterns, or directories.

For parquet and DuckDB sources, `date` is cast to DuckDB `DATE`. Parquet directories may use Hive partitioning such as `concept_id=FLU_VAX/`; only concept IDs requested by metadata are loaded.

## Example

```r
concepts <- data.table::data.table(
  person_id = c("1", "1", "2"),
  concept_id = c("FLU_VAX", "BMI", "BMI"),
  date = as.Date(c("2023-10-01", "2023-11-01", "2023-11-01")),
  value = c("TRUE", "22.5", "30")
)
```

The same person may have multiple rows for one concept, and records may fall inside or outside a requested window. Selectors decide how matches are reduced.

## Important semantics

- Window bounds are inclusive: matching SQL uses `date BETWEEN window_start AND window_end`.
- `LATEST` and `EARLIEST` select by date. If records tie on the selected date, the lexicographically largest normalized character `value` breaks the tie, producing one row.
- `RANGE_COUNT` casts `value` to a number and counts values within inclusive `range_min`/`range_max` bounds.
- Boolean presence concepts commonly use `"TRUE"`, but anchoR does not require that convention.

See [definitions/Selector.md](definitions/Selector.md) for the complete selector contract.
