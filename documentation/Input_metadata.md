# [METADATA](definitions/Metadata.md)

| Table name                | study_variables / windows_metadata                                                                                                                                                         |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Description               | Input metadata file for `anchoR`. In the current workflow this is a wide study-variable table with one row per variable-window specification.                                              |
| Source                    | User-supplied. In practice this often comes from BRIDGE `study_variables` metadata, optionally extended with extra window rows for AESIs, censoring variables, or other follow-up windows. |
| Content                   | Variable definitions, window definitions, selectors, and descriptive study metadata.                                                                                                       |
| Population                | Study variables e.g.:`study_variable.csv`.                                                                                                                                                 |
| Unit of Observation (UoO) | One row per `variable_id x window_name` definition. In a single-window setup this is often just one row per `variable_id`.                                                                 |

# CODEBOOK

Mandatory columns are the following:

| column            | format    | description                                                                                                                                                                                                                     |
| ----------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `variable_id`   | chr       | Name of the study variable. This becomes the output variable identifier. Repeat `variable_id` across rows to define multiple windows for the same variable.                                                                     |
| `concept_id`    | chr       | Concept identifier queried in the concepts source. May be missing for variables that are handled upstream or are not directly anchorable from the concepts table.                                                               |
| `start_offset`  | num       | Start of the anchoring window relative to the anchor date. In some source metadata these values may be fractional (for example `-54750.5`); `anchoR` currently coerces offsets with `as.integer()` during normalization. |
| `end_offset`    | int / num | End of the anchoring window relative to the anchor date.                                                                                                                                                                        |
| `window_name`   | chr       | Label of the window, for example `lookback`, `risk`, `induction`, `control`.                                                                                                                                                    |
| `constructor`   | chr       | Name of the window-construction function. In the current metadata this is typically `GENERIC`.                                                                                                                                  |
| `selector`      | chr       | Rule used to collapse one or more matching concept rows inside the window, for example `LATEST`, `EARLIEST`, `COUNT`, `RANGE_COUNT`.                                                                                            |

> `start_offset`/`end_offset` are the only names `anchoR` accepts for this column -- unlike some other columns below, there is no alias. If your source metadata (e.g. a BRIDGE-derived `study_variables.csv`) still uses `start_look_back`/`end_look_back` for this purpose, rename those columns to `start_offset`/`end_offset` before calling `anchor()`; `start_look_back`/`end_look_back` now name a different, unrelated column (see below).

Optional columns supported by the package, even when absent from the current metadata object:

| column               | format | description                                                                                                                                                                          |
| -------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `anchor_date_start`  | chr    | Population column used as the start anchor for the window. If missing, `anchoR` uses the `anchor_col` argument, typically `T0`.                                                     |
| `anchor_date_end`    | chr    | Population column used as the end anchor for the window. If missing, `anchoR` uses the `anchor_col` argument.                                                                       |
| `range_min`          | num    | Lower bound used by `RANGE_COUNT`.                                                                                                                                                   |
| `range_max`          | num    | Upper bound used by `RANGE_COUNT`.                                                                                                                                                   |
| `start_look_back`    | num    | `IN_PRIOR_PREG` only: restricts which prior episodes are eligible to those overlapping `[anchor + start_look_back, anchor + end_look_back]`. NA (the default) applies no filter. See [IN_PRIOR_PREG](definitions/IN_PRIOR_PREG.md). |
| `end_look_back`      | num    | `IN_PRIOR_PREG` only, paired with `start_look_back` above.                                                                                                                            |


Everything else in the current metadata object is descriptive or study-management metadata and can remain in the table without affecting the core anchoring step.

If `anchor_date_start` and `anchor_date_end` are not present, the metadata is interpreted relative to the `anchor_col` argument supplied to `anchor()` or `anchor_by_variable()`. In the current workflow that anchor is usually `T0`.

# EXAMPLE

Example rows matching the current metadata structure:


| variable_id                 | concept_id        | label                                | anchor | window    | start | end  | date_extraction_func | data_type |
| :-------------------------- | :---------------- | :----------------------------------- | :----- | :-------- | :---- | :--- | :------------------- | :-------- |
| COD_ACUTE_ASEPTIC_ARTHRITIS | M_ARTASEPTIC_AESI | Acute aseptic arthritis              | T0     | lookback  | -365  | -1   | LATEST               | BOOL      |
| COD_ACUTE_ASEPTIC_ARTHRITIS | M_ARTASEPTIC_AESI | Acute aseptic arthritis              | T0     | induction | 0     | 0    | EARLIEST             | DATE      |
| COD_ACUTE_ASEPTIC_ARTHRITIS | M_ARTASEPTIC_AESI | Acute aseptic arthritis              | T0     | risk      | 1     | 42   | EARLIEST             | DATE      |
| SV_OBESITY                  | L_OBESITY_COV     | Obesity diagnosis or obesity surgery | T0     | lookback  | -1095 | 0    | LATEST               | BOOL      |


# MULTIPLE WINDOWS

To define multiple windows for the same study variable, add multiple metadata rows with the same `variable_id` and `concept_id`, but different values in one or more of:

- `window_name`
- `window_start_offset`
- `window_end_offset`
- `selector`
- `window_definition`

Example:

| `variable_id`                 | `concept_id`        | `window_name` | `window_start_offset` | `window_end_offset` | `window_definition` | `selector` |
| :---------------------------- | :------------------ | :------------ | --------------------: | ------------------: | :------------------ | :--------- |
| `COD_ACUTE_ASEPTIC_ARTHRITIS` | `M_ARTASEPTIC_AESI` | `lookback`    |                `-365` |                `-1` | `GENERIC`           | `LATEST`   |
| `COD_ACUTE_ASEPTIC_ARTHRITIS` | `M_ARTASEPTIC_AESI` | `induction`   |                   `0` |                 `0` | `GENERIC`           | `EARLIEST` |
| `COD_ACUTE_ASEPTIC_ARTHRITIS` | `M_ARTASEPTIC_AESI` | `risk`        |                   `1` |                `42` | `GENERIC`           | `EARLIEST` |

# NOTES

- `selector` names can be filtered with `filter_supported_metadata()`.
- Rows with unsupported selectors are dropped by that helper.
- Rows with missing `concept_id` are still part of the source metadata, but they will not produce concept matches unless they are handled upstream or excluded before anchoring.
