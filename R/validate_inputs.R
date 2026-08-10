population_anchor_columns <- function(population_dt, metadata_dt) {
  # Anchor references are stored in metadata, so fail here before window
  # calculation if the population does not contain those columns.
  anchor_cols <- unique(
    c(metadata_dt$anchor_start_col, metadata_dt$anchor_end_col)
  )
  missing_anchor_cols <- setdiff(anchor_cols, names(population_dt))

  if (length(missing_anchor_cols) > 0L) {
    stop(
      sprintf(
        "`population` is missing anchor columns referenced by `metadata`: %s.",
        paste(missing_anchor_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(population_dt)
}

#' Trim population to the columns needed for window definition.
#'
#' Anchor-only callers (like `anchor()`) never need population covariates
#' beyond `person_id` and the anchor columns metadata references, so
#' dropping them here keeps the population x metadata cross join from
#' replicating unused columns.
#'
#' @param population_dt A data.table containing the study population.
#' @param metadata_dt A data.table containing the metadata for the variables.
#' @return A data.table subset of population_dt with only `person_id` and the
#'   referenced anchor columns.
#' @keywords internal
#' @noRd
population_columns_for_window <- function(population_dt, metadata_dt) {
  needed_cols <- unique(c(
    "person_id",
    metadata_dt$anchor_start_col,
    metadata_dt$anchor_end_col
  ))
  population_dt[, needed_cols, with = FALSE]
}

metadata_supported_selectors <- function(
  metadata_dt,
  selector_env = globalenv()
) {
  # Selector validation happens before any SQL runs so unsupported study
  # variables fail with a metadata error instead of a late database error.
  # A selector missing from the bundled list isn't necessarily unsupported
  # it may be a custom one built with `make_selector()` and assigned in
  # `selector_env` (mirroring how `resolve_window_constructor()` treats
  # `constructor_env` for window constructors), so those are checked
  # individually via `selector_is_resolvable()` before being flagged.
  supported_selectors <- available_selectors()
  unsupported_selectors <- setdiff(
    unique(metadata_dt$selector),
    supported_selectors
  )
  unsupported_selectors <- Filter(
    function(selector) !selector_is_resolvable(selector, selector_env),
    unsupported_selectors
  )

  if (length(unsupported_selectors) > 0L) {
    msg <- paste(
      "Unsupported selector(s) in `metadata`:",
      paste(unsupported_selectors, collapse = ", "),
      sprintf(
        "Available selectors in package `anchoR`: %s.",
        paste(supported_selectors, collapse = ", ")
      ),
      paste(
        "Use `filter_supported_metadata()` if you want to drop unsupported",
        "rows before calling `anchor()`."
      )
    )
    logger::log_error(msg)
    base::stop(msg, call. = FALSE)
  }

  invisible(metadata_dt)
}

normalize_concepts_input <- function(concepts) {
  concepts_type <- concepts_input_type(concepts)

  if (concepts_type == "table") {
    # In-memory tables are normalized immediately because downstream code may
    # mutate and type-cast them by reference.
    return(concepts_to_data_table(concepts))
  }

  if (concepts_type == "duckdb" && !file.exists(concepts)) {
    stop(
      sprintf("Concept database path does not exist: %s.", concepts),
      call. = FALSE
    )
  }

  if (concepts_type == "parquet") {
    # For parquet inputs we only validate the source paths here; the heavy read
    # is deferred so `anchor()` can query parquet directly inside DuckDB.
    normalize_parquet_sources(concepts)
  }

  concepts
}

#' Coerce a data.table column to Date in place, accepting YYYY-mm-dd strings
#'
#' Shared by population anchor-column validation and episode start/end
#' validation, both of which accept either a Date column or a character
#' column in YYYY-mm-dd format.
#'
#' @param dt A data.table.
#' @param col_name The column to coerce.
#' @param label Used in error messages, e.g. `` `population$T0` ``.
#' @return `dt`, invisibly, with `col_name` coerced to Date.
#' @keywords internal
#' @noRd
coerce_date_column <- function(dt, col_name, label) {
  values <- dt[[col_name]]

  if (inherits(values, "Date")) {
    return(invisible(dt))
  }

  stop_invalid_date <- function(message) {
    msg <- sprintf(message, label)
    logger::log_error(msg)
    base::stop(msg, call. = FALSE)
  }

  if (!is.character(values)) {
    stop_invalid_date(
      "%s must be a Date column or character in YYYY-mm-dd format."
    )
  }

  non_missing <- !is.na(values)
  invalid_format <- non_missing & !grepl(
    "^\\d{4}-\\d{2}-\\d{2}$", values
  )
  if (any(invalid_format)) {
    stop_invalid_date("%s must use the date format YYYY-mm-dd.")
  }

  parsed_values <- as.Date(values, format = "%Y-%m-%d")
  invalid_dates <- non_missing & is.na(parsed_values)
  if (any(invalid_dates)) {
    stop_invalid_date("%s contains invalid dates; use the format YYYY-mm-dd.")
  }

  dt[, (col_name) := parsed_values]
  invisible(dt)
}

validate_population_anchor_col <- function(population_dt, anchor_col) {
  coerce_date_column(
    population_dt, anchor_col, sprintf("`population$%s`", anchor_col)
  )
}

validate_variable_ids <- function(variable_ids) {
  variable_ids <- as.character(variable_ids)

  invalid <- is.na(variable_ids) |
    !nzchar(trimws(variable_ids)) |
    grepl("[/\\\\]", variable_ids) |
    grepl("[[:cntrl:]]", variable_ids)

  if (any(invalid)) {
    stop(
      paste(
        "`variable_id` must be non-missing and non-empty, and must not",
        "contain path separators or control characters."
      ),
      call. = FALSE
    )
  }

  invisible(variable_ids)
}

#' Validate an Episodes Table
#'
#' Checks the minimum structure required for the episode window engine
#' (see `R/pregnancy_window.R`) and coerces `start_episode`/`end_episode` to
#' Date.
#'
#' @param episodes A data frame with `person_id`, `start_episode`,
#'   `end_episode` columns.
#' @return A normalized `data.table`.
#' @keywords internal
#' @noRd
validate_episodes_input <- function(episodes) {
  episodes_dt <- as_data_table(episodes, "episodes")

  assert_has_columns(
    episodes_dt,
    required = c("person_id", "start_episode", "end_episode"),
    arg = "episodes"
  )

  coerce_date_column(episodes_dt, "start_episode", "`episodes$start_episode`")
  coerce_date_column(episodes_dt, "end_episode", "`episodes$end_episode`")

  episodes_dt[]
}

#' Validate Anchoring Inputs
#'
#' Standardizes the study-variable metadata shape and checks the minimum
#' structure required by the package.
#'
#' @param population A data frame containing at least `person_id` and the
#'   anchor column used for windowing.
#' @param metadata A data frame in the standard study-variable format.
#' @param concepts A concept table as a data frame, a DuckDB file path whose
#'   `concept_table` contains `person_id`, `concept_id`, and `date`, or parquet
#'   file location(s).
#' @param episodes Optional data frame with `person_id`, `start_episode`,
#'   `end_episode` columns, required when `metadata` uses an episode-based
#'   constructor. See `R/pregnancy_window.R`.
#' @param anchor_col Column to use when metadata does not specify
#'   the anchor column.
#'
#' @return Invisibly returns a list with normalized `population`, `metadata`,
#'   `concepts`, and `episodes`.
#' @export
validate_anchor_inputs <- function(
  population,
  metadata,
  concepts = NULL,
  episodes = NULL,
  anchor_col = "T0"
) {
  # Normalization is centralized here so exported functions can stay short and
  # still rely on a consistent metadata schema.
  population_dt <- as_data_table(population, "population")
  # anchor_col must be a Date column; skipping this check would cause
  # hard-to-trace problems downstream.
  validate_population_anchor_col(population_dt, anchor_col)
  metadata_dt <- as_data_table(metadata, "metadata")

  assert_has_columns(
    metadata_dt,
    required = "variable_id",
    arg = "metadata"
  )

  validate_variable_ids(metadata_dt$variable_id)

  metadata_dt <- normalize_metadata(
    metadata,
    anchor_col = anchor_col
  )

  assert_has_columns(
    population_dt,
    required = "person_id",
    arg = "population"
  )

  assert_has_columns(
    metadata_dt,
    required = c(
      "variable_id",
      "concept_id",
      "window_name",
      "constructor",
      "selector",
      "start_offset",
      "end_offset",
      "anchor_start_col",
      "anchor_end_col",
      "range_min",
      "range_max",
      "anchor_start_offset",
      "anchor_end_offset",
      "before_start_episode_offset",
      "after_start_episode_offset",
      "before_end_episode_offset",
      "after_end_episode_offset"
    ),
    arg = "metadata"
  )
  metadata_dt <- metadata_dt[, c(
    "variable_id",
    "concept_id",
    "window_name",
    "constructor",
    "selector",
    "start_offset",
    "end_offset",
    "anchor_start_col",
    "anchor_end_col",
    "range_min",
    "range_max",
    "anchor_start_offset",
    "anchor_end_offset",
    "before_start_episode_offset",
    "after_start_episode_offset",
    "before_end_episode_offset",
    "after_end_episode_offset"
  )]

  population_anchor_columns(population_dt, metadata_dt)
  metadata_supported_selectors(metadata_dt)

  concepts_obj <- NULL
  if (!is.null(concepts)) {
    # Concepts can be large, so normalize just enough to guarantee the later
    # execution path knows if it is dealing with a table, DuckDB, or parquet.
    concepts_obj <- normalize_concepts_input(concepts)
  }

  episodes_obj <- NULL
  if (!is.null(episodes)) {
    episodes_obj <- validate_episodes_input(episodes)
  }

  invisible(
    list(
      population = population_dt,
      metadata = metadata_dt,
      concepts = concepts_obj,
      episodes = episodes_obj
    )
  )
}
