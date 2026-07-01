# Test with minimal examples.
testthat::test_that("COUNT stores the matched event date in minimal output", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)
  anchor(
    population = minimal_population(),
    metadata = minimal_metadata(),
    concepts = minimal_concepts_parquet(minimal_concepts()),
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

  testthat::expect_equal(anchored$variable_id, c("cov_latest", "cov_latest"))
  testthat::expect_equal(anchored$value, c("TRUE", "FALSE"))
  testthat::expect_equal(
    anchored$date,
    as.Date(c("2023-12-20", "2024-01-14"))
  )
})

testthat::test_that("anchor honors a non-default anchor column", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  population <- data.table::copy(example_population())
  data.table::setnames(population, "T0", "anchor_date")

  anchor(
    population = population,
    metadata = minimal_metadata()[variable_id == "lab_range"],
    concepts = minimal_concepts(),
    anchor_col = "anchor_date",
    anchor_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  testthat::expect_equal(anchored$variable_id, "lab_range")
  testthat::expect_equal(anchored$value, "1")
  testthat::expect_equal(anchored$date, as.Date("2024-01-10"))
})

testthat::test_that("anchor accepts parquet concept sources", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  anchor(
    population = example_population(),
    metadata = minimal_metadata()[variable_id == "lab_range"],
    concepts = example_concepts_parquet(minimal_concepts()),
    anchor_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  testthat::expect_equal(anchored$value, "1")
  testthat::expect_equal(anchored$date, as.Date("2024-01-10"))
})

testthat::test_that("it refreshes only requested variable partition", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  metadata <- minimal_metadata()[
    variable_id %in% c("cov_latest", "cov_count")
  ]

  anchor_by_variable(
    population = example_population(),
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
    population = example_population(),
    metadata = metadata[variable_id == "cov_latest"],
    concepts = refreshed_concepts,
    anchor_hive_path = hive_path
  )

  anchored <- read_anchor_hive(hive_path)

  testthat::expect_equal(nrow(anchored[variable_id == "cov_latest"]), 2L)
  testthat::expect_equal(
    anchored[variable_id == "cov_latest" & anchor_row_id == 1L, value],
    "UPDATED"
  )
  testthat::expect_equal(nrow(anchored[variable_id == "cov_count"]), 1L)
  testthat::expect_equal(anchored[variable_id == "cov_count", value], "2")
})

testthat::test_that("reshapes variable-by-variable hive output", {
  hive_path <- tempfile(pattern = "anchor-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  metadata <- minimal_metadata()[
    variable_id %in% c("cov_latest", "lab_range")
  ]
  anchor_by_variable(
    population = example_population(),
    metadata = metadata,
    concepts = minimal_concepts(),
    anchor_hive_path = hive_path
  )
  anchored <- get_anchor_result(
    metadata = metadata,
    anchor_hive_path = hive_path
  )
  data.table::setorder(anchored, person_id, T0)

  testthat::expect_equal(anchored$person_id, c("1", "2", "2"))
  testthat::expect_equal(
    anchored$T0, as.Date(c("2024-01-01", "2024-01-15", "2024-01-15"))
  )
  testthat::expect_equal(anchored$value_cov_latest, c("TRUE", "FALSE", NA))
  expect_true(is.na(anchored$value_lab_range[[1L]]))
  testthat::expect_equal(anchored$value_lab_range[[2L]], NA_character_)
})

testthat::test_that(
  "wide output is limited to the population for single-window metadata",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    metadata <- minimal_metadata()[variable_id == "cov_latest"]
    anchor_by_variable(
      population = example_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path
    )

    anchored <- get_anchor_result(
      metadata = metadata,
      anchor_hive_path = hive_path,
      population = example_population()[1, .(person_id, T0)],
      result_shape = "wide"
    )

    testthat::expect_equal(nrow(anchored), 1L)
    testthat::expect_equal(anchored$person_id, "1")
    testthat::expect_equal(anchored$T0, as.Date("2024-01-01"))
    testthat::expect_equal(anchored$window_name, "lookback")
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
      population = example_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path
    )

    anchored <- get_anchor_result(
      metadata = metadata,
      anchor_hive_path = hive_path,
      population = example_population()[, .(person_id, T0)],
      result_shape = "wide"
    )

    data.table::setorder(anchored, person_id, T0, window_name)
    testthat::expect_equal(nrow(anchored), 4L)
    testthat::expect_equal(
      anchored[, .(person_id, T0, window_name)],
      data.table::data.table(
        person_id = c("1", "1", "2", "2"),
        T0 = as.Date(c("2024-01-01", "2024-01-01", "2024-01-15", "2024-01-15")),
        window_name = c("lookback", "lookforward", "lookback", "lookforward")
      )
    )
    testthat::expect_true(
      all(is.na(
        anchored[
          person_id == "1" & window_name == "lookforward",
          .(value_cov_latest, date_cov_latest, value_lab_range, date_lab_range)
        ]
      ))
    )
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
      population = example_population(),
      metadata = metadata,
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path
    )

    anchored <- get_anchor_result(
      metadata = metadata,
      anchor_hive_path = hive_path,
      population = example_population()[1, .(person_id, T0)],
      result_shape = "wide",
      cast_window = TRUE
    )

    testthat::expect_equal(nrow(anchored), 1L)
    testthat::expect_equal(anchored$person_id, "1")
    testthat::expect_equal(anchored$T0, as.Date("2024-01-01"))
  }
)
