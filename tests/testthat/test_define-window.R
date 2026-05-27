testthat::test_that("define_window computes relative windows", {
  windows <- define_window(example_population(), example_metadata())

  expect_s3_class(windows, "data.table")
  testthat::expect_equal(nrow(windows), 6L)

  cov_latest_1 <- windows[person_id == "1" & variable_id == "cov_latest"]
  testthat::expect_equal(cov_latest_1$window_start, as.Date("2023-12-02"))
  testthat::expect_equal(cov_latest_1$window_end, as.Date("2024-01-01"))
  expect_true(cov_latest_1$window_valid)
})

testthat::test_that("define_window supports alternate anchor columns", {
  metadata <- data.table::data.table(
    variable_id = "preg_cov",
    concept_id = "PREG_X",
    window_name = "lookback",
    constructor = "GENERIC",
    selector = "LATEST",
    start_look_back = 0L,
    end_look_back = 0L,
    anchor_date_start = "lmp_date",
    anchor_date_end = "pregnancy_end_date"
  )

  windows <- define_window(example_population(), metadata)

  testthat::expect_equal(windows$window_start, example_population()$lmp_date)
  testthat::expect_equal(
    windows$window_end, example_population()$pregnancy_end_date
  )
})

testthat::test_that("uses the supplied anchor column for T0 metadata", {
  population <- data.table::copy(example_population())
  data.table::setnames(population, "T0", "anchor_date")

  windows <- define_window(
    population = population,
    metadata = example_metadata(),
    anchor_col = "anchor_date"
  )

  cov_latest_1 <- windows[person_id == "1" & variable_id == "cov_latest"]
  testthat::expect_equal(cov_latest_1$window_start, as.Date("2023-12-02"))
  testthat::expect_equal(cov_latest_1$window_end, as.Date("2024-01-01"))
})

testthat::test_that("Missing function", {
  metadata <- data.table::data.table(
    variable_id = "preg_cov",
    concept_id = "PREG_X",
    window_name = "lookback",
    constructor = "ERROR",
    selector = "LATEST",
    start_look_back = 0L,
    end_look_back = 0L,
    anchor_date_start = "lmp_date",
    anchor_date_end = "pregnancy_end_date"
  )

  testthat::expect_error(
    define_window(example_population(), metadata),
    "Window function does not exist: error_window"
  )
})

testthat::test_that("define_window reports window function failures", {
  population <- data.table::copy(example_population())
  population[, T0 := as.character(T0)]

  testthat::expect_error(
    define_window(population, example_metadata()),
    "Error while applying window function 'generic_window':"
  )
})
