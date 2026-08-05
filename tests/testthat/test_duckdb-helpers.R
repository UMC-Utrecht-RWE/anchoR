testthat::test_that(
  "load_concepts_table restricts an in-memory table to concept_ids",
  {
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    concepts <- data.table::data.table(
      person_id = c("1", "1", "1"),
      concept_id = c("A", "B", "C"),
      date = as.Date("2023-01-01"),
      value = c("x", "y", "z")
    )

    load_concepts_table(con, concepts, concept_ids = c("A", "C"))

    loaded <- data.table::setDT(
      DBI::dbGetQuery(con, "SELECT * FROM concepts ORDER BY concept_id")
    )
    testthat::expect_equal(loaded$concept_id, c("A", "C"))
  }
)

testthat::test_that("run_prepare_con is a no-op when prepare_con is NULL", {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  testthat::expect_null(run_prepare_con(con, NULL))
  testthat::expect_false("side_table" %in% DBI::dbListTables(con))
})

testthat::test_that("run_prepare_con runs the hook against the connection", {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  run_prepare_con(con, function(prepared_con) {
    DBI::dbWriteTable(
      prepared_con, "side_table", data.table::data.table(x = 1L)
    )
  })

  testthat::expect_true("side_table" %in% DBI::dbListTables(con))
})

testthat::test_that("run_prepare_con errors when prepare_con not a function", {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  testthat::expect_error(
    run_prepare_con(con, "not a function"),
    "`prepare_con` must be a function that accepts a DBI connection.",
    fixed = TRUE
  )
})

testthat::test_that(
  "load_concepts_table keeps every row when concept_ids is NULL",
  {
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    concepts <- data.table::data.table(
      person_id = c("1", "1", "1"),
      concept_id = c("A", "B", "C"),
      date = as.Date("2023-01-01"),
      value = c("x", "y", "z")
    )

    load_concepts_table(con, concepts)

    loaded <- data.table::setDT(
      DBI::dbGetQuery(con, "SELECT * FROM concepts ORDER BY concept_id")
    )
    testthat::expect_equal(loaded$concept_id, c("A", "B", "C"))
  }
)

testthat::test_that(
  "load_concepts_table restricts a parquet source to concept_ids",
  {
    concepts <- data.table::data.table(
      person_id = c("1", "1", "1"),
      concept_id = c("A", "B", "C"),
      date = as.Date("2023-01-01"),
      value = c("x", "y", "z")
    )
    parquet_path <- example_concepts_parquet(concepts)

    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    load_concepts_table(con, parquet_path, concept_ids = c("B"))

    loaded <- data.table::setDT(DBI::dbGetQuery(con, "SELECT * FROM concepts"))
    testthat::expect_equal(loaded$concept_id, "B")
  }
)

testthat::test_that(
  "load_concepts_table attaches and restricts a DuckDB source to concept_ids", # nolint: line_length_linter.
  {
    concepts <- data.table::data.table(
      person_id = c("1", "1", "1"),
      concept_id = c("A", "B", "C"),
      date = as.Date("2023-01-01"),
      value = c("x", "y", "z")
    )
    db_path <- withr::local_tempfile(fileext = ".duckdb")
    setup_con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)
    DBI::dbWriteTable(setup_con, "concept_table", concepts)
    DBI::dbDisconnect(setup_con, shutdown = TRUE)

    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    load_concepts_table(con, db_path, concept_ids = c("A", "C"))

    loaded <- data.table::setDT(
      DBI::dbGetQuery(con, "SELECT * FROM concepts ORDER BY concept_id")
    )
    testthat::expect_equal(loaded$concept_id, c("A", "C"))
    testthat::expect_true(inherits(loaded$date, "Date") || is.character(loaded$date)) # nolint: line_length_linter.
  }
)

testthat::test_that(
  "load_concepts_table doesn't re-ATTACH an already-attached DuckDB source",
  {
    concepts <- data.table::data.table(
      person_id = "1", concept_id = "A", date = as.Date("2023-01-01"),
      value = "x"
    )
    db_path <- withr::local_tempfile(fileext = ".duckdb")
    setup_con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path)
    DBI::dbWriteTable(setup_con, "concept_table", concepts)
    DBI::dbDisconnect(setup_con, shutdown = TRUE)

    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    load_concepts_table(con, db_path)
    # A second call against the same connection must not error by trying to
    # ATTACH the same database twice.
    testthat::expect_no_error(load_concepts_table(con, db_path))

    loaded <- data.table::setDT(DBI::dbGetQuery(con, "SELECT * FROM concepts"))
    testthat::expect_equal(loaded$concept_id, "A")
  }
)

testthat::test_that("write_population_windows errors when anchor_col is missing", { # nolint: line_length_linter.
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  population_windows <- data.table::data.table(
    anchor_row_id = 1L, person_id = "1", concept_id = "A",
    variable_id = "v1", window_name = NA_character_, selector = "LATEST",
    window_start = as.Date("2023-01-01"), window_end = as.Date("2023-01-31"),
    range_min = NA_real_, range_max = NA_real_
  )

  testthat::expect_error(
    write_population_windows(con, population_windows, anchor_col = "T0"),
    "Anchor column `T0` was not found in `population_windows`.",
    fixed = TRUE
  )
})

testthat::test_that(
  "anchor() ignores concepts for concept_ids outside metadata",
  {
    # An end-to-end check that the concept_ids filter in load_concepts_table
    # never changes results -- a concept_id irrelevant to metadata must have
    # been unmatchable anyway (the join is on w.concept_id), this just locks
    # down that the filtering doesn't accidentally drop something it should
    # keep.
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    concepts <- data.table::rbindlist(list(
      minimal_concepts(),
      data.table::data.table(
        person_id = "1",
        concept_id = "UNRELATED_CONCEPT",
        date = as.Date("2023-12-25"),
        value = "TRUE"
      )
    ))

    anchor(
      population = minimal_population(),
      metadata = minimal_metadata()[variable_id == "cov_latest"],
      concepts = concepts,
      anchor_hive_path = hive_path
    )

    anchored <- read_anchor_hive(hive_path)
    testthat::expect_equal(anchored$variable_id, "cov_latest")
    testthat::expect_equal(anchored$value, "TRUE")
    testthat::expect_equal(anchored$date, as.Date("2023-12-20"))
  }
)
