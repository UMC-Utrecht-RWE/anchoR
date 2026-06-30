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
# for metadata it contains columns: variable_id, concept_id, constructor, selector, start_offset, end_offset
minimal_metadata <- function() {
  data.table::data.table(
    variable_id = c("cov_latest", "cov_count", "lab_range"),
    concept_id = c("COV_A", "COV_B", "LAB_X"),
    constructor = c("GENERIC", "PREG1", "PREG1"),
    selector = c("LATEST", "COUNT", "RANGE_COUNT"),
    start_look_back = c(-30L, -90L, -30L),
    end_look_back = c(0L, 0L, 30L)
  )
}
# minimal concepts data.table contains columns: person_id, concept_id, date, value
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

# example with pregnancy
example_population <- function() {
  data.table::data.table(
    person_id = c("1", "2"),
    T0 = as.Date(c("2024-01-01", "2024-01-15")),
    lmp_date = as.Date(c("2023-10-01", "2023-10-15")),
    pregnancy_end_date = as.Date(c("2024-03-01", "2024-02-28")),
    candidate_start = as.Date(c("2023-12-01", "2024-01-01")),
    candidate_end = as.Date(c("2024-01-31", "2024-01-31"))
  )
}

example_metadata <- function() {
  data.table::data.table(
    variable_id = c("cov_latest", "cov_count", "lab_range"),
    concept_id = c("COV_A", "COV_B", "LAB_X"),
    window_name = c("lookback", "risk", "lookforward"),
    constructor = c("GENERIC", "PREG1", "PREG1"),
    selector = c("LATEST", "COUNT", "RANGE_COUNT"),
    start_look_back = c(-30L, -90L, -30L),
    end_look_back = c(0L, 0L, 30L),
    anchor_date_start = c("T0", "T0", "T0"),
    anchor_date_end = c("T0", "T0", "T0"),
    range_min = c(NA_real_, NA_real_, 1),
    range_max = c(NA_real_, NA_real_, 5)
  )
}

example_concepts <- function() {
  data.table::data.table(
    person_id = c("1", "1", "1", "1", "2", "2", "2", "2"),
    concept_id = c(
      "COV_A",
      "COV_B",
      "COV_B",
      "T0_EVENT",
      "COV_A",
      "LAB_X",
      "LAB_X",
      "T0_EVENT"
    ),
    date = as.Date(c(
      "2023-12-20",
      "2023-11-01",
      "2023-12-15",
      "2024-01-05",
      "2024-01-14",
      "2024-01-10",
      "2024-01-25",
      "2024-01-10"
    )),
    value = c("TRUE", "1", "1", "TRUE", "FALSE", "3.2", "6.1", "TRUE")
  )
}

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
