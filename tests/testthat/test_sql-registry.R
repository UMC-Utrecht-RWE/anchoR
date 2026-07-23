testthat::test_that("selector_sql_path resolves SQL resources", {
  sql_path <- selector_sql_path("LATEST")

  testthat::expect_true(file.exists(sql_path))
  testthat::expect_match(basename(sql_path), "^latest\\.sql$")
})

testthat::test_that(
  "add_parquet_export writes one file per selector instead of overwriting",
  {
    hive_path <- withr::local_tempdir()

    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

    DBI::dbExecute(
      con,
      "CREATE TABLE latest_rows AS
       SELECT 'mixed_selector' AS variable_id, 'PRIOR' AS value"
    )
    DBI::dbExecute(
      con,
      "CREATE TABLE earliest_rows AS
       SELECT 'mixed_selector' AS variable_id, 'AFTER' AS value"
    )

    DBI::dbExecute(
      con,
      add_parquet_export("SELECT * FROM latest_rows", hive_path, "LATEST")
    )
    DBI::dbExecute(
      con,
      add_parquet_export(
        "SELECT * FROM earliest_rows", hive_path, " earliest "
      )
    )

    partition_path <- file.path(hive_path, "variable_id=mixed_selector")

    testthat::expect_setequal(
      list.files(partition_path),
      c("latest_0.parquet", "earliest_0.parquet")
    )

    anchored <- data.table::as.data.table(
      DBI::dbGetQuery(
        con,
        sprintf(
          "SELECT * FROM read_parquet('%s/**/*.parquet', hive_partitioning = true)", # nolint
          hive_path
        )
      )
    )
    data.table::setorder(anchored, value)

    testthat::expect_equal(anchored$value, c("AFTER", "PRIOR"))
  }
)

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

testthat::test_that("run_selector_queries errors on invalid anchor_hive_path", {
  old_appender <- logger::log_appender()
  if (!is.function(old_appender)) old_appender <- logger::appender_console
  withr::defer(logger::log_appender(old_appender))
  logger::log_appender(logger::appender_void)

  testthat::expect_error(
    run_selector_queries(
      con = NULL,
      selectors = "GENERIC",
      anchor_hive_path = "ciao"
    ),
    "`anchor_hive_path` must be a valid path!",
    fixed = TRUE
  )
})

testthat::test_that("run_selector_queries reports selector context on error", {
  query_fn <- run_selector_queries
  environment(query_fn) <- list2env(
    list(
      run_selector_query = function(
        con, selector, anchor_hive_path = NULL, accumulate_table = NULL
      ) {
        stop("boom", call. = FALSE)
      }
    ),
    parent = environment(run_selector_queries)
  )

  old_appender <- logger::log_appender()
  if (!is.function(old_appender)) old_appender <- logger::appender_console
  withr::defer(logger::log_appender(old_appender))
  logger::log_appender(logger::appender_void)

  testthat::expect_error(
    query_fn(
      con = NULL,
      selectors = "CIAO",
      anchor_hive_path = withr::local_tempdir()
    ),
    "Error while processing selector CIAO: boom",
    fixed = TRUE
  )
})
