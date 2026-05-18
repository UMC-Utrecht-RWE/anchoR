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

rename_first_existing <- function(x, candidates, target) {
  if (target %in% names(x)) {
    return(x)
  }

  found <- candidates[candidates %in% names(x)]

  if (length(found) > 0L) {
    data.table::setnames(x, found[[1L]], target)
  }

  x
}

normalize_selector_name <- function(x) {
  toupper(trimws(as.character(x)))
}

normalize_metadata <- function(metadata, default_anchor_col = "anchor_date") {
  metadata_dt <- as_data_table(metadata, "metadata")

  metadata_dt <- rename_first_existing(
    metadata_dt,
    candidates = c("date_extraction_func", "anchoring_function"),
    target = "selector"
  )
  metadata_dt <- rename_first_existing(
    metadata_dt,
    candidates = c("start_look_back", "window_start", "window_start_days"),
    target = "window_start_offset"
  )
  metadata_dt <- rename_first_existing(
    metadata_dt,
    candidates = c("end_look_back", "window_end", "window_end_days"),
    target = "window_end_offset"
  )
  metadata_dt <- rename_first_existing(
    metadata_dt,
    candidates = c("anchor_date_start", "window_start_anchor"),
    target = "anchor_start_col"
  )
  metadata_dt <- rename_first_existing(
    metadata_dt,
    candidates = c("anchor_date_end", "window_end_anchor"),
    target = "anchor_end_col"
  )
  metadata_dt <- rename_first_existing(
    metadata_dt,
    candidates = c("window_definition_fn", "window_function"),
    target = "window_definition"
  )

  assert_has_columns(
    metadata_dt,
    required = c(
      "variable_id",
      "concept_id",
      "selector",
      "window_start_offset",
      "window_end_offset"
    ),
    arg = "metadata"
  )

  metadata_dt[
    ,
    selector := normalize_selector_name(selector)
  ][
    ,
    window_start_offset := as.integer(window_start_offset)
  ][
    ,
    window_end_offset := as.integer(window_end_offset)
  ]

  if (!"anchor_start_col" %in% names(metadata_dt)) {
    metadata_dt[, anchor_start_col := default_anchor_col]
  }
  if (!"anchor_end_col" %in% names(metadata_dt)) {
    metadata_dt[, anchor_end_col := default_anchor_col]
  }
  if (!"window_definition" %in% names(metadata_dt)) {
    metadata_dt[, window_definition := "RELATIVE"]
  }
  if (!"range_min" %in% names(metadata_dt)) {
    metadata_dt[, range_min := NA_real_]
  }
  if (!"range_max" %in% names(metadata_dt)) {
    metadata_dt[, range_max := NA_real_]
  }

  metadata_dt[
    is.na(anchor_start_col) | trimws(anchor_start_col) == "",
    anchor_start_col := default_anchor_col
  ]
  metadata_dt[
    is.na(anchor_end_col) | trimws(anchor_end_col) == "",
    anchor_end_col := default_anchor_col
  ]
  metadata_dt[
    is.na(window_definition) | trimws(window_definition) == "",
    window_definition := "RELATIVE"
  ][
    ,
    window_definition := normalize_selector_name(window_definition)
  ][
    ,
    range_min := as.numeric(range_min)
  ][
    ,
    range_max := as.numeric(range_max)
  ]

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
