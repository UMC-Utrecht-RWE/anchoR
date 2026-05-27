testthat::test_that("available_selectors lists bundled SQL templates", {
  selectors <- available_selectors()

  expect_true(
    all(c("LATEST", "EARLIEST", "COUNT", "RANGE_COUNT") %in% selectors)
  )
  expect_true("COUNT_MORE_THEN_1" %in% selectors)
})

test_that(
  "filter_supported_metadata keeps supported when unsupported rows are dropped",
  {
    metadata <- data.table::data.table(
      variable_id = c("a", "b", "c"),
      concept_id = c("A", "B", "C"),
      date_extraction_func = c(
        "latest", "LATEST_PRIOR_ANCHOREDPREG", NA_character_
      )
    )

    filtered <- filter_supported_metadata(metadata)

    expect_s3_class(filtered, "data.table")
    testthat::expect_equal(filtered$variable_id, "a")
    testthat::expect_equal(names(filtered), names(metadata))
  }
)

test_that(
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
