testthat::test_that("validate_anchor_inputs standardizes metadata names", {
  validated <- validate_anchor_inputs(
    population = example_population(),
    metadata = example_metadata(),
    concepts = example_concepts()
  )

  expect_true(all(
    c(
      "selector",
      "start_offset",
      "end_offset",
      "anchor_start_col",
      "anchor_end_col",
      "range_min",
      "range_max"
    ) %in% names(validated$metadata)
  ))

  testthat::expect_equal(validated$metadata$anchor_start_col, rep("T0", 3L))
  testthat::expect_equal(validated$metadata$anchor_end_col, rep("T0", 3L))
  testthat::expect_equal(validated$metadata$range_min[3], 1)
  testthat::expect_equal(validated$metadata$range_max[3], 5)
})

testthat::test_that("validate_anchor_inputs fails on missing anchor columns", {
  metadata <- data.table::data.table(
    variable_id = "x",
    concept_id = "Y",
    window_name = "lookback",
    constructor = "GENERIC",
    selector = "LATEST",
    start_look_back = -1L,
    end_look_back = 0L,
    anchor_date_start = "missing_col",
    anchor_date_end = "T0"
  )

  expect_error(
    validate_anchor_inputs(example_population(), metadata, example_concepts()),
    "missing anchor columns"
  )
})

testthat::test_that("validate_anchor_inputs fails on unsupported selectors", {
  metadata <- example_metadata()
  metadata[, selector := "LATEST_PRIOR_ANCHOREDPREG"]

  expect_error(
    validate_anchor_inputs(example_population(), metadata, example_concepts()),
    "Unsupported selector"
  )
})
