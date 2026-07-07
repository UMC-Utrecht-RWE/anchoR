# [[Population|POPULATION]]

| Table name                | population                                                                                                                                               |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Input population for `anchoR`. In the current workflow this is a wide cohort / matching table rather than a long table of anchor types.                  |
| Source                    | User-specified cohort or matched population object.                                                                                                      |
| Content                   | Person identifiers, anchor dates, matching identifiers, cohort labels, and optionally pre-computed covariates or other study variables.                  |
| Population                | Study units to be anchored.                                                                                                                              |
| Unit of Observation (UoO) | Typically one row per anchored study unit. In the current workflow this is often one row per `person_id x match_id x boot_id` with a corresponding `T0`. |

# CODEBOOK

The current population object shown in `trial_run.R` contains the following core columns.

| column      | format | description                                                         |
| ----------- | ------ | ------------------------------------------------------------------- |
| `person_id` | chr    | Person identifier used to join against the concepts source.         |
| `T0`        | Date   | Main anchor date in the current workflow, when `anchor_col = "T0"`. |

# CURRENT USAGE

For the core anchoring step, `anchoR` only requires:

- `person_id`
- the anchor column supplied through `anchor_col`, currently usually `T0`

Additional date columns may also be used if metadata includes `anchor_start_col` and/or `anchor_end_col`.

The package does **not** currently expect a long population table with columns like `anchor_type` and `anchor_date`. The current workflow uses a wide table with one or more anchor-related date columns.

# EXAMPLE

Example rows matching the current population structure:

| `person_id`      | `match_id` | `boot_id` | `group`     | `T0`         | `matching_status_start` | `matching_status_end` |
| :--------------- | ---------: | --------: | :---------- | :----------- | :---------------------- | :-------------------- |
| `#ID-000000003#` |      `932` |       `0` | `CONTROL`   | `2022-10-06` | `2022-10-05`            | `2023-02-13`          |
| `#ID-000000004#` |     `1285` |       `0` | `EXPOSED`   | `2022-12-21` | `2022-12-21`            | `2022-12-21`          |
| `#ID-000000012#` |     `1431` |       `0` | `UNMATCHED` | `2023-05-15` | `2023-05-15`            | `2023-05-15`          |

The actual population object can contain many more columns, for example:

- matching variables
- demographic descriptors
- pre-computed study variables such as `SV_SEX`, `SV_REGION`, `SV_PREG_STATUS`
- study dates such as `SV_PREG_START_DATE`

# NOTES

- Extra population columns are allowed and may be useful during window construction.
- The current `get_anchor_result()` output does not automatically carry through columns such as `match_id`, `boot_id`, or `group`.
- If the same `person_id` appears in multiple population rows with the same `T0`, that distinction is not preserved in the current public result shape.
