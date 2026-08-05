testthat::test_that("make_selector wraps SQL text as an anchor_selector object", { # nolint: line_length_linter.
  sel <- make_selector("SELECT * FROM population_windows")

  testthat::expect_s3_class(sel, "anchor_selector")
  testthat::expect_equal(sel$sql, "SELECT * FROM population_windows")
})

testthat::test_that("make_selector errors on non-character input", {
  testthat::expect_error(
    make_selector(123),
    "selector_query must be a single SQL string",
    fixed = TRUE
  )
})

testthat::test_that("make_selector errors on a multi-length character vector", {
  testthat::expect_error(
    make_selector(c("SELECT 1", "SELECT 2")),
    "selector_query must be a single SQL string",
    fixed = TRUE
  )
})

testthat::test_that("make_selector errors on an empty or whitespace-only string", { # nolint: line_length_linter.
  testthat::expect_error(
    make_selector(""),
    "selector_query must not be empty",
    fixed = TRUE
  )
  testthat::expect_error(
    make_selector("   "),
    "selector_query must not be empty",
    fixed = TRUE
  )
})

testthat::test_that("selector_object_name lower-cases and appends _selector", {
  testthat::expect_equal(selector_object_name("LATEST"), "latest_selector")
  testthat::expect_equal(
    selector_object_name("  my_custom  "), "my_custom_selector"
  )
})

testthat::test_that("selector_is_resolvable is TRUE for a built-in selector", {
  testthat::expect_true(selector_is_resolvable("LATEST", environment()))
})

testthat::test_that("selector_is_resolvable is TRUE for a custom anchor_selector object", { # nolint: line_length_linter.
  env <- new.env()
  env$my_custom_selector <- make_selector("SELECT 1")

  testthat::expect_true(selector_is_resolvable("my_custom", env))
})

testthat::test_that("selector_is_resolvable is FALSE when nothing matches", {
  testthat::expect_false(selector_is_resolvable("NOT_A_SELECTOR", new.env()))
})

testthat::test_that(
  "selector_is_resolvable is FALSE when the object exists but isn't an anchor_selector", # nolint: line_length_linter.
  {
    env <- new.env()
    env$my_custom_selector <- "SELECT 1" # plain string, not make_selector()

    testthat::expect_false(selector_is_resolvable("my_custom", env))
  }
)

testthat::test_that("resolve_selector_sql returns built-in SQL text for a built-in selector", { # nolint: line_length_linter.
  sql <- resolve_selector_sql("LATEST", environment())

  testthat::expect_type(sql, "character")
  testthat::expect_true(nzchar(sql))
  testthat::expect_equal(sql, read_builtin_selector_sql("LATEST"))
})

testthat::test_that("resolve_selector_sql returns a custom selector's SQL text", { # nolint: line_length_linter.
  env <- new.env()
  env$my_custom_selector <- make_selector("SELECT 1 AS demo")

  testthat::expect_equal(
    resolve_selector_sql("my_custom", env), "SELECT 1 AS demo"
  )
})

testthat::test_that("resolve_selector_sql finds a custom selector via lexical scoping", { # nolint: line_length_linter.
  # selector_env doesn't have to hold the object directly, exists()/get()
  # use inherits = TRUE, so a parent environment is searched too.
  parent_env <- new.env()
  parent_env$my_custom_selector <- make_selector("SELECT 2 AS demo")
  child_env <- new.env(parent = parent_env)

  testthat::expect_equal(
    resolve_selector_sql("my_custom", child_env), "SELECT 2 AS demo"
  )
})

testthat::test_that("resolve_selector_sql errors when no selector resolves", {
  testthat::expect_error(
    resolve_selector_sql("NOT_A_SELECTOR", new.env()),
    paste(
      "SQL template does not exist for selector: NOT_A_SELECTOR.*",
      "must be named 'not_a_selector_selector'"
    )
  )
})

testthat::test_that(
  "resolve_selector_sql errors when the named object isn't an anchor_selector", # nolint: line_length_linter.
  {
    env <- new.env()
    env$my_custom_selector <- "SELECT 1" # plain string, not make_selector()

    testthat::expect_error(
      resolve_selector_sql("my_custom", env),
      "SQL template does not exist for selector: MY_CUSTOM"
    )
  }
)
