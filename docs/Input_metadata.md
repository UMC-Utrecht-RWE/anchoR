# METADATA

| Table name                | study_variables / windows_metadata                                                                                                                                                         |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Description               | Input metadata file for `anchoR`. In the current workflow this is a wide study-variable table with one row per variable-window specification.                                              |
| Source                    | User-supplied. In practice this often comes from BRIDGE `study_variables` metadata, optionally extended with extra window rows for AESIs, censoring variables, or other follow-up windows. |
| Content                   | Variable definitions, window definitions, selectors, and descriptive study metadata.                                                                                                       |
| Population                | Study variables.                                                                                                                                                                           |
| Unit of Observation (UoO) | One row per `variable_id x window_name` definition. In a single-window setup this is often just one row per `variable_id`.                                                                 |

# CODEBOOK

The current metadata object used in `trial_run.R` contains the following
columns.

| column                 | format    | used by anchoR | description                                                                                                                                                                                                                     |
| ---------------------- | --------- | -------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `variable_id`          | chr       | yes            | Name of the study variable. This becomes the output variable identifier. Repeat `variable_id` across rows to define multiple windows for the same variable.                                                                     |
| `concept_id`           | chr       | yes            | Concept identifier queried in the concepts source. May be missing for variables that are handled upstream or are not directly anchorable from the concepts table.                                                               |
| `raw_concept`          | chr       | no             | Provenance / source-system label for the variable or concept.                                                                                                                                                                   |
| `exposure`             | lgl       | no             | Study metadata flag indicating whether the variable is an exposure.                                                                                                                                                             |
| `outcome`              | lgl       | no             | Study metadata flag indicating whether the variable is an outcome.                                                                                                                                                              |
| `covariate`            | lgl       | no             | Study metadata flag indicating whether the variable is used as a covariate.                                                                                                                                                     |
| `data_type`            | chr       | no             | Intended output type, for example `INT`, `BOOL`, `CHAR`, `FACTOR`. Useful for downstream interpretation; not currently enforced by core anchoring logic.                                                                        |
| `window_start_offset`  | num       | yes            | Start of the anchoring window relative to the anchor date. In the current source metadata these values may be fractional (for example `-54750.5`); `anchoR` currently coerces offsets with `as.integer()` during normalization. |
| `window_end_offset`    | int / num | yes            | End of the anchoring window relative to the anchor date.                                                                                                                                                                        |
| `window_name`          | chr       | yes            | Label of the window, for example `lookback`, `risk`, `induction`, `control`.                                                                                                                                                    |
| `window_definition`    | chr       | yes            | Name of the window-construction function. In the current metadata this is typically `GENERIC`.                                                                                                                                  |
| `selector`             | chr       | yes            | Rule used to collapse one or more matching concept rows inside the window, for example `LATEST`, `EARLIEST`, `COUNT`, `RANGE_COUNT`.                                                                                            |
| `Matching`             | lgl       | no             | Study metadata flag from the source workflow.                                                                                                                                                                                   |
| `variable_description` | chr       | no             | Human-readable variable label / description.                                                                                                                                                                                    |

Optional columns supported by the package, even when absent from the current metadata object:

| column             | format | description                                                                                                                     |
| ------------------ | ------ | ------------------------------------------------------------------------------------------------------------------------------- |
| `anchor_start_col` | chr    | Population column used as the start anchor for the window. If missing, `anchoR` uses the `anchor_col` argument, typically `T0`. |
| `anchor_end_col`   | chr    | Population column used as the end anchor for the window. If missing, `anchoR` uses the `anchor_col` argument.                   |
| `range_min`        | num    | Lower bound used by `RANGE_COUNT`.                                                                                              |
| `range_max`        | num    | Upper bound used by `RANGE_COUNT`.                                                                                              |

# CURRENT USAGE

The core anchoring functions currently rely on these columns:

- `variable_id`
- `concept_id`
- `window_start_offset`
- `window_end_offset`
- `window_name`
- `window_definition`
- `selector`

Everything else in the current metadata object is descriptive or study-management metadata and can remain in the table without affecting the core anchoring step.

If `anchor_start_col` and `anchor_end_col` are not present, the metadata is interpreted relative to the `anchor_col` argument supplied to `anchor()` or `anchor_by_variable()`. In the current workflow that anchor is usually `T0`.

# EXAMPLE

Example rows matching the current metadata structure:

| `variable_id` | `concept_id` | `raw_concept`          | `exposure` | `outcome` | `covariate` | `data_type` | `window_start_offset` | `window_end_offset` | `window_name` | `window_definition` | `selector` | `Matching` | `variable_description` |
| :------------ | :----------- | :--------------------- | :--------- | :-------- | :---------- | :---------- | --------------------: | ------------------: | :------------ | :------------------ | :--------- | :--------- | :--------------------- |
| `SV_AGE`      | `PP_AGE`     | `D3`                   | `FALSE`    | `FALSE`   | `TRUE`      | `INT`       |            `-54750.5` |                 `0` | `lookback`    | `GENERIC`           | `LATEST`   | `FALSE`    | `Age`                  |
| `SV_SEX`      | `PP_SEX`     | `D3`                   | `FALSE`    | `FALSE`   | `TRUE`      | `BOOL`      |            `-54750.0` |                 `0` | `lookback`    | `GENERIC`           | `LATEST`   | `TRUE`     | `Sex`                  |
| `SV_REGION`   | `PP_REGION`  | `dap_specific_concept` | `FALSE`    | `FALSE`   | `TRUE`      | `CHAR`      |                 `0.0` |                 `0` | `lookback`    | `GENERIC`           | `LATEST`   | `TRUE`     | `Geographic region`    |

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
