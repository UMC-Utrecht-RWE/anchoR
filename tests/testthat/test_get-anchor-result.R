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

testthat::test_that(
  "get_count_anchored_variables discovers variables and counts across files",
  {
    hive_path <- tempfile(pattern = "anchor-count-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    metadata <- minimal_metadata()
    anchor(
      population = minimal_population(),
      metadata = metadata[variable_id == "cov_latest"],
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path
    )
    anchor(
      population = minimal_population(),
      metadata = metadata[variable_id == "cov_count"],
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path
    )
    latest_file <- list.files(
      file.path(hive_path, "variable_id=cov_latest"),
      pattern = "\\.parquet$",
      full.names = TRUE
    )
    file.copy(
      latest_file,
      file.path(dirname(latest_file), "additional.parquet")
    )

    result <- get_count_anchored_variables(hive_path)

    testthat::expect_identical(
      result$variable_id,
      c("cov_count", "cov_latest")
    )
    testthat::expect_equal(result$n_anchored, c(2, 2))
  }
)

testthat::test_that(
  "get_count_anchored_variables optionally includes concept counts",
  {
    hive_path <- tempfile(pattern = "anchor-count-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    metadata <- minimal_metadata()
    anchor(
      population = minimal_population(),
      metadata = metadata[variable_id %in% c("cov_latest", "cov_count")],
      concepts = minimal_concepts(),
      anchor_hive_path = hive_path
    )
    result <- get_count_anchored_variables(
      anchor_hive_path = hive_path,
      include_concept_counts = TRUE,
      concepts = minimal_concepts(),
      variable_concepts = metadata[, .(variable_id, concept_id)]
    )

    testthat::expect_named(
      result,
      c("variable_id", "n_anchored", "concept_id", "n_concept")
    )
    testthat::expect_equal(result$n_anchored, c(2, 1))
    testthat::expect_equal(result$n_concept, c(2, 2))
  }
)

testthat::test_that(
  "get_count_anchored_variables requires concepts when requested",
  {
    hive_path <- tempfile(pattern = "anchor-count-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    testthat::expect_error(
      get_count_anchored_variables(
        hive_path,
        include_concept_counts = TRUE
      ),
      "`concepts` must be supplied"
    )
  }
)

testthat::test_that(
  "get_count_anchored_variables validates include_concept_counts",
  {
    hive_path <- tempfile(pattern = "anchor-count-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    for (bad_value in list("yes", NA, c(TRUE, FALSE))) {
      testthat::expect_error(
        get_count_anchored_variables(
          hive_path,
          include_concept_counts = bad_value
        ),
        "`include_concept_counts` must be TRUE or FALSE."
      )
    }
  }
)

testthat::test_that(
  "get_count_anchored_variables requires one existing hive directory",
  {
    hive_path <- tempfile(pattern = "anchor-count-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    bad_paths <- list(
      file.path(hive_path, "does-not-exist"),
      c(hive_path, hive_path),
      NA_character_,
      1
    )
    for (bad_path in bad_paths) {
      testthat::expect_error(
        get_count_anchored_variables(bad_path),
        "`anchor_hive_path` must be one existing directory."
      )
    }
  }
)

testthat::test_that(
  "get_count_anchored_variables requires variable_concepts when requested",
  {
    hive_path <- tempfile(pattern = "anchor-count-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    testthat::expect_error(
      get_count_anchored_variables(
        hive_path,
        include_concept_counts = TRUE,
        concepts = minimal_concepts()
      ),
      "`variable_concepts` must be supplied"
    )
  }
)

testthat::test_that(
  "get_count_anchored_variables reports zero concept counts when the
  mapping has no non-missing concept_id",
  {
    hive_path <- tempfile(pattern = "anchor-count-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    write_anchor_hive_fixture(
      anchor_hive_path = hive_path,
      variable_id = "v1",
      rows = data.table::data.table(
        person_id = c("1", "2"),
        T0 = as.Date(c("2024-01-01", "2024-01-15")),
        window_name = "fup",
        value = "TRUE",
        date = as.Date(c("2024-01-10", "2024-01-20"))
      )
    )

    result <- get_count_anchored_variables(
      anchor_hive_path = hive_path,
      include_concept_counts = TRUE,
      concepts = minimal_concepts(),
      variable_concepts = data.table::data.table(
        variable_id = "v1",
        concept_id = NA_character_
      )
    )

    testthat::expect_equal(result$variable_id, "v1")
    testthat::expect_equal(result$n_anchored, 2)
    testthat::expect_true(is.na(result$concept_id))
    testthat::expect_equal(result$n_concept, 0)
  }
)

#--- Tests for get_anchor_result input validation and output shapes
testthat::test_that(
  "get_anchor_result errors when population lacks required columns",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    testthat::expect_error(
      get_anchor_result(
        metadata = data.table::data.table(variable_id = "v1"),
        anchor_hive_path = hive_path,
        population = data.table::data.table(person_id = "1")
      ),
      "`population` is missing required columns: T0."
    )
  }
)

testthat::test_that(
  "get_anchor_result errors when anchor_hive_path is NULL or missing",
  {
    metadata <- data.table::data.table(variable_id = "v1")

    testthat::expect_error(
      get_anchor_result(metadata = metadata, anchor_hive_path = NULL),
      "`anchor_hive_path` must be a valid path!"
    )
    testthat::expect_error(
      get_anchor_result(
        metadata = metadata,
        anchor_hive_path = file.path(tempdir(), "no-such-anchor-hive")
      ),
      "`anchor_hive_path` must be a valid path!"
    )
  }
)

testthat::test_that(
  "get_anchor_result errors on an unknown result_shape",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    write_anchor_hive_fixture(
      anchor_hive_path = hive_path,
      variable_id = "v1",
      rows = data.table::data.table(
        person_id = "1",
        T0 = as.Date("2024-01-01"),
        window_name = "fup",
        value = "TRUE",
        date = as.Date("2024-01-10")
      )
    )

    testthat::expect_error(
      get_anchor_result(
        metadata = data.table::data.table(variable_id = "v1"),
        anchor_hive_path = hive_path,
        result_shape = "tall"
      ),
      "`result_shape` must be either 'wide' or 'long'!"
    )
  }
)

testthat::test_that(
  "get_anchor_result returns only the long-output columns, ordered, for
  requested variables",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    write_anchor_hive_fixture(
      anchor_hive_path = hive_path,
      variable_id = "v1",
      rows = data.table::data.table(
        person_id = c("2", "1"),
        T0 = as.Date(c("2024-01-15", "2024-01-01")),
        window_name = "fup",
        value = c("FALSE", "TRUE"),
        date = as.Date(c("2024-01-20", "2024-01-10")),
        n = c(1L, 1L)
      )
    )
    write_anchor_hive_fixture(
      anchor_hive_path = hive_path,
      variable_id = "v_not_requested",
      rows = data.table::data.table(
        person_id = "1",
        T0 = as.Date("2024-01-01"),
        window_name = "fup",
        value = "TRUE",
        date = as.Date("2024-01-10"),
        n = 1L
      )
    )

    result <- get_anchor_result(
      metadata = data.table::data.table(variable_id = "v1"),
      anchor_hive_path = hive_path,
      result_shape = "long"
    )

    testthat::expect_s3_class(result, "data.table")
    testthat::expect_named(
      result,
      c("person_id", "T0", "variable_id", "window_name", "date", "value")
    )
    testthat::expect_equal(result$variable_id, c("v1", "v1"))
    testthat::expect_equal(result$person_id, c("1", "2"))
    testthat::expect_equal(result$value, c("TRUE", "FALSE"))
    testthat::expect_s3_class(result$date, "Date")
    testthat::expect_s3_class(result$T0, "Date")
  }
)

testthat::test_that(
  "get_anchor_result long output errors when the hive lacks long columns",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    write_anchor_hive_fixture(
      anchor_hive_path = hive_path,
      variable_id = "v1",
      rows = data.table::data.table(
        person_id = "1",
        T0 = as.Date("2024-01-01"),
        window_name = "fup",
        value = "TRUE"
      )
    )

    testthat::expect_error(
      get_anchor_result(
        metadata = data.table::data.table(variable_id = "v1"),
        anchor_hive_path = hive_path,
        result_shape = "long"
      ),
      "Anchored results are missing required long-output columns: date."
    )
  }
)

testthat::test_that(
  "get_anchor_result refuses ambiguous wide output but keeps every row in
  long output",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    # Two events for the same person_id/T0/window_name, as an `ALL`
    # selector would produce.
    write_anchor_hive_fixture(
      anchor_hive_path = hive_path,
      variable_id = "v_all",
      rows = data.table::data.table(
        person_id = c("1", "1"),
        T0 = as.Date("2024-01-01"),
        window_name = "fup",
        value = c("A", "B"),
        date = as.Date(c("2024-01-05", "2024-01-10"))
      )
    )
    metadata <- data.table::data.table(variable_id = "v_all")

    testthat::expect_error(
      get_anchor_result(
        metadata = metadata,
        anchor_hive_path = hive_path,
        result_shape = "wide"
      ),
      "use `result_shape = \"long\"`"
    )

    result <- get_anchor_result(
      metadata = metadata,
      anchor_hive_path = hive_path,
      result_shape = "long"
    )
    testthat::expect_equal(nrow(result), 2L)
    testthat::expect_setequal(result$value, c("A", "B"))
  }
)

testthat::test_that(
  "get_anchor_result imputes missing wide values when impute_missing is
  TRUE",
  {
    hive_path <- tempfile(pattern = "anchor-hive-")
    dir.create(hive_path)
    on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

    write_anchor_hive_fixture(
      anchor_hive_path = hive_path,
      variable_id = "v_tf",
      rows = data.table::data.table(
        person_id = "1",
        T0 = as.Date("2024-01-01"),
        window_name = "fup",
        value = "TRUE",
        date = as.Date("2024-01-10")
      )
    )
    metadata <- data.table::data.table(
      variable_id = "v_tf",
      is_expected_missing = FALSE,
      variable_type = "TF"
    )
    # Person "2" has no anchored row, so their value cell starts as NA.
    population <- data.table::data.table(
      person_id = c("1", "2"),
      T0 = as.Date(c("2024-01-01", "2024-01-15"))
    )

    not_imputed <- get_anchor_result(
      metadata = metadata,
      anchor_hive_path = hive_path,
      population = population,
      impute_missing = FALSE
    )
    data.table::setorder(not_imputed, person_id)
    testthat::expect_identical(
      not_imputed$value_v_tf, c("TRUE", NA_character_)
    )

    imputed <- get_anchor_result(
      metadata = metadata,
      anchor_hive_path = hive_path,
      population = population,
      impute_missing = TRUE
    )
    data.table::setorder(imputed, person_id)
    testthat::expect_identical(imputed$value_v_tf, c(TRUE, FALSE))
    testthat::expect_equal(nrow(imputed), nrow(population))
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
