#' Make a Selector SQL Template
#'
#' Wraps a SQL `SELECT` statement as a selector definable outside the anchoR
#' package, this is the SQL-template equivalent of `make_constructor()`.
#'
#' Unlike a constructor (a plain R function over a `data.table`), a selector
#' runs as SQL directly inside the DuckDB connection `anchor()` opens, where
#' `population_windows` and `concepts` are already loaded.
#'
#' @param selector_query A single SQL `SELECT` statement (a length-1
#'   character string).
#' @return An object of class `anchor_selector` wrapping the SQL text.
#' @export
make_selector <- function(selector_query) {
  if (!is.character(selector_query) || length(selector_query) != 1L) {
    stop_log("selector_query must be a single SQL string")
  }

  if (!nzchar(trimws(selector_query))) {
    stop_log("selector_query must not be empty")
  }

  structure(list(sql = selector_query), class = "anchor_selector")
}

#' Name a Custom Selector Would Be Looked Up Under
#'
#' @param selector_name Value of the metadata `selector` column.
#' @return The `<selector>_selector` object name, lower-cased.
#' @keywords internal
selector_object_name <- function(selector_name) {
  paste0(tolower(normalize_selector_name(selector_name)), "_selector")
}

#' Check Whether a Selector Resolves to Something Runnable
#'
#' Used by `metadata_supported_selectors()` to accept selector names that
#' aren't bundled with the package but are defined by the caller. Existence
#' only, deliberately cheap: it doesn't fetch or validate the SQL text.
#'
#' @param selector_name Value of the metadata `selector` column.
#' @param selector_env Environment searched for user-defined selectors.
#' @return `TRUE` if a built-in template or a `selector_env` object of class
#'   `anchor_selector` and the expected name exists, `FALSE` otherwise.
#' @keywords internal
selector_is_resolvable <- function(selector_name, selector_env) {
  normalized <- normalize_selector_name(selector_name)

  if (selector_sql_exists(normalized)) {
    return(TRUE)
  }

  obj_name <- selector_object_name(normalized)
  exists(obj_name, envir = selector_env, inherits = TRUE) &&
    inherits(
      get(obj_name, envir = selector_env, inherits = TRUE),
      "anchor_selector"
    )
}

#' Resolve a Selector's SQL by Name
#'
#' Looks up the SQL text for a given `selector` value. Built-in selectors
#' (e.g. `RANGE_COUNT`) are always resolved from the bundled `inst/sql`
#' templates. A user-defined selector is found by name
#' (`<selector>_selector`, lower-cased) in `selector_env`, so anyone can add
#' one with `make_selector()` without editing this package, the same
#' pattern `resolve_window_constructor()` uses for window constructors.
#'
#' @param selector_name Value of the metadata `selector` column.
#' @param selector_env Environment searched for user-defined selectors.
#' @return SQL text (a single string) for the selector.
#' @keywords internal
resolve_selector_sql <- function(selector_name, selector_env) {
  normalized <- normalize_selector_name(selector_name)

  if (selector_sql_exists(normalized)) {
    return(read_builtin_selector_sql(normalized))
  }

  obj_name <- selector_object_name(normalized)
  if (exists(obj_name, envir = selector_env, inherits = TRUE)) {
    candidate <- get(obj_name, envir = selector_env, inherits = TRUE)
    if (inherits(candidate, "anchor_selector")) {
      return(candidate$sql)
    }
  }

  stop_log(
    sprintf(
      paste(
        "SQL template does not exist for selector: %s.",
        "Looked in the anchoR package and in `selector_env`; a custom",
        "selector must be named '%s', built with `make_selector()`, and",
        "live in (or be visible from) `selector_env`."
      ),
      normalized,
      obj_name
    )
  )
}
