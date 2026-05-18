test_that("available_selectors lists bundled SQL templates", {
  selectors <- available_selectors()

  expect_true(all(c("LATEST", "EARLIEST", "COUNT", "RANGE_COUNT") %in% selectors))
  expect_true("COUNT_MORE_THEN_1" %in% selectors)
})
