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

  testthat::expect_error(
    validate_anchor_inputs(example_population(), metadata, example_concepts()),
    "Unsupported selector"
  )
})

testthat::test_that("returns input when selectors are supported", {
  metadata <- data.table::data.table(
    selector = c("LATEST", "COUNT", "LATEST")
  )

  result <- metadata_supported_selectors(metadata)

  testthat::expect_identical(result, metadata)
})

testthat::test_that(
  "reports unsupported selectors once with guidance",
  {
    old_appender <- logger::log_appender()
    if (!is.function(old_appender)) old_appender <- logger::appender_console
    withr::defer(logger::log_appender(old_appender))
    logger::log_appender(logger::appender_void)

    metadata <- data.table::data.table(
      selector = c("LATEST", "UNSUPPORTED_A", "UNSUPPORTED_A", "UNSUPPORTED_B")
    )

    err <- tryCatch(
      {
        metadata_supported_selectors(metadata)
        NULL
      },
      error = identity
    )

    expected_msg <- paste(
      "Unsupported selector(s) in `metadata`:",
      "UNSUPPORTED_A, UNSUPPORTED_B",
      sprintf(
        "Available selectors in package `anchoR`: %s.",
        paste(available_selectors(), collapse = ", ")
      ),
      paste(
        "Use `filter_supported_metadata()` if you want to drop unsupported",
        "rows before calling `anchor()`."
      )
    )

    testthat::expect_s3_class(err, "error")
    testthat::expect_identical(conditionMessage(err), expected_msg)
  }
)

testthat::test_that(
  "metadata_supported_selectors stops without attaching a call",
  {
    old_appender <- logger::log_appender()
    if (!is.function(old_appender)) old_appender <- logger::appender_console
    withr::defer(logger::log_appender(old_appender))
    logger::log_appender(logger::appender_void)

    metadata <- data.table::data.table(selector = "UNSUPPORTED_A")

    err <- tryCatch(
      {
        metadata_supported_selectors(metadata)
        NULL
      },
      error = identity
    )

    testthat::expect_s3_class(err, "error")
    testthat::expect_null(conditionCall(err))
  }
)

testthat::test_that("returns input when anchors exist", {
  population <- example_population()
  metadata <- data.table::data.table(
    anchor_start_col = c("T0", "candidate_start"),
    anchor_end_col = c("candidate_end", "T0")
  )

  result <- population_anchor_columns(population, metadata)

  testthat::expect_identical(result, population)
})

testthat::test_that("returns input when anchors exist", {
  population <- example_population()
  metadata <- data.table::data.table(
    anchor_start_col = c("T0", "missing_start"),
    anchor_end_col = c("candidate_end", "missing_end")
  )

  testthat::expect_error(
    population_anchor_columns(population, metadata),
    "`population` is missing anchor columns referenced by `metadata`: missing_start, missing_end\\." # nolint
  )
})
