testthat::test_that("if target already exists, aliases are ignored", {
  population <- minimal_population()
  original_names <- names(population)

  # T0 already exists, so aliases should be ignored
  rename_first_matching_column(
    population,
    target = "T0"
  )

  expect_identical(names(population), original_names)
})

testthat::test_that("renames matching alias to target", {
  # Create data with an old column name that should be renamed
  dt <- data.table::data.table(
    person_id = c("1", "2"),
    start_look_back = as.integer(c(-30, -30))
  )

  rename_first_matching_column(
    dt,
    target = "start_offset",
    aliases = "start_look_back"
  )

  testthat::expect_true("start_offset" %in% names(dt))
  expect_false("start_look_back" %in% names(dt))
})

testthat::test_that("Returns unchanged when target and aliases don't exist", {
  dt <- data.table::data.table(
    person_id = c("1", "2"),
    value = c(1, 2)
  )
  original_names <- names(dt)

  rename_first_matching_column(
    dt,
    target = "nonexistent_target",
    aliases = c("alias1", "alias2")
  )

  expect_identical(names(dt), original_names)
})

testthat::test_that("handles multiple aliases, renames first match", {
  # Create data with one of several possible old column names
  dt <- data.table::data.table(
    person_id = c("1", "2"),
    end_look_back = as.integer(c(0, 0))
  )

  # Provide multiple aliases; should rename first matching one
  rename_first_matching_column(
    dt,
    target = "end_offset",
    aliases = c("end_date", "end_look_back", "end_value")
  )

  testthat::expect_true("end_offset" %in% names(dt))
  expect_false("end_look_back" %in% names(dt))
})

testthat::test_that("empty aliases vector leaves data unchanged", {
  dt <- data.table::data.table(
    person_id = c("1", "2"),
    old_column = c(1, 2)
  )
  original_names <- names(dt)

  rename_first_matching_column(
    dt,
    target = "new_column",
    aliases = character()
  )

  expect_identical(names(dt), original_names)
})

testthat::test_that("returns invisibly", {
  dt <- data.table::data.table(person_id = c("1", "2"))

  result <- rename_first_matching_column(
    dt,
    target = "test",
    aliases = "nonexistent"
  )

  # Invisible return means the object is returned but not printed automatically
  # The result should be a data.frame with the same data
  expect_false(is.null(result))
  testthat::expect_true(is.data.frame(result))
  expect_identical(names(result), c("person_id"))
})

testthat::test_that("respects order of aliases when multiple exist", {
  # Create data with two possible old column names, but NOT the target
  dt <- data.table::data.table(
    person_id = c("1", "2"),
    date_extraction_func = c("LATEST", "LATEST"),
    old_selector = c("OLD", "OLD")
  )

  # Provide aliases in specific order; should match and rename first one
  rename_first_matching_column(
    dt,
    target = "selector",
    aliases = c("date_extraction_func", "old_selector")
  )

  # it should be renamed to selector since it's first in aliases
  testthat::expect_true("selector" %in% names(dt))
  expect_false("date_extraction_func" %in% names(dt))
  # Second alias shouldn't be touched
  testthat::expect_true("old_selector" %in% names(dt))
})

testthat::test_that("normalize_selector_name: converts to uppercase", {
  testthat::expect_equal(normalize_selector_name("latest"), "LATEST")
  testthat::expect_equal(normalize_selector_name("count"), "COUNT")
  testthat::expect_equal(
    normalize_selector_name("RANGE_COUNT"), "RANGE_COUNT"
  )
  testthat::expect_equal(normalize_selector_name(123), "123")
  testthat::expect_equal(normalize_selector_name(TRUE), "TRUE")
  testthat::expect_equal(normalize_selector_name(FALSE), "FALSE")
})

testthat::test_that("normalize_selector_name: trims whitespace", {
  testthat::expect_equal(normalize_selector_name("  latest  "), "LATEST")
  testthat::expect_equal(normalize_selector_name("\tCOUNT\n"), "COUNT")
  testthat::expect_equal(
    normalize_selector_name(" RANGE_COUNT "), "RANGE_COUNT"
  )
})

testthat::test_that("normalize_selector_name: handles vector input", {
  result <- normalize_selector_name(c("latest", "count", "  range  "))
  testthat::expect_equal(result, c("LATEST", "COUNT", "RANGE"))
})

testthat::test_that("normalize_selector_name: handles empty and NA values", {
  testthat::expect_equal(normalize_selector_name(""), "")
  testthat::expect_true(is.na(normalize_selector_name(NA)))
})

testthat::test_that("replaces T0 and empty values with anchor_col", {
  result <- normalize_anchor_reference(
    c("T0", "t0", "  T0  ", "", NA, "OTHER_COL"),
    anchor_col = "visit_date"
  )
  testthat::expect_equal(
    result,
    c(
      "visit_date", "visit_date", "visit_date",
      "visit_date", "visit_date", "OTHER_COL"
    )
  )
})

testthat::test_that("preserves non-T0 values unchanged", {
  result <- normalize_anchor_reference(
    c("enrollment_date", "  baseline_date  ", "event_date"),
    anchor_col = "T0"
  )
  testthat::expect_equal(
    result,
    c("enrollment_date", "baseline_date", "event_date")
  )
})

testthat::test_that("errors when required columns are missing", {
  dt <- data.table::data.table(person_id = c("1", "2"))

  testthat::expect_error(
    assert_has_columns(
      dt,
      required = c("person_id", "date"), arg = "population"
    ),
    regexp = "`population` is missing required columns: date\\."
  )
})

testthat::test_that("adds column when missing", {
  dt <- data.table::data.table(person_id = c("1", "2"))

  add_column_if_missing(dt, "new_col", 5)

  testthat::expect_true("new_col" %in% names(dt))
  testthat::expect_equal(dt$new_col, rep(5, nrow(dt)))
})

testthat::test_that("does not overwrite existing column", {
  dt <- data.table::data.table(a = c(1L, 2L))
  original <- data.table::copy(dt)

  add_column_if_missing(dt, "a", 99L)

  testthat::expect_identical(dt, original)
})

testthat::test_that("returns invisibly and returns the data.table", {
  dt <- data.table::data.table(x = 1:3)

  result <- add_column_if_missing(dt, "y", 0)

  testthat::expect_true(
    inherits(result, "data.table") || inherits(result, "data.frame")
  )
  testthat::expect_identical(result, dt)
})

testthat::test_that("as_data_table errors when given a non-data-frame", {
  testthat::expect_error(
    as_data_table(list(a = 1), "population"),
    "`population` must be a data frame.",
    fixed = TRUE
  )
  testthat::expect_error(
    as_data_table(1:3, "metadata"),
    "`metadata` must be a data frame.",
    fixed = TRUE
  )
})

testthat::test_that("as_data_table copies rather than aliasing the input", {
  original <- data.table::data.table(x = 1L)
  copied <- as_data_table(original, "population")
  copied[, x := 99L]

  testthat::expect_equal(original$x, 1L)
})

testthat::test_that("looks_like_glob detects glob metacharacters", {
  testthat::expect_true(looks_like_glob("concepts/*.parquet"))
  testthat::expect_true(looks_like_glob("concepts/file?.parquet"))
  testthat::expect_true(looks_like_glob("concepts/[abc].parquet"))
  testthat::expect_false(looks_like_glob("concepts/file.parquet"))
  testthat::expect_false(looks_like_glob("/plain/path"))
})

testthat::test_that("concepts_input_type identifies a data frame as a table", {
  testthat::expect_equal(
    concepts_input_type(data.table::data.table(x = 1)), "table"
  )
})

testthat::test_that("concepts_input_type identifies a .duckdb path", {
  testthat::expect_equal(concepts_input_type("concepts.duckdb"), "duckdb")
  testthat::expect_equal(
    concepts_input_type("path/to/CONCEPTS.DUCKDB"), "duckdb"
  )
})

testthat::test_that("concepts_input_type falls back to parquet for other character input", { # nolint: line_length_linter.
  testthat::expect_equal(concepts_input_type("concepts.parquet"), "parquet")
  testthat::expect_equal(concepts_input_type("concepts/"), "parquet")
  testthat::expect_equal(
    concepts_input_type(c("a.parquet", "b.parquet")), "parquet"
  )
})

testthat::test_that("concepts_input_type errors on unsupported input", {
  testthat::expect_error(
    concepts_input_type(123),
    "`concepts` must be a data frame, a DuckDB file path, or parquet file location\\(s\\)\\." # nolint: line_length_linter.
  )
  testthat::expect_error(concepts_input_type(character()))
})

testthat::test_that("normalize_parquet_sources errors when concepts isn't a parquet source", { # nolint: line_length_linter.
  testthat::expect_error(
    normalize_parquet_sources("concepts.duckdb"),
    "`concepts` is not a parquet source.",
    fixed = TRUE
  )
})

testthat::test_that("normalize_parquet_sources expands a directory of parquet files", { # nolint: line_length_linter.
  tmp <- withr::local_tempdir()
  file.create(file.path(tmp, "a.parquet"))
  file.create(file.path(tmp, "b.parquet"))
  file.create(file.path(tmp, "not_parquet.txt"))

  result <- normalize_parquet_sources(tmp)

  testthat::expect_setequal(
    basename(result), c("a.parquet", "b.parquet")
  )
})

testthat::test_that("normalize_parquet_sources errors on a directory with no parquet files", { # nolint: line_length_linter.
  tmp <- withr::local_tempdir()

  testthat::expect_error(
    normalize_parquet_sources(tmp),
    sprintf("No parquet files found under `%s`.", tmp),
    fixed = TRUE
  )
})

testthat::test_that("normalize_parquet_sources passes through an existing file unchanged", { # nolint: line_length_linter.
  tmp <- withr::local_tempfile(fileext = ".parquet")
  file.create(tmp)

  testthat::expect_equal(normalize_parquet_sources(tmp), tmp)
})

testthat::test_that("normalize_parquet_sources passes through a glob pattern unchanged", { # nolint: line_length_linter.
  glob <- file.path(withr::local_tempdir(), "*.parquet")

  testthat::expect_equal(normalize_parquet_sources(glob), glob)
})

testthat::test_that("normalize_parquet_sources errors when a path neither exists nor looks like a glob", { # nolint: line_length_linter.
  missing_path <- file.path(withr::local_tempdir(), "missing.parquet")

  testthat::expect_error(
    normalize_parquet_sources(missing_path),
    sprintf("Concept parquet source does not exist: %s.", missing_path),
    fixed = TRUE
  )
})

testthat::test_that("concepts_to_data_table passes a table straight through as_data_table", { # nolint: line_length_linter.
  result <- concepts_to_data_table(minimal_concepts())

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_equal(result$person_id, minimal_concepts()$person_id)
  testthat::expect_true(inherits(result$date, "Date"))
})

testthat::test_that("concepts_to_data_table adds a value column when missing", {
  no_value <- minimal_concepts()[, .(person_id, concept_id, date)]

  result <- concepts_to_data_table(no_value)

  testthat::expect_true("value" %in% names(result))
  testthat::expect_true(all(is.na(result$value)))
})

testthat::test_that("concepts_to_data_table errors on a missing required column", { # nolint: line_length_linter.
  bad <- minimal_concepts()[, .(person_id, date)]

  testthat::expect_error(
    concepts_to_data_table(bad),
    "`concepts` is missing required columns: concept_id\\."
  )
})

testthat::test_that("concepts_to_data_table reads from a DuckDB file", {
  path <- withr::local_tempfile(fileext = ".duckdb")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path)
  DBI::dbWriteTable(con, "concept_table", minimal_concepts())
  DBI::dbDisconnect(con, shutdown = TRUE)

  result <- concepts_to_data_table(path)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_setequal(
    names(result), c("person_id", "concept_id", "date", "value")
  )
  testthat::expect_equal(nrow(result), nrow(minimal_concepts()))
  testthat::expect_true(inherits(result$date, "Date"))
})

testthat::test_that("concepts_to_data_table errors when the DuckDB file doesn't exist", { # nolint: line_length_linter.
  missing_path <- file.path(withr::local_tempdir(), "missing.duckdb")

  testthat::expect_error(
    concepts_to_data_table(missing_path),
    sprintf("Concept database path does not exist: %s.", missing_path),
    fixed = TRUE
  )
})

testthat::test_that("concepts_to_data_table reads from a parquet file", {
  path <- example_concepts_parquet(minimal_concepts())

  result <- concepts_to_data_table(path)

  testthat::expect_true(data.table::is.data.table(result))
  testthat::expect_setequal(
    names(result), c("person_id", "concept_id", "date", "value")
  )
  testthat::expect_equal(nrow(result), nrow(minimal_concepts()))
  testthat::expect_true(inherits(result$date, "Date"))
})
