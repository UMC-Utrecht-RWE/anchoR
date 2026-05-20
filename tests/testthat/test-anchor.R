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

test_that("anchor writes selector results to the parquet hive", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  anchor(
    population = example_population(),
    metadata = example_metadata()[variable_id == "cov_latest"],
    concepts = example_concepts(),
    save_parquet_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  expect_equal(anchored$variable_id, c("cov_latest", "cov_latest"))
  expect_equal(anchored$value, c("TRUE", "FALSE"))
  expect_equal(
    anchored$date,
    as.Date(c("2023-12-20", "2024-01-14"))
  )
})

test_that("anchor honors a non-default anchor column", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  population <- data.table::copy(example_population())
  data.table::setnames(population, "T0", "anchor_date")

  anchor(
    population = population,
    metadata = example_metadata()[variable_id == "lab_range"],
    concepts = example_concepts(),
    anchor_col = "anchor_date",
    save_parquet_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  expect_equal(anchored$variable_id, "lab_range")
  expect_equal(anchored$value, "1")
  expect_equal(anchored$date, as.Date("2024-01-10"))
})

test_that("anchor accepts parquet concept sources", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  anchor(
    population = example_population(),
    metadata = example_metadata()[variable_id == "lab_range"],
    concepts = example_concepts_parquet(),
    save_parquet_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  expect_equal(anchored$value, "1")
  expect_equal(anchored$date, as.Date("2024-01-10"))
})

test_that("anchor_by_variable refreshes only the requested variable partition", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  metadata <- example_metadata()[
    variable_id %in% c("cov_latest", "cov_count")
  ]

  anchor_by_variable(
    population = example_population(),
    metadata = metadata,
    concepts = example_concepts(),
    save_parquet_hive_path = hive_path
  )

  refreshed_concepts <- data.table::rbindlist(list(
    example_concepts(),
    data.table::data.table(
      person_id = "1",
      concept_id = "COV_A",
      date = as.Date("2023-12-31"),
      value = "UPDATED"
    )
  ))

  anchor_by_variable(
    population = example_population(),
    metadata = metadata[variable_id == "cov_latest"],
    concepts = refreshed_concepts,
    save_parquet_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  expect_equal(nrow(anchored[variable_id == "cov_latest"]), 2L)
  expect_equal(
    anchored[variable_id == "cov_latest" & anchor_row_id == 1L, value],
    "UPDATED"
  )
  expect_equal(nrow(anchored[variable_id == "cov_count"]), 1L)
  expect_equal(anchored[variable_id == "cov_count", value], "2")
})

test_that("get_anchor_result reshapes variable-by-variable hive output", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  metadata <- example_metadata()[
    variable_id %in% c("cov_latest", "lab_range")
  ]

  anchor_by_variable(
    population = example_population(),
    metadata = metadata,
    concepts = example_concepts(),
    save_parquet_hive_path = hive_path
  )

  anchored <- get_anchor_result(
    metadata = metadata,
    anchor_hive_path = hive_path
  )
  data.table::setorder(anchored, anchor_row_id)

  expect_equal(anchored$anchor_row_id, c(1L, 2L))
  expect_equal(anchored$value_cov_latest, c("TRUE", "FALSE"))
  expect_true(is.na(anchored$value_lab_range[[1L]]))
  expect_equal(anchored$value_lab_range[[2L]], "1")
})
