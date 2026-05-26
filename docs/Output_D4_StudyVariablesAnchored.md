# OUTPUT

| Table name                | anchored result / `D4_StudyVariablesAnchored` |
| ------------------------- | --------------------------------------------- |
| Description               | Output of `anchoR`. Concept records are filtered to metadata-defined windows and collapsed with the selected selector. |
| Source                    | Concepts source + population + metadata + `anchor_col`. |
| Content                   | Anchored variable values in narrow or wide format, depending on `get_anchor_result()`. |
| Population                | As in the input population. |
| Unit of Observation (UoO) | In narrow format: one row per matched `person_id x T0 x variable_id x window_name`. In wide format: one row per `person_id x T0`. |

# NARROW OUTPUT

The current long-format public result is returned by:

```r
get_anchor_result(
  metadata = metadata,
  anchor_hive_path = anchor_hive_path,
  result_shape = "narrow"
)
```

Codebook:

| column | format | description |
| ------ | ------ | ----------- |
| `person_id` | chr | Person identifier from the population input. |
| `T0` | Date | Value of the anchor column used during anchoring. In the current workflow this is usually `population$T0`. |
| `variable_id` | chr | Variable identifier from metadata. |
| `window_name` | chr | Window label from metadata. |
| `date` | Date | Anchored event date returned by the selector. |
| `value` | chr | Anchored value returned by the selector. |

Example:

| `person_id` | `T0` | `variable_id` | `window_name` | `date` | `value` |
| :---------- | :--- | :------------ | :------------ | :----- | :------ |
| `#ID-000000003#` | `2022-10-06` | `SV_SEX` | `lookback` | `2022-10-06` | `M` |
| `#ID-000000003#` | `2022-10-06` | `SV_REGION` | `lookback` | `2022-10-06` | `REG2` |
| `#ID-000000012#` | `2023-05-15` | `SV_PREG_STATUS` | `lookback` | `2023-05-15` | `TRUE` |

Current behavior:

- The narrow result is sparse.
- Rows with no matching concept record in the requested window are omitted.
- The public result includes `T0`, not a generic `anchor_type` / `anchor_date`
  pair.

# WIDE OUTPUT

Wide output is returned by:

```r
get_anchor_result(
  metadata = metadata,
  anchor_hive_path = anchor_hive_path,
  result_shape = "wide"
)
```

This yields one row per `person_id x T0` and creates columns of the form:

- `value_<variable_id>`
- `date_<variable_id>`

Wide output is appropriate when `metadata$variable_id` is unique in the result
set. If the same `variable_id` is repeated for several windows, wide output is
ambiguous and narrow output is preferred.

# NOTES

- The current result returned by `get_anchor_result()` does not carry through
  `match_id`, `boot_id`, `group`, or other extra columns from the population
  input.
- The current result uses `window_name` rather than `window`.
- When `anchor_col = "T0"`, the output column is named `T0`.
