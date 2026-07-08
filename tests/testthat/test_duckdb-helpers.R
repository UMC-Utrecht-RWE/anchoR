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
