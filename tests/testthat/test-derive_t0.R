test_that("derive_t0 finds the earliest event in the requested window", {
  population <- example_population()
  concepts <- example_concepts()

  derived <- derive_t0(
    population = population,
    concepts = concepts,
    concept_id = "T0_EVENT",
    selector = "EARLIEST",
    window_start_col = "candidate_start",
    window_end_col = "candidate_end"
  )

  expect_equal(derived$anchor_date, as.Date(c("2024-01-05", "2024-01-10")))
})

test_that("derive_t0 returns NA when no concept is found", {
  population <- example_population()
  concepts <- example_concepts()

  derived <- derive_t0(
    population = population,
    concepts = concepts,
    concept_id = "DOES_NOT_EXIST"
  )

  expect_true(all(is.na(derived$anchor_date)))
})
