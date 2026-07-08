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
    anchored[variable_id == "cov_latest" & anchor_row_id == 1L, value],
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
      unlink(one_at_a_time_path, recursive = TRUE, force = TRUE), add = TRUE
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

    # `anchor_row_id` is a synthetic id scoped to each `anchor_impl()` call
    # (see `finalize_windows()`), so it is not expected to match across
    # different chunkings -- only the actual anchored content is.
    result_cols <- c("person_id", "T0", "variable_id", "value", "date", "n")
    one_at_a_time <- read_anchor_hive(one_at_a_time_path)[, ..result_cols]
    batched <- read_anchor_hive(batched_path)[, ..result_cols]
    data.table::setorder(one_at_a_time, variable_id, person_id)
    data.table::setorder(batched, variable_id, person_id)

    testthat::expect_equal(batched, one_at_a_time)
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
        anchor_row_id = c(1L, 2L),
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
