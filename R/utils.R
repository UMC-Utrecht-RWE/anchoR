`%||%` <- function(lhs, rhs) {
  if (is.null(lhs)) {
    return(rhs)
  }

  lhs
}

as_data_table <- function(x, arg) {
  if (!is.data.frame(x)) {
    stop(sprintf("`%s` must be a data frame.", arg), call. = FALSE)
  }

  # Most package code mutates tables by reference, so always copy here to avoid
  # surprising callers by changing the object they passed in.
  data.table::as.data.table(data.table::copy(x))
}

assert_has_columns <- function(x, required, arg) {
  missing_cols <- setdiff(required, names(x))

  if (length(missing_cols) > 0L) {
    stop(
      sprintf(
        "`%s` is missing required columns: %s.",
        arg,
        paste(missing_cols, collapse = ", ")
      ),
      call. = FALSE
    )
  }

  invisible(x)
}

normalize_selector_name <- function(x) {
  toupper(trimws(as.character(x)))
}

looks_like_glob <- function(x) {
  grepl("[\\*\\?\\[]", x)
}

concepts_input_type <- function(concepts) {
  if (is.data.frame(concepts)) {
    return("table")
  }

  # Classifying the source once keeps the rest of the pipeline from repeating
  # path heuristics in every place concepts are loaded.
  if (!is.character(concepts) || length(concepts) == 0L) {
    stop(
      paste(
        "`concepts` must be a data frame, a DuckDB file path,",
        "or parquet file location(s)."
      ),
      call. = FALSE
    )
  }

  if (
    length(concepts) == 1L &&
    identical(tolower(tools::file_ext(concepts)), "duckdb")
  ) {
    return("duckdb")
  }

  "parquet"
}

normalize_parquet_sources <- function(concepts) {
  if (concepts_input_type(concepts) != "parquet") {
    stop("`concepts` is not a parquet source.", call. = FALSE)
  }

  # Expand directories early so the SQL layer always receives an explicit list
  # of parquet sources, regardless of how the caller grouped the files.
  parquet_sources <- unlist(
    lapply(
      concepts,
      function(path) {
        if (dir.exists(path)) {
          parquet_files <- list.files(
            path,
            pattern = "\\.parquet$",
            full.names = TRUE,
            recursive = TRUE
          )

          if (length(parquet_files) == 0L) {
            stop(
              sprintf("No parquet files found under `%s`.", path),
              call. = FALSE
            )
          }

          return(parquet_files)
        }

        if (file.exists(path) || looks_like_glob(path)) {
          return(path)
        }

        stop(
          sprintf("Concept parquet source does not exist: %s.", path),
          call. = FALSE
        )
      }
    ),
    use.names = FALSE
  )

  as.character(parquet_sources)
}

rename_first_matching_column <- function(x, target, aliases) {
  # Metadata arrives with study-specific names, so rename once instead of
  # making every downstream function know all historical aliases.
  if (target %in% names(x)) {
    return(invisible(x))
  }

  source <- intersect(aliases, names(x))
  if (length(source) == 0L) {
    return(invisible(x))
  }

  data.table::setnames(x, source[[1L]], target)
  invisible(x)
}

add_column_if_missing <- function(x, name, value) {
  # Defaults are only filled when absent so study metadata can override them
  # without being silently overwritten by package assumptions.
  if (!name %in% names(x)) {
    data.table::set(x, j = name, value = value)
  }

  invisible(x)
}

normalize_anchor_reference <- function(x, anchor_col) {
  # Treat "T0" as a symbolic placeholder so callers can rename the actual
  # anchor column without rewriting every metadata file.
  anchor_ref <- trimws(as.character(x))
  anchor_ref[is.na(anchor_ref) | anchor_ref == ""] <- anchor_col
  anchor_ref[toupper(anchor_ref) == "T0"] <- anchor_col
  anchor_ref
}

normalize_metadata <- function(metadata, anchor_col = "T0") {
  # Canonicalize metadata once so later code can reason about selectors,
  # offsets, and anchor columns without special cases.
  metadata_dt <- as_data_table(metadata, "metadata")

  rename_first_matching_column(
    metadata_dt,
    target = "selector",
    aliases = "date_extraction_func"
  )
  rename_first_matching_column(
    metadata_dt,
    target = "window_start_offset",
    aliases = "start_look_back"
  )
  rename_first_matching_column(
    metadata_dt,
    target = "window_end_offset",
    aliases = "end_look_back"
  )
  rename_first_matching_column(
    metadata_dt,
    target = "anchor_start_col",
    aliases = "anchor_date_start"
  )
  rename_first_matching_column(
    metadata_dt,
    target = "anchor_end_col",
    aliases = "anchor_date_end"
  )

  data.table::set(
    metadata_dt,
    j = "selector",
    value = normalize_selector_name(metadata_dt$selector)
  )
  data.table::set(
    metadata_dt,
    j = "window_start_offset",
    value = as.integer(metadata_dt$window_start_offset)
  )
  data.table::set(
    metadata_dt,
    j = "window_end_offset",
    value = as.integer(metadata_dt$window_end_offset)
  )
  data.table::set(
    metadata_dt,
    j = "concept_id",
    value = as.character(metadata_dt$concept_id)
  )

  # These defaults keep the minimal metadata shape small while still giving the
  # windowing and selector code every column it expects.
  add_column_if_missing(
    metadata_dt,
    name = "anchor_start_col",
    value = rep(anchor_col, nrow(metadata_dt))
  )
  add_column_if_missing(
    metadata_dt,
    name = "anchor_end_col",
    value = rep(anchor_col, nrow(metadata_dt))
  )
  add_column_if_missing(
    metadata_dt,
    name = "range_min",
    value = rep(NA_real_, nrow(metadata_dt))
  )
  add_column_if_missing(
    metadata_dt,
    name = "range_max",
    value = rep(NA_real_, nrow(metadata_dt))
  )

  data.table::set(
    metadata_dt,
    j = "anchor_start_col",
    value = normalize_anchor_reference(metadata_dt$anchor_start_col, anchor_col)
  )
  data.table::set(
    metadata_dt,
    j = "anchor_end_col",
    value = normalize_anchor_reference(metadata_dt$anchor_end_col, anchor_col)
  )
  data.table::set(
    metadata_dt,
    j = "range_min",
    value = as.numeric(metadata_dt$range_min)
  )
  data.table::set(
    metadata_dt,
    j = "range_max",
    value = as.numeric(metadata_dt$range_max)
  )

  # Return a fully standardized table so validation and execution never need to
  # branch on legacy names or loose column types.
  metadata_dt[]
}

concepts_to_data_table <- function(concepts) {
  concepts_type <- concepts_input_type(concepts)

  if (concepts_type == "duckdb") {
    if (!file.exists(concepts)) {
      stop(
        sprintf("Concept database path does not exist: %s.", concepts),
        call. = FALSE
      )
    }

    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    DBI::dbExecute(
      con,
      sprintf(
        "ATTACH '%s' AS concepts_db (READ_ONLY);",
        normalizePath(concepts, winslash = "/")
      )
    )

    # DuckDB-backed concepts are materialized only for helpers like `derive_t0`
    # that rely on data.table overlap joins instead of SQL templates.
    concepts_dt <- data.table::as.data.table(
      DBI::dbGetQuery(
        con,
        paste(
          "SELECT
          person_id,
          concept_id,
          CAST(date AS DATE) AS date,
          value",
          "FROM concepts_db.concept_table"
        )
      )
    )
  } else if (concepts_type == "parquet") {
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:")
    on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

    # Reading parquet through DuckDB keeps one code path for all non-table
    # sources and avoids re-implementing parquet handling in base R.
    concepts_dt <- data.table::as.data.table(
      DBI::dbGetQuery(
        con,
        paste(
          "SELECT person_id, concept_id, CAST(date AS DATE) AS date, value",
          "FROM read_parquet(",
          parquet_paths_sql(con, concepts),
          ", hive_partitioning = true, union_by_name = true)"
        )
      )
    )
  } else {
    concepts_dt <- as_data_table(concepts, "concepts")
  }

  assert_has_columns(
    concepts_dt,
    required = c("person_id", "concept_id", "date"),
    arg = "concepts"
  )

  if (!"value" %in% names(concepts_dt)) {
    # Some concept sources are purely event-based; adding `value` keeps the
    # selector interface uniform across boolean and valued concepts.
    concepts_dt[, value := NA_character_]
  }

  # Date coercion is centralized here so later code can compare dates directly
  # without worrying about how DBI represented them.
  concepts_dt[, date := as.Date(date)]
  concepts_dt[]
}
