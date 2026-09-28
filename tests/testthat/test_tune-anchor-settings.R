testthat::test_that(
  "anchor_tuning_grid gives 'whole'/'selector' one row and crosses 'variable'",
  {
    grid <- anchor_tuning_grid(
      by_values = c("whole", "variable", "selector"),
      chunk_size_values = c(1L, 2L),
      staging_mode_values = c("memory", "disk"),
      publish_values = c("once", "per_chunk")
    )

    # 1 ("whole") + 1 ("selector") + 2 * 2 * 2 ("variable" cross) = 10.
    testthat::expect_equal(nrow(grid), 10L)
    testthat::expect_equal(sum(grid$by == "whole"), 1L)
    testthat::expect_equal(sum(grid$by == "selector"), 1L)
    testthat::expect_equal(sum(grid$by == "variable"), 8L)

    non_variable_rows <- grid[by != "variable"]
    testthat::expect_true(all(is.na(non_variable_rows$chunk_size)))
    testthat::expect_true(all(is.na(non_variable_rows$staging_mode)))
    testthat::expect_true(all(is.na(non_variable_rows$publish)))

    variable_rows <- grid[by == "variable"]
    testthat::expect_false(anyNA(variable_rows$chunk_size))
    testthat::expect_false(anyNA(variable_rows$staging_mode))
    testthat::expect_false(anyNA(variable_rows$publish))
  }
)

testthat::test_that(
  "tune_anchor_settings ranks combinations and reports the fastest as best",
  {
    result <- tune_anchor_settings(
      population = minimal_population(),
      metadata = minimal_metadata(),
      concepts = minimal_concepts(),
      by_values = c("whole", "variable"),
      chunk_size_values = 1L,
      staging_mode_values = "memory",
      publish_values = "once",
      repeats = 1L
    )

    testthat::expect_true(all(result$runs$success))
    testthat::expect_equal(nrow(result$summary), 2L)
    testthat::expect_false(is.unsorted(result$summary$median_elapsed_secs))
    testthat::expect_equal(
      result$best$setting_id, result$summary$setting_id[1]
    )
  }
)

testthat::test_that(
  "tune_anchor_settings records failures instead of stopping",
  {
    metadata <- minimal_metadata()
    metadata[variable_id == "cov_latest", constructor := "NOPE_CONSTRUCTOR"]

    result <- tune_anchor_settings(
      population = minimal_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      by_values = c("whole", "selector"),
      repeats = 1L
    )

    testthat::expect_false(any(result$runs$success))
    testthat::expect_true(all(grepl(
      "Window function does not exist", result$runs$error_message
    )))
    testthat::expect_true(all(is.na(result$summary$median_elapsed_secs)))
    testthat::expect_null(result$best)
  }
)

testthat::test_that(
  "tune_anchor_settings validates inputs before benchmarking anything",
  {
    testthat::expect_error(
      tune_anchor_settings(
        population = minimal_population(),
        metadata = minimal_metadata(),
        concepts = minimal_concepts(),
        by_values = "not_a_mode"
      ),
      "by_values"
    )
  }
)

testthat::test_that(
  "tune_anchor_settings uses and cleans up the benchmark hive root",
  {
    benchmark_hive_root <- withr::local_tempdir()

    result <- tune_anchor_settings(
      population = minimal_population(),
      metadata = minimal_metadata(),
      concepts = minimal_concepts(),
      by_values = "whole",
      repeats = 1L,
      benchmark_hive_root = benchmark_hive_root
    )

    testthat::expect_true(result$runs$success)
    remaining_files <- list.files(
      benchmark_hive_root,
      all.files = TRUE,
      no.. = TRUE
    )
    testthat::expect_length(remaining_files, 0L)
  }
)

testthat::test_that("tune_anchor_settings requires an existing hive root", {
  missing_root <- tempfile(pattern = "missing-anchor-tune-root-")

  testthat::expect_error(
    tune_anchor_settings(
      population = minimal_population(),
      metadata = minimal_metadata(),
      concepts = minimal_concepts(),
      benchmark_hive_root = missing_root
    ),
    "benchmark_hive_root"
  )
})
