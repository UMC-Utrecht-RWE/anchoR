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
})

#--- Tests for episode_windows
# All expected values below were independently verified against
# episode_windows() directly (not copied from pregnancy_window_engine's
# behaviour), using the "prior" episode from pregnancy_episodes_cases():
# [2025-01-07, 2025-05-07].
testthat::test_that("episode_windows: neither pair set falls back to the episode's own unshifted span", { # nolint: line_length_linter.
  w <- episode_windows(
    as.Date("2025-01-07"), as.Date("2025-05-07"),
    NA_real_, NA_real_, NA_real_, NA_real_
  )
  testthat::expect_equal(nrow(w), 1L)
  testthat::expect_equal(w$window_start, as.Date("2025-01-07"))
  testthat::expect_equal(w$window_end, as.Date("2025-05-07"))
})

testthat::test_that("episode_windows: one side per pair set (outward side) matches the unshifted span", { # nolint: line_length_linter.
  w <- episode_windows(
    as.Date("2025-01-07"), as.Date("2025-05-07"),
    0, NA_real_, NA_real_, 0
  )
  testthat::expect_equal(w$window_start, as.Date("2025-01-07"))
  testthat::expect_equal(w$window_end, as.Date("2025-05-07"))
})

testthat::test_that("episode_windows: one side per pair set (inward side) also matches the unshifted span", { # nolint: line_length_linter.
  w <- episode_windows(
    as.Date("2025-01-07"), as.Date("2025-05-07"),
    NA_real_, 0, 0, NA_real_
  )
  testthat::expect_equal(w$window_start, as.Date("2025-01-07"))
  testthat::expect_equal(w$window_end, as.Date("2025-05-07"))
})

testthat::test_that("episode_windows: a single offset per pair shifts both edges of one shared window", { # nolint: line_length_linter.
  w <- episode_windows(
    as.Date("2025-01-07"), as.Date("2025-05-07"),
    -7, NA_real_, -7, NA_real_
  )
  testthat::expect_equal(w$window_start, as.Date("2024-12-31"))
  testthat::expect_equal(w$window_end, as.Date("2025-04-30"))
})

testthat::test_that("episode_windows: both pairs set -> two regions", {
  w <- episode_windows(
    as.Date("2025-01-07"), as.Date("2025-05-07"),
    -7, 7, -7, 7
  )
  testthat::expect_equal(nrow(w), 2L)
  testthat::expect_equal(
    w$window_start, as.Date(c("2024-12-31", "2025-04-30"))
  )
  testthat::expect_equal(w$window_end, as.Date(c("2025-01-14", "2025-05-14")))
})

testthat::test_that("episode_windows: 0/0 on both pairs collapses each region to a single day", { # nolint: line_length_linter.
  w <- episode_windows(
    as.Date("2025-01-07"), as.Date("2025-05-07"),
    0, 0, 0, 0
  )
  testthat::expect_equal(nrow(w), 2L)
  testthat::expect_equal(
    w$window_start, as.Date(c("2025-01-07", "2025-05-07"))
  )
  testthat::expect_equal(w$window_end, as.Date(c("2025-01-07", "2025-05-07")))
})

testthat::test_that("episode_windows: both pairs specified, shifted later", {
  w <- episode_windows(
    as.Date("2025-01-07"), as.Date("2025-05-07"),
    7, 14, 7, 14
  )
  testthat::expect_equal(
    w$window_start, as.Date(c("2025-01-14", "2025-05-14"))
  )
  testthat::expect_equal(w$window_end, as.Date(c("2025-01-21", "2025-05-21")))
})

testthat::test_that("episode_windows: only the start pair fully specified emits just that region", { # nolint: line_length_linter.
  w <- episode_windows(
    as.Date("2025-01-07"), as.Date("2025-05-07"),
    -7, 7, NA_real_, NA_real_
  )
  testthat::expect_equal(nrow(w), 1L)
  testthat::expect_equal(w$window_start, as.Date("2024-12-31"))
  testthat::expect_equal(w$window_end, as.Date("2025-01-14"))
})

testthat::test_that("episode_windows: only the end pair fully specified emits just that region", { # nolint: line_length_linter.
  w <- episode_windows(
    as.Date("2025-01-07"), as.Date("2025-05-07"),
    NA_real_, NA_real_, -7, 7
  )
  testthat::expect_equal(nrow(w), 1L)
  testthat::expect_equal(w$window_start, as.Date("2025-04-30"))
  testthat::expect_equal(w$window_end, as.Date("2025-05-14"))
})

testthat::test_that("episode_windows errors on an inverted start pair", {
  testthat::expect_error(
    episode_windows(
      as.Date("2025-01-07"), as.Date("2025-05-07"),
      1, 0, NA_real_, NA_real_
    ),
    "before_start_episode_offset"
  )
})

testthat::test_that("episode_windows errors on an inverted end pair", {
  testthat::expect_error(
    episode_windows(
      as.Date("2025-01-07"), as.Date("2025-05-07"),
      NA_real_, NA_real_, 1, 0
    ),
    "before_end_episode_offset"
  )
})

#--- Tests for pregnancy_window_engine
# A hand-built window_dt (mirroring what define_window() would eventually
# feed the constructor's transform_fn with) so these tests exercise
# pregnancy_window_engine() directly, with full control over every column,
# instead of going through define_window(), which already resolves and
# calls the constructor internally, so re-running the engine on its
# (already exploded) output would double-process it.
cases_window_dt <- function(
  constructor,
  before_start = NA_real_, after_start = NA_real_,
  before_end = NA_real_, after_end = NA_real_,
  t0 = as.Date("2026-03-07"),
  episodes = NULL
) {
  if (is.null(episodes)) {
    episodes <- pregnancy_episodes_cases()[, .(start_episode, end_episode)]
  }
  data.table::data.table(
    person_id = "1",
    T0 = t0,
    variable_id = "x",
    constructor = constructor,
    anchor_start_col = "T0",
    anchor_end_col = "T0",
    anchor_start_offset = NA_real_,
    anchor_end_offset = NA_real_,
    before_start_episode_offset = before_start,
    after_start_episode_offset = after_start,
    before_end_episode_offset = before_end,
    after_end_episode_offset = after_end,
    .episodes = list(episodes)
  )
}

testthat::test_that("pregnancy_window_engine CURRENT selects current episode", {
  out <- pregnancy_window_engine(
    cases_window_dt("in_current_pregnancy", -7, 7, -7, 7),
    episode_select = "CURRENT"
  )
  testthat::expect_equal(nrow(out), 2L)
  testthat::expect_equal(
    out$window_start, as.Date(c("2025-12-31", "2026-04-30"))
  )
  testthat::expect_equal(out$window_end, as.Date(c("2026-01-14", "2026-05-14")))
})

testthat::test_that("pregnancy_window_engine PRIOR selects the prior episode", {
  out <- pregnancy_window_engine(
    cases_window_dt("in_prior_pregnancy", -7, 7, -7, 7),
    episode_select = "PRIOR"
  )
  testthat::expect_equal(nrow(out), 2L)
  testthat::expect_equal(
    out$window_start, as.Date(c("2024-12-31", "2025-04-30"))
  )
  testthat::expect_equal(out$window_end, as.Date(c("2025-01-14", "2025-05-14")))
})

testthat::test_that("pregnancy_window_engine CURRENT_AND_PRIOR unions both episodes' windows", { # nolint: line_length_linter.
  out <- pregnancy_window_engine(
    cases_window_dt("in_current_and_prior", -7, 7, -7, 7),
    episode_select = "CURRENT_AND_PRIOR"
  )
  testthat::expect_equal(nrow(out), 4L)
  # current's two regions first (selected <- rbind(current, prior)), then
  # prior's two.
  testthat::expect_equal(
    out$window_start,
    as.Date(c("2025-12-31", "2026-04-30", "2024-12-31", "2025-04-30"))
  )
  testthat::expect_equal(
    out$window_end,
    as.Date(c("2026-01-14", "2026-05-14", "2025-01-14", "2025-05-14"))
  )
})

testthat::test_that("pregnancy_window_engine CURRENT produces no rows when T0 is not inside any episode", { # nolint: line_length_linter.
  out <- pregnancy_window_engine(
    cases_window_dt(
      "in_current_pregnancy", 0, 0, 0, 0,
      t0 = as.Date("2025-08-01")
    ),
    episode_select = "CURRENT"
  )
  testthat::expect_equal(nrow(out), 0L)
})

testthat::test_that("pregnancy_window_engine PRIOR falls back to T0-relative when there is no current episode", { # nolint: line_length_linter.
  # T0 = 2025-08-01 falls in the gap after the prior episode ends
  # (2025-05-07) and before the current episode starts (2026-01-07): no
  # episode contains it, so classify_episodes() falls back to T0-relative
  # prior/future, and the (now-"prior") episode's own unshifted span comes
  # through unchanged.
  out <- pregnancy_window_engine(
    cases_window_dt(
      "in_prior_pregnancy",
      NA_real_, NA_real_, NA_real_, NA_real_,
      t0 = as.Date("2025-08-01")
    ),
    episode_select = "PRIOR"
  )
  testthat::expect_equal(nrow(out), 1L)
  testthat::expect_equal(out$window_start, as.Date("2025-01-07"))
  testthat::expect_equal(out$window_end, as.Date("2025-05-07"))
})

testthat::test_that("pregnancy_window_engine OUTSIDE_ALL uses anchor offsets, not episode borders", { # nolint: line_length_linter.
  window_dt <- data.table::data.table(
    person_id = "1", T0 = as.Date("2021-03-01"), variable_id = "x",
    constructor = "outside_all_pregnancy",
    anchor_start_col = "T0", anchor_end_col = "T0",
    anchor_start_offset = -500L, anchor_end_offset = 0L,
    before_start_episode_offset = NA_real_,
    after_start_episode_offset = NA_real_,
    before_end_episode_offset = NA_real_,
    after_end_episode_offset = NA_real_,
    .episodes = list(
      pregnancy_episodes_simple()[, .(start_episode, end_episode)]
    )
  )
  out <- pregnancy_window_engine(window_dt, episode_select = "OUTSIDE_ALL")
  testthat::expect_equal(nrow(out), 2L)
  testthat::expect_equal(
    out$window_start, as.Date(c("2019-10-18", "2020-07-01"))
  )
  testthat::expect_equal(out$window_end, as.Date(c("2019-12-31", "2020-12-31")))
})

testthat::test_that("pregnancy_window_engine surfaces an inverted-pair error from episode_windows", { # nolint: line_length_linter.
  testthat::expect_error(
    pregnancy_window_engine(
      cases_window_dt("in_current_pregnancy", 1, 0, NA_real_, NA_real_),
      episode_select = "CURRENT"
    ),
    "before_start_episode_offset"
  )
})
