# [[Concepts|CONCEPTS]]

| Table name                | concepts /`concept_table` / parquet concept files                                                                                                                                           |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Input concepts source for`anchoR`. This contains the raw event records that are filtered to metadata-defined windows and collapsed with selectors such as `LATEST`, `EARLIEST`, or `COUNT`. |
| Source                    | User-supplied. In the current workflow this is often a parquet concept store such as`D3_CONCEPTS_parquet`, but the package also accepts an in-memory table or a DuckDB file.                |
| Content                   | One row per concept event, with a person identifier, concept identifier, event date, and value.                                                                                             |
| Population                | All concept records available for anchoring.                                                                                                                                                |
| Unit of Observation (UoO) | One row per`person_id x concept_id x date x value` record.                                                                                                                                  |

# CODEBOOK

The current concepts object shown in your results has the following columns.

| column       | format | description                                                                                                                |
| ------------ | ------ | -------------------------------------------------------------------------------------------------------------------------- |
| `person_id`  | chr    | Person identifier used to join concept events to the population input.                                                     |
| `concept_id` | chr    | Concept identifier matched against`metadata$concept_id`.                                                                   |
| `date`       | Date   | Event date used to determine whether a concept record falls inside the requested window.                                   |
| `value`      | chr    | Value associated with the concept event. In the current concepts output this is often`TRUE` for presence/absence concepts. |

# CURRENT USAGE

For the core anchoring step, `anchoR` currently expects concept data to expose
exactly these fields:

- `person_id`
- `concept_id`
- `date`
- `value`

These are the columns selected by `load_concepts_table()` before the selector
queries run.

The package accepts three concept source types:

- an in-memory `data.frame` or `data.table`
- a DuckDB file containing a table named `concept_table`
- parquet file path(s), including directories

In the current workflow shown in `trial_run.R`, concepts are commonly passed as
a parquet location such as:

```r
concepts <- "anchoR_input/D3_CONCEPTS_parquet"
```

# EXAMPLE

Example rows matching the current concepts structure:

| `person_id`      | `concept_id`     | `date`       | `value` |
| :--------------- | :--------------- | :----------- | :------ |
| `#ID-000001945#` | `B_COAGDEF_AESI` | `2022-12-09` | `TRUE`  |
| `#ID-000004163#` | `B_COAGDEF_AESI` | `2012-09-29` | `TRUE`  |
| `#ID-000007439#` | `B_COAGDEF_AESI` | `2010-10-31` | `TRUE`  |
| `#ID-000007439#` | `VP_VZV`         | `2022-10-04` | `TRUE`  |
| `#ID-000004377#` | `VP_VZV`         | `2023-08-20` | `TRUE`  |

# INTERPRETATION

In the current concepts table:

- `concept_id` identifies the event type
- `date` is the event date used for anchoring
- `value` is stored as character and is often `TRUE` for binary event concepts

The same person can have:

- multiple rows for the same `concept_id`
- rows for many different `concept_id` values
- events that occur both inside and outside the requested anchoring windows

# NOTES

- `metadata$concept_id` is matched directly against `concepts$concept_id`.
- For many binary concepts, `value = "TRUE"` is sufficient because presence of
  the record is what matters.
- If concepts are stored in DuckDB, the package expects a table named
  `concept_table`.
- If concepts are stored in parquet, the package reads them through DuckDB and
  casts `date` to `DATE`.
