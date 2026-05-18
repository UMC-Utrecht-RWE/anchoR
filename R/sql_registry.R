selector_sql_root <- function(package = "anchoR") {
  sql_root <- system.file("sql", package = package)

  if (!nzchar(sql_root)) {
    local_root <- file.path(getwd(), "inst", "sql")
    if (dir.exists(local_root)) {
      sql_root <- normalizePath(local_root, winslash = "/")
    }
  }

  if (!nzchar(sql_root) || !dir.exists(sql_root)) {
    stop("Could not locate `inst/sql` for the anchoR package.", call. = FALSE)
  }

  sql_root
}

#' List Available Selector SQL Templates
#'
#' @param package Package name used to resolve `inst/sql`.
#'
#' @return A character vector of selector names.
#' @export
available_selectors <- function(package = "anchoR") {
  sql_files <- list.files(
    selector_sql_root(package = package),
    pattern = "\\.sql$",
    full.names = FALSE
  )

  toupper(tools::file_path_sans_ext(sql_files))
}

#' Get the Path to a Selector SQL Template
#'
#' @param selector Selector name such as `"LATEST"` or `"COUNT"`.
#' @param package Package name used to resolve `inst/sql`.
#'
#' @return An absolute path to the SQL template.
#' @export
selector_sql_path <- function(selector, package = "anchoR") {
  selector <- normalize_selector_name(selector[[1L]])
  sql_path <- file.path(
    selector_sql_root(package = package),
    paste0(tolower(selector), ".sql")
  )

  if (!file.exists(sql_path)) {
    stop(
      sprintf("No SQL template found for selector `%s`.", selector),
      call. = FALSE
    )
  }

  sql_path
}

read_selector_sql <- function(selector, package = "anchoR") {
  paste(
    readLines(selector_sql_path(selector, package = package), warn = FALSE),
    collapse = "\n"
  )
}
