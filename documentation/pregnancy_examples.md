## pregnancy_periods

| person_id | T0         |
| --------- | ---------- |
| 1         | 2021-04-02 |
| 1         | 2022-08-16 |
| 2         | 2022-08-16 |
| 3         | 2021-04-02 |

## pregnancy_metadata

| variable_id    | concept_id    | constructor              | selector | start_offset | end_offset | other_arguments                                                                                                                                                                | description_constructor                                                                                                                                   |
| -------------- | ------------- | ------------------------ | -------- | -----------: | ---------: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| preg_example_1 | gest_diabetes | IN_PRIOR_PREG            | LATEST   |            0 |    -3652.5 | start_pregnancy_offset = 0, end_pregnancy_offset = 0, start_preg_window = 'start_pregnancy + start_pregnancy_offset', end_preg_window = 'end_pregnancy + end_pregnancy_offset' | Look for records during (parts) of prior pregnancies, defined here only by start and end pregnancy                                                        |
| preg_example_2 | gest_diabetes | SINCE_START_CURRENT_PREG | LATEST   |            0 |    -3652.5 | start_preg_offset = 0, anchor_offset = 0                                                                                                                                       | Look for records between start pregnancy and the anchor date (T0)                                                                                         |
| preg_example_3 | multi_foetal  | ANYTIME_CURRENT_PREG     | EARLIEST |            0 |    -3652.5 | start_preg_offset = 0, end_preg_offset = 30                                                                                                                                    | Look for records between start_pregnancy and end_pregnancy + 30                                                                                           |
| preg_example_4 | obesity       | OUTSIDE_ALL_PREG         | LATEST   |            0 |    -3652.5 | start_preg_offset = 0, end_preg_offset = 0                                                                                                                                     | Look for records outside of start_pregnancy and end_pregnancy dates, i.e., between consecutive end_pregnancy + 1 and start_pregnancy - 1                  |
| preg_example_5 | abortion      | IN_PRIOR_PREG            | LATEST   |            0 |    -3652.5 | start_preg_offset = 90, end_offset = 166, start_preg_window = 'start_pregnancy + start_preg_offset', end_preg_window = 'min(end_pregnancy, start_pregnancy + end_offset)'      | Look for records during (parts) of prior pregnancy, here defined by start_pregnancy + 90 days and the earliest of end_pregnancy and start_pregnancy + 166 |

## pregnancy_concepts

| person_id | concept_id    | date       | value |
| --------- | ------------- | ---------- | ----- |
| 1         | gest_diabetes | 2021-05-01 | TRUE  |
| 1         | multi_foetal  | 2022-12-30 | TRUE  |
| 1         | obesity       | 2020-06-15 | TRUE  |
| 1         | abortion      | 2021-07-01 | TRUE  |
| 2         | abortion      | 2021-07-01 | TRUE  |

## intermediate_windows_pregnancy

| person_id | T0         | variable_id    | start      | end        |
| --------- | ---------- | -------------- | ---------- | ---------- |
| 1         | 2021-04-02 | preg_example_1 | 2020-01-01 | 2020-09-01 |
| 1         | 2022-08-16 | preg_example_1 | 2020-01-01 | 2020-09-01 |
| 1         | 2022-08-16 | preg_example_1 | 2021-02-15 | 2021-05-20 |
| 1         | 2021-04-02 | preg_example_2 | 2021-02-15 | 2021-04-02 |
| 1         | 2022-08-16 | preg_example_2 | 2022-03-01 | 2022-08-16 |
| 1         | 2021-04-02 | preg_example_3 | 2021-02-15 | 2021-06-19 |
| 1         | 2022-08-16 | preg_example_3 | 2022-03-01 | 2022-12-31 |
| 1         | 2021-04-02 | preg_example_4 | 2011-04-02 | 2019-12-31 |
| 1         | 2021-04-02 | preg_example_4 | 2020-09-02 | 2021-02-14 |
| 1         | 2022-08-16 | preg_example_4 | 2011-04-02 | 2019-12-31 |
| 1         | 2022-08-16 | preg_example_4 | 2020-09-02 | 2021-02-14 |
| 1         | 2022-08-16 | preg_example_4 | 2021-05-21 | 2022-08-15 |
| 1         | 2021-04-02 | preg_example_5 | 2020-03-31 | 2020-06-15 |
| 1         | 2022-08-16 | preg_example_5 | 2020-03-31 | 2020-06-15 |
| 1         | 2022-08-16 | preg_example_5 | 2021-05-16 | 2021-05-20 |
| 2         | 2022-08-16 | preg_example_1 | 2021-02-15 | 2021-08-01 |
| 2         | 2022-08-16 | preg_example_2 | 2022-03-01 | 2022-08-16 |
| 2         | 2022-08-16 | preg_example_3 | 2022-03-01 | 2022-12-31 |
| 2         | 2022-08-16 | preg_example_4 | 2012-08-15 | 2021-02-14 |
| 2         | 2022-08-16 | preg_example_4 | 2021-08-02 | 2022-08-15 |
| 2         | 2022-08-16 | preg_example_5 | 2021-05-16 | 2021-07-31 |
| 3         | 2021-04-02 | preg_example_1 | NA         | NA         |
| 3         | 2021-04-02 | preg_example_2 | 2021-02-15 | 2021-04-02 |
| 3         | 2021-04-02 | preg_example_3 | 2021-02-15 | 2021-08-31 |
| 3         | 2021-04-02 | preg_example_4 | 2011-04-02 | 2021-02-14 |
| 3         | 2021-04-02 | preg_example_5 | NA         | NA         |

## pregnancy_output

| person_id | T0         | variable_id    | date       | value |
| --------- | ---------- | -------------- | ---------- | ----- |
| 1         | 2021-04-02 | preg_example_1 | NA         | NA    |
| 1         | 2022-08-16 | preg_example_1 | 2021-05-01 | TRUE  |
| 2         | 2022-08-16 | preg_example_1 | NA         | NA    |
| 3         | 2021-04-02 | preg_example_1 | NA         | NA    |
| 1         | 2021-04-02 | preg_example_2 | 2021-05-01 | TRUE  |
| 1         | 2022-08-16 | preg_example_2 | NA         | NA    |
| 2         | 2022-08-16 | preg_example_2 | NA         | NA    |
| 3         | 2021-04-02 | preg_example_2 | NA         | NA    |
| 1         | 2021-04-02 | preg_example_3 | NA         | NA    |
| 1         | 2022-08-16 | preg_example_3 | 2022-12-30 | TRUE  |
| 2         | 2022-08-16 | preg_example_3 | NA         | NA    |
| 3         | 2021-04-02 | preg_example_3 | NA         | NA    |
| 1         | 2021-04-02 | preg_example_4 | NA         | NA    |
| 1         | 2022-08-16 | preg_example_4 | NA         | NA    |
| 2         | 2022-08-16 | preg_example_4 | NA         | NA    |
| 3         | 2021-04-02 | preg_example_4 | NA         | NA    |
| 1         | 2021-04-02 | preg_example_5 | NA         | NA    |
| 1         | 2022-08-16 | preg_example_5 | NA         | NA    |
| 2         | 2022-08-16 | preg_example_5 | 2021-07-01 | TRUE  |
| 3         | 2021-04-02 | preg_example_5 | NA         | NA    |
