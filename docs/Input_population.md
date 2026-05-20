# METADATA

| Table name                | population                                                                                                  |
| ------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Description               | Input of AnchoR. Table with a list of unique unit identifiers, typically person_id and anchor dates / types |
| Source                    | user specified; may come from a cohort on which the time anchor or time anchors have been selected          |
| Step                      |                                                                                                             |
| Content                   |                                                                                                             |
| Population                | study units (person ids and time anchors)                                                                   |
| Unit of Observation (UoO) | person_id x time-anchor x window x study variable                                                           |

# CODEBOOK

| variable_in_output | variable(s) needed                                                                   | retrieved | computed | format | rule_of_calculation | description | vocabulary              |
| ------------------ | ------------------------------------------------------------------------------------ | --------- | -------- | ------ | ------------------- | ----------- | ----------------------- |
| person_id          | population$person_id                                                                 | x         |          | chr    |                     |             |                         |
| anchor_type        | metadata anchor value                                                                |           |          | chr    |                     |             |                         |
| anchor_date        | metadata anchor, corresponding population column                                     |           | x        | date   |                     |             |                         |



# EXAMPLE

Note, when multiple 

| **person_id** | **anchor_type**   | **anchor_date** |
| :------------ | :---------------- | :-------------- |
| 1             | T0                | 2024-09-01      |
| 1             | start_eligibility | 2023-08-12      |


