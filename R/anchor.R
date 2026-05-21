#' Resolve and create the anchor parquet hive root if needed.
#' It checks if a path is usable before any partition work:
#' - it rejects NULL
#' - it creates the hive directory if it does not exist
#' - it returns a normalized absolute path
#' @param save_parquet_hive_path Character scalar path to the hive root.
#'
#' @return A normalized absolute path.
#' @keywords internal
#' @noRd
ensure_anchor_hive_path <- function(save_parquet_hive_path) {
  logger::log_trace("Validating `save_parquet_hive_path` input.")
  if (is.null(save_parquet_hive_path)) {
    msg <- "`save_parquet_hive_path` must be a valid path!"
    logger::log_error(msg)
    base::stop(msg, call. = FALSE)
  }

  if (!dir.exists(save_parquet_hive_path)) {
    logger::log_info(
      sprintf(
        "Creating parquet hive directory: %s",
        save_parquet_hive_path
      )
    )
    dir.create(save_parquet_hive_path, recursive = TRUE)
  }

  normalized_path <- normalizePath(
    save_parquet_hive_path,
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
#' @param save_parquet_hive_path Character scalar path to the hive root.
#' @param variable_id Character scalar variable ID.
#'
#' @return A character scalar path to the partition directory.
#' @keywords internal
#' @noRd
anchor_partition_path <- function(save_parquet_hive_path, variable_id) {
  partition_path <- file.path(
    save_parquet_hive_path,
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
#' @param keep_all Logical. If \code{TRUE}, keeps the full
#'   population-by-metadata cross join and fills unmatched rows with missing
#'   values. If \code{FALSE} (default), returns only rows with at least one
#'   matching concept record.
#' @param save_parquet_hive_path Character. Path to an existing (or creatable)
#'   directory where selector query results are written as a partitioned parquet
#'   hive. Must not be \code{NULL}.
#'
#' @return Invisibly, the function writes parquet files to
#'   \code{save_parquet_hive_path}. When no valid windows exist and
#'   \code{keep_all = TRUE}, a \code{data.table} with missing anchored values
#'   is returned directly.
#' @export
anchor <- function(
  population,
  metadata,
  concepts,
  anchor_col = "T0",
  keep_all = FALSE,
  save_parquet_hive_path = NULL
) {
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

  # Define windows for all person-variable combinations.
  # Impossible anchors will be marked and filtered out later.
  window_dt <- define_window(
    population = validated$population,
    metadata = validated$metadata,
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

  save_parquet_hive_path <- ensure_anchor_hive_path(save_parquet_hive_path)
  logger::log_trace(
    sprintf(
      "Writing anchored parquet output under `%s`.", save_parquet_hive_path
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
        nrow(validated$metadata),
        if (keep_all) "with missing anchors" else "an empty sparse result"
      )
    )
    if (keep_all) {
      # Some downstream code expects one row per person-variable pair even when
      # nothing can be anchored, so keep the design matrix and mark it missing.
      window_dt[
        , `:=`(value = NA_character_, date = as.Date(NA), n = NA_integer_)
      ]
      return(window_dt[])
    }

    # When sparse output is requested, an empty typed table is clearer than
    # returning the full cross join filled with missing values.
    return(
      window_dt[0][
        , `:=`(value = character(), date = as.Date(character()), n = integer())
      ]
    )
  }

  # Prepare to work in a SQL enviroment.
  logger::log_debug(
    "Opening in-memory DuckDB connection for selector execution."
  )
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:", read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  logger::log_trace("Loading concepts into DuckDB execution context.")
  load_concepts_table(con, validated$concepts)
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
    save_parquet_hive_path = save_parquet_hive_path
  )
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
  keep_all = FALSE,
  save_parquet_hive_path = NULL
) {
  validated <- validate_anchor_inputs(
    population = population,
    metadata = metadata,
    concepts = concepts,
    anchor_col = anchor_col
  )

  save_parquet_hive_path <- ensure_anchor_hive_path(save_parquet_hive_path)
  metadata_dt <- validated$metadata
  variable_ids <- unique(as.character(metadata_dt$variable_id))
  logger::log_debug(
    sprintf(
      paste(
        "`anchor_by_variable()` received %d population row(s),",
        "%d metadata row(s), anchor_col `%s`, keep_all = %s."
      ),
      nrow(validated$population),
      nrow(metadata_dt),
      anchor_col,
      keep_all
    )
  )

  for (current_variable_id in variable_ids) {
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
      tmpdir = dirname(save_parquet_hive_path)
    )
    dir.create(staging_hive_path, recursive = TRUE)
    logger::log_trace(
      sprintf(
        "Created staging parquet hive for variable_id `%s`: %s",
        current_variable_id,
        staging_hive_path
      )
    )

    tryCatch(
      {
        anchor(
          population = validated$population,
          metadata = variable_metadata,
          concepts = validated$concepts,
          anchor_col = anchor_col,
          keep_all = keep_all,
          save_parquet_hive_path = staging_hive_path
        )

        target_partition_path <- anchor_partition_path(
          save_parquet_hive_path,
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
      }
    )
  }
  invisible(variable_ids)
}
