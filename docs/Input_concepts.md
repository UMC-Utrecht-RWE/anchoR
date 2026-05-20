## Metadata

| Table name                | concept_table (in D3_concepts.db)                                                                                                                                                                                   |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Database with a table per concept. Concepts are records (dates with optionally values) per person.                                                                                                                  |
| Source                    | user supplied                                                                                                                                                                                                       |
| Step                      |                                                                                                                                                                                                                     |
| Content                   |                                                                                                                                                                                                                     |
| Population                |                                                                                                                                                                                                                     |
| Unit of Observation (UoO) | All records that can be categorized in at least on concept_id. Thus, we have one row per record categorized in one or more concept ids (it is possible that the same record is categorized in different concepts).  |

## Codebook

| variable_in_output | variable(s) needed                         | format | rule_of_calculation  | description                                                                                                                                                                   | vocabulary         |
| ------------------ | ------------------------------------------ | ------ | -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------ |
| person_id          |                                            | string |                      | unique person identifier                                                                                                                                                      |                    |
| concept_id         |                                            | string | see processing steps | Concept Name/Description                                                                                                                                                      |                    |
| date               |                                            | date   |                      | The date in which the record is identified                                                                                                                                    |                    |
| value              | dap_specific_concept_map:keep_value_column | string | see processing steps | Value takes the numeric value for numeric concepts (weight, laboratory values, …), TRUE for concepts defined from the presence of the record and the CAT for categorical data | INT,TRUE/FALSE,CAT |


## EXAMPLE


| **person_id** | concept_id        | date       | value |
| :------------ | :---------------- | :--------- | ----- |
| 1             | M_ARTASEPTIC_AESI | 2020-01-01 | TRUE  |
| 1             | M_ARTASEPTIC_AESI | 2024-09-05 | TRUE  |
| 1             | M_ARTASEPTIC_AESI | 2026-02-03 | TRUE  |
| 1             | L_OBESITY_COV     | 2024-07-02 | TRUE  |

