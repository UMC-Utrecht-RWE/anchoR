#' Resolve and create the anchor parquet hive root if needed.
#' It checks if a path is usable before any partition work:
#' - it rejects NULL
#' - it creates the hive directory if it does not exist
#' - it returns a normalized absolute path
#' @param anchor_hive_path Character scalar path to the hive root.
#'
#' @return A normalized absolute path.
#' @keywords internal
#' @noRd
ensure_anchor_hive_path <- function(anchor_hive_path) {
  logger::log_trace("Validating `anchor_hive_path` input.")
  if (is.null(anchor_hive_path)) {
    msg <- "`anchor_hive_path` must be a valid path!"
    logger::log_error(msg)
    base::stop(msg, call. = FALSE)
  }

  if (!dir.exists(anchor_hive_path)) {
    logger::log_info(
      sprintf(
        "Creating parquet hive directory: %s",
        anchor_hive_path
      )
    )
    dir.create(anchor_hive_path, recursive = TRUE)
  }

  normalized_path <- normalizePath(
    anchor_hive_path,
    winslash = "/",
    mustWork = TRUE
  )
  logger::log_debug(
    sprintf("Resolved parquet hive path: %s", normalized_path)
  )

  normalized_path
}

#' Build the Hive-style partition directory name for a given variable.
#'
#' @param anchor_hive_path Character scalar path to the hive root.
#' @param variable_id Character scalar variable ID.
#'
#' @return A character scalar path to the partition directory.
#' @keywords internal
#' @noRd
anchor_partition_path <- function(anchor_hive_path, variable_id) {
  partition_path <- file.path(
    anchor_hive_path,
    paste0("variable_id=", variable_id)
  )
  logger::log_trace(
    sprintf(
      "Computed parquet partition path for variable_id `%s`: %s",
      variable_id,
      partition_path
    )
  )

  partition_path
}

#' Move a staged parquet partition into the target hive, trying a single
#' filesystem move first and falling back to copy-and-delete if that fails.
#'
#' @param source_partition_path Character path for staged partition directory.
#' @param target_partition_path Character path for target partition directory.
#' @param variable_id Character scalar variable ID, used for logging.
#' @return Invisibly returns the target partition path if the move succeeded.
#' @keywords internal
#' @noRd
move_anchor_partition <- function(
  source_partition_path,
  target_partition_path,
  variable_id
) {
  logger::log_debug(
    sprintf(
      paste(
        "Moving staged parquet partition for variable_id `%s`",
        "from `%s` to `%s`."
      ),
      variable_id,
      source_partition_path,
      target_partition_path
    )
  )
  if (file.rename(source_partition_path, target_partition_path)) {
    logger::log_trace(
      sprintf(
        "Renamed staged parquet  in a single filesystem move for `%s`.",
        variable_id
      )
    )
    return(invisible(target_partition_path))
  }

  logger::log_trace(
    sprintf(
      "Falling back to copy-and-delete while moving parquet for `%s`.",
      variable_id
    )
  )
  dir.create(target_partition_path, recursive = TRUE, showWarnings = FALSE)
  staged_files <- list.files(
    source_partition_path,
    full.names = TRUE,
    all.files = TRUE,
    no.. = TRUE
  )
  copied <- file.copy(
    from = staged_files,
    to = target_partition_path,
    recursive = TRUE,
    copy.mode = TRUE,
    copy.date = TRUE
  )

  if (!all(copied)) {
    msg <- sprintf(
      paste(
        "Could not move staged parquet files for variable_id `%s`",
        "into `%s`."
      ),
      variable_id,
      target_partition_path
    )
    logger::log_error(msg)
    base::stop(msg, call. = FALSE)
  }

  unlink(source_partition_path, recursive = TRUE, force = TRUE)
  logger::log_trace(
    sprintf(
      "Copied %d staged parquet file(s) for variable_id `%s`.",
      length(staged_files),
      variable_id
    )
  )
  invisible(target_partition_path)
}

#' Core Windowing + Selector Execution Given an Open Connection
#'
#' Shared by [anchor()] and [anchor_by_variable()] so that opening a DuckDB
#' connection and loading `concepts` happens once per caller instead of once
#' per `variable_id`. `anchor_by_variable()` used to call `anchor()` itself
#' once per variable, which meant re-validating/re-copying `population`,
#' re-opening DuckDB, and re-scanning (or re-copying) the entire `concepts`
#' source once per variable; for metadata files with many standard-window
#' variables that repeated concepts scan dominated runtime. This function
#' factors out the part that is genuinely per-variable (window definition,
#' writing `population_windows`, running the selector queries) so callers can
#' share the expensive setup across many calls.
#'
#' @param con An open DBI connection with `concepts` already loaded.
#' @param population_dt Validated population `data.table` (not yet trimmed to
#'   window columns).
#' @param metadata_dt Validated metadata `data.table` for the variable(s) to
#'   process in this call.
#' @param anchor_col Column in `population_dt` used as the index date when
#'   metadata does not specify an anchor column.
#' @param anchor_hive_path Existing, normalized path to write selector output.
#' @return Invisibly `NULL` on success, or (only when no window was valid) the
#'   same empty typed table `anchor()` has always returned in that case.
#' @keywords internal
#' @noRd
anchor_impl <- function(
  con,
  population_dt,
  metadata_dt,
  anchor_col,
  anchor_hive_path
) {
  # Define windows for all person-variable combinations.
  # Impossible anchors will be marked and filtered out later.
  # Only person_id and the anchor columns metadata references are needed past
  # this point, so trim other population covariates before the cross join
  # multiplies them across every metadata row.
  window_population <- population_columns_for_window(
    population_dt, metadata_dt
  )
  window_dt <- define_window(
    population = window_population,
    metadata = metadata_dt,
    anchor_col = anchor_col
  )
  logger::log_debug(
    sprintf(
      paste(
        "`define_window()` produced %d row(s); %d valid and %d invalid window."
      ),
      nrow(window_dt),
      sum(window_dt$window_valid),
      sum(!window_dt$window_valid)
    )
  )

  # Remove impossible anchors.
  valid_windows <- window_dt[window_valid == TRUE]
  if (nrow(valid_windows) == 0L) {
    logger::log_info(
      sprintf(
        paste(
          "No valid windows remained after filtering for %d metadata row(s).",
          "Returning %s output."
        ),
        nrow(metadata_dt),
        "empty"
      )
    )

    # When sparse output is requested, an empty typed table is clearer than
    # returning the full cross join filled with missing values.
    return(
      window_dt[0][
        , `:=`(value = character(), date = as.Date(character()), n = integer())
      ]
    )
  }

  # Only valid windows are written because invalid ones can never match and
  # would only make the SQL side do unnecessary work.
  logger::log_debug(
    sprintf(
      "Writing %d valid population window row(s) to DuckDB.",
      nrow(valid_windows)
    )
  )
  write_population_windows(
    con,
    valid_windows,
    anchor_col = anchor_col
  )

  selector_names <- unique(valid_windows$selector)
  run_selector_queries(
    con = con,
    selectors = selector_names,
    anchor_hive_path = anchor_hive_path
  )

  invisible(NULL)
}

#' Anchor Study Variables to an Index Date
#'
#' Applies metadata-driven windowing and selector rules to a concept table,
#' producing one anchored value and event date per person-variable combination.
#'
#' @param population A data frame containing the study population. Must include
#'   a \code{person_id} column and the anchor date column specified by
#'   \code{anchor_col}.
#' @param metadata A data frame describing the variables to anchor. Must contain
#'   the columns required by \code{validate_anchor_inputs()}.
#' @param concepts A concept table as a data frame, a DuckDB file path whose
#'   \code{concept_table} contains \code{person_id}, \code{concept_id}, and
#'   \code{date}, or parquet file location(s).
#' @param anchor_col Character. Name of the column in \code{population} to use
#'   as the index date when metadata does not specify an anchor column.
#'   Defaults to \code{"T0"}.
#' @param anchor_hive_path Character. Path to an existing (or creatable)
#'   directory where selector query results are written as a partitioned parquet
#'   hive. Must not be \code{NULL}.
#'
#' @return Invisibly, function writes parquet files to anchor_hive_path
#' @export
anchor <- function(
  population,
  metadata,
  concepts,
  anchor_col = "T0",
  anchor_hive_path = NULL
) {
  logger::log_debug("Starting anchor().")
  # Normalize inputs at the beginning so the rest
  # of the workflow has stable input.
  validated <- validate_anchor_inputs(
    population = population,
    metadata = metadata,
    concepts = concepts,
    anchor_col = anchor_col
  )
  concepts_type <- if (is.null(validated$concepts)) {
    "NULL"
  } else {
    concepts_input_type(validated$concepts)
  }
  logger::log_debug(
    sprintf(
      paste(
        "Validated inputs: %d population row(s), %d metadata row(s), ",
        "%d unique variable_id(s), concept source type `%s`."
      ),
      nrow(validated$population),
      nrow(validated$metadata),
      length(unique(validated$metadata$variable_id)),
      concepts_type
    )
  )

  anchor_hive_path <- ensure_anchor_hive_path(anchor_hive_path)
  logger::log_trace(
    sprintf(
      "Writing anchored parquet output under `%s`.", anchor_hive_path
    )
  )

  # Prepare to work in a SQL enviroment.
  logger::log_debug(
    "Opening in-memory DuckDB connection for selector execution."
  )
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:", read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  logger::log_trace("Loading concepts into DuckDB execution context.")
  load_concepts_table(con, validated$concepts)

  result <- anchor_impl(
    con = con,
    population_dt = validated$population,
    metadata_dt = validated$metadata,
    anchor_col = anchor_col,
    anchor_hive_path = anchor_hive_path
  )

  logger::log_debug("Finished anchor().")
  result
}

#' Anchor study variables one variable_id at a the time
#'
#' Runs [anchor()] separately for each unique \code{variable_id} in
#' \code{metadata}. Each variable is first written to a temporary parquet hive
#' and then swapped into the target hive partition, so rerunning one variable
#' replaces only that variable's prior results.
#'
#' @inheritParams anchor
#'
#' @return Invisibly returns the processed \code{variable_id} values.
#' @export
anchor_by_variable <- function(
  population,
  metadata,
  concepts,
  anchor_col = "T0",
  anchor_hive_path = NULL
) {
  validated <- validate_anchor_inputs(
    population = population,
    metadata = metadata,
    concepts = concepts,
    anchor_col = anchor_col
  )

  anchor_hive_path <- ensure_anchor_hive_path(anchor_hive_path)
  metadata_dt <- validated$metadata
  variable_ids <- unique(as.character(metadata_dt$variable_id))
  concepts_type <- if (is.null(validated$concepts)) {
    "NULL"
  } else {
    concepts_input_type(validated$concepts)
  }
  logger::log_debug(
    sprintf(
      paste(
        "`anchor_by_variable()` received %d population row(s),",
        "%d metadata row(s), anchor_col `%s`, concept source type `%s`."
      ),
      nrow(validated$population),
      nrow(metadata_dt),
      anchor_col,
      concepts_type
    )
  )

  # A single connection and a single load of `concepts` are shared across
  # every variable_id below instead of one per variable (see `anchor_impl()`)
  # -- for parquet or in-memory concepts, that used to mean re-scanning or
  # re-copying the entire concept table once per variable.
  logger::log_debug(
    "Opening in-memory DuckDB connection for selector execution."
  )
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:", read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  logger::log_trace("Loading concepts into DuckDB execution context.")
  load_concepts_table(con, validated$concepts)

  for (current_variable_id in variable_ids) {
    variable_start_time <- Sys.time()
    variable_metadata <- metadata_dt[variable_id == current_variable_id]
    logger::log_info(
      sprintf("Anchoring variable_id: %s", current_variable_id)
    )
    logger::log_debug(
      sprintf(
        paste(
          "Current variable_id `%s` has %d metadata row(s) and selector(s): %s"
        ),
        current_variable_id,
        nrow(variable_metadata),
        paste(unique(variable_metadata$selector), collapse = ", ")
      )
    )

    staging_hive_path <- tempfile(
      pattern = "anchor-stage-",
      tmpdir = dirname(anchor_hive_path)
    )
    dir.create(staging_hive_path, recursive = TRUE)
    staging_hive_path <- ensure_anchor_hive_path(staging_hive_path)
    logger::log_trace(
      sprintf(
        "Created staging parquet hive for variable_id `%s`: %s",
        current_variable_id,
        staging_hive_path
      )
    )

    tryCatch(
      {
        anchor_impl(
          con = con,
          population_dt = validated$population,
          metadata_dt = variable_metadata,
          anchor_col = anchor_col,
          anchor_hive_path = staging_hive_path
        )

        target_partition_path <- anchor_partition_path(
          anchor_hive_path,
          current_variable_id
        )
        staging_partition_path <- anchor_partition_path(
          staging_hive_path,
          current_variable_id
        )

        if (dir.exists(target_partition_path)) {
          logger::log_debug(
            sprintf(
              "Deleting existing parquet partition for variable_id `%s`.",
              current_variable_id
            )
          )
          unlink(target_partition_path, recursive = TRUE, force = TRUE)
        }

        if (dir.exists(staging_partition_path)) {
          move_anchor_partition(
            source_partition_path = staging_partition_path,
            target_partition_path = target_partition_path,
            variable_id = current_variable_id
          )
        } else {
          logger::log_debug(
            sprintf(
              paste(
                "No parquet partition was produced for variable_id `%s`.",
                "The target hive was left without that partition."
              ),
              current_variable_id
            )
          )
        }
      },
      finally = {
        logger::log_trace(
          sprintf(
            "Cleaning staging parquet hive for variable_id `%s`: %s",
            current_variable_id,
            staging_hive_path
          )
        )
        unlink(staging_hive_path, recursive = TRUE, force = TRUE)

        variable_duration <- difftime(
          Sys.time(), variable_start_time,
          units = "secs"
        )
        logger::log_info(
          sprintf(
            "Finished anchoring variable_id `%s` in %.2f secs.",
            current_variable_id,
            as.numeric(variable_duration)
          )
        )
      }
    )
  }
  logger::log_debug(
    sprintf(
      "Finished anchor_by_variable() for %d variable_id(s).",
      length(variable_ids)
    )
  )
  invisible(variable_ids)
}
