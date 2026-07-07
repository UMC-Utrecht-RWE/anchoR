testthat::test_that("validate_anchor_inputs standardizes metadata names", {
  # minimal_metadata() already uses the start_look_back/end_look_back
  # aliases, so this exercises the renaming to start_offset/end_offset too.
  validated <- validate_anchor_inputs(
    population = minimal_population(),
    metadata = minimal_metadata(),
    concepts = minimal_concepts()
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
  # minimal_metadata() does not set range_min/range_max, so they default to
  # NA even for its RANGE_COUNT row (lab_range).
  testthat::expect_true(is.na(validated$metadata$range_min[3]))
  testthat::expect_true(is.na(validated$metadata$range_max[3]))
})

testthat::test_that(
  "validate_anchor_inputs accepts character anchor dates in YYYY-mm-dd format",
  {
    population <- minimal_population()[1:2]
    population[, T0 := as.character(T0)]

    validated <- validate_anchor_inputs(
      population = population,
      metadata = minimal_metadata(),
      concepts = minimal_concepts()
    )

    testthat::expect_s3_class(validated$population$T0, "Date")
    testthat::expect_identical(
      as.character(validated$population$T0),
      c("2024-01-01", "2024-01-15")
    )
  }
)

testthat::test_that(
  "validate_anchor_inputs fails on population anchor dates outside YYYY-mm-dd",
  {
    population <- minimal_population()[1:2]
    population[, T0 := c("01-01-2024", "2024-01-15")]

    testthat::expect_error(
      validate_anchor_inputs(
        population = population,
        metadata = minimal_metadata(),
        concepts = minimal_concepts()
      ),
      "must use the date format YYYY-mm-dd"
    )
  }
)

testthat::test_that(
  "validate_anchor_inputs fails on invalid population anchor dates",
  {
    population <- minimal_population()[1:2]
    population[, T0 := c("2024-02-30", "2024-01-15")]

    testthat::expect_error(
      validate_anchor_inputs(
        population = population,
        metadata = minimal_metadata(),
        concepts = minimal_concepts()
      ),
      "contains invalid dates; use the format YYYY-mm-dd"
    )
  }
)

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
    validate_anchor_inputs(minimal_population(), metadata, minimal_concepts()),
    "missing anchor columns"
  )
})

testthat::test_that("validate_anchor_inputs fails on unsupported selectors", {
  metadata <- minimal_metadata()
  metadata[, selector := "LATEST_PRIOR_ANCHOREDPREG"]

  testthat::expect_error(
    validate_anchor_inputs(minimal_population(), metadata, minimal_concepts()),
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
  # This test is purely about column presence, not real anchoring data, so
  # it builds its own population with the extra anchor columns it needs
  # rather than relying on minimal_population(), which only has T0.
  population <- data.table::data.table(
    person_id = "1",
    T0 = as.Date("2024-01-01"),
    candidate_start = as.Date("2023-01-01"),
    candidate_end = as.Date("2023-06-01")
  )
  metadata <- data.table::data.table(
    anchor_start_col = c("T0", "candidate_start"),
    anchor_end_col = c("candidate_end", "T0")
  )

  result <- population_anchor_columns(population, metadata)

  testthat::expect_identical(result, population)
})

testthat::test_that("errors when referenced anchor columns are missing", {
  population <- minimal_population()
  metadata <- data.table::data.table(
    anchor_start_col = c("T0", "missing_start"),
    anchor_end_col = c("T0", "missing_end")
  )

  testthat::expect_error(
    population_anchor_columns(population, metadata),
    "`population` is missing anchor columns referenced by `metadata`: missing_start, missing_end\\." # nolint
  )
})

testthat::test_that(
  "population_columns_for_window keeps only person_id and referenced anchors",
  {
    population <- example_population()
    metadata <- data.table::data.table(
      anchor_start_col = c("T0", "lmp_date"),
      anchor_end_col = c("T0", "pregnancy_end_date")
    )

    result <- population_columns_for_window(population, metadata)

    testthat::expect_identical(
      names(result),
      c("person_id", "T0", "lmp_date", "pregnancy_end_date")
    )
    testthat::expect_identical(result$person_id, population$person_id)
  }
)
