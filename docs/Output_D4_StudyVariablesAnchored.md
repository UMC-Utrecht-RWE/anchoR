# OUTPUT

| Table name                | anchored result / `D4_StudyVariablesAnchored` |
| ------------------------- | --------------------------------------------- |
| Description               | Output of `anchoR`. Concept records are filtered to metadata-defined windows and collapsed with the selected selector. |
| Source                    | Concepts source + population + metadata + `anchor_col`. |
| Content                   | Anchored variable values returned in narrow or wide format by `get_anchor_result()`. |
| Population                | Subset of the input population with at least one anchored result among the requested variables. |
| Unit of Observation (UoO) | In narrow format: one row per matched `person_id x T0 x variable_id x window_name`. In wide format: one row per `person_id x T0` combination present in the anchored result. |

# NARROW OUTPUT

The long-format public result is returned by:

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
| `T0` | Date | Anchor value used during output. The current implementation writes the anchor column to output as `T0`. |
| `variable_id` | chr | Variable identifier from metadata. |
| `window_name` | chr | Window label from metadata. |
| `date` | Date | Anchored event date returned by the selector. |
| `value` | chr | Anchored value returned by the selector. |

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

This yields one row per `person_id x T0` combination present in the anchored
result and creates columns of the form:

- `value_<variable_id>`
- `date_<variable_id>`

Codebook:

| column | format | description |
| ------ | ------ | ----------- |
| `person_id` | chr | Person identifier from the population input. |
| `T0` | Date | Anchor value written to output. |
| `value_<variable_id>` | chr | Anchored value for the corresponding study variable. `NA` means that variable did not produce an anchored result for that row. |
| `date_<variable_id>` | Date | Anchored event date for the corresponding study variable. `NA` means that variable did not produce an anchored result for that row. |

Example wide output shape:

| `person_id` | `T0` | `value_COD_ACUTE_ENCEPHALOMYELITIS` | `value_COD_GBSYNDROME` | `value_COD_NARCOLEPSY` | `value_SV_OBESITY` | `date_COD_ACUTE_ENCEPHALOMYELITIS` | `date_COD_GBSYNDROME` | `date_COD_NARCOLEPSY` | `date_SV_OBESITY` |
| :---------- | :--- | :---------------------------------- | :--------------------- | :--------------------- | :----------------- | :--------------------------------- | :-------------------- | :-------------------- | :---------------- |
| `#ID-000000853#` | `2022-10-12` | `TRUE` | `NA` | `NA` | `NA` | `2022-08-07` | `NA` | `NA` | `NA` |
| `#ID-000001103#` | `2023-03-21` | `NA` | `NA` | `NA` | `TRUE` | `NA` | `NA` | `NA` | `2022-12-09` |
| `#ID-000001161#` | `2022-10-12` | `NA` | `NA` | `TRUE` | `NA` | `NA` | `NA` | `2022-08-20` | `NA` |

Current behavior:

- `NA` in a `value_<variable_id>` or `date_<variable_id>` column means that
  variable did not produce an anchored result for that `person_id x T0` row.
- Rows for which none of the requested variables produced an anchored result
  are absent from the wide result.
- In current `data.table` output, the result is keyed by `person_id` and `T0`.
- `window_name` is not retained in wide output.

Wide output is appropriate when all of the following are true:

- `metadata$variable_id` is unique in the requested metadata
- the anchored result contains no duplicate `person_id + T0 + variable_id`
  combinations

If the same `variable_id` is repeated for several windows, wide output is
ambiguous and narrow output is preferred.

# NOTES

- The current result returned by `get_anchor_result()` does not carry through
  `match_id`, `boot_id`, `group`, or other extra columns from the population
  input.
- The current result uses `window_name` rather than `window`.
- The output column is currently named `T0` even when a different `anchor_col`
  was used during anchoring.
- `keep_all = TRUE` does not currently force a full persisted design matrix in
  normal runs; unmatched rows are still absent from the parquet-backed result.
