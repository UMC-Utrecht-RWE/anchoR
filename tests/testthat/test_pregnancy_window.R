#--- Tests for nest_episodes_onto_population
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

#--- Tests for classify_episodes
testthat::test_that("Test classify_episodes intended behaviour", {
  # T0 before the first episode
  testthat::expect_equal(
    classify_episodes(
      pregnancy_episodes_simple(),
      as.Date("2019-12-31")
    )$episode_class,
    c("future", "future")
  )
  # T0 in the first episode
  testthat::expect_equal(
    classify_episodes(
      pregnancy_episodes_simple(),
      as.Date("2020-01-01")
    )$episode_class,
    c("current", "future")
  )

  # T0 between the two episodes
  testthat::expect_equal(
    classify_episodes(
      pregnancy_episodes_simple(),
      as.Date("2020-07-01")
    )$episode_class,
    c("prior", "future")
  )

  # T0 in the second episode
  testthat::expect_equal(
    classify_episodes(
      pregnancy_episodes_simple(),
      as.Date("2021-01-01")
    )$episode_class,
    c("prior", "current")
  )
  # T0 after the second episode
  testthat::expect_equal(
    classify_episodes(
      pregnancy_episodes_simple(),
      as.Date("2023-01-01")
    )$episode_class,
    c("prior", "prior")
  )
}

#--- Tests for define_episode_boundary
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
