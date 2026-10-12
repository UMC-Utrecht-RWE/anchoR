# End-to-end and edge-case tests for the episode-based constructors.
#
# test_pregnancy_window.R covers the window formula unit by unit; this file
# runs whole scenarios through define_window()/anchor() so a regression in
# nesting, classification, clipping, SQL, or the `by` modes shows up as a
# wrong number of matched pregnancies.

#--- Nesting episodes onto population ---------------------------------------

testthat::test_that("nesting ignores an `id` column in episodes", {
  # Regression: the per-person lookup used to resolve `id` to the episodes
  # table's own `id` column, so every person silently got zero episodes.
  episodes <- pregnancy_episodes_lookback()
  episodes[, id := "unrelated"]

  nested <- nest_episodes_onto_population(
    pregnancy_population_lookback(), episodes
  )

  testthat::expect_equal(nrow(nested$.episodes[[1]]), 5L)
})

testthat::test_that("nesting matches person_id across integer and character", {
  episodes <- pregnancy_episodes_lookback()
  episodes[, person_id := 1L]

  nested <- nest_episodes_onto_population(
    pregnancy_population_lookback(), episodes
  )

  testthat::expect_equal(nrow(nested$.episodes[[1]]), 5L)
})

testthat::test_that("a person without episodes gets an empty episode table", {
  population <- data.table::data.table(
    person_id = c("1", "2"),
    T0 = as.Date("2026-06-15")
  )

  nested <- nest_episodes_onto_population(
    population, pregnancy_episodes_lookback()
  )

  testthat::expect_equal(nrow(nested$.episodes[[2]]), 0L)
  testthat::expect_named(
    nested$.episodes[[2]], c("start_episode", "end_episode")
  )
})

#--- Prior pregnancies within a lookback, end to end ------------------------

prior_lookback_metadata <- function(selector = "ALL", ...) {
  episode_metadata_row(
    "in_prior_pregnancy",
    selector = selector,
    variable_id = "prior_10y",
    anchor_start_offset = -3652,
    ...
  )
}

testthat::test_that("in_prior_pregnancy finds every pregnancy in a 10-year lookback", { # nolint: line_length_linter.
  result <- run_episode_anchor(
    pregnancy_population_lookback(),
    prior_lookback_metadata(),
    pregnancy_concepts_lookback(),
    pregnancy_episodes_lookback()
  )

  # 2014: fully before the lookback, excluded.
  # 2016: straddles the lookback start (2016-06-15), so only its LATE
  #       record is kept.
  # 2018, 2020: fully inside, both records kept.
  # Current pregnancy: not prior, excluded.
  testthat::expect_equal(
    sort(result$date),
    as.Date(c(
      "2016-08-22",
      "2018-01-11", "2018-08-22",
      "2020-01-11", "2020-08-22"
    ))
  )
})

testthat::test_that("without a lookback, in_prior_pregnancy finds every earlier pregnancy", { # nolint: line_length_linter.
  metadata <- episode_metadata_row("in_prior_pregnancy", selector = "COUNT")

  result <- run_episode_anchor(
    pregnancy_population_lookback(),
    metadata,
    pregnancy_concepts_lookback(),
    pregnancy_episodes_lookback()
  )

  # Four earlier pregnancies x two records each.
  testthat::expect_equal(result$value, "8")
})

testthat::test_that("LATEST over prior pregnancies picks the most recent record", { # nolint: line_length_linter.
  result <- run_episode_anchor(
    pregnancy_population_lookback(),
    prior_lookback_metadata("LATEST"),
    pregnancy_concepts_lookback(),
    pregnancy_episodes_lookback()
  )

  testthat::expect_equal(result$date, as.Date("2020-08-22"))
  testthat::expect_equal(result$value, "LATE")
})

testthat::test_that("every `by` mode counts the same prior pregnancies", {
  run_count <- function(...) {
    run_episode_anchor(
      pregnancy_population_lookback(),
      prior_lookback_metadata("COUNT"),
      pregnancy_concepts_lookback(),
      pregnancy_episodes_lookback(),
      ...
    )$value
  }

  testthat::expect_equal(run_count(by = "whole"), "5")
  testthat::expect_equal(run_count(by = "selector"), "5")
  testthat::expect_equal(
    run_count(by = "variable", chunk_size = 1L, staging_mode = "memory"),
    "5"
  )
  testthat::expect_equal(
    run_count(
      by = "variable", chunk_size = 1L,
      staging_mode = "disk", publish = "per_chunk"
    ),
    "5"
  )
})

testthat::test_that("episode order in the input does not change the result", {
  episodes <- pregnancy_episodes_lookback()[c(5L, 2L, 4L, 1L, 3L)]

  result <- run_episode_anchor(
    pregnancy_population_lookback(),
    prior_lookback_metadata("COUNT"),
    pregnancy_concepts_lookback(),
    episodes
  )

  testthat::expect_equal(result$value, "5")
})

testthat::test_that("episodes with an `id` column still match end to end", {
  episodes <- pregnancy_episodes_lookback()
  episodes[, id := "unrelated"]

  result <- run_episode_anchor(
    pregnancy_population_lookback(),
    prior_lookback_metadata("COUNT"),
    pregnancy_concepts_lookback(),
    episodes
  )

  testthat::expect_equal(result$value, "5")
})

testthat::test_that("each T0 of the same person gets its own prior pregnancies", { # nolint: line_length_linter.
  # 2019-06-01 is outside every pregnancy, so "prior" falls back to
  # "ended before T0": 2014, 2016 and 2018, all inside that T0's lookback.
  population <- data.table::data.table(
    person_id = "1",
    T0 = as.Date(c("2026-06-15", "2019-06-01"))
  )

  result <- run_episode_anchor(
    population,
    prior_lookback_metadata("COUNT"),
    pregnancy_concepts_lookback(),
    pregnancy_episodes_lookback()
  )
  data.table::setorder(result, T0)

  testthat::expect_equal(result$T0, as.Date(c("2019-06-01", "2026-06-15")))
  testthat::expect_equal(result$value, c("6", "5"))
})

testthat::test_that("people only get their own pregnancies", {
  episodes <- rbind(
    pregnancy_episodes_lookback(),
    data.table::data.table(
      person_id = "2",
      start_episode = as.Date("2019-01-01"),
      end_episode = as.Date("2019-09-01")
    )
  )
  population <- data.table::data.table(
    person_id = c("1", "2", "3"),
    T0 = as.Date("2026-06-15")
  )
  concepts <- rbind(
    pregnancy_concepts_lookback(),
    data.table::data.table(
      person_id = c("2", "3"),
      concept_id = "PREG_MARKER",
      date = as.Date("2019-02-01"),
      value = "TRUE"
    )
  )

  result <- run_episode_anchor(
    population, prior_lookback_metadata("COUNT"), concepts, episodes
  )

  # Person 3 has no episodes, so no prior pregnancy and no row.
  testthat::expect_equal(result$person_id, c("1", "2"))
  testthat::expect_equal(result$value, c("5", "1"))
})

#--- Data-quality edge cases -------------------------------------------------
# These pin the *current* behaviour for episode data that breaks the
# "episodes don't overlap and have both dates" assumption. Each one silently
# drops a pregnancy, which is a likely cause of "fewer prior pregnancies
# than expected". If the behaviour is changed on purpose (e.g. to warn or to
# treat touching episodes as prior), update these tests with it.

testthat::test_that("a pregnancy ending on the day the current one starts is not prior", { # nolint: line_length_linter.
  episodes <- data.table::data.table(
    start_episode = as.Date(c("2025-03-01", "2025-12-01")),
    end_episode = as.Date(c("2025-12-01", "2026-09-01"))
  )

  classified <- classify_episodes(episodes, as.Date("2026-06-15"))

  testthat::expect_equal(classified$episode_class, c(NA_character_, "current"))
})

testthat::test_that("a pregnancy overlapping the current one is not prior", {
  episodes <- data.table::data.table(
    start_episode = as.Date(c("2025-03-01", "2025-12-01")),
    end_episode = as.Date(c("2025-12-20", "2026-09-01"))
  )

  classified <- classify_episodes(episodes, as.Date("2026-06-15"))

  testthat::expect_equal(classified$episode_class, c(NA_character_, "current"))
})

testthat::test_that("a pregnancy with a missing end date is never selected", {
  episodes <- data.table::data.table(
    start_episode = as.Date(c("2020-01-01", "2025-12-01")),
    end_episode = as.Date(c(NA, "2026-09-01"))
  )

  classified <- classify_episodes(episodes, as.Date("2026-06-15"))

  testthat::expect_equal(classified$episode_class, c(NA_character_, "current"))
})

testthat::test_that("an overlapping earlier pregnancy drops out of in_prior_pregnancy end to end", { # nolint: line_length_linter.
  episodes <- data.table::data.table(
    person_id = "1",
    start_episode = as.Date(c("2025-03-01", "2025-12-01")),
    end_episode = as.Date(c("2025-12-20", "2026-09-01"))
  )
  concepts <- data.table::data.table(
    person_id = "1",
    concept_id = "PREG_MARKER",
    date = as.Date("2025-04-01"),
    value = "TRUE"
  )

  result <- run_episode_anchor(
    pregnancy_population_lookback(),
    episode_metadata_row("in_prior_pregnancy"),
    concepts,
    episodes
  )

  testthat::expect_equal(nrow(result), 0L)
})

testthat::test_that("T0 inside two overlapping episodes makes both current", {
  # Duplicate pregnancy records: both contain T0, both are selected, and a
  # record inside both windows is counted twice.
  episodes <- data.table::data.table(
    person_id = "1",
    start_episode = as.Date(c("2025-12-01", "2025-11-20")),
    end_episode = as.Date(c("2026-09-01", "2026-08-25"))
  )
  concepts <- data.table::data.table(
    person_id = "1",
    concept_id = "PREG_MARKER",
    date = as.Date("2026-01-10"),
    value = "TRUE"
  )

  result <- run_episode_anchor(
    pregnancy_population_lookback(),
    episode_metadata_row("in_current_pregnancy", selector = "COUNT"),
    concepts,
    episodes
  )

  testthat::expect_equal(result$value, "2")
})

#--- Recipes from documentation/Recipes_episode_windows.md -------------------
# One test per recipe, using the page's example person, so the documented
# results can't drift from the code.

recipe_episodes <- function() {
  data.table::data.table(
    person_id = "1",
    start_episode = as.Date(c("2025-03-01", "2025-12-01")),
    end_episode = as.Date(c("2025-06-15", "2026-09-01"))
  )
}

recipe_population <- function() {
  data.table::data.table(
    person_id = "1",
    T0 = as.Date("2026-06-15"),
    lmp_date = as.Date("2025-12-01")
  )
}

recipe_windows <- function(constructor, ...) {
  windows <- define_window(
    recipe_population(),
    episode_metadata_row(constructor, ...),
    episodes = recipe_episodes()
  )
  data.table::setorder(windows, window_start)
  windows[, .(
    window_start = as.character(window_start),
    window_end = as.character(window_end)
  )]
}

expect_windows <- function(windows, starts, ends) {
  testthat::expect_equal(windows$window_start, starts)
  testthat::expect_equal(windows$window_end, ends)
}

testthat::test_that("recipe 1: any time during the current pregnancy", {
  expect_windows(
    recipe_windows("in_current_pregnancy"),
    "2025-12-01", "2026-09-01"
  )
})

testthat::test_that("recipe 2: from LMP up to the day before T0", {
  expect_windows(
    recipe_windows("in_current_pregnancy", anchor_end_offset = -1),
    "2025-12-01", "2026-06-14"
  )
})

testthat::test_that("recipe 3: first trimester, capped to short pregnancies", {
  expect_windows(
    recipe_windows(
      "in_current_pregnancy",
      after_start_episode_offset = 83, cap_end_to_episode = TRUE
    ),
    "2025-12-01", "2026-02-22"
  )

  short_episode <- data.table::data.table(
    person_id = "1",
    start_episode = as.Date("2025-12-01"),
    end_episode = as.Date("2026-02-09")
  )
  population <- data.table::data.table(
    person_id = "1", T0 = as.Date("2026-01-15")
  )
  capped <- define_window(
    population,
    episode_metadata_row(
      "in_current_pregnancy",
      after_start_episode_offset = 83, cap_end_to_episode = TRUE
    ),
    episodes = short_episode
  )
  uncapped <- define_window(
    population,
    episode_metadata_row(
      "in_current_pregnancy", after_start_episode_offset = 83
    ),
    episodes = short_episode
  )

  testthat::expect_equal(capped$window_end, as.Date("2026-02-09"))
  testthat::expect_equal(uncapped$window_end, as.Date("2026-02-22"))
})

testthat::test_that("recipe 4: N days before LMP needs both start-pair columns", { # nolint: line_length_linter.
  expect_windows(
    recipe_windows(
      "in_current_pregnancy",
      before_start_episode_offset = -365, after_start_episode_offset = -1
    ),
    "2024-12-01", "2025-11-30"
  )
  # The documented trap: the outer side alone runs to the end of pregnancy.
  expect_windows(
    recipe_windows(
      "in_current_pregnancy", before_start_episode_offset = -365
    ),
    "2024-12-01", "2026-09-01"
  )
})

testthat::test_that("recipe 5: N days before LMP through the first trimester", {
  expect_windows(
    recipe_windows(
      "in_current_pregnancy",
      before_start_episode_offset = -365, after_start_episode_offset = 83,
      cap_end_to_episode = TRUE
    ),
    "2024-12-01", "2026-02-22"
  )
})

testthat::test_that("recipe 5b: the same window with GENERIC on an LMP column", { # nolint: line_length_linter.
  windows <- define_window(
    recipe_population(),
    data.table::data.table(
      variable_id = "v",
      concept_id = "PREG_MARKER",
      constructor = "GENERIC",
      selector = "ALL",
      start_offset = -365L,
      end_offset = 83L,
      anchor_start_col = "lmp_date",
      anchor_end_col = "lmp_date"
    )
  )

  testthat::expect_equal(windows$window_start, as.Date("2024-12-01"))
  testthat::expect_equal(windows$window_end, as.Date("2026-02-22"))
})

testthat::test_that("recipe 6a: outside_all_pregnancy from T0 stops at LMP - 1", { # nolint: line_length_linter.
  expect_windows(
    recipe_windows(
      "outside_all_pregnancy",
      anchor_start_offset = -365, anchor_end_offset = -1
    ),
    "2025-06-16", "2025-11-30"
  )
})

testthat::test_that("recipe 6b: outside_all_pregnancy from an LMP column", {
  expect_windows(
    recipe_windows(
      "outside_all_pregnancy",
      anchor_start_col = "lmp_date", anchor_end_col = "lmp_date",
      anchor_start_offset = -365, anchor_end_offset = -1
    ),
    c("2024-12-01", "2025-06-16"),
    c("2025-02-28", "2025-11-30")
  )
})

testthat::test_that("recipe 7: during any earlier pregnancy", {
  expect_windows(
    recipe_windows("in_prior_pregnancy"),
    "2025-03-01", "2025-06-15"
  )
})

testthat::test_that("recipe 8: N days after delivery needs both end-pair columns", { # nolint: line_length_linter.
  expect_windows(
    recipe_windows(
      "in_current_pregnancy",
      before_end_episode_offset = 1, after_end_episode_offset = 42
    ),
    "2026-09-02", "2026-10-13"
  )
  # The documented trap: the outer side alone starts the window at LMP.
  expect_windows(
    recipe_windows("in_current_pregnancy", after_end_episode_offset = 42),
    "2025-12-01", "2026-10-13"
  )
})

testthat::test_that("recipe 9: from N days before LMP up to T0", {
  expect_windows(
    recipe_windows(
      "in_current_pregnancy",
      before_start_episode_offset = -365, anchor_end_offset = 0
    ),
    "2024-12-01", "2026-06-15"
  )
})

testthat::test_that("recipe 10: during the current or any earlier pregnancy", {
  expect_windows(
    recipe_windows("in_current_and_prior"),
    c("2025-03-01", "2025-12-01"),
    c("2025-06-15", "2026-09-01")
  )
})

testthat::test_that("two rows with the same variable_id and window_name are combined", { # nolint: line_length_linter.
  metadata <- rbind(
    episode_metadata_row(
      "outside_all_pregnancy",
      variable_id = "obesity",
      anchor_start_col = "lmp_date", anchor_end_col = "lmp_date",
      anchor_start_offset = -365, anchor_end_offset = -1
    ),
    episode_metadata_row(
      "in_current_pregnancy",
      variable_id = "obesity",
      after_start_episode_offset = 83, cap_end_to_episode = TRUE
    ),
    fill = TRUE
  )
  concepts <- data.table::data.table(
    person_id = "1",
    concept_id = "PREG_MARKER",
    date = as.Date(c("2025-01-10", "2025-04-01", "2026-01-20", "2026-05-01")),
    value = c("before_lmp", "earlier_pregnancy", "first_trimester", "week_22")
  )

  all_rows <- run_episode_anchor(
    recipe_population(), metadata, concepts, recipe_episodes()
  )
  latest <- run_episode_anchor(
    recipe_population(),
    metadata[, selector := "LATEST"],
    concepts,
    recipe_episodes()
  )

  testthat::expect_setequal(all_rows$value, c("before_lmp", "first_trimester"))
  testthat::expect_equal(latest$value, "first_trimester")
})
