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

# One variable per constructor, each using offsets that combine the raw
# anchor-relative boundary with a clamp toward the selected episode(s):
# - complex_current: raw window T0 +/- 400 days, start clamped to no earlier
#   than start_episode - 30, end clamped to no later than end_episode + 30.
#   person 1 @ 2021-04-02: [2021-01-16, 2021-06-19].
#   person 1 @ 2022-08-16 and person 2 @ 2022-08-16 (same episode 3 dates):
#     [2022-01-30, 2022-12-31].
#   person 3 @ 2021-04-02: [2021-01-16, 2021-10-14].
#   person 1 @ 2021-01-01: no row (no current episode).
# - complex_prior: raw window is T0 itself, start clamped to no later than
#   start_episode + 60, end clamped to no earlier than end_episode - 60 --
#   one row per prior episode.
#   person 1 @ 2021-04-02: [2020-03-01, 2021-04-02] (episode 1).
#   person 1 @ 2022-08-16: [2020-03-01, 2022-08-16] (episode 1) and
#     [2021-04-16, 2022-08-16] (episode 2).
#   person 2 @ 2022-08-16: [2021-04-16, 2022-08-16] (episode 1).
#   person 3 @ 2021-04-02 and person 1 @ 2021-01-01: no rows (zero prior
#   episodes / no current episode, respectively).
# - complex_current_and_prior: raw window [T0 - 3000, T0], no clamps, so
#   every selected episode (current + every prior) gets the *same* window --
#   this is what makes ALL return several identical-window rows per person.
#   person 1 @ 2021-04-02: 2 rows, both [2013-01-14, 2021-04-02].
#   person 1 @ 2022-08-16: 3 rows, all [2014-05-30, 2022-08-16].
#   person 2 @ 2022-08-16: 2 rows, both [2014-05-30, 2022-08-16].
#   person 3 @ 2021-04-02: 1 row, [2013-01-14, 2021-04-02].
# - complex_outside: search range [T0 - 3000, T0], gaps between *all* of a
#   person's episodes (doesn't need a current episode, so person 1 @
#   2021-01-01 still gets 2 gap rows: [2012-10-15, 2019-12-31] and
#   [2020-09-02, 2021-01-01]).
pregnancy_metadata_complex <- function() {
  data.table::data.table(
    variable_id = c(
      "complex_current", "complex_prior", "complex_current_and_prior",
      "complex_outside"
    ),
    concept_id = c(
      "GEST_DIAB_CURRENT", "GEST_DIAB_PRIOR", "GEST_DIAB_CURRENT", "OBESITY"
    ),
    constructor = c(
      "in_current_pregnancy", "in_prior_pregnancy",
      "in_current_and_prior", "outside_all_pregnancy"
    ),
    selector = c("LATEST", "LATEST", "ALL", "LATEST"),
    start_offset = 0L,
    end_offset = 0L,
    anchor_start_offset = c(-400L, 0L, -3000L, -3000L),
    anchor_end_offset = c(400L, 0L, 0L, 0L),
    before_start_episode_offset = c(30L, NA_real_, NA_real_, NA_real_),
    after_start_episode_offset = c(NA_real_, 60L, NA_real_, NA_real_),
    before_end_episode_offset = c(NA_real_, 60L, NA_real_, NA_real_),
    after_end_episode_offset = c(30L, NA_real_, NA_real_, NA_real_)
  )
}

# GEST_DIAB_CURRENT: one record inside complex_current's window for person 1
# @ 2022-08-16 ([2022-01-30, 2022-12-31]).
# GEST_DIAB_PRIOR: two records for complex_prior's two candidate windows for
# person 1 @ 2022-08-16 ([2020-03-01, 2022-08-16] and [2021-04-16,
# 2022-08-16]) -- one inside only the first, one inside both, so LATEST must
# pick the later one (2022-05-01) across both windows.
# OBESITY: one record inside complex_outside's second gap for person 1 @
# 2022-08-16 ([2020-09-02, 2021-02-14]).
pregnancy_concepts_complex <- function() {
  data.table::data.table(
    person_id = c("1", "1", "1", "1"),
    concept_id = c(
      "GEST_DIAB_CURRENT", "GEST_DIAB_PRIOR", "GEST_DIAB_PRIOR", "OBESITY"
    ),
    date = as.Date(c(
      "2022-06-01", "2020-05-01", "2022-05-01", "2020-10-15"
    )),
    value = c("TRUE", "TRUE", "TRUE", "TRUE")
  )
}
