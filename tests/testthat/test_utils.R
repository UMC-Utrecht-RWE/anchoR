testthat::test_that("if target already exists, aliases are ignored", {
  population <- example_population()
  original_names <- names(population)

  # T0 already exists, so aliases should be ignored
  rename_first_matching_column(
    population,
    target = "T0"
  )

  expect_identical(names(population), original_names)
})

testthat::test_that("renames matching alias to target", {
  # Create data with an old column name that should be renamed
  dt <- data.table::data.table(
    person_id = c("1", "2"),
    start_look_back = as.integer(c(-30, -30))
  )

  rename_first_matching_column(
    dt,
    target = "start_offset",
    aliases = "start_look_back"
  )

  testthat::expect_true("start_offset" %in% names(dt))
  expect_false("start_look_back" %in% names(dt))
})

testthat::test_that("Returns unchanged when target and aliases don't exist", {
  dt <- data.table::data.table(
    person_id = c("1", "2"),
    value = c(1, 2)
  )
  original_names <- names(dt)

  rename_first_matching_column(
    dt,
    target = "nonexistent_target",
    aliases = c("alias1", "alias2")
  )

  expect_identical(names(dt), original_names)
})

testthat::test_that("handles multiple aliases, renames first match", {
  # Create data with one of several possible old column names
  dt <- data.table::data.table(
    person_id = c("1", "2"),
    end_look_back = as.integer(c(0, 0))
  )

  # Provide multiple aliases; should rename first matching one
  rename_first_matching_column(
    dt,
    target = "end_offset",
    aliases = c("end_date", "end_look_back", "end_value")
  )

  testthat::expect_true("end_offset" %in% names(dt))
  expect_false("end_look_back" %in% names(dt))
})

testthat::test_that("empty aliases vector leaves data unchanged", {
  dt <- data.table::data.table(
    person_id = c("1", "2"),
    old_column = c(1, 2)
  )
  original_names <- names(dt)

  rename_first_matching_column(
    dt,
    target = "new_column",
    aliases = character()
  )

  expect_identical(names(dt), original_names)
})

testthat::test_that("returns invisibly", {
  dt <- data.table::data.table(person_id = c("1", "2"))

  result <- rename_first_matching_column(
    dt,
    target = "test",
    aliases = "nonexistent"
  )

  # Invisible return means the object is returned but not printed automatically
  # The result should be a data.frame with the same data
  expect_false(is.null(result))
  testthat::expect_true(is.data.frame(result))
  expect_identical(names(result), c("person_id"))
})

testthat::test_that("respects order of aliases when multiple exist", {
  # Create data with two possible old column names, but NOT the target
  dt <- data.table::data.table(
    person_id = c("1", "2"),
    date_extraction_func = c("LATEST", "LATEST"),
    old_selector = c("OLD", "OLD")
  )

  # Provide aliases in specific order; should match and rename first one
  rename_first_matching_column(
    dt,
    target = "selector",
    aliases = c("date_extraction_func", "old_selector")
  )

  # it should be renamed to selector since it's first in aliases
  testthat::expect_true("selector" %in% names(dt))
  expect_false("date_extraction_func" %in% names(dt))
  # Second alias shouldn't be touched
  testthat::expect_true("old_selector" %in% names(dt))
})

testthat::test_that("normalize_selector_name: converts to uppercase", {
  testthat::expect_equal(normalize_selector_name("latest"), "LATEST")
  testthat::expect_equal(normalize_selector_name("count"), "COUNT")
  testthat::expect_equal(normalize_selector_name("Range_Count"), "RANGE_COUNT")
  testthat::expect_equal(normalize_selector_name(123), "123")
  testthat::expect_equal(normalize_selector_name(TRUE), "TRUE")
  testthat::expect_equal(normalize_selector_name(FALSE), "FALSE")
})

testthat::test_that("normalize_selector_name: trims whitespace", {
  testthat::expect_equal(normalize_selector_name("  latest  "), "LATEST")
  testthat::expect_equal(normalize_selector_name("\tCOUNT\n"), "COUNT")
  testthat::expect_equal(
    normalize_selector_name(" range_count "), "RANGE_COUNT"
  )
})

testthat::test_that("normalize_selector_name: handles vector input", {
  result <- normalize_selector_name(c("latest", "count", "  range  "))
  testthat::expect_equal(result, c("LATEST", "COUNT", "RANGE"))
})

testthat::test_that("normalize_selector_name: handles empty and NA values", {
  testthat::expect_equal(normalize_selector_name(""), "")
  testthat::expect_true(is.na(normalize_selector_name(NA)))
})

testthat::test_that("replaces T0 and empty values with anchor_col", {
  result <- normalize_anchor_reference(
    c("T0", "t0", "  T0  ", "", NA, "OTHER_COL"),
    anchor_col = "visit_date"
  )
  testthat::expect_equal(
    result,
    c(
      "visit_date", "visit_date", "visit_date",
      "visit_date", "visit_date", "OTHER_COL"
    )
  )
})

testthat::test_that("preserves non-T0 values unchanged", {
  result <- normalize_anchor_reference(
    c("enrollment_date", "  baseline_date  ", "event_date"),
    anchor_col = "T0"
  )
  testthat::expect_equal(
    result,
    c("enrollment_date", "baseline_date", "event_date")
  )
})

testthat::test_that("errors when required columns are missing", {
  dt <- data.table::data.table(person_id = c("1", "2"))

  testthat::expect_error(
    assert_has_columns(
      dt,
      required = c("person_id", "date"), arg = "population"
    ),
    regexp = "`population` is missing required columns: date\\."
  )
})
