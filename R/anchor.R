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

#' Delete existing parquet partitions for the given variable_ids.
#'
#' @param anchor_hive_path Existing path to the hive root.
#' @param variable_ids Character vector about to be (re)written.
#' @return Invisibly `NULL`.
#' @keywords internal
#' @noRd
clear_anchor_partitions <- function(anchor_hive_path, variable_ids) {
  for (variable_id in variable_ids) {
    partition_path <- anchor_partition_path(anchor_hive_path, variable_id)
    if (dir.exists(partition_path)) {
      logger::log_debug(
        sprintf(
          paste(
            "Clearing existing parquet partition for variable_id `%s`",
            "before rewrite."
          ),
          variable_id
        )
      )
      unlink(partition_path, recursive = TRUE, force = TRUE)
    }
  }
  invisible(NULL)
}

#' Order variable_ids by Selector for Chunking
#'
#' Each `variable_id`'s first-listed `selector` value (in case it spans more
#' than one across multiple windows) is used as a stable sort key, so
#' variable_ids sharing a selector end up adjacent. Ties (same selector) keep
#' their original relative order.
#'
#' @param metadata_dt A data.table with `variable_id` and `selector` columns.
#' @return A character vector of unique `variable_id` values, ordered by
#'   selector.
#' @keywords internal
#' @noRd
order_variable_ids_by_selector <- function(metadata_dt) {
  variable_ids <- unique(as.character(metadata_dt$variable_id))
  first_selector_per_variable <- metadata_dt$selector[
    match(variable_ids, metadata_dt$variable_id)
  ]

  variable_ids[order(first_selector_per_variable)]
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

  # Clear each target variable_id's existing partition before writing so a
  # rerun always fully replaces it, rather than trusting
  clear_anchor_partitions(anchor_hive_path, unique(valid_windows$variable_id))

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
  load_concepts_table(
    con,
    validated$concepts,
    concept_ids = unique(as.character(validated$metadata$concept_id))
  )

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

#' Anchor study variables in chunks of variable_ids
#'
#' Runs the anchoring pipeline over \code{metadata} in chunks of
#' \code{chunk_size} \code{variable_id} values at a time (default 20) instead
#' of computing every variable in one pass like [anchor()]. Each chunk is
#' first written to a temporary parquet hive and then swapped into the target
#' hive one \code{variable_id} partition at a time, so rerunning a subset of
#' variables replaces only their partitions and leaves the rest of the hive
#' untouched. Batching several variables per chunk lets one selector query
#' (and its join against \code{concepts}) cover all of them at once, which is
#' far cheaper than one query per variable when \code{concepts} is a large
#' parquet or DuckDB source. Variables are ordered by selector before being
#' sliced into chunks, so each chunk is as selector-homogeneous as
#' \code{chunk_size} allows (see [anchor_by_selector()] for the case where you
#' want every same-selector variable processed in one uncapped query instead
#' of bounding the blast radius with \code{chunk_size}).
#'
#' @inheritParams anchor
#' @param chunk_size Number of \code{variable_id} values to process per pass.
#'   Larger chunks mean fewer (and cheaper) \code{concepts} scans, but a
#'   larger \code{population_windows} working table per pass and a bigger
#'   unit of "all swapped or none swapped" if a chunk errors partway through.
#'   Set to \code{1} to process strictly one variable at a time.
#'
#' @return Invisibly returns the processed \code{variable_id} values.
#' @export
anchor_by_variable <- function(
  population,
  metadata,
  concepts,
  anchor_col = "T0",
  anchor_hive_path = NULL,
  chunk_size = 20L
) {
  if (!is.numeric(chunk_size) || length(chunk_size) != 1L || chunk_size < 1) {
    stop_log("`chunk_size` must be a single positive number.")
  }

  validated <- validate_anchor_inputs(
    population = population,
    metadata = metadata,
    concepts = concepts,
    anchor_col = anchor_col
  )

  anchor_hive_path <- ensure_anchor_hive_path(anchor_hive_path)
  metadata_dt <- validated$metadata
  variable_ids <- unique(as.character(metadata_dt$variable_id))

  # Variable_ids are ordered by selector before slicing into chunks (see
  # `order_variable_ids_by_selector()`) so each chunk is as
  # selector-homogeneous as `chunk_size` allows -- `run_selector_queries()`
  # still runs one join per distinct selector *within* a chunk, so grouping
  # same-selector variables together keeps that count as low as possible
  # instead of leaving it to metadata row order.
  ordered_variable_ids <- order_variable_ids_by_selector(metadata_dt)

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

  # Variables are processed in chunks rather than strictly one at a time so a
  # single selector query (and its concepts join) can cover several variables
  # at once -- DuckDB's `COPY ... PARTITION_BY (variable_id)` already fans a
  # multi-variable result out into separate partitions on its own, so
  # batching only changes how many variables feed one query, not how the
  # output is laid out. Each chunk still stages to its own temporary hive and
  # only swaps a variable's target partition after the whole chunk succeeded,
  # so the atomicity guarantee is the same as processing one variable at a
  # time -- just at chunk granularity instead of variable granularity.
  variable_id_chunks <- split(
    ordered_variable_ids,
    ceiling(seq_along(ordered_variable_ids) / chunk_size)
  )

  # A single connection and a single load of `concepts` are shared across
  # every chunk below instead of one per variable (see `anchor_impl()`) --
  # for parquet or in-memory concepts, that used to mean re-scanning or
  # re-copying the entire concept table once per variable.
  logger::log_debug(
    "Opening in-memory DuckDB connection for selector execution."
  )
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:", read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  logger::log_trace("Loading concepts into DuckDB execution context.")
  load_concepts_table(
    con,
    validated$concepts,
    concept_ids = unique(as.character(metadata_dt$concept_id))
  )

  for (chunk_index in seq_along(variable_id_chunks)) {
    chunk_variable_ids <- variable_id_chunks[[chunk_index]]
    chunk_start_time <- Sys.time()
    chunk_metadata <- metadata_dt[variable_id %in% chunk_variable_ids]

    logger::log_info(
      sprintf(
        "Anchoring chunk %d/%d (%d variable_id(s)): %s",
        chunk_index,
        length(variable_id_chunks),
        length(chunk_variable_ids),
        paste(chunk_variable_ids, collapse = ", ")
      )
    )
    logger::log_debug(
      sprintf(
        "Chunk %d/%d has %d metadata row(s) and selector(s): %s",
        chunk_index,
        length(variable_id_chunks),
        nrow(chunk_metadata),
        paste(unique(chunk_metadata$selector), collapse = ", ")
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
        "Created staging parquet hive for chunk %d/%d: %s",
        chunk_index,
        length(variable_id_chunks),
        staging_hive_path
      )
    )

    tryCatch(
      {
        anchor_impl(
          con = con,
          population_dt = validated$population,
          metadata_dt = chunk_metadata,
          anchor_col = anchor_col,
          anchor_hive_path = staging_hive_path
        )

        # The chunk was written as a whole, but the target hive is still
        # updated one variable_id partition at a time, so a variable with no
        # matching windows in this chunk does not disturb the others.
        for (current_variable_id in chunk_variable_ids) {
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
        }
      },
      finally = {
        logger::log_trace(
          sprintf(
            "Cleaning staging parquet hive for chunk %d/%d: %s",
            chunk_index,
            length(variable_id_chunks),
            staging_hive_path
          )
        )
        unlink(staging_hive_path, recursive = TRUE, force = TRUE)

        chunk_duration <- difftime(
          Sys.time(), chunk_start_time,
          units = "secs"
        )
        logger::log_info(
          sprintf(
            "Finished anchoring chunk %d/%d in %.2f secs.",
            chunk_index,
            length(variable_id_chunks),
            as.numeric(chunk_duration)
          )
        )
      }
    )
  }
  logger::log_debug(
    sprintf(
      "Finished anchor_by_variable() for %d variable_id(s) in %d chunk(s).",
      length(variable_ids),
      length(variable_id_chunks)
    )
  )
  invisible(variable_ids)
}

#' Anchor Study Variables Grouped by Selector
#'
#' Runs [anchor()] once per unique \code{selector} value in \code{metadata},
#' so a single selector query (and its join against \code{concepts}) covers
#' every variable that uses that selector, however many there are -- no
#' \code{chunk_size} cap splits a selector's variables across more than one
#' query the way [anchor_by_variable()] can. This is the cheapest option in
#' terms of \code{concepts} scans (at most one per distinct selector in
#' \code{metadata}). Each call to [anchor()] safely replaces only the
#' \code{variable_id} partitions it computes and leaves the rest of
#' \code{anchor_hive_path} untouched, so rerunning \code{anchor_by_selector()}
#' with the same or a smaller \code{metadata} is safe; it just does not give
#' you [anchor_by_variable()]'s \code{chunk_size}-bounded blast radius --
#' every variable sharing a selector is recomputed together in one query.
#'
#' @inheritParams anchor
#'
#' @return Invisibly returns the processed \code{selector} values.
#' @export
anchor_by_selector <- function(
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
  selectors <- unique(as.character(metadata_dt$selector))
  logger::log_debug(
    sprintf(
      paste(
        "`anchor_by_selector()` received %d population row(s),",
        "%d metadata row(s) across %d selector(s)."
      ),
      nrow(validated$population),
      nrow(metadata_dt),
      length(selectors)
    )
  )

  for (current_selector in selectors) {
    selector_start_time <- Sys.time()
    selector_metadata <- metadata_dt[selector == current_selector]
    logger::log_info(
      sprintf(
        "Anchoring selector `%s` (%d variable_id(s)).",
        current_selector,
        length(unique(selector_metadata$variable_id))
      )
    )

    anchor(
      population = validated$population,
      metadata = selector_metadata,
      concepts = validated$concepts,
      anchor_col = anchor_col,
      anchor_hive_path = anchor_hive_path
    )

    logger::log_info(
      sprintf(
        "Finished anchoring selector `%s` in %.2f secs.",
        current_selector,
        as.numeric(
          difftime(Sys.time(), selector_start_time, units = "secs")
        )
      )
    )
  }

  logger::log_debug(
    sprintf(
      "Finished anchor_by_selector() for %d selector(s).",
      length(selectors)
    )
  )
  invisible(selectors)
}
