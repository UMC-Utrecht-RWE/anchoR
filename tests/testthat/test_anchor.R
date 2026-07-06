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

testthat::test_that("anchor writes selector results to the parquet hive", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  anchor(
    population = example_population(),
    metadata = example_metadata()[variable_id == "cov_latest"],
    concepts = example_concepts(),
    anchor_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  testthat::expect_equal(anchored$variable_id, c("cov_latest", "cov_latest"))
  testthat::expect_equal(anchored$value, c("TRUE", "FALSE"))
  testthat::expect_equal(
    anchored$date,
    as.Date(c("2023-12-20", "2024-01-14"))
  )
})

testthat::test_that(
  "anchor ignores unrelated population covariates",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    population <- data.table::copy(example_population())
    population[, sex := c("F", "M")]

    anchor(
      population = population,
      metadata = example_metadata()[variable_id == "cov_latest"],
      concepts = example_concepts(),
      anchor_hive_path = hive_path
    )

    anchored <- read_anchor_hive(hive_path)

    testthat::expect_equal(anchored$variable_id, c("cov_latest", "cov_latest"))
    testthat::expect_equal(anchored$value, c("TRUE", "FALSE"))
    testthat::expect_equal(
      anchored$date,
      as.Date(c("2023-12-20", "2024-01-14"))
    )
  }
)

testthat::test_that("anchor honors a non-default anchor column", {
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
    anchor_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  testthat::expect_equal(anchored$variable_id, "lab_range")
  testthat::expect_equal(anchored$value, "1")
  testthat::expect_equal(anchored$date, as.Date("2024-01-10"))
})

testthat::test_that("anchor accepts parquet concept sources", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  anchor(
    population = example_population(),
    metadata = example_metadata()[variable_id == "lab_range"],
    concepts = example_concepts_parquet(),
    anchor_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  testthat::expect_equal(anchored$value, "1")
  testthat::expect_equal(anchored$date, as.Date("2024-01-10"))
})

testthat::test_that("it refreshes only requested variable partition", {
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
    anchor_hive_path = hive_path
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
    anchor_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  testthat::expect_equal(nrow(anchored[variable_id == "cov_latest"]), 2L)
  testthat::expect_equal(
    anchored[variable_id == "cov_latest" & anchor_row_id == 1L, value],
    "UPDATED"
  )
  testthat::expect_equal(nrow(anchored[variable_id == "cov_count"]), 1L)
  testthat::expect_equal(anchored[variable_id == "cov_count", value], "2")
})

testthat::test_that("reshapes variable-by-variable hive output", {
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
    anchor_hive_path = hive_path
  )
  anchored <- get_anchor_result(
    metadata = metadata,
    anchor_hive_path = hive_path
  )
  data.table::setorder(anchored, person_id, T0)

  testthat::expect_equal(anchored$person_id, c("1", "2", "2"))
  testthat::expect_equal(
    anchored$T0, as.Date(c("2024-01-01", "2024-01-15", "2024-01-15"))
  )
  testthat::expect_equal(anchored$value_cov_latest, c("TRUE", "FALSE", NA))
  expect_true(is.na(anchored$value_lab_range[[1L]]))
  testthat::expect_equal(anchored$value_lab_range[[2L]], NA_character_)
})

testthat::test_that(
  "wide output is limited to the population for single-window metadata",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    metadata <- example_metadata()[variable_id == "cov_latest"]
    anchor_by_variable(
      population = example_population(),
      metadata = metadata,
      concepts = example_concepts(),
      anchor_hive_path = hive_path
    )

    anchored <- get_anchor_result(
      metadata = metadata,
      anchor_hive_path = hive_path,
      population = example_population()[1, .(person_id, T0)],
      result_shape = "wide"
    )

    testthat::expect_equal(nrow(anchored), 1L)
    testthat::expect_equal(anchored$person_id, "1")
    testthat::expect_equal(anchored$T0, as.Date("2024-01-01"))
    testthat::expect_equal(anchored$window_name, "lookback")
  }
)

testthat::test_that(
  "wide output does not leak rows outside a single-window population",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    write_anchor_hive_fixture(
      anchor_hive_path = hive_path,
      variable_id = "cov_latest",
      rows = data.table::data.table(
        anchor_row_id = c(1L, 2L),
        person_id = c("1", "2"),
        T0 = as.Date(c("2024-01-01", "2024-01-15")),
        window_name = c("fup", "fup"),
        value = c("TRUE", "FALSE"),
        date = as.Date(c("2024-01-10", "2024-01-20")),
        n = c(1L, 1L)
      )
    )

    anchored <- get_anchor_result(
      metadata = data.table::data.table(
        variable_id = "cov_latest",
        window_name = "fup"
      ),
      anchor_hive_path = hive_path,
      population = data.table::data.table(
        person_id = "1",
        T0 = as.Date("2024-01-01"),
        match_id = "m1",
        group = "treated"
      ),
      result_shape = "wide"
    )

    # Before the fix this returned 2 rows because existing hive rows were not
    # constrained to the requested population before the backfill step.
    testthat::expect_equal(nrow(anchored), 1L)
    testthat::expect_equal(anchored$person_id, "1")
    testthat::expect_equal(anchored$T0, as.Date("2024-01-01"))
    testthat::expect_equal(anchored$match_id, "m1")
    testthat::expect_equal(anchored$group, "treated")
    testthat::expect_equal(anchored$window_name, "fup")
    testthat::expect_equal(anchored$value_cov_latest, "TRUE")
  }
)

testthat::test_that(
  "wide output one row per population-window key when cast_window is FALSE",
  {
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
      anchor_hive_path = hive_path
    )

    anchored <- get_anchor_result(
      metadata = metadata,
      anchor_hive_path = hive_path,
      population = example_population()[, .(person_id, T0)],
      result_shape = "wide"
    )

    data.table::setorder(anchored, person_id, T0, window_name)
    testthat::expect_equal(nrow(anchored), 4L)
    testthat::expect_equal(
      anchored[, .(person_id, T0, window_name)],
      data.table::data.table(
        person_id = c("1", "1", "2", "2"),
        T0 = as.Date(c("2024-01-01", "2024-01-01", "2024-01-15", "2024-01-15")),
        window_name = c("lookback", "lookforward", "lookback", "lookforward")
      )
    )
    testthat::expect_true(
      all(is.na(
        anchored[
          person_id == "1" & window_name == "lookforward",
          .(value_cov_latest, date_cov_latest, value_lab_range, date_lab_range)
        ]
      ))
    )
  }
)

testthat::test_that(
  "wide output backfills one row per population key when cast_window is TRUE",
  {
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
      anchor_hive_path = hive_path
    )

    anchored <- get_anchor_result(
      metadata = metadata,
      anchor_hive_path = hive_path,
      population = example_population()[1, .(person_id, T0)],
      result_shape = "wide",
      cast_window = TRUE
    )

    testthat::expect_equal(nrow(anchored), 1L)
    testthat::expect_equal(anchored$person_id, "1")
    testthat::expect_equal(anchored$T0, as.Date("2024-01-01"))
  }
)
