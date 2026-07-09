# ---------------------------------------------------------------------------
# outside_all_event_gaps(): the complement of the union of events within
# a search range, tested directly since it is the trickiest piece of the
# event engine.
# ---------------------------------------------------------------------------

testthat::test_that("outside_all_event_gaps finds gaps between events", {
  events <- data.table::data.table(
    event_start = as.Date(c("2020-01-01", "2021-02-15", "2022-03-01")),
    event_end = as.Date(c("2020-09-01", "2021-05-20", "2022-12-01"))
  )

  gaps <- outside_all_event_gaps(
    events,
    anchor = as.Date("2022-08-16"),
    start_offset = 0L,
    end_offset = -1000L
  )

  # An event always fences a gap, even the one containing the anchor, so
  # there is no gap after the third event starts (2022-03-01).
  testthat::expect_equal(
    gaps$window_start,
    as.Date(c("2019-11-20", "2020-09-02", "2021-05-21"))
  )
  testthat::expect_equal(
    gaps$window_end,
    as.Date(c("2019-12-31", "2021-02-14", "2022-02-28"))
  )
})

testthat::test_that(
  "outside_all_event_gaps returns one gap when no event overlaps",
  {
    events <- data.table::data.table(
      event_start = as.Date("2010-01-01"),
      event_end = as.Date("2010-06-01")
    )

    gaps <- outside_all_event_gaps(
      events,
      anchor = as.Date("2024-01-01"),
      start_offset = -30L,
      end_offset = 0L
    )

    testthat::expect_equal(gaps$window_start, as.Date("2023-12-02"))
    testthat::expect_equal(gaps$window_end, as.Date("2024-01-01"))
  }
)

# ---------------------------------------------------------------------------
# event_window_engine(): tested directly on a hand-built window_dt so the
# selection + offset rules are visible without going through define_window().
# ---------------------------------------------------------------------------

event_window_dt <- function(
  constructor,
  start_offset = 0L,
  end_offset = 0L,
  end_cap_offset = NA_real_,
  start_look_back = NA_real_,
  end_look_back = NA_real_,
  events = NULL
) {
  if (is.null(events)) {
    events <- data.table::data.table(
      event_start = as.Date(c("2020-01-01", "2021-02-15", "2022-03-01")),
      event_end = as.Date(c("2020-09-01", "2021-05-20", "2022-12-01"))
    )
  }

  data.table::data.table(
    person_id = "1",
    T0 = as.Date("2022-08-16"),
    variable_id = "v",
    constructor = constructor,
    anchor_start_col = "T0",
    event_col = "pregnancy_events",
    start_offset = start_offset,
    end_offset = end_offset,
    end_cap_offset = end_cap_offset,
    start_look_back = start_look_back,
    end_look_back = end_look_back,
    pregnancy_events = list(events)
  )
}

testthat::test_that(
  "event_window_engine PRIOR selects events ending before the anchor",
  {
    out <- event_window_engine(
      event_window_dt("IN_PRIOR_PREG"),
      event_select = "PRIOR"
    )

    testthat::expect_equal(nrow(out), 2L)
    testthat::expect_equal(
      out$window_start, as.Date(c("2020-01-01", "2021-02-15"))
    )
    testthat::expect_equal(
      out$window_end, as.Date(c("2020-09-01", "2021-05-20"))
    )
  }
)

testthat::test_that("event_window_engine PRIOR applies an end cap", {
  out <- event_window_engine(
    event_window_dt(
      "IN_PRIOR_PREG",
      start_offset = 90L, end_offset = 0L, end_cap_offset = 166
    ),
    event_select = "PRIOR"
  )

  testthat::expect_equal(
    out$window_start, as.Date(c("2020-03-31", "2021-05-16"))
  )
  testthat::expect_equal(
    out$window_end, as.Date(c("2020-06-15", "2021-05-20"))
  )
})

testthat::test_that(
  "event_window_engine PRIOR filters out episodes outside the lookback range",
  {
    # anchor (T0) = 2022-08-16, lookback = [T0 - 500, T0]. Episode 1
    # (2020-01-01/2020-09-01) ends well before the lookback range starts, so
    # it never becomes a candidate at all. Episode 2 (2021-02-15/2021-05-20)
    # overlaps the lookback range, so it is kept -- and with start_offset/
    # end_offset both 0 here, its window is exactly the episode's own span.
    out <- event_window_engine(
      event_window_dt(
        "IN_PRIOR_PREG",
        start_look_back = -500, end_look_back = 0
      ),
      event_select = "PRIOR"
    )

    testthat::expect_equal(nrow(out), 1L)
    testthat::expect_equal(out$window_start, as.Date("2021-02-15"))
    testthat::expect_equal(out$window_end, as.Date("2021-05-20"))
  }
)

testthat::test_that(
  "event_window_engine PRIOR lookback range only filters, never clips",
  {
    # Same lookback range as above ([T0 - 500, T0] ~= [2021-04-03,
    # 2022-08-16]), but start_offset/end_offset now shift episode 2's window
    # to [2021-01-16, 2021-06-19] -- window_start ends up *before* the
    # lookback's own lower bound. The shifted window is kept exactly as
    # computed, proving the lookback range only decides which episodes are
    # eligible; it never truncates the resulting window.
    out <- event_window_engine(
      event_window_dt(
        "IN_PRIOR_PREG",
        start_offset = -30L, end_offset = 30L,
        start_look_back = -500, end_look_back = 0
      ),
      event_select = "PRIOR"
    )

    testthat::expect_equal(nrow(out), 1L)
    testthat::expect_equal(out$window_start, as.Date("2021-01-16"))
    testthat::expect_equal(out$window_end, as.Date("2021-06-19"))
  }
)

testthat::test_that(
  "event_window_engine PRIOR leaves windows alone when lookback is NA",
  {
    out <- event_window_engine(
      event_window_dt("IN_PRIOR_PREG"),
      event_select = "PRIOR"
    )

    testthat::expect_equal(
      out$window_start, as.Date(c("2020-01-01", "2021-02-15"))
    )
    testthat::expect_equal(
      out$window_end, as.Date(c("2020-09-01", "2021-05-20"))
    )
  }
)

testthat::test_that(
  "IN_PRIOR_PREG lookback range flows end to end through define_window",
  {
    metadata <- data.table::data.table(
      variable_id = "gest_diabetes_prior",
      concept_id = "GEST_DIAB",
      constructor = "IN_PRIOR_PREG",
      selector = "LATEST",
      start_offset = 0L,
      end_offset = 0L,
      start_look_back = -500L,
      end_look_back = 0L,
      event_col = "pregnancy_events"
    )

    windows <- define_window(event_population(), metadata)

    # Person 1's two prior episodes end at 2020-09-01 and 2021-05-20; anchor
    # is 2022-08-16. Only the second overlaps the 500-day lookback range, so
    # the first is filtered out before a window row is even created -- only
    # one candidate window reaches define_window() at all.
    testthat::expect_equal(nrow(windows), 1L)
    testthat::expect_true(windows$window_valid)
    testthat::expect_equal(windows$window_end, as.Date("2021-05-20"))
  }
)

testthat::test_that(
  "event_window_engine CURRENT with event_END covers whole event",
  {
    out <- event_window_engine(
      event_window_dt("ANYTIME_CURRENT_PREG", end_offset = 30L),
      event_select = "CURRENT",
      end_boundary = "event_END"
    )

    testthat::expect_equal(out$window_start, as.Date("2022-03-01"))
    testthat::expect_equal(out$window_end, as.Date("2022-12-31"))
  }
)

testthat::test_that("event_window_engine CURRENT with ANCHOR stops at T0", {
  out <- event_window_engine(
    event_window_dt("SINCE_START_CURRENT_PREG"),
    event_select = "CURRENT",
    end_boundary = "ANCHOR"
  )

  testthat::expect_equal(out$window_start, as.Date("2022-03-01"))
  testthat::expect_equal(out$window_end, as.Date("2022-08-16"))
})

testthat::test_that(
  "event_window_engine contributes zero rows when nothing matches",
  {
    no_events <- data.table::data.table(
      event_start = as.Date(character()),
      event_end = as.Date(character())
    )

    out <- event_window_engine(
      event_window_dt("IN_PRIOR_PREG", events = no_events),
      event_select = "PRIOR"
    )

    testthat::expect_equal(nrow(out), 0L)
  }
)

testthat::test_that(
  "event_window_engine OUTSIDE_ALL uses start/end offset as search range",
  {
    out <- event_window_engine(
      event_window_dt(
        "OUTSIDE_ALL_PREG",
        start_offset = 0L, end_offset = -1000L
      ),
      event_select = "OUTSIDE_ALL"
    )

    testthat::expect_equal(nrow(out), 3L)
    testthat::expect_true(all(out$window_start <= out$window_end))
  }
)

# ---------------------------------------------------------------------------
# The four named constructors: thin wrappers over event_window_engine.
# ---------------------------------------------------------------------------

testthat::test_that(
  "the four event constructors dispatch to the right engine parameters",
  {
    prior <- in_prior_preg_window(event_window_dt("IN_PRIOR_PREG"))
    testthat::expect_equal(nrow(prior), 2L)

    anytime <- anytime_current_preg_window(
      event_window_dt("ANYTIME_CURRENT_PREG")
    )
    testthat::expect_equal(anytime$window_end, as.Date("2022-12-01"))

    since_start <- since_start_current_preg_window(
      event_window_dt("SINCE_START_CURRENT_PREG")
    )
    testthat::expect_equal(since_start$window_end, as.Date("2022-08-16"))

    outside <- outside_all_preg_window(
      event_window_dt(
        "OUTSIDE_ALL_PREG",
        start_offset = 0L, end_offset = -1000L
      )
    )
    testthat::expect_equal(nrow(outside), 3L)
  }
)

# ---------------------------------------------------------------------------
# End-to-end: row expansion through define_window(), and the SQL aggregation
# fix through anchor() + get_anchor_result().
# ---------------------------------------------------------------------------

testthat::test_that(
  "define_window expands one row into multiple candidate windows",
  {
    windows <- define_window(event_population(), event_metadata())

    # Person 1 has two prior events -> two candidate windows; person 2
    # has none -> zero candidate windows.
    testthat::expect_equal(nrow(windows), 2L)
    testthat::expect_equal(windows$person_id, c("1", "1"))
    testthat::expect_true(all(windows$window_valid))
  }
)

testthat::test_that(
  "multiple candidate windows for one variable collapse to one LATEST result",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    anchor(
      population = event_population(),
      metadata = event_metadata(),
      concepts = event_concepts(),
      anchor_hive_path = hive_path
    )

    anchored <- read_anchor_hive(hive_path)

    # Both prior-pregnancy windows for person 1 contain a matching
    # GEST_DIAB record; LATEST must pick the later one across both, as a
    # single row.
    testthat::expect_equal(nrow(anchored), 1L)
    testthat::expect_equal(anchored$person_id, "1")
    testthat::expect_equal(anchored$date, as.Date("2021-03-01"))
    testthat::expect_equal(anchored$value, "TRUE")
  }
)

# ---------------------------------------------------------------------------
# The full documented scenario: all 5 pregnancy_examples.md constructors at
# once, via pregnancy_population_with_events()/pregnancy_metadata_translated()
# (adapters over the pregnancy_population/pregnancy_periods/pregnancy_metadata
# fixtures above). Every expected value below was independently re-derived
# from the PRIOR/CURRENT/OUTSIDE_ALL rules against pregnancy_periods(), not
# copied from the untrusted pregnancy_output()/intermediate_windows_pregnancy().
# ---------------------------------------------------------------------------

testthat::test_that(
  "define_window reproduces the documented candidate windows per person/T0",
  {
    windows <- define_window(
      pregnancy_population_with_events(), pregnancy_metadata_translated()
    )
    windows <- windows[order(variable_id, person_id, T0, window_start)]

    # Person 1 has two episodes ending before T0 = 2021-04-02's *other* row
    # (T0 = 2022-08-16), so IN_PRIOR_PREG produces one window for the
    # 2021-04-02 row and two for the 2022-08-16 row; person 3's only
    # episode contains its T0, so it contributes none.
    prior <- windows[variable_id == "preg_example_1"]
    testthat::expect_equal(nrow(prior), 4L)
    testthat::expect_equal(prior$person_id, c("1", "1", "1", "2"))

    # OUTSIDE_ALL_PREG for person 1 at T0 = 2022-08-16: three episodes give
    # three gaps within the [T0 - 3652, T0] search range (an episode always
    # fences a gap, so nothing extends past the third episode's start).
    outside_person1 <- windows[
      variable_id == "preg_example_4" & person_id == "1" & T0 == "2022-08-16"
    ]
    testthat::expect_equal(nrow(outside_person1), 3L)
    testthat::expect_equal(
      outside_person1$window_end,
      as.Date(c("2019-12-31", "2021-02-14", "2022-02-28"))
    )
  }
)

testthat::test_that(
  "anchor() resolves the documented pregnancy scenario end to end",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    anchor(
      population = pregnancy_population_with_events(),
      metadata = pregnancy_metadata_translated(),
      concepts = pregnancy_concepts(),
      anchor_hive_path = hive_path
    )

    anchored <- read_anchor_hive(hive_path)
    anchored <- anchored[order(variable_id)]

    # preg_example_2 (gest_diabetes record falls between two SINCE_START
    # windows, matching neither) and preg_example_4 (the obesity record
    # falls inside a pregnancy, so OUTSIDE_ALL_PREG correctly excludes it)
    # produce no rows at all -- only 3 of the 5 variables match anything.
    testthat::expect_equal(
      anchored$variable_id,
      c("preg_example_1", "preg_example_3", "preg_example_5")
    )
    testthat::expect_equal(anchored$person_id, c("1", "1", "2"))
    testthat::expect_equal(anchored$T0, as.Date(rep("2022-08-16", 3)))
    testthat::expect_equal(
      anchored$date, as.Date(c("2021-05-01", "2022-12-30", "2021-07-01"))
    )
  }
)
