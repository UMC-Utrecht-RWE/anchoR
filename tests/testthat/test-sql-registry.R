test_that("selector_sql_path resolves SQL resources", {
  sql_path <- selector_sql_path("LATEST")

  expect_true(file.exists(sql_path))
  expect_match(basename(sql_path), "^latest\\.sql$")
})
