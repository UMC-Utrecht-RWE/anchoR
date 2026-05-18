test_that("anchor applies selector SQL templates", {
  anchored <- anchor(
    population = example_population(),
    metadata = example_metadata(),
    concepts = example_concepts(),
    keep_all = FALSE
  )

  expect_s3_class(anchored, "data.table")
  expect_equal(nrow(anchored), 4L)

  latest_1 <- anchored[person_id == "1" & variable_id == "cov_latest"]
  count_1 <- anchored[person_id == "1" & variable_id == "cov_count"]
  latest_2 <- anchored[person_id == "2" & variable_id == "cov_latest"]
  range_2 <- anchored[person_id == "2" & variable_id == "lab_range"]

  expect_equal(latest_1$value, "TRUE")
  expect_equal(count_1$value, "2")
  expect_equal(latest_2$value, "FALSE")
  expect_equal(range_2$value, "1")
  expect_equal(range_2$date, as.Date("2024-01-10"))
})

test_that("anchor can keep unmatched rows", {
  anchored <- anchor(
    population = example_population(),
    metadata = example_metadata(),
    concepts = example_concepts(),
    keep_all = TRUE
  )

  expect_equal(nrow(anchored), 6L)

  unmatched <- anchored[person_id == "1" & variable_id == "lab_range"]
  expect_true(is.na(unmatched$value))
  expect_true(is.na(unmatched$date))
})
