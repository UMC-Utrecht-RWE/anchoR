# Anchored output

`anchor()` writes sparse selector results to a parquet Hive partitioned by `variable_id`. `get_anchor_result()` reads selected variables and returns either long or wide output.

The persisted anchor field is always named `T0`, even when anchoring used a differently named `anchor_col`.

## Long output

```r
get_anchor_result(metadata, anchor_hive_path, result_shape = "long")
```

| column | type | meaning |
| --- | --- | --- |
| `person_id` | character | Person identifier. |
| `T0` | `Date` | Anchor date used for the output row. |
| `variable_id` | character | Metadata variable identifier. |
| `window_name` | character | Metadata window label, possibly `NA`. |
| `date` | `Date` | Date selected by the selector. |
| `value` | character | Value or aggregate returned by the selector. |

Long output is sparse: a window with no matching concept record contributes no row. All built-in selectors except `ALL` return at most one row per key.

Passing `population` affects only wide output. It does not backfill or filter long output.

## Wide output

With the defaults (`cast_window = FALSE`, `only_date = FALSE`):

```r
get_anchor_result(
  metadata,
  anchor_hive_path,
  population = population,
  result_shape = "wide"
)
```

The row key is `person_id + T0 + window_name`; columns are `value_<variable_id>` and `date_<variable_id>`.

With `cast_window = TRUE`, the row key is `person_id + T0`, and window names move into columns: `value_<window_name>_<variable_id>` and `date_<window_name>_<variable_id>`.

With `only_date = TRUE`, value columns are omitted and the `date_` prefix is also omitted by the current implementation. Columns are `<variable_id>` or `<window_name>_<variable_id>`.

### Population completion

When `population` is supplied, wide output is restricted to its `person_id/T0` keys, missing keys are backfilled, and additional population columns are reattached. Without `population`, only keys found in persisted selector results can appear.

For `cast_window = FALSE`, population completion produces one row per known population key and requested/discovered window name—not necessarily exactly one row per population member.

### Ambiguous wide results

Wide output stops when anchored data contains more than one row for a `person_id + T0 + window_name + variable_id` cell. This normally occurs with `ALL`. Use `result_shape = "long"` rather than allowing an arbitrary aggregation.

Repeating a `variable_id` for distinct `window_name` values is supported and is not by itself ambiguous.

### Missing-value imputation

`impute_missing = TRUE` applies only to wide value columns. Metadata must include:

- `variable_id`;
- `is_expected_missing`; and
- `variable_type`.

Rows with `is_expected_missing = TRUE` remain missing. Other boolean types (`TF`, `BOOL`, `BOOLEAN`, `LOGICAL`) are imputed to `FALSE`; categorical types (`CAT`, `FACTOR`) are imputed to `0`. Dates and other variable types are not imputed. When required metadata fields are only partly supplied, anchoR warns and skips imputation.

## Empty and sparse hives

Recomputing a variable replaces its partition. If it produces no matches, its old partition is removed. `get_anchor_result()` currently requires the hive to contain readable parquet data; a completely empty hive raises a DuckDB `read_parquet()` error rather than returning an empty table. Pipelines should treat this case explicitly.

See [get_anchor_result_walkthrough.md](get_anchor_result_walkthrough.md) for implementation detail and [definitions/Wide Output.md](<definitions/Wide Output.md>) for a compact definition.
