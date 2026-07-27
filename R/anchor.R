#' Make sure the hive folder exists, and return its full path.
#'
#' Creates the folder if it's missing, and stops with an error if no path
#' was given at all.
#'
#' @param anchor_hive_path Path to the hive folder.
#'
#' @return The absolute path to the (now existing) hive folder.
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

#' Build the subfolder path where one variable's parquet files live.
#'
#' Each variable gets its own subfolder inside the hive, named
#' `variable_id=<id>`. This just builds that path.
#'
#' @param anchor_hive_path Path to the hive folder.
#' @param variable_id The variable's id.
#'
#' @return The path to that variable's subfolder.
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

#' Move one variable's parquet files from staging into the target hive.
#'
#' Tries a plain rename first, which is instant on most local disks. If
#' that doesn't work (for example, the two folders are on different
#' drives), it falls back to copying the files across and then deleting
#' the originals.
#'
#' @param source_partition_path Where the files are right now.
#' @param target_partition_path Where they should end up.
#' @param variable_id The variable's id, used for logging.
#' @return Invisibly, the target path once the move is done.
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

#' Copy finished variables from local scratch into the real output hive.
#'
#' Goes through the requested variables one at a time. If the local scratch
#' hive holds a variable, this deletes its old copy in the output hive (if
#' any) and replaces it with the new one. It skips a variable that was never
#' produced, leaving the output hive's existing copy untouched.
#'
#' @param local_hive_path The local scratch hive that every chunk wrote
#'   into.
#' @param anchor_hive_path The real output hive (this can be slow or
#'   network storage).
#' @param variable_ids Which variables to copy over, normally just the ones
#'   that finished successfully.
#' @return Invisibly `NULL`.
#' @keywords internal
#' @noRd
publish_anchor_partitions <- function(
  local_hive_path,
  anchor_hive_path,
  variable_ids
) {
  for (current_variable_id in variable_ids) {
    target_partition_path <- anchor_partition_path(
      anchor_hive_path,
      current_variable_id
    )
    local_partition_path <- anchor_partition_path(
      local_hive_path,
      current_variable_id
    )

    if (!dir.exists(local_partition_path)) {
      logger::log_debug(
        sprintf(
          paste(
            "No parquet partition was produced for variable_id `%s`.",
            "The target hive was left without that partition."
          ),
          current_variable_id
        )
      )
      next
    }

    if (dir.exists(target_partition_path)) {
      logger::log_debug(
        sprintf(
          "Deleting existing parquet partition for variable_id `%s`.",
          current_variable_id
        )
      )
      unlink(target_partition_path, recursive = TRUE, force = TRUE)
    }

    move_anchor_partition(
      source_partition_path = local_partition_path,
      target_partition_path = target_partition_path,
      variable_id = current_variable_id
    )
  }

  invisible(NULL)
}

#' Write an in-memory accumulator table to the real output hive.
#'
#' Used by [anchor_by_variable()]'s "memory" staging mode: instead of a
#' local scratch hive on disk, chunk results pile up in one DuckDB table
#' (see `add_table_accumulation()`), and this is the single write that
#' finally sends that table to `anchor_hive_path` as parquet. Because the
#' underlying `COPY ... OVERWRITE_OR_IGNORE` only touches the
#' `variable_id` values present in the table, a variable that was never
#' produced never appears here, and this leaves its existing output (if
#' any) alone, the same behavior as `publish_anchor_partitions()`, just
#' without needing a local hive or a list of variable ids to check.
#'
#' @param con An open database connection.
#' @param table_name Name of the accumulator table to publish. If it
#'   doesn't exist (nothing was ever accumulated), this is a no-op.
#' @param anchor_hive_path The real output hive (this can be slow or
#'   network storage).
#' @return Invisibly `NULL`.
#' @keywords internal
#' @noRd
publish_accumulated_table <- function(con, table_name, anchor_hive_path) {
  if (!(table_name %in% DBI::dbListTables(con))) {
    logger::log_debug(
      sprintf(
        "No rows were accumulated in `%s`; nothing to publish.", table_name
      )
    )
    return(invisible(NULL))
  }

  DBI::dbExecute(
    con,
    add_parquet_export(
      sprintf("SELECT * FROM %s", table_name),
      anchor_hive_path
    )
  )

  invisible(NULL)
}

#' Sort variable_ids so ones sharing a selector sit next to each other.
#'
#' Groups variables by which selector rule they use (using each variable's
#' first-listed selector, in case it appears more than once), while keeping
#' their original order within each group.
#'
#' @param metadata_dt A data.table with `variable_id` and `selector` columns.
#' @return The unique `variable_id` values, sorted by selector.
#' @keywords internal
#' @noRd
order_variable_ids_by_selector <- function(metadata_dt) {
  variable_ids <- unique(as.character(metadata_dt$variable_id))
  first_selector_per_variable <- metadata_dt$selector[
    match(variable_ids, metadata_dt$variable_id)
  ]

  variable_ids[order(first_selector_per_variable)]
}

#' Do the windowing and selector work for one batch of variables.
#'
#' Shared by [anchor()] and [anchor_by_variable()] so the expensive setup
#' (opening a DuckDB connection, loading `concepts`) only happens once,
#' instead of once per variable. This function does the part that's
#' different for each batch: building the person-by-variable time windows,
#' and running the selector queries that turn those windows into anchored
#' values.
#'
#' @param con An open DBI connection with `concepts` already loaded.
#' @param population_dt Validated population `data.table` (not yet trimmed to
#'   window columns).
#' @param metadata_dt Validated metadata `data.table` for the variable(s) to
#'   process in this call.
#' @param anchor_col Column in `population_dt` used as the index date when
#'   metadata does not specify an anchor column.
#' @param anchor_hive_path Existing, normalized path to write selector output.
#' @param clear_existing_partitions Whether to clear partitions before writing.
#' @return Invisibly `NULL` on success, or (only when no window was valid) the
#'   same empty typed table `anchor()` has always returned in that case.
#' @keywords internal
#' @noRd
anchor_impl <- function(
  con,
  population_dt,
  metadata_dt,
  anchor_col,
  anchor_hive_path = NULL,
  accumulate_table = NULL,
  clear_existing_partitions = TRUE
) {
  # Define windows for all person-variable combinations, then mark
  # impossible anchors and filter them out below. Only person_id and the
  # anchor columns metadata references are needed past this point, so trim
  # other population covariates before the cross join multiplies them
  # across every metadata row.
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

  # Only valid windows go to disk: invalid ones can never match, and
  # including them would only waste work on the SQL side.
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

  window_variable_ids <- unique(valid_windows$variable_id)
  selector_names <- unique(valid_windows$selector)
  rm(window_population, window_dt, valid_windows)
  gc()

  # Clear each target variable_id's existing partition before writing, so a
  # rerun always fully replaces it instead of mixing old rows with new ones.
  if (clear_existing_partitions) {
    clear_anchor_partitions(
      anchor_hive_path,
      window_variable_ids
    )
  }

  run_selector_queries(
    con = con,
    selectors = selector_names,
    anchor_hive_path = anchor_hive_path,
    accumulate_table = accumulate_table
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
#' @return Invisibly `NULL`; writes parquet files to `anchor_hive_path` as a
#'   side effect.
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

#' Anchor study variables in batches
#'
#' Does the same job as [anchor()], but works through \code{metadata} in
#' batches of \code{chunk_size} variables at a time (default 20) instead of
#' all at once.
#'
#' Every batch's results are held somewhere other than
#' \code{anchor_hive_path} until they're ready to publish either in one
#' growing DuckDB table (\code{staging_mode = "memory"}, the default), or
#' in a scratch folder on local disk (\code{staging_mode = "disk"}, under
#' \code{staging_dir}). Either way, this keeps the repeated reading and
#' writing that happens while batches are being computed off
#' \code{anchor_hive_path}, which matters when it points at slow or
#' network storage. \code{"memory"} avoids an extra local write-then-read
#' round trip that \code{"disk"} needs, but holds the whole run's output in
#' memory (DuckDB spills to local disk on its own if that gets too big);
#' \code{"disk"} bounds memory use to one batch at a time instead.
#'
#' \code{publish} controls when that held output gets written to
#' \code{anchor_hive_path}. With \code{publish = "once"} (the default),
#' nothing is written until every batch in the call has finished
#' successfully, and if any batch fails, nothing is written at all,
#' \code{anchor_hive_path} is left exactly as it was before the call, and
#' the error is raised, so you never end up with some variables refreshed
#' and others not. With \code{publish = "per_chunk"}, each batch's results
#' are written as soon as that batch finishes, so a later batch's failure
#' doesn't discard earlier batches' already-published results. This is
#' useful if \code{anchor_hive_path} is fast enough that the extra writes
#' don't matter and you'd rather keep whatever progress you can.
#'
#' Whichever combination is used, publishing only ever replaces the
#' \code{variable_id} partitions that were computed and leaves the rest of
#' \code{anchor_hive_path} untouched, so re-running for just a few
#' variables is always safe.
#'
#' Grouping several variables into one batch also means a single query
#' (and a single join against \code{concepts}) can cover all of them at
#' once, which is much cheaper than running one query per variable.
#' Variables are sorted by selector before being split into batches, so
#' each batch groups same-selector variables together as much as
#' \code{chunk_size} allows (see [anchor_by_selector()] if you'd rather
#' always process every variable sharing a selector together, with no
#' batch-size limit).
#'
#' @inheritParams anchor
#' @param chunk_size How many variables to process per batch. Bigger
#'   batches mean fewer (and cheaper) scans of \code{concepts}, but (with
#'   \code{publish = "once"}) also throw away more work if a batch fails
#'   partway through, since nothing is saved until the whole call succeeds.
#'   Use \code{1} to process one variable at a time.
#' @param staging_dir Folder to use for DuckDB's own temporary files, and
#'   (only when \code{staging_mode = "disk"}) for the local scratch hive
#'   every batch writes into. Defaults to \code{tempdir()}. Only change
#'   this if your machine's default temporary folder is itself slow or on
#'   a network drive.
#' @param staging_mode Where each batch's results are held before being
#'   published: \code{"memory"} (default) accumulates them in one DuckDB
#'   table; \code{"disk"} writes them to a local scratch parquet hive
#'   instead. See Details.
#' @param publish When to write results to \code{anchor_hive_path}:
#'   \code{"once"} (default) after the whole call succeeds, all together;
#'   \code{"per_chunk"} after each batch, incrementally. See Details.
#'
#' @return Invisibly returns the variable ids that were processed.
#' @export
anchor_by_variable <- function(
  population,
  metadata,
  concepts,
  anchor_col = "T0",
  anchor_hive_path = NULL,
  chunk_size = 20L,
  staging_dir = NULL,
  staging_mode = c("memory", "disk"),
  publish = c("once", "per_chunk")
) {
  staging_mode <- match.arg(staging_mode)
  publish <- match.arg(publish)

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
  # selector-homogeneous as `chunk_size` allows. `run_selector_queries()`
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
        "%d metadata row(s), anchor_col `%s`, concept source type `%s`,",
        "staging_mode `%s`, publish `%s`."
      ),
      nrow(validated$population),
      nrow(metadata_dt),
      anchor_col,
      concepts_type,
      staging_mode,
      publish
    )
  )

  # Variables are processed in chunks rather than strictly one at a time, so
  # a single selector query (and its concepts join) can cover several
  # variables at once. DuckDB's `COPY ... PARTITION_BY (variable_id)`
  # already fans a multi-variable result out into separate partitions on
  # its own, so batching only changes how many variables feed one query,
  # not how the output is laid out.
  variable_id_chunks <- split(
    ordered_variable_ids,
    ceiling(seq_along(ordered_variable_ids) / chunk_size)
  )

  # `staging_dir` defaults to `tempdir()`, local disk on the machine running
  # this process. It always holds DuckDB's own spill files; when
  # `staging_mode == "disk"` it also holds the local scratch hive every
  # chunk writes into, deliberately independent of `anchor_hive_path` so
  # that write traffic never touches it until the final publish step.
  if (is.null(staging_dir)) {
    staging_dir <- tempdir()
  }
  if (!dir.exists(staging_dir)) {
    dir.create(staging_dir, recursive = TRUE)
  }
  staging_dir <- normalizePath(staging_dir, winslash = "/", mustWork = TRUE)

  local_hive_path <- NULL
  accumulate_table <- NULL

  if (staging_mode == "disk") {
    local_hive_path <- tempfile(pattern = "anchor-local-", tmpdir = staging_dir)
    dir.create(local_hive_path, recursive = TRUE)
    local_hive_path <- ensure_anchor_hive_path(local_hive_path)
    on.exit(
      unlink(local_hive_path, recursive = TRUE, force = TRUE),
      add = TRUE
    )
    logger::log_trace(
      sprintf("Created local scratch parquet hive: %s", local_hive_path)
    )
  } else {
    accumulate_table <- "anchor_results"
  }

  duckdb_temp_dir <- tempfile(
    pattern = "anchor-duckdb-tmp-",
    tmpdir = staging_dir
  )
  dir.create(duckdb_temp_dir, recursive = TRUE)
  on.exit(
    unlink(duckdb_temp_dir, recursive = TRUE, force = TRUE),
    add = TRUE
  )

  # A single connection and a single load of `concepts` are shared across
  # every chunk below instead of one per variable (see `anchor_impl()`).
  # For parquet or in-memory concepts, that used to mean re-scanning or
  # re-copying the entire concept table once per variable.
  logger::log_debug(
    "Opening in-memory DuckDB connection for selector execution."
  )
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:", read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  # Any out-of-core spill DuckDB needs during the join/windowing below, or
  # (in "memory" staging mode) to keep the accumulator table from outgrowing
  # RAM goes to local scratch instead of wherever it would otherwise
  # default to.
  DBI::dbExecute(
    con,
    sprintf("SET temp_directory = '%s';", duckdb_temp_dir)
  )

  logger::log_trace("Loading concepts into DuckDB execution context.")
  load_concepts_table(
    con,
    validated$concepts,
    concept_ids = unique(as.character(metadata_dt$concept_id))
  )

  publish_chunk <- function(chunk_variable_ids) {
    logger::log_debug(
      sprintf(
        "Publishing %d variable_id partition(s) to `%s`.",
        length(chunk_variable_ids),
        anchor_hive_path
      )
    )
    if (staging_mode == "disk") {
      publish_anchor_partitions(
        local_hive_path = local_hive_path,
        anchor_hive_path = anchor_hive_path,
        variable_ids = chunk_variable_ids
      )
    } else {
      publish_accumulated_table(
        con = con,
        table_name = accumulate_table,
        anchor_hive_path = anchor_hive_path
      )
      # Reset so the next publish (per-chunk mode) only exports the rows
      # that chunk produced, not everything published so far.
      DBI::dbExecute(con, sprintf("DROP TABLE IF EXISTS %s;", accumulate_table))
    }
  }

  processed_variable_ids <- character(0)
  loop_error <- NULL

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

    # Every chunk writes into the same local scratch hive or accumulator
    # table both use `OVERWRITE_OR_IGNORE`/plain inserts keyed by
    # `variable_id`, so chunks with disjoint variable_id sets never collide.
    loop_error <- tryCatch(
      {
        anchor_impl(
          con = con,
          population_dt = validated$population,
          metadata_dt = chunk_metadata,
          anchor_col = anchor_col,
          anchor_hive_path = local_hive_path,
          accumulate_table = accumulate_table,
          clear_existing_partitions = FALSE
        )
        NULL
      },
      error = function(e) e
    )

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

    if (!is.null(loop_error)) {
      break
    }
    processed_variable_ids <- c(processed_variable_ids, chunk_variable_ids)

    if (publish == "per_chunk") {
      publish_chunk(chunk_variable_ids)
    }
  }

  if (publish == "once") {
    # If any chunk failed, the whole run is discarded: nothing is published
    # to `anchor_hive_path`, which is left exactly as it was before this
    # call.
    if (!is.null(loop_error)) {
      logger::log_error(
        sprintf(
          paste(
            "Chunk failed; discarding results for this run.",
            "`%s` is left unchanged."
          ),
          anchor_hive_path
        )
      )
      stop(loop_error)
    }

    # `anchor_hive_path` is only touched here, once for the whole run,
    # instead of once per chunk.
    publish_chunk(processed_variable_ids)
  } else if (!is.null(loop_error)) {
    # publish == "per_chunk": every chunk before the failing one was already
    # published as it completed, so only the error needs to propagate now.
    stop(loop_error)
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

#' Anchor study variables, one selector at a time
#'
#' Runs [anchor()] once for each distinct \code{selector} value found in
#' \code{metadata}, so every variable that shares a selector is covered by
#' a single query (and a single join against \code{concepts}), no matter
#' how many variables share it; unlike [anchor_by_variable()], there is no
#' \code{chunk_size} limit splitting a selector's variables across more
#' than one query. Affected \code{variable_id} partitions are cleared once
#' before selector processing begins. The calls leave the rest of
#' \code{anchor_hive_path} untouched, so rerunning \code{anchor_by_selector()}
#' with the same or a smaller \code{metadata} is safe; it just does not give
#' you [anchor_by_variable()]'s \code{chunk_size}-bounded blast radius, since
#' every variable sharing a selector is recomputed together in one query.
#'
#' @inheritParams anchor
#'
#' @return Invisibly returns the selector values that were processed.
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

  # Clear partition paths before this new selector loop starts.
  clear_anchor_partitions(
    anchor_hive_path,
    unique(as.character(metadata_dt$variable_id))
  )

  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:", read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  load_concepts_table(
    con,
    validated$concepts,
    concept_ids = unique(as.character(metadata_dt$concept_id))
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

    anchor_impl(
      con = con,
      population_dt = validated$population,
      metadata_dt = selector_metadata,
      anchor_col = anchor_col,
      anchor_hive_path = anchor_hive_path,
      clear_existing_partitions = FALSE
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
