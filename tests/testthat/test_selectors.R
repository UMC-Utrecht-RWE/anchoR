testthat::test_that("available_selectors lists bundled SQL templates", {
  selectors <- available_selectors()

  testthat::expect_true(
    all(c("LATEST", "EARLIEST", "COUNT", "RANGE_COUNT", "ALL") %in% selectors)
  )
  testthat::expect_true("COUNT_MORE_THAN_1" %in% selectors)
})

testthat::test_that(
  "filter_supported_metadata keeps supported when unsupported rows are dropped",
  {
    metadata <- data.table::data.table(
      variable_id = c("a", "b", "c"),
      concept_id = c("A", "B", "C"),
      date_extraction_func = c(
        "latest", "LATEST_PRIOR_ANCHOREDPREG", NA_character_
      )
    )

    filtered <- filter_supported_metadata(
      metadata,
      selector_col = "date_extraction_func"
    )

    testthat::expect_s3_class(filtered, "data.table")
    testthat::expect_equal(filtered$variable_id, "a")
    testthat::expect_equal(names(filtered), names(metadata))
  }
)

testthat::test_that(
  "filter_supported_metadata keeps all rows when selectors are supported",
  {
    metadata <- data.table::data.table(
      variable_id = c("a", "b"),
      concept_id = c("A", "B"),
      selector = c("LATEST", "count")
    )

    filtered <- filter_supported_metadata(metadata)

    testthat::expect_equal(filtered$selector, c("LATEST", "count"))
  }
)

testthat::test_that(
  "range_count selector buckets the raw count via concept_ranges",
  {
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    withr::defer(DBI::dbDisconnect(con, shutdown = TRUE))

    # p1: 0 matching concept rows (never appears in concepts at all).
    # p2: 1 match, p3: 3 matches, p4: 5 matches.
    DBI::dbWriteTable(con, "population_windows", data.table::data.table(
      person_id = c("p1", "p2", "p3", "p4"),
      T0 = as.Date("2024-06-01"),
      variable_id = "v1",
      concept_id = "C1",
      window_name = "w",
      selector = "RANGE_COUNT",
      window_start = as.Date("2024-01-01"),
      window_end = as.Date("2024-12-31")
    ))

    DBI::dbWriteTable(con, "concepts", data.table::data.table(
      person_id = c("p2", "p3", "p3", "p3", "p4", "p4", "p4", "p4", "p4"), # nolint p1 not in concepts
      concept_id = "C1",
      date = as.Date(c(
        "2024-03-01",
        "2024-03-01", "2024-04-01", "2024-05-01",
        "2024-01-15", "2024-02-15", "2024-03-15", "2024-04-15", "2024-05-15"
      )),
      value = NA_character_
    ))

    DBI::dbWriteTable(con, "concept_ranges", data.table::data.table(
      concept_id = "C1",
      new_value = c(1, 2, 3, 4),
      lower_range = c(0, 1, 3, 5),
      upper_range = c(0, 2, 4, 99999)
    ))

    result <- data.table::as.data.table(
      DBI::dbGetQuery(con, read_selector_sql_query("RANGE_COUNT"))
    )
    data.table::setorder(result, person_id)

    # p1 has 0 matching concept rows, which is itself a valid, countable
    # outcome (falls in the lower_range=0/upper_range=0 bucket) and must not
    # be silently dropped from the result.
    testthat::expect_equal(result$person_id, c("p1", "p2", "p3", "p4"))
    testthat::expect_equal(result$value, c("1", "2", "3", "4"))
    testthat::expect_equal(result$n, c(0, 1, 3, 5))
  }
)

#--- SQL-level tests for the bundled selectors

# One `population_windows` row per person/window, shaped like the table
# `write_population_windows()` builds. `selector` is filled by
# `run_selector()` unless the caller sets it.
selector_windows <- function(
  person_id,
  window_name = "w",
  window_start = "2024-01-01",
  window_end = "2024-01-31",
  selector = NA_character_
) {
  data.table::data.table(
    person_id = person_id,
    T0 = as.Date("2024-02-01"),
    concept_id = "C1",
    variable_id = "v1",
    window_name = window_name,
    selector = selector,
    window_start = as.Date(window_start),
    window_end = as.Date(window_end),
    range_min = NA_real_,
    range_max = NA_real_
  )
}

selector_concepts <- function(person_id, date, value = NA_character_) {
  data.table::data.table(
    person_id = person_id,
    concept_id = "C1",
    date = as.Date(date),
    value = value
  )
}

# Run one selector's SQL against in-memory `population_windows`, `concepts`
# and (for RANGE_COUNT) `concept_ranges` tables.
run_selector <- function(selector, windows, concepts, concept_ranges = NULL) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  windows <- data.table::copy(windows)
  windows[is.na(selector), selector := ..selector]
  windows[, anchor_row_id := .I]
  DBI::dbWriteTable(con, "population_windows", windows)
  DBI::dbWriteTable(con, "concepts", concepts)
  if (is.null(concept_ranges)) {
    concept_ranges <- data.table::data.table(
      concept_id = "C1", new_value = 1, lower_range = 0, upper_range = 99999
    )
  }
  DBI::dbWriteTable(con, "concept_ranges", concept_ranges)

  result <- data.table::as.data.table(
    DBI::dbGetQuery(con, read_selector_sql_query(selector))
  )
  if ("date" %in% names(result)) {
    result[, date := as.Date(date)]
  }
  data.table::setorder(result, person_id, window_name, date)
  result[]
}

testthat::test_that(
  "every bundled selector honors the shared output contract",
  {
    # p1 has two windows: in `a`, events sit exactly on window_start and
    # window_end with one event a day outside on each side; `b` has two
    # events. p2 has matching events but its window belongs to another
    # selector, so it must not show up.
    concepts <- selector_concepts(
      person_id = c(rep("p1", 6), "p2", "p2"),
      date = c(
        "2023-12-31", "2024-01-01", "2024-01-31", "2024-02-01",
        "2024-03-10", "2024-03-20",
        "2024-01-10", "2024-01-20"
      )
    )
    required_cols <- c(
      "person_id", "T0", "variable_id", "window_name", "value", "date", "n"
    )

    for (selector in available_selectors()) {
      other_selector <- if (selector == "COUNT") "LATEST" else "COUNT"
      windows <- data.table::rbindlist(list(
        selector_windows("p1", "a", "2024-01-01", "2024-01-31"),
        selector_windows("p1", "b", "2024-03-01", "2024-03-31"),
        selector_windows("p2", "a", selector = other_selector)
      ))

      result <- run_selector(selector, windows, concepts)

      testthat::expect_true(
        all(required_cols %in% names(result)),
        info = selector
      )
      testthat::expect_equal(unique(result$person_id), "p1", info = selector)
      testthat::expect_equal(
        unique(result$window_name), c("a", "b"),
        info = selector
      )
      # Both inclusive boundary events count, the two outside events don't.
      testthat::expect_true(all(result$n == 2), info = selector)
      testthat::expect_true(
        all(result[window_name == "a", date] %in% as.Date(c("2024-01-01", "2024-01-31"))), # nolint
        info = selector
      )
      testthat::expect_type(result$value, "character")

      rows_per_key <- result[
        ,
        .N,
        by = .(person_id, T0, variable_id, window_name)
      ]$N
      expected_rows <- if (selector == "ALL") 2L else 1L
      testthat::expect_true(all(rows_per_key == expected_rows), info = selector)
    }
  }
)

testthat::test_that(
  "LATEST keeps the latest event, breaks date ties on the largest value
  and counts every match",
  {
    windows <- selector_windows(c("p1", "p2", "p3"))
    concepts <- selector_concepts(
      person_id = c("p1", "p1", "p1", "p2"),
      date = c("2024-01-05", "2024-01-20", "2024-01-20", "2024-01-10"),
      value = c("Z", "A", "B", NA_character_)
    )

    result <- run_selector("LATEST", windows, concepts)

    # p3 has no matching event, so it gets no row.
    testthat::expect_equal(result$person_id, c("p1", "p2"))
    testthat::expect_equal(result$value, c("B", "TRUE"))
    testthat::expect_equal(result$date, as.Date(c("2024-01-20", "2024-01-10")))
    testthat::expect_equal(result$n, c(3, 1))
  }
)

testthat::test_that(
  "EARLIEST keeps the earliest event, breaks date ties on the largest
  value and counts every match",
  {
    windows <- selector_windows(c("p1", "p2", "p3"))
    concepts <- selector_concepts(
      person_id = c("p1", "p1", "p1", "p2"),
      date = c("2024-01-05", "2024-01-05", "2024-01-20", "2024-01-10"),
      value = c("A", "B", "Z", NA_character_)
    )

    result <- run_selector("EARLIEST", windows, concepts)

    testthat::expect_equal(result$person_id, c("p1", "p2"))
    testthat::expect_equal(result$value, c("B", "TRUE"))
    testthat::expect_equal(result$date, as.Date(c("2024-01-05", "2024-01-10")))
    testthat::expect_equal(result$n, c(3, 1))
  }
)

testthat::test_that(
  "COUNT returns the number of matches as text with the latest date and
  drops people with no match",
  {
    windows <- selector_windows(c("p1", "p2", "p3"))
    concepts <- selector_concepts(
      person_id = c("p1", "p1", "p1", "p2"),
      date = c("2024-01-05", "2024-01-25", "2024-01-15", "2024-01-10")
    )

    result <- run_selector("COUNT", windows, concepts)

    # Unlike RANGE_COUNT, zero matches produce no row at all.
    testthat::expect_equal(result$person_id, c("p1", "p2"))
    testthat::expect_equal(result$value, c("3", "1"))
    testthat::expect_equal(result$date, as.Date(c("2024-01-25", "2024-01-10")))
    testthat::expect_equal(result$n, c(3, 1))
  }
)

testthat::test_that(
  "COUNT_MORE_THAN_1 flags only people with at least two matches",
  {
    windows <- selector_windows(c("p1", "p2", "p3", "p4"))
    concepts <- selector_concepts(
      person_id = c("p1", "p2", "p2", "p3", "p3", "p3"),
      date = c(
        "2024-01-05",
        "2024-01-05", "2024-01-25",
        "2024-01-05", "2024-01-15", "2024-01-10"
      )
    )

    result <- run_selector("COUNT_MORE_THAN_1", windows, concepts)

    # p1 has one match and p4 none, so neither gets a row.
    testthat::expect_equal(result$person_id, c("p2", "p3"))
    testthat::expect_equal(result$value, c("TRUE", "TRUE"))
    testthat::expect_equal(result$date, as.Date(c("2024-01-25", "2024-01-15")))
    testthat::expect_equal(result$n, c(2, 3))
  }
)

testthat::test_that(
  "ALL returns one row per matching event, each carrying the total count",
  {
    windows <- selector_windows(c("p1", "p2"))
    concepts <- selector_concepts(
      person_id = c("p1", "p1"),
      date = c("2024-01-05", "2024-01-20"),
      value = c("5", NA_character_)
    )

    result <- run_selector("ALL", windows, concepts)

    testthat::expect_equal(result$person_id, c("p1", "p1"))
    testthat::expect_equal(result$date, as.Date(c("2024-01-05", "2024-01-20")))
    testthat::expect_identical(result$value, c("5", "TRUE"))
    testthat::expect_equal(result$n, c(2, 2))
  }
)

testthat::test_that(
  "RANGE_COUNT places counts on a bucket edge into that bucket",
  {
    windows <- selector_windows(c("p2", "p3"))
    concepts <- selector_concepts(
      person_id = c("p2", "p2", "p3", "p3", "p3"),
      date = c(
        "2024-01-05", "2024-01-06",
        "2024-01-05", "2024-01-06", "2024-01-07"
      )
    )
    concept_ranges <- data.table::data.table(
      concept_id = "C1",
      new_value = c(1, 2),
      lower_range = c(0, 3),
      upper_range = c(2, 99999)
    )

    result <- run_selector("RANGE_COUNT", windows, concepts, concept_ranges)

    # 2 is the upper edge of bucket 1 and 3 the lower edge of bucket 2.
    testthat::expect_equal(result$n, c(2, 3))
    testthat::expect_equal(result$value, c("1", "2"))
  }
)

testthat::test_that(
  "LATEST and EARLIEST break date ties numerically for numeric values",
  {
    # All events share one date, so the value tie-break decides. Text
    # comparison would pick "9", "80" and "5.5"; numeric picks the largest.
    windows <- selector_windows(c("p1", "p2", "p3"))
    concepts <- selector_concepts(
      person_id = c("p1", "p1", "p2", "p2", "p3", "p3"),
      date = "2024-01-10",
      value = c("9", "10", "120", "80", "5.5", "12")
    )

    for (selector in c("LATEST", "EARLIEST")) {
      result <- run_selector(selector, windows, concepts)
      data.table::setorder(result, person_id)

      testthat::expect_equal(
        result$value, c("10", "120", "12"),
        info = selector
      )
    }
  }
)

testthat::test_that(
  "LATEST and EARLIEST rank tied non-numeric values above numbers",
  {
    windows <- selector_windows(c("p1", "p2", "p3", "p4"))
    concepts <- selector_concepts(
      person_id = c("p1", "p1", "p2", "p2", "p3", "p3", "p4", "p4"),
      date = "2024-01-10",
      value = c(
        NA_character_, "-3",
        "", "-3",
        "1000", "abc",
        "1", "1.0"
      )
    )

    for (selector in c("LATEST", "EARLIEST")) {
      result <- run_selector(selector, windows, concepts)
      data.table::setorder(result, person_id)

      # Non-numeric values get a NULL value_number, which DuckDB sorts above
      # every number. p1/p2: a missing or empty value beats a number (a NULL
      # value is returned as "TRUE"). p3: text beats numbers. p4: equal
      # numbers fall back to the raw text.
      testthat::expect_equal(
        result$value, c("TRUE", "", "abc", "1.0"),
        info = selector
      )
    }
  }
)
