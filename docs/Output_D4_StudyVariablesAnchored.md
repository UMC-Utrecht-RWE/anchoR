# METADATA

| Table name                | D4\_StudyVariablesAnchored                                                                                                                   |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Output of AnchoR. Long format database with information of each covariate, in each window, for each combination of person id and time anchor |
| Source                    | concepts database, data table of person id and time anchors (population), metadata, anchor column                                            |
| Step                      |                                                                                                                                              |
| Content                   | Covariate values anchored to dates based on time windows and count-value functions                                                           |
| Population                | As in population                                                                                                                             |
| Unit of Observation (UoO) | person_id x time-anchor x window x study variable                                                                                            |

# CODEBOOK

| variable_in_output | variable(s) needed                                                                   | retrieved | computed | format | rule_of_calculation | description | vocabulary              |
| ------------------ | ------------------------------------------------------------------------------------ | --------- | -------- | ------ | ------------------- | ----------- | ----------------------- |
| person_id          | population$person_id                                                                 | x         |          | chr    |                     |             |                         |
| anchor_type        | metadata anchor value                                                                |           |          | chr    |                     |             |                         |
| anchor_date        | metadata anchor, corresponding population column                                     |           | x        | date   |                     |             |                         |
| variable_id        | variable_id from metadata                                                            |           | x        | chr    |                     |             | see below [Parameters]  |
| window             | metadata window                                                                      |           |          |        |                     |             |                         |
| value              | value of the covariate; may be date, boolean, integer, factor as defined by metadata |           | x        | chr    |                     |             | DATE, BOOL, INT, FACTOR |

# EXAMPLE

| **person_id** | **anchor_type** | **anchor_date** | variable_id                 | window    | **value**  |
| :------------ | :-------------- | :-------------- | :-------------------------- | :-------- | :--------- |
| 1             | T0              | 2024-09-01      | COD_ACUTE_ASEPTIC_ARTHRITIS | lookback  | FALSE      |
| 1             | T0              | 2024-09-01      | COD_ACUTE_ASEPTIC_ARTHRITIS | induction | NA         |
| 1             | T0              | 2024-09-01      | COD_ACUTE_ASEPTIC_ARTHRITIS | risk      | 2024-09-05 |
| 1             | T0              | 2024-09-01      | SV_OBESITY                  | lookback  | TRUE       |
