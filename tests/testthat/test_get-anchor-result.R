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

#--- Tests for imputing_missing
testthat::test_that(
  "imputing_missing returns input unchanged when no imputation columns are present", # nolint
  {
    wide_anchored <- data.table::data.table(
      person_id = "1", value_v1 = NA_character_
    )
    metadata <- data.table::data.table(other_col = "irrelevant")

    result <- imputing_missing(wide_anchored, metadata)

    testthat::expect_identical(result, wide_anchored)
  }
)

testthat::test_that(
  "imputing_missing warns and skips when only some imputation columns are present", # nolint
  {
    wide_anchored <- data.table::data.table(
      person_id = "1", value_v1 = NA_character_
    )
    metadata <- data.table::data.table(
      variable_id = "v1", is_expected_missing = FALSE
    )

    testthat::expect_warning(
      result <- imputing_missing(wide_anchored, metadata),
      "Present: variable_id, is_expected_missing\\. Missing: variable_type\\."
    )
    testthat::expect_identical(result$value_v1, NA_character_)
  }
)

testthat::test_that("imputing_missing imputes missing TF values as FALSE", {
  wide_anchored <- data.table::data.table(
    person_id = c("1", "2"), value_v1 = c(NA, "TRUE")
  )
  metadata <- data.table::data.table(
    variable_id = "v1", is_expected_missing = FALSE, variable_type = "TF"
  )

  result <- imputing_missing(wide_anchored, metadata)

  testthat::expect_equal(result$value_v1, c(FALSE, TRUE))
  testthat::expect_type(result$value_v1, "logical")
})

testthat::test_that(
  "imputing_missing replaces invalid non-missing TF values with TRUE",
  {
    wide_anchored <- data.table::data.table(
      person_id = "1", value_v1 = "banana"
    )
    metadata <- data.table::data.table(
      variable_id = "v1", is_expected_missing = FALSE, variable_type = "BOOL"
    )

    testthat::expect_output(
      result <- imputing_missing(wide_anchored, metadata)
    )

    testthat::expect_true(result$value_v1)
  }
)

testthat::test_that(
  "imputing_missing leaves the string \"TRUE\" as TRUE",
  {
    wide_anchored <- data.table::data.table(
      person_id = "1", value_v1 = "TRUE"
    )
    metadata <- data.table::data.table(
      variable_id = "v1",
      is_expected_missing = FALSE,
      variable_type = "BOOLEAN"
    )

    result <- imputing_missing(wide_anchored, metadata)

    testthat::expect_true(result$value_v1)
  }
)

testthat::test_that(
  "BUG: imputing_missing turns a \"1\" TF value into NA, not TRUE", # nolint: line_length_linter.
  {
    # `"1"` is in the function's own "already valid, don't touch" list
    # (c(TRUE, 1, "TRUE", "1")), so it's never routed through the
    # invalid-value-to-TRUE branch -- but the final blanket
    # `as.logical(get(value_col))` call doesn't understand the string "1"
    # (as.logical("1") is NA in base R; only "TRUE"/"T"/"true" etc. parse),
    # so it silently comes out NA instead of TRUE. This test documents the
    # current (surprising) behavior, not the documented intent -- flag if
    # this should actually be fixed to impute TRUE for "1" like it does for
    # "TRUE".
    wide_anchored <- data.table::data.table(person_id = "1", value_v1 = "1")
    metadata <- data.table::data.table(
      variable_id = "v1",
      is_expected_missing = FALSE,
      variable_type = "BOOLEAN"
    )

    result <- imputing_missing(wide_anchored, metadata)

    testthat::expect_true(is.na(result$value_v1))
  }
)

testthat::test_that("imputing_missing imputes missing CAT values as 0", {
  wide_anchored <- data.table::data.table(
    person_id = c("1", "2"), value_v1 = c(NA, "2")
  )
  metadata <- data.table::data.table(
    variable_id = "v1", is_expected_missing = FALSE, variable_type = "CAT"
  )

  result <- imputing_missing(wide_anchored, metadata)

  testthat::expect_equal(result$value_v1, c("0", "2"))
})

testthat::test_that(
  "imputing_missing leaves is_expected_missing variables untouched",
  {
    wide_anchored <- data.table::data.table(
      person_id = "1", value_v1 = NA_character_
    )
    metadata <- data.table::data.table(
      variable_id = "v1", is_expected_missing = TRUE, variable_type = "TF"
    )

    result <- imputing_missing(wide_anchored, metadata)

    testthat::expect_true(is.na(result$value_v1))
  }
)

testthat::test_that(
  "imputing_missing skips a variable whose value column isn't in wide_anchored", # nolint
  {
    wide_anchored <- data.table::data.table(person_id = "1")
    metadata <- data.table::data.table(
      variable_id = "not_present",
      is_expected_missing = FALSE,
      variable_type = "TF"
    )

    result <- imputing_missing(wide_anchored, metadata)

    testthat::expect_equal(names(result), "person_id")
  }
)

testthat::test_that(
  "imputing_missing leaves unrecognized variable_type values unchanged",
  {
    wide_anchored <- data.table::data.table(
      person_id = "1", value_v1 = NA_integer_
    )
    metadata <- data.table::data.table(
      variable_id = "v1", is_expected_missing = FALSE, variable_type = "INT"
    )

    result <- imputing_missing(wide_anchored, metadata)

    testthat::expect_true(is.na(result$value_v1))
  }
)
