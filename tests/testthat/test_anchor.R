# Test with minimal examples.
testthat::test_that("COUNT stores the matched event date in minimal output", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)
  anchor(
    population = minimal_population(),
    metadata = minimal_metadata(),
    concepts = minimal_concepts(),
    anchor_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  cov_count <- anchored[variable_id == "cov_count"]

  testthat::expect_equal(cov_count$person_id, c("2", "3"))
  testthat::expect_equal(cov_count$value, c("1", "1"))
  testthat::expect_equal(
    cov_count$date,
    as.Date(c("2023-11-01", "2023-12-15"))
  )
})

testthat::test_that(
  "LATEST/EARLIEST break same-date ties on the larger value",
  {
    # Locks down the arg_max/arg_min rewrite of latest.sql/earliest.sql:
    # LATEST must pick the row with the winning (latest) date, then the
    # larger value on ties; EARLIEST the winning (earliest) date, then the
    # larger value on ties. Each concept_id also carries a third, non-tied
    # record so a wrong date comparison (not just a wrong tie-break) would
    # be caught too.
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    population <- data.table::data.table(
      person_id = "1", T0 = as.Date("2024-01-01")
    )
    metadata <- data.table::data.table(
      variable_id = c("latest_tie", "earliest_tie"),
      concept_id = c("TIE_LATEST", "TIE_EARLIEST"),
      constructor = "GENERIC",
      selector = c("LATEST", "EARLIEST"),
      start_offset = -3650L,
      end_offset = 0L
    )
    concepts <- data.table::data.table(
      person_id = "1",
      concept_id = c(
        "TIE_LATEST", "TIE_LATEST", "TIE_LATEST",
        "TIE_EARLIEST", "TIE_EARLIEST", "TIE_EARLIEST"
      ),
      date = as.Date(c(
        "2023-06-01", "2023-06-01", "2022-01-01",
        "2021-01-01", "2021-01-01", "2022-01-01"
      )),
      value = c("A", "B", "Z", "X", "Y", "Z")
    )

    anchor(
      population = population,
      metadata = metadata,
      concepts = concepts,
      anchor_hive_path = hive_path
    )

    anchored <- read_anchor_hive(hive_path)
    data.table::setorder(anchored, variable_id)

    testthat::expect_equal(
      anchored[variable_id == "latest_tie", .(value, date, n)],
      data.table::data.table(
        value = "B", date = as.Date("2023-06-01"), n = 3L
      )
    )
    testthat::expect_equal(
      anchored[variable_id == "earliest_tie", .(value, date, n)],
      data.table::data.table(
        value = "Y", date = as.Date("2021-01-01"), n = 3L
      )
    )
  }
)

# Test with more realistic examples.
testthat::test_that("anchor writes selector results to the parquet hive", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  anchor(
    population = minimal_population(),
    metadata = minimal_metadata()[variable_id == "cov_latest"],
    concepts = minimal_concepts(),
    anchor_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  # Only person 1's cov_latest window ([2023-12-02, 2024-01-01]) actually
  # covers a COV_A record; person 5's COV_A (2024-01-14) falls before their
  # window ([2024-01-31, 2024-03-01]) opens.
  testthat::expect_equal(anchored$variable_id, "cov_latest")
  testthat::expect_equal(anchored$value, "TRUE")
  testthat::expect_equal(anchored$date, as.Date("2023-12-20"))
})

testthat::test_that(
  "rerunning anchor() into the same path replaces, not duplicates, rows",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    metadata <- minimal_metadata()[variable_id == "cov_latest"]

    anchor(
      population = minimal_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path
    )

    refreshed_concepts <- data.table::rbindlist(list(
      minimal_concepts(),
      data.table::data.table(
        person_id = "1", concept_id = "COV_A",
        date = as.Date("2023-12-31"), value = "UPDATED"
      )
    ))

    anchor(
      population = minimal_population(),
      metadata = metadata,
      concepts = refreshed_concepts,
      anchor_hive_path = hive_path
    )

    anchored <- read_anchor_hive(hive_path)

    testthat::expect_equal(nrow(anchored), 1L)
    testthat::expect_equal(anchored$value, "UPDATED")
    testthat::expect_equal(anchored$date, as.Date("2023-12-31"))
  }
)

testthat::test_that(
  "anchor keeps every selector's rows when one variable_id mixes selectors",
  {
    # Regression test: a single variable_id with a lookback window on LATEST
    # and induction/risk windows on EARLIEST used to lose the LATEST window's
    # rows entirely, because both selectors' `COPY ... PARTITION_BY
    # (variable_id)` writes landed on the same default filename inside that
    # variable_id's partition, and the second selector to run silently
    # overwrote the first's output file.
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    population <- data.table::data.table(
      person_id = "1", T0 = as.Date("2024-01-01")
    )
    metadata <- data.table::data.table(
      variable_id = c("mixed_selector", "mixed_selector"),
      concept_id = c("MIX", "MIX"),
      constructor = "GENERIC",
      window_name = c("lookback", "risk"),
      selector = c("LATEST", "EARLIEST"),
      start_offset = c(-30L, 1L),
      end_offset = c(-1L, 30L)
    )
    concepts <- data.table::data.table(
      person_id = c("1", "1"),
      concept_id = c("MIX", "MIX"),
      date = as.Date(c("2023-12-15", "2024-01-10")),
      value = c("PRIOR", "AFTER")
    )

    anchor(
      population = population,
      metadata = metadata,
      concepts = concepts,
      anchor_hive_path = hive_path
    )

    anchored <- read_anchor_hive(hive_path)
    data.table::setorder(anchored, window_name)

    testthat::expect_equal(anchored$window_name, c("lookback", "risk"))
    testthat::expect_equal(anchored$value, c("PRIOR", "AFTER"))
    testthat::expect_equal(
      anchored$date, as.Date(c("2023-12-15", "2024-01-10"))
    )
  }
)

testthat::test_that(
  "anchor ignores unrelated population covariates",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    population <- data.table::copy(minimal_population())
    population[, sex := c("F", "M", "F", "M", "F")]

    anchor(
      population = population,
      metadata = minimal_metadata()[variable_id == "cov_latest"],
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path
    )

    anchored <- read_anchor_hive(hive_path)

    testthat::expect_equal(anchored$variable_id, "cov_latest")
    testthat::expect_equal(anchored$value, "TRUE")
    testthat::expect_equal(anchored$date, as.Date("2023-12-20"))
  }
)

testthat::test_that("anchor honors a non-default anchor column", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  population <- data.table::copy(minimal_population())
  data.table::setnames(population, "T0", "anchor_date")

  anchor(
    population = population,
    metadata = minimal_metadata()[variable_id == "cov_latest"],
    concepts = minimal_concepts(),
    anchor_col = "anchor_date",
    anchor_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  testthat::expect_equal(anchored$variable_id, "cov_latest")
  testthat::expect_equal(anchored$value, "TRUE")
  testthat::expect_equal(anchored$date, as.Date("2023-12-20"))
})

testthat::test_that("anchor accepts parquet concept sources", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  anchor(
    population = minimal_population(),
    metadata = minimal_metadata()[variable_id == "cov_latest"],
    concepts = example_concepts_parquet(minimal_concepts()),
    anchor_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  testthat::expect_equal(anchored$value, "TRUE")
  testthat::expect_equal(anchored$date, as.Date("2023-12-20"))
})

testthat::test_that("it refreshes only requested variable partition", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  metadata <- minimal_metadata()[
    variable_id %in% c("cov_latest", "cov_count")
  ]

  anchor_by_variable(
    population = minimal_population(),
    metadata = metadata,
    concepts = minimal_concepts(),
    anchor_hive_path = hive_path
  )

  refreshed_concepts <- data.table::rbindlist(list(
    minimal_concepts(),
    data.table::data.table(
      person_id = "1",
      concept_id = "COV_A",
      date = as.Date("2023-12-31"),
      value = "UPDATED"
    )
  ))

  anchor_by_variable(
    population = minimal_population(),
    metadata = metadata[variable_id == "cov_latest"],
    concepts = refreshed_concepts,
    anchor_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  # Refreshing only cov_latest picks up the new, later COV_A record for
  # person 1 and leaves the untouched cov_count partition (person 2 and 3)
  # exactly as it was.
  testthat::expect_equal(nrow(anchored[variable_id == "cov_latest"]), 1L)
  testthat::expect_equal(
    anchored[variable_id == "cov_latest", value],
    "UPDATED"
  )
  testthat::expect_equal(nrow(anchored[variable_id == "cov_count"]), 2L)
  testthat::expect_equal(
    anchored[variable_id == "cov_count"][order(person_id), value],
    c("1", "1")
  )
})

testthat::test_that(
  "chunk_size batches variables (multiple selectors) without changing output",
  {
    # minimal_metadata() spans three different selectors (LATEST, COUNT,
    # RANGE_COUNT), so batching all three variables into one chunk exercises
    # one selector query per selector instead of per variable_id.
    metadata <- minimal_metadata()

    one_at_a_time_path <- tempfile(pattern = "anchor-hive-")
    dir.create(one_at_a_time_path)
    on.exit(
      unlink(one_at_a_time_path, recursive = TRUE, force = TRUE),
      add = TRUE
    )
    anchor_by_variable(
      population = minimal_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = one_at_a_time_path,
      chunk_size = 1
    )

    batched_path <- tempfile(pattern = "anchor-hive-")
    dir.create(batched_path)
    on.exit(unlink(batched_path, recursive = TRUE, force = TRUE), add = TRUE)
    anchor_by_variable(
      population = minimal_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = batched_path,
      chunk_size = 20
    )

    result_cols <- c("person_id", "T0", "variable_id", "value", "date", "n")
    one_at_a_time <- read_anchor_hive(one_at_a_time_path)[, ..result_cols]
    batched <- read_anchor_hive(batched_path)[, ..result_cols]
    data.table::setorder(one_at_a_time, variable_id, person_id)
    data.table::setorder(batched, variable_id, person_id)

    testthat::expect_equal(batched, one_at_a_time)
  }
)

testthat::test_that(
  "a failed chunk discards the whole run instead of publishing earlier chunks",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    # `lab_range`'s selector (RANGE_COUNT) sorts last among the three
    # selectors in `minimal_metadata()`, so with `chunk_size = 1` it lands in
    # the final chunk -- `cov_count` and `cov_latest` succeed in earlier
    # chunks before this one fails.
    metadata <- minimal_metadata()
    metadata[variable_id == "lab_range", constructor := "NOPE_CONSTRUCTOR"]

    testthat::expect_error(
      anchor_by_variable(
        population = minimal_population(),
        metadata = metadata,
        concepts = minimal_concepts(),
        anchor_hive_path = hive_path,
        chunk_size = 1
      ),
      "Window function does not exist"
    )

    # Even though cov_count and cov_latest were computed successfully before
    # the failing chunk, nothing should have been published.
    testthat::expect_length(list.files(hive_path, recursive = TRUE), 0L)
  }
)

testthat::test_that(
  "staging_mode = 'disk' produces the same output as the default 'memory'",
  {
    metadata <- minimal_metadata()

    memory_path <- tempfile(pattern = "anchor-hive-")
    dir.create(memory_path)
    on.exit(unlink(memory_path, recursive = TRUE, force = TRUE), add = TRUE)
    anchor_by_variable(
      population = minimal_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = memory_path,
      chunk_size = 1,
      staging_mode = "memory"
    )

    disk_path <- tempfile(pattern = "anchor-hive-")
    dir.create(disk_path)
    on.exit(unlink(disk_path, recursive = TRUE, force = TRUE), add = TRUE)
    anchor_by_variable(
      population = minimal_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = disk_path,
      chunk_size = 1,
      staging_mode = "disk"
    )

    result_cols <- c("person_id", "T0", "variable_id", "value", "date", "n")
    memory_result <- read_anchor_hive(memory_path)[, ..result_cols]
    disk_result <- read_anchor_hive(disk_path)[, ..result_cols]
    data.table::setorder(memory_result, variable_id, person_id)
    data.table::setorder(disk_result, variable_id, person_id)

    testthat::expect_equal(memory_result, disk_result)
  }
)

testthat::test_that(
  "publish = 'per_chunk' keeps earlier chunks when a later one fails",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    # Same setup as the all-or-nothing test above (lab_range fails and sorts
    # into the final chunk), but with publish = "per_chunk" the opposite is
    # expected: cov_count and cov_latest should already be on disk by the
    # time lab_range's chunk fails.
    metadata <- minimal_metadata()
    metadata[variable_id == "lab_range", constructor := "NOPE_CONSTRUCTOR"]

    testthat::expect_error(
      anchor_by_variable(
        population = minimal_population(),
        metadata = metadata,
        concepts = minimal_concepts(),
        anchor_hive_path = hive_path,
        chunk_size = 1,
        publish = "per_chunk"
      ),
      "Window function does not exist"
    )

    anchored <- read_anchor_hive(hive_path)
    testthat::expect_setequal(
      unique(anchored$variable_id), c("cov_count", "cov_latest")
    )
  }
)

testthat::test_that(
  "staging_mode = 'disk' and publish = 'per_chunk' also keep earlier chunks",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    metadata <- minimal_metadata()
    metadata[variable_id == "lab_range", constructor := "NOPE_CONSTRUCTOR"]

    testthat::expect_error(
      anchor_by_variable(
        population = minimal_population(),
        metadata = metadata,
        concepts = minimal_concepts(),
        anchor_hive_path = hive_path,
        chunk_size = 1,
        staging_mode = "disk",
        publish = "per_chunk"
      ),
      "Window function does not exist"
    )

    anchored <- read_anchor_hive(hive_path)
    testthat::expect_setequal(
      unique(anchored$variable_id), c("cov_count", "cov_latest")
    )
  }
)

testthat::test_that("reshapes variable-by-variable hive output", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  metadata <- minimal_metadata()[
    variable_id %in% c("cov_latest", "lab_range")
  ]
  anchor_by_variable(
    population = minimal_population(),
    metadata = metadata,
    concepts = minimal_concepts(),
    anchor_hive_path = hive_path
  )
  anchored <- get_anchor_result(
    metadata = metadata,
    anchor_hive_path = hive_path
  )
  data.table::setorder(anchored, person_id, T0)

  # cov_latest matches only person 1; lab_range's concept (LAB_X) never
  # appears in minimal_concepts(), so it never produces a match and its
  # value/date columns are entirely NA.
  testthat::expect_equal(anchored$person_id, "1")
  testthat::expect_equal(anchored$T0, as.Date("2024-01-01"))
  testthat::expect_equal(anchored$value_cov_latest, "TRUE")
  testthat::expect_true(is.na(anchored$value_lab_range))
})

testthat::test_that(
  "wide output is limited to the population for single-window metadata",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    metadata <- minimal_metadata()[variable_id == "cov_latest"]
    anchor_by_variable(
      population = minimal_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path
    )

    anchored <- get_anchor_result(
      metadata = metadata,
      anchor_hive_path = hive_path,
      population = minimal_population()[1, .(person_id, T0)],
      result_shape = "wide"
    )

    testthat::expect_equal(nrow(anchored), 1L)
    testthat::expect_equal(anchored$person_id, "1")
    testthat::expect_equal(anchored$T0, as.Date("2024-01-01"))
    # minimal_metadata() does not set window_name, so it is NA rather than
    # a real window label here.
    testthat::expect_true(is.na(anchored$window_name))
  }
)

testthat::test_that(
  "wide output does not leak rows outside a single-window population",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    write_anchor_hive_fixture(
      anchor_hive_path = hive_path,
      variable_id = "cov_latest",
      rows = data.table::data.table(
        person_id = c("1", "2"),
        T0 = as.Date(c("2024-01-01", "2024-01-15")),
        window_name = c("fup", "fup"),
        value = c("TRUE", "FALSE"),
        date = as.Date(c("2024-01-10", "2024-01-20")),
        n = c(1L, 1L)
      )
    )

    anchored <- get_anchor_result(
      metadata = data.table::data.table(
        variable_id = "cov_latest",
        window_name = "fup"
      ),
      anchor_hive_path = hive_path,
      population = data.table::data.table(
        person_id = "1",
        T0 = as.Date("2024-01-01"),
        match_id = "m1",
        group = "treated"
      ),
      result_shape = "wide"
    )

    # Before the fix this returned 2 rows because existing hive rows were not
    # constrained to the requested population before the backfill step.
    testthat::expect_equal(nrow(anchored), 1L)
    testthat::expect_equal(anchored$person_id, "1")
    testthat::expect_equal(anchored$T0, as.Date("2024-01-01"))
    testthat::expect_equal(anchored$match_id, "m1")
    testthat::expect_equal(anchored$group, "treated")
    testthat::expect_equal(anchored$window_name, "fup")
    testthat::expect_equal(anchored$value_cov_latest, "TRUE")
  }
)

testthat::test_that(
  "wide output one row per population-window key when cast_window is FALSE",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    metadata <- minimal_metadata()[
      variable_id %in% c("cov_latest", "lab_range")
    ]
    anchor_by_variable(
      population = minimal_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path
    )

    anchored <- get_anchor_result(
      metadata = metadata,
      anchor_hive_path = hive_path,
      population = minimal_population()[, .(person_id, T0)],
      result_shape = "wide"
    )

    # minimal_metadata() gives both variables the same (NA) window_name, so
    # this is one row per population key rather than per key x window_name;
    # the backfill still guarantees all 5 population rows are present.
    data.table::setorder(anchored, person_id, T0)
    testthat::expect_equal(nrow(anchored), 5L)
    testthat::expect_equal(anchored$person_id, as.character(1:5))
    testthat::expect_true(all(is.na(anchored$window_name)))
    testthat::expect_equal(
      anchored$value_cov_latest, c("TRUE", NA, NA, NA, NA)
    )
    testthat::expect_true(all(is.na(anchored$value_lab_range)))
  }
)

testthat::test_that(
  "wide output backfills one row per population key when cast_window is TRUE",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    metadata <- minimal_metadata()[
      variable_id %in% c("cov_latest", "lab_range")
    ]
    anchor_by_variable(
      population = minimal_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path
    )

    anchored <- get_anchor_result(
      metadata = metadata,
      anchor_hive_path = hive_path,
      population = minimal_population()[1, .(person_id, T0)],
      result_shape = "wide",
      cast_window = TRUE
    )

    testthat::expect_equal(nrow(anchored), 1L)
    testthat::expect_equal(anchored$person_id, "1")
    testthat::expect_equal(anchored$T0, as.Date("2024-01-01"))
  }
)

testthat::test_that(
  "order_variable_ids_by_selector groups same-selector variables together",
  {
    metadata <- data.table::data.table(
      variable_id = c("a", "b", "c", "d"),
      selector = c("COUNT", "LATEST", "COUNT", "LATEST")
    )

    ordered <- order_variable_ids_by_selector(metadata)

    # "COUNT" sorts before "LATEST"; within each selector, original relative
    # order (a before c, b before d) is preserved by the stable sort.
    testthat::expect_equal(ordered, c("a", "c", "b", "d"))
  }
)

testthat::test_that(
  "order_variable_ids_by_selector uses a variable_id's first-listed selector",
  {
    # variable_id "x" spans two windows with different selectors; its sort
    # key should come from whichever selector is listed first for it.
    metadata <- data.table::data.table(
      variable_id = c("x", "y", "x"),
      selector = c("LATEST", "COUNT", "EARLIEST")
    )

    ordered <- order_variable_ids_by_selector(metadata)

    testthat::expect_equal(ordered, c("y", "x"))
  }
)

testthat::test_that(
  "anchor_by_selector batches variables by selector and matches anchor()",
  {
    # minimal_metadata() spans three selectors (LATEST, COUNT, RANGE_COUNT),
    # so this exercises one anchor() call per selector.
    metadata <- minimal_metadata()

    reference_path <- tempfile(pattern = "anchor-hive-")
    dir.create(reference_path)
    on.exit(unlink(reference_path, recursive = TRUE, force = TRUE), add = TRUE)
    anchor(
      population = minimal_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = reference_path
    )

    by_selector_path <- tempfile(pattern = "anchor-hive-")
    dir.create(by_selector_path)
    on.exit(
      unlink(by_selector_path, recursive = TRUE, force = TRUE),
      add = TRUE
    )
    processed_selectors <- anchor_by_selector(
      population = minimal_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = by_selector_path
    )

    testthat::expect_setequal(
      processed_selectors, c("LATEST", "COUNT", "RANGE_COUNT")
    )

    result_cols <- c("person_id", "T0", "variable_id", "value", "date", "n")
    reference <- read_anchor_hive(reference_path)[, ..result_cols]
    by_selector <- read_anchor_hive(by_selector_path)[, ..result_cols]
    data.table::setorder(reference, variable_id, person_id)
    data.table::setorder(by_selector, variable_id, person_id)

    testthat::expect_equal(by_selector, reference)
  }
)

testthat::test_that(
  "anchor_by_selector preserves two selectors for one variable_id",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    population <- minimal_population()
    metadata <- minimal_metadata()[selector %in% c("LATEST", "COUNT")]
    metadata[, variable_id := "mixed"]
    concepts <- minimal_concepts()

    anchor_by_selector(
      population = population,
      metadata = metadata,
      concepts = concepts,
      anchor_hive_path = hive_path
    )

    partition_path <- file.path(hive_path, "variable_id=mixed")
    testthat::expect_setequal(
      list.files(partition_path),
      c("latest_0.parquet", "count_0.parquet")
    )
  }
)
