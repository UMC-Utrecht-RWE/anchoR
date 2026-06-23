`%||%` <- function(lhs, rhs) {
  if (is.null(lhs)) {
    return(rhs)
  }

  lhs
}

stop_log <- function(message) {
  msg <- sprintf(message)
  logger::log_error(msg)
  base::stop(msg, call. = FALSE)
}


as_data_table <- function(x, arg) {
  if (!is.data.frame(x)) {
    stop(sprintf("`%s` must be a data frame.", arg), call. = FALSE)
  }

  # Most package code mutates tables by reference, so always copy here to avoid
  # surprising callers by changing the object they passed in.
  data.table::as.data.table(data.table::copy(x))
}

normalize_multiple_episodes <- function(multiple_episodes) {
  if (is.null(multiple_episodes)) {
    return(NULL)
  }

  episodes_dt <- as_data_table(multiple_episodes, "multiple_episodes")
  rename_first_matching_column(
    episodes_dt,
    target = "episode_id",
    aliases = "pregnancy_id"
  )
  rename_first_matching_column(
    episodes_dt,
    target = "episode_start",
    aliases = "lmp_date"
  )
  rename_first_matching_column(
    episodes_dt,
    target = "episode_end",
    aliases = "pregnancy_end_date"
  )
  assert_has_columns(
    episodes_dt,
    required = c("person_id", "episode_id", "episode_start", "episode_end"),
    arg = "multiple_episodes"
  )

  episodes_dt[, `:=`(
    person_id = as.character(person_id),
    episode_id = as.character(episode_id),
    episode_start = as.Date(episode_start),
    episode_end = as.Date(episode_end)
  )]

  episodes_dt[]
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

#' Takes a data frame x, a target column name (new standard name), and aliases
#' (vector of old possible names). If the target column already exists
#' it returns data unchanged (no rename needed).
#' If matching aliases found → renames the first matching one to the target name
#' @param x data frame or data table to rename columns in
#' @param target the new standard column name to rename to
#' @param aliases vector of old possible column names that should be renamed
#' to the target if the target doesn't already exist
#' @return x with the first matching alias renamed to target, or unchanged if
#' target already exists or no aliases found
#' @keywords internal
#' @noRd
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

  # If metadata is missing required columns add them with NA values
  # For now only window_name needs to be added if missing,
  # Because in targe that is possible
  add_column_if_missing(metadata_dt, "window_name", NA_character_)
  add_column_if_missing(metadata_dt, "constructor", "GENERIC")

  rename_first_matching_column(
    metadata_dt,
    target = "selector",
    aliases = "date_extraction_func"
  )
  rename_first_matching_column(
    metadata_dt,
    target = "start_offset",
    aliases = "start_look_back"
  )
  rename_first_matching_column(
    metadata_dt,
    target = "end_offset",
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

  metadata_dt[, `:=`(
    constructor = toupper(trimws(as.character(constructor))),
    selector = normalize_selector_name(selector),
    start_offset = as.integer(start_offset),
    end_offset = as.integer(end_offset),
    concept_id = as.character(concept_id)
  )]
  metadata_dt[
    is.na(constructor) | constructor == "",
    constructor := "GENERIC"
  ]

  # These defaults keep the minimal metadata shape small while still giving the
  # windowing and selector code every column it expects.
  if (!"anchor_start_col" %in% names(metadata_dt)) {
    metadata_dt[
      , anchor_start_col := anchor_col
    ]
  }
  if (!"anchor_end_col" %in% names(metadata_dt)) {
    metadata_dt[
      , anchor_end_col := anchor_col
    ]
  }
  if (!"range_min" %in% names(metadata_dt)) metadata_dt[, range_min := NA_real_]
  if (!"range_max" %in% names(metadata_dt)) metadata_dt[, range_max := NA_real_]

  metadata_dt[, `:=`(
    anchor_start_col = normalize_anchor_reference(anchor_start_col, anchor_col),
    anchor_end_col = normalize_anchor_reference(anchor_end_col, anchor_col),
    range_min = as.numeric(range_min),
    range_max = as.numeric(range_max)
  )]

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
