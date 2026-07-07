# a set of minimal example data.tables to use in tests for 5 individuals.
# For population it contains columns: person_id and T0
minimal_population <- function() {
  data.table::data.table(
    person_id = c("1", "2", "3", "4", "5"),
    T0 = as.Date(c(
      "2024-01-01",
      "2024-01-15",
      "2024-02-01",
      "2024-02-15",
      "2024-03-01"
    ))
  )
}
# for metadata it contains columns:
# variable_id, concept_id, constructor, selector, start_offset, end_offset
minimal_metadata <- function() {
  data.table::data.table(
    variable_id = c("cov_latest", "cov_count", "lab_range"),
    concept_id = c("COV_A", "COV_B", "LAB_X"),
    constructor = c("GENERIC", "GENERIC", "GENERIC"),
    selector = c("LATEST", "COUNT", "RANGE_COUNT"),
    start_look_back = c(-30L, -90L, -30L),
    end_look_back = c(0L, 0L, 30L)
  )
}
# minimal concepts data.table contains columns:
# person_id, concept_id, date, value
minimal_concepts <- function() {
  data.table::data.table(
    person_id = c("1", "2", "3", "4", "5"),
    concept_id = c(
      "COV_A",
      "COV_B",
      "COV_B",
      "T0_EVENT",
      "COV_A"
    ),
    date = as.Date(c(
      "2023-12-20",
      "2023-11-01",
      "2023-12-15",
      "2024-01-05",
      "2024-01-14"
    )),
    value = c("TRUE", "1", "1", "TRUE", "FALSE")
  )
}

# minimal output, including person_id, T0, variabled_id, date and value
minimal_output <- function() {
  data.table::data.table(
    person_id = rep(c("1", "2", "3", "4", "5"), 3),
    T0 = rep(as.Date(c(
      "2024-01-01",
      "2024-01-15",
      "2024-02-01",
      "2024-02-15",
      "2024-03-01"
    )), 3),
    variable_id = c(
      rep("cov_latest", 5),
      rep("cov_count", 5),
      rep("lab_range", 5)
    ),
    date = c(
      c("2023-12-20", NA, NA, NA, NA),
      c(NA, "2023-11-01", "2023-11-03", NA, NA),
      c(NA, NA, NA, NA, NA)
    ),
    value = c(
      c("TRUE", NA, NA, NA, NA),
      c(NA, "1", "1", NA, NA),
      c(0, 0, 0, 0, 0)
    )
  )
}

# example with pregnancy
pregnancy_periods <- function() {
  data.table::data.table(
    person_id = c("1", "1", "1", "2", "2", "3"),
    start_pregnancy = as.Date(c(
      "2020-01-01",
      "2021-02-15",
      "2022-03-01",
      "2021-02-15",
      "2022-03-01",
      "2021-02-15"
    )),
    end_pregnancy = as.Date(c(
      "2020-09-01",
      "2021-05-20",
      "2022-12-01",
      "2021-08-01",
      "2022-12-01",
      "2021-09-14"
    ))
  )
}

pregnancy_population <- function() {
  data.table::data.table(
    person_id = c("1", "1", "2", "3"),
    T0 = as.Date(c(
      "2021-04-02",
      "2022-08-16",
      "2022-08-16",
      "2021-04-02"
    ))
  )
}

pregnancy_metadata <- function() {
  data.table::data.table(
    variable_id = c(
      "preg_example_1",
      "preg_example_2",
      "preg_example_3",
      "preg_example_4",
      "preg_example_5"
    ),
    concept_id = c(
      "gest_diabetes",
      "gest_diabetes",
      "multi_foetal",
      "obesity",
      "abortion"
    ),
    constructor = c(
      "IN_PRIOR_PREG",
      "SINCE_START_CURRENT_PREG",
      "ANYTIME_CURRENT_PREG",
      "OUTSIDE_ALL_PREG",
      "IN_PRIOR_PREG"
    ),
    selector = c(
      "LATEST",
      "LATEST",
      "EARLIEST",
      "LATEST",
      "LATEST"
    ),
    start_offset = c(0, 0, 0, 0, 0),
    end_offset = c(-3652.5, -3652.5, -3652.5, -3652.5, -3652.5),
    other_arguments = c(
      "start_pregnancy_offset = 0, end_pregnancy_offset = 0,
      start_preg_window = 'start_pregnancy + start_pregnancy_offset',
      end_preg_window = 'end_pregnancy + end_pregnancy_offset'",
      "start_preg_offset = 0, anchor_offset = 0",
      "start_preg_offset = 0, end_preg_offset = 30",
      "start_preg_offset = 0, end_preg_offset = 0",
      "start_preg_offset = 90, end_offset = 166,
      start_preg_window = 'start_pregnancy + start_preg_offset',
      end_preg_window = 'min(end_pregnancy, start_pregnancy + end_offset)'"
    ),
    description_constructor = c(
      "Look for records during (parts) of prior pregnancies,
      defined here only by start and end pregnancy",
      "Look for records between start pregnancy and the anchor date (T0)",
      "Look for records between start_pregnancy and end_pregnancy + 30",
      "Look for records outside of start_pregnancy and end_pregnancy dates,
      i.e., between consecutive end_pregnancy + 1 and start_pregnancy - 1",
      "Look for records during (parts) of prior pregnancy,
      here defined by start_pregnancy + 90 days and the earliest of
      end_pregnancy and start_pregnancy + 166"
    )
  )
}
pregnancy_concepts <- function() {
  data.table::data.table(
    person_id = c("1", "1", "1", "1", "2"),
    concept_id = c(
      "gest_diabetes",
      "multi_foetal",
      "obesity",
      "abortion",
      "abortion"
    ),
    date = as.Date(c(
      "2021-05-01",
      "2022-12-30",
      "2020-06-15",
      "2021-07-01",
      "2021-07-01"
    )),
    value = c(TRUE, TRUE, TRUE, TRUE, TRUE)
  )
}


intermediate_windows_pregnancy <- function() {
  data.table::data.table(
    person_id = c(
      "1", "1", "1",
      "1", "1",
      "1", "1",
      "1", "1",
      "1", "1", "1",
      "1", "1", "1",
      "2", "2", "2", "2", "2", "2",
      "3", "3", "3", "3", "3"
    ),
    T0 = as.Date(c(
      "2021-04-02", "2022-08-16", "2022-08-16",
      "2021-04-02", "2022-08-16",
      "2021-04-02", "2022-08-16",
      "2021-04-02", "2021-04-02",
      "2022-08-16", "2022-08-16", "2022-08-16",
      "2021-04-02", "2022-08-16", "2022-08-16",
      "2022-08-16", "2022-08-16", "2022-08-16", "2022-08-16",
      "2022-08-16", "2022-08-16",
      "2021-04-02", "2021-04-02", "2021-04-02", "2021-04-02", "2021-04-02"
    )),
    variable_id = c(
      "preg_example_1", "preg_example_1", "preg_example_1",
      "preg_example_2", "preg_example_2",
      "preg_example_3", "preg_example_3",
      "preg_example_4", "preg_example_4",
      "preg_example_4", "preg_example_4", "preg_example_4",
      "preg_example_5", "preg_example_5", "preg_example_5",
      "preg_example_1", "preg_example_2", "preg_example_3",
      "preg_example_4", "preg_example_4", "preg_example_5",
      "preg_example_1", "preg_example_2", "preg_example_3",
      "preg_example_4", "preg_example_5"
    ),
    start = as.Date(c(
      "2020-01-01", "2020-01-01", "2021-02-15",
      "2021-02-15", "2022-03-01",
      "2021-02-15", "2022-03-01",
      "2011-04-02", "2020-09-02",
      "2011-04-02", "2020-09-02", "2021-05-21",
      "2020-03-31", "2020-03-31", "2021-05-16",
      "2021-02-15", "2022-03-01", "2022-03-01",
      "2012-08-15", "2021-08-02", "2021-05-16",
      NA, "2021-02-15", "2021-02-15",
      "2011-04-02", NA
    )),
    end = as.Date(c(
      "2020-09-01", "2020-09-01", "2021-05-20",
      "2021-04-02", "2022-08-16",
      "2021-06-19", "2022-12-31",
      "2019-12-31", "2021-02-14",
      "2019-12-31", "2021-02-14", "2022-08-15",
      "2020-06-15", "2020-06-15", "2021-05-20",
      "2021-08-01", "2022-08-16", "2022-12-31",
      "2021-02-14", "2022-08-15", "2021-07-31",
      NA, "2021-04-02", "2021-08-31",
      "2021-02-14", NA
    ))
  )
}

pregnancy_output <- function() {
  data.table::data.table(
    person_id = c(
      "1", "1", "2", "3",
      "1", "1", "2", "3",
      "1", "1", "2", "3",
      "1", "1", "2", "3",
      "1", "1", "2", "3"
    ),
    T0 = as.Date(c(
      "2021-04-02", "2022-08-16", "2022-08-16", "2021-04-02",
      "2021-04-02", "2022-08-16", "2022-08-16", "2021-04-02",
      "2021-04-02", "2022-08-16", "2022-08-16", "2021-04-02",
      "2021-04-02", "2022-08-16", "2022-08-16", "2021-04-02",
      "2021-04-02", "2022-08-16", "2022-08-16", "2021-04-02"
    )),
    variable_id = c(
      rep("preg_example_1", 4),
      rep("preg_example_2", 4),
      rep("preg_example_3", 4),
      rep("preg_example_4", 4),
      rep("preg_example_5", 4)
    ),
    date = as.Date(c(
      NA, "2021-05-01", NA, NA,
      "2021-05-01", NA, NA, NA,
      NA, "2022-12-30", NA, NA,
      NA, NA, NA, NA,
      NA, NA, "2021-07-01", NA
    )),
    value = c(
      NA, TRUE, NA, NA,
      TRUE, NA, NA, NA,
      NA, TRUE, NA, NA,
      NA, NA, NA, NA,
      NA, NA, TRUE, NA
    )
  )
}

# Hand-computed fixtures for the event-based window constructors
# (R/pregnancy_window.R). Unlike pregnancy_output/intermediate_windows_pregnancy
# above, every number here was worked out by hand against the constructor
# rules and can be trusted as ground truth.
#
# Person "1" has three pregnancy events; person "2" has none (covers the
# "no candidate window" case). T0 = 2022-08-16 falls inside person 1's third
# event (2022-03-01 to 2022-12-01).
event_population <- function() {
  data.table::data.table(
    person_id = c("1", "2"),
    T0 = as.Date(c("2022-08-16", "2022-08-16")),
    pregnancy_events = list(
      data.table::data.table(
        event_start = as.Date(c("2020-01-01", "2021-02-15", "2022-03-01")),
        event_end = as.Date(c("2020-09-01", "2021-05-20", "2022-12-01"))
      ),
      data.table::data.table(
        event_start = as.Date(character()),
        event_end = as.Date(character())
      )
    )
  )
}

# One variable_id, IN_PRIOR_PREG: person 1 has two prior events (ended
# before T0), each becoming its own candidate window with no offset.
event_metadata <- function() {
  data.table::data.table(
    variable_id = "gest_diabetes_prior",
    concept_id = "GEST_DIAB",
    constructor = "IN_PRIOR_PREG",
    selector = "LATEST",
    start_offset = 0L,
    end_offset = 0L,
    event_col = "pregnancy_events"
  )
}

# Two GEST_DIAB records for person 1, one inside each prior event, so a
# LATEST selector must pick the later one (2021-03-01) across both candidate
# windows -- this is what exercises the SQL PARTITION BY fix.
event_concepts <- function() {
  data.table::data.table(
    person_id = c("1", "1"),
    concept_id = c("GEST_DIAB", "GEST_DIAB"),
    date = as.Date(c("2020-05-01", "2021-03-01")),
    value = c("TRUE", "TRUE")
  )
}

# Adapters that reuse the documented pregnancy_periods()/pregnancy_population()
# /pregnancy_metadata() fixtures above with the event engine. Two things
# still need translating, since those fixtures predate the event engine:
# - population/periods are two separate tables (one row per person,
#   one row per pregnancy) instead of population with a nested episode
#   list-column, so pregnancy_periods() is nested onto pregnancy_population()
#   per person.
# - pregnancy_metadata()'s start_offset/end_offset are placeholders for this
#   engine (the real per-row parameters lived in its free-text
#   `other_arguments`, which anchoR deliberately does not parse -- see
#   R/pregnancy_window.R). Each row below is that same other_arguments text
#   translated by hand into start_offset/end_offset/end_cap_offset.
pregnancy_population_with_events <- function() { # nolint
  population <- data.table::copy(pregnancy_population())
  periods <- pregnancy_periods()

  population[
    ,
    pregnancy_events := lapply(person_id, function(id) {
      periods[
        person_id == id,
        .(event_start = start_pregnancy, event_end = end_pregnancy)
      ]
    })
  ]
  population[]
}

pregnancy_metadata_translated <- function() {
  meta <- pregnancy_metadata()

  data.table::data.table(
    variable_id = meta$variable_id,
    concept_id = meta$concept_id,
    constructor = meta$constructor,
    selector = meta$selector,
    start_offset = c(0L, 0L, 0L, 0L, 90L),
    end_offset = c(0L, 0L, 30L, -3652L, 0L),
    end_cap_offset = c(NA_real_, NA_real_, NA_real_, NA_real_, 166),
    event_col = "pregnancy_events"
  )
}

## Functions
example_concepts_parquet <- function(data = NULL) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  parquet_path <- tempfile(fileext = ".parquet")
  DBI::dbWriteTable(
    con, "concepts_source", data,
    overwrite = TRUE
  )
  DBI::dbExecute(
    con,
    sprintf(
      "COPY concepts_source TO '%s' (FORMAT PARQUET)",
      normalizePath(parquet_path, winslash = "/", mustWork = FALSE)
    )
  )

  parquet_path
}


read_anchor_hive <- function(anchor_hive_path) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  anchor_hive_path_sql <- as.character(
    DBI::dbQuoteString(
      con,
      normalizePath(anchor_hive_path, winslash = "/", mustWork = TRUE)
    )
  )
  anchored_dt <- data.table::as.data.table(
    DBI::dbGetQuery(
      con,
      paste(
        "SELECT * FROM read_parquet(",
        anchor_hive_path_sql,
        ", hive_partitioning = true, union_by_name = true)",
        "ORDER BY variable_id, anchor_row_id;"
      )
    )
  )

  if ("date" %in% names(anchored_dt)) {
    anchored_dt[, date := as.Date(date)]
  }

  anchored_dt[]
}

write_anchor_hive_fixture <- function(anchor_hive_path, variable_id, rows) {
  partition_path <- file.path(
    anchor_hive_path,
    paste0("variable_id=", variable_id)
  )
  dir.create(partition_path, recursive = TRUE, showWarnings = FALSE)

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  DBI::dbWriteTable(con, "fixture_rows", rows, overwrite = TRUE)
  DBI::dbExecute(
    con,
    sprintf(
      "COPY fixture_rows TO '%s' (FORMAT PARQUET)",
      normalizePath(
        file.path(partition_path, "part-0.parquet"),
        winslash = "/",
        mustWork = FALSE
      )
    )
  )
}
