test_that("define_window computes relative windows", {
  windows <- define_window(example_population(), example_metadata())

  expect_s3_class(windows, "data.table")
  expect_equal(nrow(windows), 6L)

  cov_latest_1 <- windows[person_id == "1" & variable_id == "cov_latest"]
  expect_equal(cov_latest_1$window_start, as.Date("2023-12-02"))
  expect_equal(cov_latest_1$window_end, as.Date("2024-01-01"))
  expect_true(cov_latest_1$window_valid)
})

test_that("define_window supports alternate anchor columns", {
  metadata <- data.table::data.table(
    variable_id = "preg_cov",
    concept_id = "PREG_X",
    selector = "LATEST",
    start_look_back = 0L,
    end_look_back = 0L,
    anchor_date_start = "lmp_date",
    anchor_date_end = "pregnancy_end_date"
  )

  windows <- define_window(example_population(), metadata)

  expect_equal(windows$window_start, example_population()$lmp_date)
  expect_equal(windows$window_end, example_population()$pregnancy_end_date)
})

test_that("define_window uses the supplied anchor column for T0 metadata", {
  population <- data.table::copy(example_population())
  data.table::setnames(population, "T0", "anchor_date")

  windows <- define_window(
    population = population,
    metadata = example_metadata(),
    anchor_col = "anchor_date"
  )

  cov_latest_1 <- windows[person_id == "1" & variable_id == "cov_latest"]
  expect_equal(cov_latest_1$window_start, as.Date("2023-12-02"))
  expect_equal(cov_latest_1$window_end, as.Date("2024-01-01"))
})
