read_anchor_hive_columns <- function(anchor_hive_path) {
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
  if ("T0" %in% names(anchored_dt)) {
    anchored_dt[, T0 := as.Date(T0)]
  }

  anchored_dt[]
}

test_that("anchor saves person_id, T0, and window_name to parquet output", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  anchor(
    population = example_population(),
    metadata = example_metadata()[variable_id == "cov_latest"],
    concepts = example_concepts(),
    save_parquet_hive_path = hive_path
  )

  anchored <- read_anchor_hive_columns(hive_path)

  expect_true(all(c("person_id", "T0", "window_name") %in% names(anchored)))
  expect_equal(anchored$person_id, c("1", "2"))
  expect_equal(anchored$T0, as.Date(c("2024-01-01", "2024-01-15")))
  expect_equal(anchored$window_name, c("lookback", "lookback"))
})

test_that("get_anchor_result narrow includes person_id, T0, and window_name", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  metadata <- data.table::data.table(
    variable_id = "cov_count_generic",
    concept_id = "COV_B",
    window_name = "risk",
    window_definition = "GENERIC",
    selector = "COUNT",
    start_look_back = -90L,
    end_look_back = 0L,
    anchor_date_start = "T0",
    anchor_date_end = "T0"
  )

  anchor(
    population = example_population(),
    metadata = metadata,
    concepts = example_concepts(),
    save_parquet_hive_path = hive_path
  )

  anchored <- get_anchor_result(
    metadata = metadata,
    anchor_hive_path = hive_path,
    result_shape = "narrow"
  )

  expect_equal(
    names(anchored),
    c("person_id", "T0", "variable_id", "window_name", "date", "value")
  )
  expect_equal(anchored$person_id, "1")
  expect_equal(anchored$T0, as.Date("2024-01-01"))
  expect_equal(anchored$variable_id, "cov_count_generic")
  expect_equal(anchored$window_name, "risk")
  expect_equal(anchored$date, as.Date("2023-12-15"))
  expect_equal(anchored$value, "2")
})
