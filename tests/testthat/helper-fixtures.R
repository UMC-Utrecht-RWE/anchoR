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
    selector = c("LATEST", "COUNT", "EARLIEST"),
    start_offset = c(-30L, -90L, -30L),
    end_offset = c(0L, 0L, 30L),
    range_min = c(NA_real_, NA_real_, 0),
    range_max = c(NA_real_, NA_real_, 10)
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
      c(NA, NA, NA, NA, NA)
    )
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
        "ORDER BY variable_id, person_id, T0, window_name;"
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
