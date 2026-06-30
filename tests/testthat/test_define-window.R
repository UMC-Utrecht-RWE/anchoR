custom_define_window <- function(required_cols = "index_date") {
  my_window <- make_constructor(
    transform_fn = function(window_dt) {
      window_dt[, window_start := index_date - 30]
      window_dt[, window_end := index_date + 30]
      window_dt[]
    },
    required_cols = required_cols
  )

  define_window_with_custom <- define_window
  environment(define_window_with_custom) <- list2env(
    list(custom_window = my_window),
    parent = environment(define_window)
  )

  population <- data.table::data.table(
    person_id = c("1", "2"),
    T0 = as.Date(c("2024-01-01", "2024-01-15")),
    index_date = as.Date(c("2024-02-01", "2024-02-15"))
  )

  metadata <- data.table::data.table(
    variable_id = "custom_window",
    concept_id = "CUSTOM",
    constructor = "CUSTOM",
    selector = "LATEST",
    start_look_back = 0L,
    end_look_back = 0L
  )

  list(
    define_window = define_window_with_custom,
    population = population,
    metadata = metadata
  )
}

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

  testthat::expect_no_error(
    define_window(population, example_metadata())
  )
})

testthat::test_that("generic_window_check works correctly", {
  # Test with invalid window type
  invalid_window <- data.frame(
    anchor_start_col = "T0",
    anchor_end_col = "T0",
    start_offset = 0,
    end_offset = 0
  )

  testthat::expect_error(
    generic_window_check(invalid_window),
    "window_dt must be a data.table"
  )

  # Test with invalid window data
  invalid_window <- data.table::data.table(
    anchor_start_col = "T0",
    anchor_end_col = "T0",
    start_offset = 0,
    end_offset = 0
  )

  testthat::expect_error(
    generic_window_check(invalid_window),
    "window_dt is missing mandatory metadata columns"
  )

  # Test with valid window data
  valid_window <- data.table::data.table(
    constructor = "T0"
  )
  testthat::expect_no_error(
    generic_window_check(valid_window)
  )
})

testthat::test_that("make_constructor fails with messages", {
  testthat::expect_error(
    make_constructor(transform_fn = "not_a_function"),
    "transform_fn must be a function"
  )

  testthat::expect_error(
    make_constructor(transform_fn = function(x) x, required_cols = 123),
    "required_cols must be a character vector"
  )

  testthat::expect_error(
    make_constructor(
      transform_fn = function(x) x,
      check_fn = "not_a_function"
    ),
    "check_fn must be NULL or a function"
  )

  case <- custom_define_window(required_cols = "wrong_column")

  testthat::expect_error(
    case$define_window(case$population, case$metadata),
    "missing required column\\(s\\): wrong_column"
  )
})

testthat::test_that("define_window applies a custom constructor", {
  case <- custom_define_window()

  windows <- case$define_window(case$population, case$metadata)

  testthat::expect_equal(
    windows$window_start,
    as.Date(c("2024-01-02", "2024-01-16"))
  )
  testthat::expect_equal(
    windows$window_end,
    as.Date(c("2024-03-02", "2024-03-16"))
  )
  testthat::expect_true(all(windows$window_valid))
})

testthat::test_that("generic_window computes start and end dates", {
  window_dt <- data.table::data.table(
    constructor = "GENERIC",
    anchor_start_col = "T0",
    anchor_end_col = "T0",
    start_offset = c(-30L, 0L),
    end_offset = c(0L, 30L),
    T0 = as.Date(c("2024-02-01", "2024-02-15"))
  )

  out <- generic_window(window_dt)

  testthat::expect_equal(
    out$window_start,
    as.Date(c("2024-01-02", "2024-02-15"))
  )
  testthat::expect_equal(
    out$window_end,
    as.Date(c("2024-02-01", "2024-03-16"))
  )
})


testthat::test_that("cross_join_population_metadata works as expected", {
    population <- minimal_population()
    metadata <- minimal_metadata()
    res <- cross_join_population_metadata(population, metadata)

    testthat::expect_equal(nrow(res), nrow(population) * nrow(metadata))
    testthat::expect_equal(
      names(res),
      c("person_id", "T0", "variable_id", "concept_id", "constructor",
        "selector", "start_look_back", "end_look_back")
    )
})
