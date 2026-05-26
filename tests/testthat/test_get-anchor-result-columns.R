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

testthat::test_that("anchor saves person_id, T0, and window_name to parquet output", {
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
  testthat::expect_equal(anchored$person_id, c("1", "2"))
  testthat::expect_equal(anchored$T0, as.Date(c("2024-01-01", "2024-01-15")))
  testthat::expect_equal(anchored$window_name, c("lookback", "lookback"))
})

testthat::test_that("narrow includes person_id, T0, and window_name", {
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

  testthat::expect_equal(
    names(anchored),
    c("person_id", "T0", "variable_id", "window_name", "date", "value")
  )
  testthat::expect_equal(anchored$person_id, "1")
  testthat::expect_equal(anchored$T0, as.Date("2024-01-01"))
  testthat::expect_equal(anchored$variable_id, "cov_count_generic")
  testthat::expect_equal(anchored$window_name, "risk")
  testthat::expect_equal(anchored$date, as.Date("2023-12-15"))
  testthat::expect_equal(anchored$value, "2")
})

testthat::test_that("get_anchor_result wide is keyed by person_id and T0", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  metadata <- data.table::data.table(
    variable_id = c("cov_latest_generic", "cov_count_generic"),
    concept_id = c("COV_A", "COV_B"),
    window_name = c("lookback", "risk"),
    window_definition = c("GENERIC", "GENERIC"),
    selector = c("LATEST", "COUNT"),
    start_look_back = c(-30L, -90L),
    end_look_back = c(0L, 0L),
    anchor_date_start = c("T0", "T0"),
    anchor_date_end = c("T0", "T0")
  )

  anchor_by_variable(
    population = example_population(),
    metadata = metadata,
    concepts = example_concepts(),
    save_parquet_hive_path = hive_path
  )

  anchored <- get_anchor_result(
    metadata = metadata,
    anchor_hive_path = hive_path,
    result_shape = "wide"
  )
  data.table::setorder(anchored, person_id, T0)

  testthat::expect_equal(names(anchored)[1:2], c("person_id", "T0"))
  testthat::expect_equal(anchored$person_id, c("1", "2"))
  testthat::expect_equal(anchored$T0, as.Date(c("2024-01-01", "2024-01-15")))
  testthat::expect_equal(anchored$value_cov_latest_generic, c("TRUE", "FALSE"))
  testthat::expect_equal(anchored$value_cov_count_generic[[1L]], "2")
  expect_true(is.na(anchored$value_cov_count_generic[[2L]]))
})

testthat::test_that("get_anchor_result wide fails on duplicate variable_id values", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  metadata <- example_metadata()[variable_id == "cov_latest"]

  anchor(
    population = example_population(),
    metadata = metadata,
    concepts = example_concepts(),
    save_parquet_hive_path = hive_path
  )

  expect_error(
    get_anchor_result(
      metadata = data.table::rbindlist(list(metadata, metadata)),
      anchor_hive_path = hive_path,
      result_shape = "wide"
    ),
    "duplicate `variable_id`"
  )
})
