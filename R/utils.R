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

rename_first_matching_column <- function(x, target, aliases) {
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
  if (!name %in% names(x)) {
    data.table::set(x, j = name, value = value)
  }

  invisible(x)
}

normalize_anchor_reference <- function(x, anchor_col) {
  anchor_ref <- trimws(as.character(x))
  anchor_ref[is.na(anchor_ref) | anchor_ref == ""] <- anchor_col
  anchor_ref[toupper(anchor_ref) == "T0"] <- anchor_col
  anchor_ref
}

normalize_metadata <- function(metadata, anchor_col = "T0") {
  # It may rename existing columns into the package’s canonical names:
  ## date_extraction_func to selector
  ## start_look_back to window_start_offset
  ## end_look_back to window_end_offset
  # It normalizes values:
  ## uppercases selector
  ## coerces offsets to integer
  # It adds internal columns so downstream code can rely on a fixed schema:
  ## anchor_start_col
  ## anchor_end_col
  ## window_definition
  ## range_min
  ## range_max

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
    name = "window_definition",
    value = rep("RELATIVE", nrow(metadata_dt))
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
    j = "window_definition",
    value = toupper(trimws(as.character(metadata_dt$window_definition)))
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

  metadata_dt[]
}

concepts_to_data_table <- function(concepts) {
  if (is.character(concepts) && length(concepts) == 1L) {
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

    concepts_dt <- data.table::as.data.table(
      DBI::dbGetQuery(
        con,
        paste(
          "SELECT person_id, concept_id, CAST(date AS DATE) AS date, value",
          "FROM concepts_db.concept_table"
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
    concepts_dt[, value := NA_character_]
  }

  concepts_dt[, date := as.Date(date)]
  concepts_dt[]
}
