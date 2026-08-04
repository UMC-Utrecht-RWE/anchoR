testthat::test_that("Test nest_episodes_onto_population intended behaviour", {
  nested <- nest_episodes_onto_population(
    pregnancy_population_simple(),
    pregnancy_episodes_simple()
  )
  testthat::expect_equal(typeof(nested$.episodes), "list")
  testthat::expect_true(nested$.episodes[[1]]$start_episode[1] == "2020-01-01")

  nested <- nest_episodes_onto_population(
    pregnancy_population_complex(),
    pregnancy_episodes_complex()
  )

  testthat::expect_equal(dim(nested$.episodes[[1]]), c(3, 2))
})

testthat::test_that("Test define_episode_boundary intended behaviour", {
  window_dt <- define_window(
    pregnancy_population_simple(),
    pregnancy_metadata_simple(),
    episodes = pregnancy_episodes_simple()
  )
})

testthat::test_that("", {})

testthat::test_that("", {})

testthat::test_that("", {})

testthat::test_that("", {})
testthat::test_that("", {})
testthat::test_that("", {})

testthat::test_that("", {})
testthat::test_that("", {})
testthat::test_that("", {})
testthat::test_that("", {})

testthat::test_that("", {})
testthat::test_that("", {})

testthat::test_that("", {})
