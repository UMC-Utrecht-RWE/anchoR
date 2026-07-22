testthat::test_that(
  "get_anchor_result keeps every population row sharing a person_id/T0 key", # nolint
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

    # Matching with replacement: the person "1"/T0 key is shared by two rows
    # distinguished only by `match_id`, e.g. the same control matched to two
    # exposed persons.
    duplicated_population <- data.table::rbindlist(list(
      minimal_population()[, match_id := "m1"],
      data.table::data.table(
        person_id = "1", T0 = as.Date("2024-01-01"), match_id = "m2"
      )
    ))

    result <- get_anchor_result(
      metadata = minimal_metadata()[variable_id == "cov_latest"],
      anchor_hive_path = hive_path,
      population = duplicated_population,
      result_shape = "wide"
    )

    testthat::expect_equal(nrow(result), nrow(duplicated_population))
    testthat::expect_setequal(
      result[person_id == "1", match_id], c("m1", "m2")
    )
    # Both rows for person "1" share the same anchored value, since it is
    # computed once per person_id/T0 key and left-joined onto every
    # population row for that key.
    testthat::expect_equal(
      length(unique(result[person_id == "1", value_cov_latest])), 1L
    )
  }
)
