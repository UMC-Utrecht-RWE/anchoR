test_that("available_selectors lists bundled SQL templates", {
  selectors <- available_selectors()

  expect_true(all(c("LATEST", "EARLIEST", "COUNT", "RANGE_COUNT") %in% selectors))
  expect_true("COUNT_MORE_THEN_1" %in% selectors)
})

test_that("filter_supported_metadata keeps supported rows and warns on dropped rows", {
  metadata <- data.table::data.table(
    variable_id = c("a", "b", "c"),
    concept_id = c("A", "B", "C"),
    date_extraction_func = c("latest", "LATEST_PRIOR_ANCHOREDPREG", NA_character_)
  )

  expect_warning(
    filtered <- filter_supported_metadata(metadata),
    "Dropped 2 metadata row"
  )

  expect_s3_class(filtered, "data.table")
  expect_equal(filtered$variable_id, "a")
  expect_equal(names(filtered), names(metadata))
})

test_that("filter_supported_metadata does not warn when all selectors are supported", {
  metadata <- data.table::data.table(
    variable_id = c("a", "b"),
    concept_id = c("A", "B"),
    selector = c("LATEST", "count")
  )

  expect_no_warning(
    filtered <- filter_supported_metadata(metadata)
  )

  expect_equal(filtered$selector, c("LATEST", "count"))
})
