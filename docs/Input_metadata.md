# METADATA

| Table name                | windows_metadata                                                                                                                                                  |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Description               | Input metadata file for AnchoR. Specifies per study variable the source concept, which                                                                            |
| Source                    | User-supplied. May be a combination of information from the BRIDGE study_variables metadata, and information about AESIs, censoring reasons from a study protocol |
| Step                      |                                                                                                                                                                   |
| Content                   | Specification of windows per study variable in which anchoring needs to occur                                                                                     |
| Population                | study variables                                                                                                                                                   |
| Unit of Observation (UoO) | study_variable x time-anchor x window                                                                                                                             |

# CODEBOOK

| variable_in_output  | variable(s) needed                                                                                                         | format | description | vocabulary                               |
| ------------------- | -------------------------------------------------------------------------------------------------------------------------- | ------ | ----------- | ---------------------------------------- |
| variable_id         | name of the study variable                                                                                                 | chr    |             |                                          |
| concept_id          | name of the source cnoncept                                                                                                | chr    |             |                                          |
| label               | character string description of the study variable                                                                         |        |             |                                          |
| anchor              | name of the time anchor; column in the population dataset                                                                  | chr    |             |                                          |
| window              | name of the window to be defined with start and end                                                                        | chr    |             | e.g., lookback, risk, control, induction |
| start               | start date of window, specified as numeric with respect to anchor                                                          | int    |             | see below [Parameters]                   |
| end                 | end date of window, specified as numeric with respect to anchor                                                            | int    |             |                                          |
| date_extraction_fun | function which defines how to assign the study variable a value based on the occurence of records within the target window | chr    |             | EARLIEST, LATEST                         |
| data_type           | what type of variable is created in the output                                                                             |        |             | DATE, BOOL, INT, FACTOR                  |


# EXAMPLE


| variable_id                 | concept_id        | label                                | anchor | window    | start | end | date_extraction_func | data_type |
| :-------------------------- | :---------------- | :----------------------------------- | :----- | :-------- | :---- | :-- | :------------------- | :-------- |
| COD_ACUTE_ASEPTIC_ARTHRITIS | M_ARTASEPTIC_AESI | Acute aseptic arthritis              | T0     | lookback  | -365  | -1  | LATEST               | BOOL      |
| COD_ACUTE_ASEPTIC_ARTHRITIS | M_ARTASEPTIC_AESI | Acute aseptic arthritis              | T0     | induction | 0     | 0   | EARLIEST             | DATE      |
| COD_ACUTE_ASEPTIC_ARTHRITIS | M_ARTASEPTIC_AESI | Acute aseptic arthritis              | T0     | risk      | 1     | 42  | EARLIEST             | DATE      |
| SV_OBESITY                  | L_OBESITY_COV     | Obesity diagnosis or obesity surgery | T0     | lookback  | -1095 | 0   | LATEST               | BOOL      |


