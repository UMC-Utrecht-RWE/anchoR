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

example_concepts_parquet <- function() {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  parquet_path <- tempfile(fileext = ".parquet")
  DBI::dbWriteTable(con, "concepts_source", example_concepts(), overwrite = TRUE)
  DBI::dbExecute(
    con,
    sprintf(
      "COPY concepts_source TO '%s' (FORMAT PARQUET)",
      normalizePath(parquet_path, winslash = "/", mustWork = FALSE)
    )
  )

  parquet_path
}
