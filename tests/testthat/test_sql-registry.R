testthat::test_that("selector_sql_path resolves SQL resources", {
  sql_path <- selector_sql_path("LATEST")

  testthat::expect_true(file.exists(sql_path))
  testthat::expect_match(basename(sql_path), "^latest\\.sql$")
})

mocked_selector_sql_root <- function(system_file) {
  root_fn <- selector_sql_root
  environment(root_fn) <- list2env(
    list(system.file = system_file),
    parent = environment(selector_sql_root)
  )
  root_fn
}

mocked_selector_sql_path <- function(root_fn) {
  path_fn <- selector_sql_path
  environment(path_fn) <- list2env(
    list(selector_sql_root = root_fn),
    parent = environment(selector_sql_path)
  )
  path_fn
}

testthat::test_that("selector_sql_root errors when sql root cannot be found", {
  root_fn <- mocked_selector_sql_root(function(...) "")

  tmp <- withr::local_tempdir()
  withr::local_dir(tmp)

  testthat::expect_error(
    root_fn(),
    "Could not locate `inst/sql` for the anchoR package.",
    fixed = TRUE
  )
})

testthat::test_that(
  "selector_sql_root falls back to inst/sql under the working directory",
  {
    root_fn <- mocked_selector_sql_root(function(...) "")

    tmp <- withr::local_tempdir()
    local_root <- file.path(tmp, "inst", "sql")
    dir.create(local_root, recursive = TRUE)
    withr::local_dir(tmp)

    testthat::expect_identical(
      root_fn(),
      normalizePath(local_root, winslash = "/")
    )
  }
)

testthat::test_that(
  "selector_sql_path errors when the selector template is missing",
  {
    tmp <- withr::local_tempdir()
    path_fn <- mocked_selector_sql_path(function() tmp)

    testthat::expect_error(
      path_fn("latest"),
      "No SQL template found for selector `LATEST`.",
      fixed = TRUE
    )
  }
)

testthat::test_that("", {})

testthat::test_that("", {})
testthat::test_that("", {})
testthat::test_that("", {})
testthat::test_that("", {})
