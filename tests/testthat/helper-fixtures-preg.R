# Fixtures for the episode-based (pregnancy) window engine, defined in
# the script R/pregnancy_window.R

# Two level of tests data:
#   - `pregnancy_*_simple()`: one person, two episodes. Small enough to trace
#     through the clamp formula by hand.
#   - `pregnancy_*_complex()`: three people, six episodes, including a T0
#     that falls in the gap between two episodes (no current episode at
#     all). Exercises multiple prior episodes, the union in
#     in_current_and_prior, several outside_all gaps, and a selector picking
#     the latest match across multiple candidate windows.

# ---------------------------------------------------------------------------
# SIMPLE: one person ("1"), two non-overlapping episodes, T0 inside the
# second one.
#
#   episode 1 (prior):   2020-01-01 -------- 2020-06-30
#   episode 2 (current):            2021-01-01 --- T0=2021-03-01 --- 2021-06-30
#
# ---------------------------------------------------------------------------

pregnancy_episodes_simple <- function() {
  data.table::data.table(
    person_id = c("1", "1"),
    start_episode = as.Date(c("2020-01-01", "2021-01-01")),
    end_episode = as.Date(c("2020-06-30", "2021-06-30"))
  )
}

pregnancy_population_simple <- function() {
  data.table::data.table(
    person_id = "1",
    T0 = as.Date("2021-03-01")
  )
}

# One variable per constructor, each using for constructors:
# - simple_current: start pinned to the current episode's own start; end left
#   as the raw anchor boundary (anchor_end_offset = 0, no end clamps), so it
#   stops exactly at T0. Window: [2021-01-01, 2021-03-01].
# - simple_prior: all four clamp offsets 0 (with anchor_start_offset =
#   anchor_end_offset = 0 too, see the engine doc's NA-propagation caveat),
#   pinning the window to the one prior episode's own unshifted span.
#   Window: [2020-01-01, 2020-06-30].
# - simple_current_and_prior: same full pin as simple_prior, applied to both
#   the current and the prior episode. Windows: [2021-01-01, 2021-06-30]
#   (current) and [2020-01-01, 2020-06-30] (prior).
# - simple_outside: search range [T0 - 500, T0] = [2019-10-18, 2021-03-01].
#   Two gaps: before episode 1, and between episode 1 and episode 2 (episode
#   2 itself fences the range's upper edge, even though T0 sits inside it).
#   Windows: [2019-10-18, 2019-12-31] and [2020-07-01, 2020-12-31].
pregnancy_metadata_simple <- function() {
  data.table::data.table(
    variable_id = c(
      "simple_current", "simple_prior", "simple_current_and_prior",
      "simple_outside"
    ),
    concept_id = c(
      "GEST_DIAB_CURRENT", "GEST_DIAB_PRIOR", "GEST_DIAB_CURRENT", "OBESITY"
    ),
    constructor = c(
      "in_current_pregnancy", "in_prior_pregnancy",
      "in_current_and_prior", "outside_all_pregnancy"
    ),
    selector = c("LATEST", "LATEST", "ALL", "LATEST"),
    start_offset = 0L, # unused by episode-based constructors, still required
    end_offset = 0L,
    anchor_start_offset = c(0L, 0L, 0L, -500L),
    anchor_end_offset = c(0L, 0L, 0L, 0L),
    before_start_episode_offset = c(0, 0, 0, NA_real_),
    after_start_episode_offset = c(0, 0, 0, NA_real_),
    before_end_episode_offset = c(NA_real_, 0, 0, NA_real_),
    after_end_episode_offset = c(NA_real_, 0, 0, NA_real_)
  )
}

# One record per variable, each placed squarely inside that variable's
# window above, so an end-to-end anchor() call returns exactly one row per
# variable.
pregnancy_concepts_simple <- function() {
  data.table::data.table(
    person_id = "1",
    concept_id = c("GEST_DIAB_CURRENT", "GEST_DIAB_PRIOR", "OBESITY"),
    date = as.Date(c("2021-02-01", "2020-03-01", "2019-11-15")),
    value = c("TRUE", "TRUE", "TRUE")
  )
}

# ---------------------------------------------------------------------------
# COMPLEX: three people, six episodes total.
#
#   person 1: 2020-01-01/09-01, 2021-02-15/05-20, 2022-03-01/12-01
#   person 2:                  2021-02-15/08-01,  2022-03-01/12-01
#   person 3:                  2021-02-15/09-14
#
# Five population rows exercise five distinct situations:
#   - person 1 @ 2021-04-02: current = episode 2, one prior episode (1)
#   - person 1 @ 2022-08-16: current = episode 3, two prior episodes (1, 2)
#   - person 2 @ 2022-08-16: current = episode 2, one prior episode (1)
#   - person 3 @ 2021-04-02: current = its only episode, zero prior episodes
#   - person 1 @ 2021-01-01: falls in the gap between episodes 1 and 2, so
#     there is no current episode at all -- in_prior_pregnancy and
#     in_current_and_prior therefore produce nothing for this row, but
#     outside_all_pregnancy (which doesn't need a current episode) still
#     does.
# ---------------------------------------------------------------------------

pregnancy_episodes_complex <- function() {
  data.table::data.table(
    person_id = c("1", "1", "1", "2", "2", "3"),
    start_episode = as.Date(c(
      "2020-01-01", "2021-02-15", "2022-03-01",
      "2021-02-15", "2022-03-01",
      "2021-02-15"
    )),
    end_episode = as.Date(c(
      "2020-09-01", "2021-05-20", "2022-12-01",
      "2021-08-01", "2022-12-01",
      "2021-09-14"
    ))
  )
}

pregnancy_population_complex <- function() {
  data.table::data.table(
    person_id = c("1", "1", "2", "3", "1"),
    T0 = as.Date(c(
      "2021-04-02", "2022-08-16", "2022-08-16", "2021-04-02", "2021-01-01"
    ))
  )
}
