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

# One variable per constructor. NOTE: `anchor_start_offset`/`anchor_end_offset`
# are a hard boundary applied to *every* episode-based constructor (not just
# `outside_all_pregnancy`): every candidate window is clipped to
# `[anchor_start_col + anchor_start_offset, anchor_end_col +
# anchor_end_offset]`, and a window entirely outside that boundary comes out
# invalid. `simple_current`/`simple_prior`/`simple_current_and_prior` below
# set both to `0`, i.e. a boundary of exactly `[T0, T0]` -- since none of
# their border-offset windows land on T0 itself, all three end up **invalid
# and produce no result**, verified end to end through `anchor()`. Only
# `simple_outside` (which needs a real anchor-relative range) still works.
# This is deliberately left as-is here as an illustration of the failure
# mode, not fixed -- see `documentation/definitions/Episode-Based Window
# Engine.md` for the clip rule.
# - simple_current: border offsets pin the window to the current episode's
#   own unshifted span, [2021-01-01, 2021-06-30], but the anchor_start_offset
#   = anchor_end_offset = 0 clip narrows the hard boundary to exactly
#   [2021-03-01, 2021-03-01] (T0), which doesn't overlap it -> invalid.
# - simple_prior: same clip issue; the prior episode's own unshifted span
#   ([2020-01-01, 2020-06-30]) doesn't overlap [T0, T0] either -> invalid.
# - simple_current_and_prior: same clip issue for both the current and the
#   prior episode's windows -> both invalid.
# - simple_outside: search range [T0 - 500, T0] = [2019-10-18, 2021-03-01].
#   Two gaps: before episode 1, and between episode 1 and episode 2 (episode
#   2 itself fences the range's upper edge, even though T0 sits inside it).
#   Windows: [2019-10-18, 2019-12-31] and [2020-07-01, 2020-12-31]. The
#   anchor-offset clip is a no-op here, since outside_all_pregnancy's search
#   range already *is* that same boundary.
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

# One record per variable, placed inside that variable's *border-offset*
# window. As of the anchor-offset clip described above, only the
# `simple_outside` (OBESITY) record actually survives end to end through
# `anchor()`; the other two land in windows the anchor_start_offset = 0/
# anchor_end_offset = 0 clip has made invalid.
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
#     there is no current episode at all, in_prior_pregnancy and
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

# One variable per constructor. As with `pregnancy_metadata_simple()`,
# `anchor_start_offset`/`anchor_end_offset` are now a hard boundary applied
# to every constructor (see the clip rule in `documentation/definitions/
# Episode-Based Window Engine.md`), not just `outside_all_pregnancy`; every
# row below was re-verified against the current engine via `define_window()`.
# - complex_current: border offsets give [start_episode + 30, end_episode +
#   30], then clipped to the hard boundary [T0 - 400, T0 + 400].
#   person 1 @ 2021-04-02: [2021-03-17, 2021-06-19] (unclipped -- the
#   boundary is wide enough here).
#   person 1 @ 2022-08-16 and person 2 @ 2022-08-16 (same episode 3 dates):
#     [2022-03-31, 2022-12-31].
#   person 3 @ 2021-04-02: [2021-03-17, 2021-10-14].
#   person 1 @ 2021-01-01: no row (no current episode).
# - complex_prior: border offsets give [start_episode + 60, end_episode - 60]
#   NOTE: with `anchor_start_offset = anchor_end_offset = 0`, the hard
#   boundary here is exactly `[T0, T0]`, and none of the prior-episode
#   windows land on T0 -- **every complex_prior row is invalid**, verified
#   against `define_window()`; `LATEST` produces no result for it end to
#   end. This is left as-is to illustrate the failure mode, the same way
#   `pregnancy_metadata_simple()`'s `simple_prior` does.
# - complex_current_and_prior: boundary [T0 - 3000, T0]. Prior-episode
#   windows (unshifted spans, e.g. [2020-01-01, 2020-09-01]) are already
#   within it and pass through unclipped; the *current* episode's own
#   unshifted span gets its end clipped down to T0 itself.
#   person 1 @ 2021-04-02: 2 rows: [2021-02-15, 2021-04-02] (current,
#     clipped) and [2020-01-01, 2020-09-01] (prior).
#   person 1 @ 2022-08-16: 3 rows: [2022-03-01, 2022-08-16] (current,
#     clipped), [2020-01-01, 2020-09-01] and [2021-02-15, 2021-05-20]
#     (both prior).
#   person 2 @ 2022-08-16: 2 rows: [2022-03-01, 2022-08-16] (current,
#     clipped) and [2021-02-15, 2021-08-01] (prior).
#   person 3 @ 2021-04-02: 1 row, [2021-02-15, 2021-04-02] (current,
#     clipped; zero prior episodes).
#   person 1 @ 2021-01-01: no current episode, so only the prior-episode
#     fallback applies: 1 row, [2020-01-01, 2020-09-01] (unclipped).
# - complex_outside: search range [T0 - 3000, T0], gaps between *all* of a
#   person's episodes (doesn't need a current episode, so person 1 @
#   2021-01-01 still gets 2 gap rows: [2012-10-15, 2019-12-31] and
#   [2020-09-02, 2021-01-01]). The anchor-offset clip is a no-op here, same
#   as `simple_outside`.
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
# @ 2022-08-16 ([2022-03-31, 2022-12-31]); it also lands inside
# complex_current_and_prior's clipped current-episode window for the same
# person/date ([2022-03-01, 2022-08-16]), so it matches both variables.
# GEST_DIAB_PRIOR: NOTE -- with complex_prior now entirely invalid (see the
# anchor-offset clip note on `pregnancy_metadata_complex()`), neither record
# below matches complex_prior at all end to end; they're left in place only
# because they don't hit anything else either, so they don't affect the
# other variables' matches. Kept as a visible illustration, not fixed.
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

# ---------------------------------------------------------------------------
# As for examples in the discussion.
pregnancy_episodes_cases <- function() {
  data.table::data.table(
    person_id = c("1", "1"),
    start_episode = as.Date(c("2025-01-07", "2026-01-07")),
    end_episode = as.Date(c("2025-05-07", "2026-05-07"))
  )
}

pregnancy_population_cases <- function() {
  data.table::data.table(
    person_id = "1",
    T0 = as.Date("2026-03-07")
  )
}

# Case 1: In prior pregnancy, look for events between LMP + 140 until the end
# of pregnancy
# Case 2: In prior pregnancy, look for events between LMP - 14 and LMP + 140.
# Should not count events after LMP + 140.
# Case 3: In prior and current pregnancy before anchor_date, look for events
# LMP - 14 and LMP + 140. Should not count events after
# min(anchor_date + 1, LMP + 140) should not be count.
# Case 4: In current pregnancy, look for events between anchor_date - 1
# and anchor_date + 42.
# Case 5: In current pregnancy, look for events between the
# max(LMP + 210, anchor_date) and LMP + 258.
pregnancy_metadata_cases <- function() {
  data.table::data.table(
    variable_id = c(
      "case1", "case2", "case3", "case4", "case5"
    ),
    concept_id = "DEMO",
    constructor = c(
      "in_prior_pregnancy", "in_prior_pregnancy", "in_current_and_prior",
      "in_current_pregnancy", "in_current_pregnancy"
    ),
    selector = "ALL",
    start_offset = 0L, # unused by episode-based constructors, still required
    end_offset = 0L,
    anchor_start_offset = c(NA_real_, NA_real_, -999, 1, 0),
    anchor_end_offset = c(NA_real_, NA_real_, -1, 42, 999),
    before_start_episode_offset = c(140, -14, -14, NA_real_, 210),
    after_start_episode_offset = c(999, 140, 140, NA_real_, 250),
    before_end_episode_offset = c(0, 0, 0, 0, 0),
    after_end_episode_offset = c(0, 0, 0, 0, 0)
  )
}

# Case 6: constructor = GENERIC (not episode-based at all), "within one
# month after the current pregnancy ended": anchored directly at a
# `pregnancy_end_date` population column
# It needs its own population/metadata pair instead of
# pregnancy_population_cases()/pregnancy_episodes_cases().
# Window: [2022-03-01, 2022-03-31].
pregnancy_population_case6 <- function() {
  data.table::data.table(
    person_id = "1",
    T0 = as.Date("2021-09-01"),
    pregnancy_end_date = as.Date("2022-03-01")
  )
}

pregnancy_metadata_case6 <- function() {
  data.table::data.table(
    variable_id = "case6",
    concept_id = "DEMO",
    constructor = "GENERIC",
    selector = "ALL",
    start_offset = 0L,
    end_offset = 30L,
    anchor_start_col = "pregnancy_end_date",
    anchor_end_col = "pregnancy_end_date"
  )
}

pregnancy_concepts_cases <- function() {
  data.table::data.table(
    person_id = "1",
    concept_id = "DEMO",
    date = as.Date(c(
      "2025-08-01", # inside case1
      "2025-02-01", # inside case2
      "2026-02-01", # inside case3 (current-episode side)
      "2026-05-07", # inside case4
      "2026-08-20" # inside case5
    )),
    value = "TRUE"
  )
}
