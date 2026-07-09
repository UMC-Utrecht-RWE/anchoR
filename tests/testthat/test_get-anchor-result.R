testthat::test_that(
  "population_conflict_columns names the one column that varies",
  {
    population_dt <- data.table::data.table(
      person_id = c("1", "1", "2"),
      T0 = as.Date(c("2024-01-01", "2024-01-01", "2024-02-01")),
      match_id = c("m1", "m2", "m3"),
      sex = c("F", "F", "M")
    )
    duplicate_keys <- data.table::data.table(
      person_id = "1", T0 = as.Date("2024-01-01")
    )

    testthat::expect_equal(
      population_conflict_columns(population_dt, duplicate_keys), "match_id"
    )
  }
)

testthat::test_that(
  "population_conflict_columns names every varying column",
  {
    population_dt <- data.table::data.table(
      person_id = c("1", "1"),
      T0 = as.Date(c("2024-01-01", "2024-01-01")),
      match_id = c("m1", "m2"),
      group = c("case", "control")
    )
    duplicate_keys <- data.table::data.table(
      person_id = "1", T0 = as.Date("2024-01-01")
    )

    testthat::expect_setequal(
      population_conflict_columns(population_dt, duplicate_keys),
      c("match_id", "group")
    )
  }
)

testthat::test_that(
  "get_anchor_result warns and keeps the first row when population keys clash", # nolint
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    anchor(
      population = minimal_population(),
      metadata = minimal_metadata()[variable_id == "cov_latest"],
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path
    )

    conflicting_population <- data.table::rbindlist(list(
      minimal_population()[, match_id := "m1"],
      data.table::data.table(
        person_id = "1", T0 = as.Date("2024-01-01"), match_id = "m2"
      )
    ))

    result <- NULL
    testthat::expect_warning(
      result <- get_anchor_result(
        metadata = minimal_metadata()[variable_id == "cov_latest"],
        anchor_hive_path = hive_path,
        population = conflicting_population,
        result_shape = "wide"
      ),
      "Conflicting column\\(s\\): match_id"
    )

    testthat::expect_equal(nrow(result[person_id == "1"]), 1L)
    testthat::expect_equal(
      result[person_id == "1", match_id], "m1"
    )
  }
)
