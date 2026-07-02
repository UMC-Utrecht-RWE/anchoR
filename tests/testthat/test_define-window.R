# ---------------------------------------------------------------------------
# cross_join_population_metadata(): one row per person x variable
# ---------------------------------------------------------------------------

testthat::test_that("cross_join_population_metadata works as expected", {
  res <- cross_join_population_metadata(
    minimal_population(),
    minimal_metadata()
  )

  testthat::expect_equal(
    nrow(res), nrow(minimal_population()) * nrow(minimal_metadata())
  )
  testthat::expect_equal(
    names(res),
    c(
      "person_id", "T0", "variable_id", "concept_id", "constructor",
      "selector", "start_look_back", "end_look_back"
    )
  )
})

# ---------------------------------------------------------------------------
# generic_window_check(): the shared validation used by built-in constructors
# ---------------------------------------------------------------------------

testthat::test_that("generic_window_check works correctly", {
  testthat::expect_error(
    generic_window_check(data.frame(constructor = "T0")),
    "window_dt must be a data.table"
  )

  testthat::expect_error(
    generic_window_check(data.table::data.table(anchor_start_col = "T0")),
    "window_dt is missing mandatory metadata columns"
  )

  testthat::expect_no_error(
    generic_window_check(data.table::data.table(constructor = "T0"))
  )
})

# ---------------------------------------------------------------------------
# make_constructor(): the public factory used to build a window constructor.
# These tests double as usage documentation for anyone adding a new window
# type without editing anchoR itself.
# ---------------------------------------------------------------------------

testthat::test_that("make_constructor fails fast on a malformed factory call", {
  testthat::expect_error(
    make_constructor(transform_fn = "not_a_function"),
    "transform_fn must be a function"
  )

  testthat::expect_error(
    make_constructor(transform_fn = function(x) x, required_cols = 123),
    "required_cols must be a character vector"
  )

  testthat::expect_error(
    make_constructor(
      transform_fn = function(x) x,
      check_fn = "not_a_function"
    ),
    "check_fn must be NULL or a function"
  )
})

testthat::test_that("constructor enforces required_cols", {
  offset_window <- make_constructor(
    transform_fn = function(window_dt) {
      window_dt[, window_start := anchor_date - offset_days]
      window_dt[, window_end := anchor_date + offset_days]
      window_dt[]
    },
    required_cols = c("anchor_date", "offset_days")
  )

  testthat::expect_error(
    offset_window(data.table::data.table(anchor_date = as.Date("2024-01-10"))),
    "missing required column\\(s\\): offset_days"
  )
})

testthat::test_that("constructor with make_constructor computes windows", {
  # This is the same recipe a package user follows to add a window type
  # anchoR doesn't ship: wrap a transform_fn, declare what it needs, get a
  # constructor back. No changes to anchoR's source are required.
  offset_window <- make_constructor(
    transform_fn = function(window_dt) {
      window_dt[, window_start := anchor_date - offset_days]
      window_dt[, window_end := anchor_date + offset_days]
      window_dt[]
    },
    required_cols = c("anchor_date", "offset_days")
  )

  out <- offset_window(
    data.table::data.table(
      anchor_date = as.Date("2024-01-10"),
      offset_days = 5
    )
  )

  testthat::expect_equal(out$window_start, as.Date("2024-01-05"))
  testthat::expect_equal(out$window_end, as.Date("2024-01-15"))
})

# ---------------------------------------------------------------------------
# generic_window(): the built-in constructor, tested directly on a data.table
# so its date arithmetic can be checked without going through define_window().
# ---------------------------------------------------------------------------

testthat::test_that("generic_window computes start and end dates", {
  window_dt <- data.table::data.table(
    constructor = "GENERIC",
    anchor_start_col = "T0",
    anchor_end_col = "T0",
    start_offset = c(-30L, 0L),
    end_offset = c(0L, 30L),
    T0 = as.Date(c("2024-02-01", "2024-02-15"))
  )

  out <- generic_window(window_dt)

  testthat::expect_equal(
    out$window_start,
    as.Date(c("2024-01-02", "2024-02-15"))
  )
  testthat::expect_equal(
    out$window_end,
    as.Date(c("2024-02-01", "2024-03-16"))
  )
})

# ---------------------------------------------------------------------------
# resolve_window_constructor(): looks in exactly two places -- the anchoR
# namespace for built-ins, `constructor_env` for anything else. Tested in
# isolation so the lookup rule is clear without define_window()'s plumbing.
# ---------------------------------------------------------------------------

testthat::test_that(
  "resolve_window_constructor finds built-ins regardless of constructor_env",
  {
    fn <- resolve_window_constructor("GENERIC", constructor_env = new.env())
    testthat::expect_identical(fn, generic_window)
  }
)

testthat::test_that(
  "resolve_window_constructor finds a constructor via constructor_env",
  {
    my_window <- function(window_dt) window_dt
    user_env <- list2env(list(my_window = my_window))

    fn <- resolve_window_constructor("MY", constructor_env = user_env)
    testthat::expect_identical(fn, my_window)
  }
)

testthat::test_that("resolve_window_constructor errors when nothing matches", {
  testthat::expect_error(
    resolve_window_constructor("NOPE", constructor_env = new.env()),
    "Window function does not exist: nope_window"
  )
})

# ---------------------------------------------------------------------------
# apply_window_constructors(): the dispatch loop, tested on a bare data.table
# with no population/metadata involved.
# ---------------------------------------------------------------------------

testthat::test_that("apply_window_constructors fills window_start/window_end", {
  window_dt <- data.table::data.table(
    constructor = "GENERIC",
    anchor_start_col = "T0",
    anchor_end_col = "T0",
    start_offset = -30L,
    end_offset = 0L,
    T0 = as.Date("2024-01-01")
  )

  apply_window_constructors(window_dt, constructor_env = globalenv())

  testthat::expect_equal(window_dt$window_start, as.Date("2023-12-02"))
  testthat::expect_equal(window_dt$window_end, as.Date("2024-01-01"))
})

testthat::test_that(
  "apply_window_constructors names the constructor when it errors",
  {
    window_dt <- data.table::data.table(constructor = "BROKEN")
    broken_window <- function(window_dt) stop("boom")
    user_env <- list2env(list(broken_window = broken_window))

    testthat::expect_error(
      apply_window_constructors(window_dt, constructor_env = user_env),
      "Error while applying window constructor 'BROKEN': boom"
    )
  }
)

# ---------------------------------------------------------------------------
# finalize_windows(): row order, window_valid, anchor_row_id -- isolated from
# both the cross join and the constructor dispatch.
# ---------------------------------------------------------------------------

testthat::test_that("finalize_windows restores the pre-cross-join row order", {
  window_dt <- data.table::data.table(
    .window_row_id = c(2L, 1L),
    window_start = as.Date(c("2024-01-01", "2024-01-01")),
    window_end = as.Date(c("2024-01-02", "2024-01-02"))
  )

  out <- finalize_windows(window_dt)

  testthat::expect_equal(out$anchor_row_id, c(1L, 2L))
  testthat::expect_false(".window_row_id" %in% names(out))
})

testthat::test_that(
  "finalize_windows marks window valid when start <= end and neither missing",
  {
    window_dt <- data.table::data.table(
      .window_row_id = 1:3,
      window_start = as.Date(c("2024-01-01", NA, "2024-01-10")),
      window_end = as.Date(c("2024-01-02", "2024-01-02", "2024-01-01"))
    )

    out <- finalize_windows(window_dt)

    testthat::expect_equal(out$window_valid, c(TRUE, FALSE, FALSE))
  }
)

# ---------------------------------------------------------------------------
# define_window(): end-to-end, using the curated minimal_* fixtures.
# ---------------------------------------------------------------------------

testthat::test_that("define_window computes relative windows", {
  windows <- define_window(minimal_population(), minimal_metadata())

  testthat::expect_s3_class(windows, "data.table")
  testthat::expect_equal(nrow(windows), 15L)

  cov_latest_1 <- windows[person_id == "1" & variable_id == "cov_latest"]
  testthat::expect_equal(cov_latest_1$window_start, as.Date("2023-12-02"))
  testthat::expect_equal(cov_latest_1$window_end, as.Date("2024-01-01"))
  testthat::expect_true(cov_latest_1$window_valid)
})

testthat::test_that("define_window uses caller-supplied global anchor column", {
  population <- data.table::copy(minimal_population())
  data.table::setnames(population, "T0", "anchor_date")

  windows <- define_window(
    population = population,
    metadata = minimal_metadata(),
    anchor_col = "anchor_date"
  )

  cov_latest_1 <- windows[person_id == "1" & variable_id == "cov_latest"]
  testthat::expect_equal(cov_latest_1$window_start, as.Date("2023-12-02"))
  testthat::expect_equal(cov_latest_1$window_end, as.Date("2024-01-01"))
})

testthat::test_that("define_window supports per-variable anchor columns", {
  # A single metadata table can mix anchors: one variable's window comes from
  # T0, another's from a completely different pair of date columns (e.g. a
  # pregnancy episode). generic_window() loops by anchor column name so this
  # works without special-casing any particular anchor.
  population <- data.table::data.table(
    person_id = "1",
    T0 = as.Date("2024-01-01"),
    episode_start = as.Date("2023-06-01"),
    episode_end = as.Date("2023-09-01")
  )

  metadata <- data.table::data.table(
    variable_id = "episode_var",
    concept_id = "EPISODE_X",
    constructor = "GENERIC",
    selector = "LATEST",
    start_offset = 0,
    end_offset = 0,
    anchor_date_start = "episode_start",
    anchor_date_end = "episode_end"
  )

  windows <- define_window(population, metadata)

  testthat::expect_equal(windows$window_start, population$episode_start)
  testthat::expect_equal(windows$window_end, population$episode_end)
})

testthat::test_that(
  "define_window errors when metadata references an unknown constructor",
  {
    metadata <- minimal_metadata()[1]
    metadata[, constructor := "NOPE"]

    testthat::expect_error(
      define_window(minimal_population(), metadata),
      "Window function does not exist: nope_window"
    )
  }
)

testthat::test_that(
  "define_window resolves a user-defined constructor through constructor_env",
  {
    # A package user extends anchoR by building a constructor with
    # make_constructor() and naming it "<constructor>_window". They don't edit
    # anchoR or its namespace -- passing an environment containing the
    # function is enough.
    index_window <- make_constructor(
      transform_fn = function(window_dt) {
        window_dt[, window_start := index_date - 30]
        window_dt[, window_end := index_date + 30]
        window_dt[]
      },
      required_cols = "index_date"
    )
    user_env <- list2env(list(index_window = index_window))

    population <- data.table::data.table(
      person_id = c("1", "2"),
      T0 = as.Date(c("2024-01-01", "2024-01-15")),
      index_date = as.Date(c("2024-02-01", "2024-02-15"))
    )
    metadata <- data.table::data.table(
      variable_id = "custom_var",
      concept_id = "CUSTOM",
      constructor = "INDEX",
      selector = "LATEST",
      start_offset = 0,
      end_offset = 0
    )

    windows <- define_window(population, metadata, constructor_env = user_env)

    testthat::expect_equal(windows$window_start, population$index_date - 30)
    testthat::expect_equal(windows$window_end, population$index_date + 30)
    testthat::expect_true(all(windows$window_valid))
  }
)

testthat::test_that("a custom constructor enforces its own required columns", {
  index_window <- make_constructor(
    transform_fn = function(window_dt) window_dt,
    required_cols = "index_date"
  )
  user_env <- list2env(list(index_window = index_window))

  metadata <- data.table::data.table(
    variable_id = "custom_var",
    concept_id = "CUSTOM",
    constructor = "INDEX",
    selector = "LATEST",
    start_offset = 0,
    end_offset = 0
  )

  testthat::expect_error(
    define_window(
      minimal_population(), metadata,
      constructor_env = user_env
    ),
    "missing required column\\(s\\): index_date"
  )
})
