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
  "imputing_missing returns input unchanged when all required metadata
  columns are absent",
  {
    wide_anchored <- data.table::data.table(
      person_id = "1",
      value_bool_var = NA_character_
    )
    metadata <- data.table::data.table(other_col = "x")

    testthat::expect_silent(
      result <- imputing_missing(wide_anchored, metadata)
    )

    testthat::expect_identical(result, wide_anchored)
  }
)

testthat::test_that(
  "imputing_missing warns and skips imputation when metadata is only
  partially missing required columns",
  {
    wide_anchored <- data.table::data.table(
      person_id = "1",
      value_bool_var = NA_character_
    )
    metadata <- data.table::data.table(
      variable_id = "bool_var",
      is_expected_missing = FALSE
    )

    testthat::expect_warning(
      result <- imputing_missing(wide_anchored, metadata),
      "Present: variable_id, is_expected_missing\\. Missing: variable_type\\."
    )

    testthat::expect_identical(result, wide_anchored)
  }
)

testthat::test_that(
  "imputing_missing fills missing boolean values with FALSE and coerces
  the column to logical, recognizing 1/0 string encodings of TRUE/FALSE",
  {
    wide_anchored <- data.table::data.table(
      person_id = c("1", "2", "3", "4"),
      value_bool_var = c("TRUE", NA_character_, "1", "0")
    )
    metadata <- data.table::data.table(
      variable_id = "bool_var",
      is_expected_missing = FALSE,
      variable_type = "TF"
    )

    result <- imputing_missing(wide_anchored, metadata)

    testthat::expect_identical(
      result$value_bool_var, c(TRUE, FALSE, TRUE, FALSE)
    )
    testthat::expect_type(result$value_bool_var, "logical")
  }
)

testthat::test_that(
  "imputing_missing does not flip explicit FALSE values to TRUE",
  {
    wide_anchored <- data.table::data.table(
      person_id = c("1", "2"),
      value_bool_var = c("FALSE", FALSE)
    )
    metadata <- data.table::data.table(
      variable_id = "bool_var",
      is_expected_missing = FALSE,
      variable_type = "TF"
    )

    result <- imputing_missing(wide_anchored, metadata)

    testthat::expect_identical(result$value_bool_var, c(FALSE, FALSE))
  }
)

testthat::test_that(
  "imputing_missing replaces invalid boolean values with TRUE",
  {
    old_appender <- logger::log_appender()
    if (!is.function(old_appender)) old_appender <- logger::appender_console
    withr::defer(logger::log_appender(old_appender))
    logger::log_appender(logger::appender_void)

    wide_anchored <- data.table::data.table(
      person_id = "1",
      value_bool_var = "yes"
    )
    metadata <- data.table::data.table(
      variable_id = "bool_var",
      is_expected_missing = FALSE,
      variable_type = "BOOL"
    )

    invisible(utils::capture.output(
      result <- imputing_missing(wide_anchored, metadata)
    ))

    testthat::expect_identical(result$value_bool_var, TRUE)
  }
)

testthat::test_that(
  "imputing_missing leaves missing values as NA when is_expected_missing
  is TRUE",
  {
    wide_anchored <- data.table::data.table(
      person_id = c("1", "2"),
      value_bool_var = c(NA_character_, "TRUE")
    )
    metadata <- data.table::data.table(
      variable_id = "bool_var",
      is_expected_missing = TRUE,
      variable_type = "TF"
    )

    result <- imputing_missing(wide_anchored, metadata)

    testthat::expect_identical(
      result$value_bool_var, c(NA_character_, "TRUE")
    )
  }
)

testthat::test_that(
  "imputing_missing fills missing categorical values with 0",
  {
    wide_anchored <- data.table::data.table(
      person_id = c("1", "2"),
      value_cat_var = c(NA_character_, "2")
    )
    metadata <- data.table::data.table(
      variable_id = "cat_var",
      is_expected_missing = FALSE,
      variable_type = "CAT"
    )

    result <- imputing_missing(wide_anchored, metadata)

    testthat::expect_identical(result$value_cat_var, c("0", "2"))
  }
)

testthat::test_that(
  "imputing_missing leaves non-boolean, non-categorical variable types
  untouched",
  {
    wide_anchored <- data.table::data.table(
      person_id = "1",
      value_int_var = NA_character_
    )
    metadata <- data.table::data.table(
      variable_id = "int_var",
      is_expected_missing = FALSE,
      variable_type = "INT"
    )

    result <- imputing_missing(wide_anchored, metadata)

    testthat::expect_identical(result$value_int_var, NA_character_)
  }
)

testthat::test_that(
  "imputing_missing leaves unrecognized variable_type values unchanged
  for non-character columns",
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

testthat::test_that(
  "imputing_missing skips variables whose value column is absent",
  {
    wide_anchored <- data.table::data.table(person_id = "1")
    metadata <- data.table::data.table(
      variable_id = "missing_var",
      is_expected_missing = FALSE,
      variable_type = "TF"
    )

    result <- imputing_missing(wide_anchored, metadata)

    testthat::expect_identical(result, wide_anchored)
  }
)
