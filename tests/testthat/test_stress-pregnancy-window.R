# Stress test for pregnancy_window_engine(), defined in R/pregnancy_window.R.
#
# Opt-in only: it takes minutes, so it is skipped unless
# ANCHOR_STRESS_TESTS=true. Run it with:
#
#   Sys.setenv(ANCHOR_STRESS_TESTS = "true")
#   devtools::test(filter = "stress-pregnancy-window")
#
# Row counts default to 1k / 5k / 20k window_dt rows and can be overridden
# with e.g. ANCHOR_STRESS_SIZES="1000,10000,50000". Timings are printed and
# written to
# `tempdir()/pregnancy_window_stress.csv`. Synthetic data comes from
# helper-fixtures-stress.R.

stress_sizes <- function() {
  raw <- Sys.getenv("ANCHOR_STRESS_SIZES", "1000,5000,20000")
  as.integer(strsplit(raw, ",", fixed = TRUE)[[1]])
}

time_engine <- function(window_dt, episode_select) {
  gc(verbose = FALSE)
  elapsed <- system.time(
    out <- pregnancy_window_engine(window_dt, episode_select)
  )[["elapsed"]]
  list(out = out, elapsed = elapsed)
}

stress_row <- function(mode, window_dt, timed) {
  data.table::data.table(
    episode_select = mode,
    input_rows = nrow(window_dt),
    output_rows = nrow(timed$out),
    seconds = timed$elapsed,
    ms_per_row = 1000 * timed$elapsed / nrow(window_dt),
    est_minutes_per_1M_rows = timed$elapsed / nrow(window_dt) * 1e6 / 60
  )
}

testthat::test_that("pregnancy_window_engine stress test", {
  testthat::skip_if_not(
    identical(Sys.getenv("ANCHOR_STRESS_TESTS"), "true"),
    "Set ANCHOR_STRESS_TESTS=true to run the stress test."
  )
  withr::local_seed(1026)

  n_variables <- 5L
  modes <- c("CURRENT", "PRIOR", "CURRENT_AND_PRIOR", "OUTSIDE_ALL")
  results <- list()

  for (n_rows in stress_sizes()) {
    window_dt <- stress_window_dt(
      max(1L, n_rows %/% n_variables),
      stress_metadata_default(n_variables)
    )

    for (mode in modes) {
      timed <- time_engine(window_dt, mode)
      out <- timed$out

      # Sanity: output only holds input rows and only real windows.
      testthat::expect_s3_class(out, "data.table")
      testthat::expect_lte(
        data.table::uniqueN(out[, .(person_id, variable_id)]),
        nrow(window_dt)
      )
      testthat::expect_false(anyNA(out$window_start))
      testthat::expect_false(anyNA(out$window_end))
      results[[length(results) + 1L]] <- stress_row(mode, window_dt, timed)
    }
  }

  results <- data.table::rbindlist(results)

  out_file <- file.path(tempdir(), "pregnancy_window_stress.csv")
  data.table::fwrite(results, out_file)

  message("\npregnancy_window_engine stress results:")
  message(paste(utils::capture.output(print(results, digits = 3)),
                collapse = "\n"))
  message("Saved to: ", out_file)

  testthat::expect_true(all(results$seconds >= 0))
})
