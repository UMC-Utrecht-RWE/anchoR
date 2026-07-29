testthat::test_that("available_selectors lists bundled SQL templates", {
  selectors <- available_selectors()

  testthat::expect_true(
    all(
      c("LATEST", "EARLIEST", "COUNT", "COUNT_CATEGORY", "ALL"
    ) %in% selectors)
  )
  testthat::expect_true("COUNT_MORE_THAN_1" %in% selectors)
})

testthat::test_that(
  "filter_supported_metadata keeps supported when unsupported rows are dropped",
  {
    metadata <- data.table::data.table(
      variable_id = c("a", "b", "c"),
      concept_id = c("A", "B", "C"),
      date_extraction_func = c(
        "latest", "LATEST_PRIOR_ANCHOREDPREG", NA_character_
      )
    )

    filtered <- filter_supported_metadata(
      metadata,
      selector_col = "date_extraction_func"
    )

    testthat::expect_s3_class(filtered, "data.table")
    testthat::expect_equal(filtered$variable_id, "a")
    testthat::expect_equal(names(filtered), names(metadata))
  }
)

testthat::test_that(
  "filter_supported_metadata keeps all rows when selectors are supported",
  {
    metadata <- data.table::data.table(
      variable_id = c("a", "b"),
      concept_id = c("A", "B"),
      selector = c("LATEST", "count")
    )

    filtered <- filter_supported_metadata(metadata)

    testthat::expect_equal(filtered$selector, c("LATEST", "count"))
  }
)

testthat::test_that(
  "count_category selector buckets the raw count via concept_ranges",
  {
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

    # p1: 0 matching concept rows (never appears in concepts at all).
    # p2: 1 match, p3: 3 matches, p4: 5 matches.
    DBI::dbWriteTable(con, "population_windows", data.table::data.table(
      person_id = c("p1", "p2", "p3", "p4"),
      T0 = as.Date("2024-06-01"),
      variable_id = "v1",
      concept_id = "C1",
      window_name = "w",
      selector = "COUNT_CATEGORY",
      window_start = as.Date("2024-01-01"),
      window_end = as.Date("2024-12-31")
    ))

    DBI::dbWriteTable(con, "concepts", data.table::data.table(
      person_id = c("p2", "p3", "p3", "p3", "p4", "p4", "p4", "p4", "p4"), # nolint p1 not in concepts
      concept_id = "C1",
      date = as.Date(c(
        "2024-03-01",
        "2024-03-01", "2024-04-01", "2024-05-01",
        "2024-01-15", "2024-02-15", "2024-03-15", "2024-04-15", "2024-05-15"
      )),
      value = NA_character_
    ))

    DBI::dbWriteTable(con, "concept_ranges", data.table::data.table(
      concept_id = "C1",
      new_value = c(1, 2, 3, 4),
      lower_range = c(0, 1, 3, 5),
      upper_range = c(0, 2, 4, 99999)
    ))

    result <- data.table::as.data.table(
      DBI::dbGetQuery(con, read_selector_sql_query("COUNT_CATEGORY"))
    )
    data.table::setorder(result, person_id)

    testthat::expect_equal(result$person_id, c("p2", "p3", "p4"))
    testthat::expect_equal(result$value, c("2", "3", "4"))
    testthat::expect_equal(result$n, c(1, 3, 5))
  }
)
