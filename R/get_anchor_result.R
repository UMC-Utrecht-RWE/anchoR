#' Retrieve and Reshape Anchored Variable Results
#'
#' Reads parquet files from an anchor hive directory via DuckDB, filters to the
#' requested variables, and pivots the long-format result into a wide
#' \code{data.table} with one column per variable for both \code{value} and
#' \code{date}.
#'
#' @param metadata A data frame describing the study variables. Must contain at
#'   least a \code{variable_id} column.
#' @param anchor_hive_path A character string giving the path to the directory
#'   that contains the anchored parquet hive. Must be a valid existing
#'   directory.
#' @param population Optional data frame with population rows to be represented
#'   in wide output. When provided, it must contain \code{person_id} and
#'   \code{T0} columns.
#' @param result_shape A character string specifying the desired shape of the
#'   output. Must be either \code{"wide"} or \code{"narrow"}.
#' @param impute_missing Logical; when \code{TRUE} and
#'   \code{result_shape = "wide"}, missing \code{value_<variable_id>} cells are
#'   imputed using \code{metadata} columns \code{is_expected_missing} and
#'   \code{variable_type} via \code{imputing_missing()}.
#' @param cast_window Logical; controls wide reshaping formula. When
#'   \code{FALSE} (default), results are cast by
#'   \code{person_id + T0 + window_name ~ variable_id}. When \code{TRUE},
#'   results are cast by \code{person_id + T0 ~ window_name + variable_id}.
#' @param only_date Logical; when \code{TRUE} and
#'   \code{result_shape = "wide"}, only date columns are cast (no
#'   \code{value_<...>} columns). When \code{FALSE}, both value and date
#'   columns are cast.
#'
#' @return When \code{result_shape = "narrow"}, a long \code{data.table}
#'   containing \code{person_id}, \code{T0}, \code{variable_id},
#'   \code{window_name}, \code{date}, and \code{value}. When
#'   \code{result_shape = "wide"}, a wide \code{data.table} with one row per
#'   \code{person_id}, \code{T0}, and \code{window_name} combination, and one
#'   pair of columns
#'   (\code{value_<variable_id>}, \code{date_<variable_id>}) per variable in
#'   \code{metadata}.
#' @export
get_anchor_result <- function(
    metadata,
    anchor_hive_path = NULL,
    population = NULL,
    result_shape = "wide",
    impute_missing = FALSE,
    cast_window = FALSE,
    only_date = FALSE
) {
  # Different selectors may return slightly different columns, so the combined
  # result needs a forgiving row bind instead of assuming one rigid shape.
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = ":memory:", read_only = FALSE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  if (!is.null(population)) {
    required_population_cols <- c("person_id", "T0")
    missing_population_cols <- setdiff(required_population_cols, names(population))
    if (length(missing_population_cols) > 0L) {
      msg <- sprintf(
        paste(
          "`population` is missing required columns:",
          "%s."
        ),
        paste(missing_population_cols, collapse = ", ")
      )
      logger::log_error(msg)
      base::stop(msg, call. = FALSE)
    }
  }

  if (is.null(anchor_hive_path) || !dir.exists(anchor_hive_path)) {
    msg <- sprintf("`anchor_hive_path` must be a valid path!")
    logger::log_error(msg)
    base::stop(msg, call. = FALSE)
  }

  anchor_hive_path_sql <- as.character(
    DBI::dbQuoteString(
      con,
      normalizePath(anchor_hive_path, winslash = "/", mustWork = TRUE)
    )
  )
  DBI::dbExecute(
    con,
    paste(
      "CREATE VIEW anchored_variables AS",
      "SELECT * FROM read_parquet(",
      anchor_hive_path_sql,
      ", hive_partitioning = true, union_by_name = true);"
    )
  )

  variable_id_list <- unique(metadata$variable_id)
  quoted_variable_ids <- vapply(
    variable_id_list,
    function(id) as.character(DBI::dbQuoteString(con, id)),
    character(1)
  )
  anchored_dt <- data.table::as.data.table(
    DBI::dbGetQuery(
      con,
      paste(
        "SELECT DISTINCT * FROM anchored_variables WHERE variable_id IN (",
        paste(quoted_variable_ids, collapse = ", "),
        ");"
      )
    )
  )
  if ("date" %in% names(anchored_dt)) {
    # DBI can round-trip DATE columns as character depending on the source, so
    # coerce back here to keep the public output type stable.
    anchored_dt[, date := as.Date(date)]
  }
  if ("T0" %in% names(anchored_dt)) {
    anchored_dt[, T0 := as.Date(T0)]
  }

  data.table::setorder(anchored_dt, anchor_row_id)
  if (result_shape == "narrow") {
    required_narrow_cols <- c(
      "person_id",
      "T0",
      "variable_id",
      "window_name",
      "date",
      "value"
    )
    missing_cols <- setdiff(required_narrow_cols, names(anchored_dt))
    if (length(missing_cols) > 0L) {
      msg <- sprintf(
        paste(
          "Anchored results are missing required narrow-output columns:",
          "%s."
        ),
        paste(missing_cols, collapse = ", ")
      )
      logger::log_error(msg)
      base::stop(msg, call. = FALSE)
    }

    anchored_dt[
      ,
      ..required_narrow_cols
    ]
  } else if (result_shape == "wide") {
    required_wide_id_cols <- c("person_id", "T0", "variable_id")
    missing_cols <- setdiff(required_wide_id_cols, names(anchored_dt))
    if (length(missing_cols) > 0L) {
      msg <- sprintf(
        paste(
          "Anchored results are missing required wide-output columns:",
          "%s."
        ),
        paste(missing_cols, collapse = ", ")
      )
      logger::log_error(msg)
      base::stop(msg, call. = FALSE)
    }

    if (anyDuplicated(metadata$variable_id) > 0L) {
      duplicated_variable_ids <- unique(
        metadata$variable_id[duplicated(metadata$variable_id)]
      )
      msg <- sprintf(
        paste(
          "`metadata` contains duplicate `variable_id` values,",
          "which makes wide output ambiguous: %s."
        ),
        paste(duplicated_variable_ids, collapse = ", ")
      )
      logger::log_error(msg)
      base::stop(msg, call. = FALSE)
    }

    duplicate_rows <- anchored_dt[
      ,
      .N,
      by = .(person_id, T0, variable_id)
    ][N > 1L]
    if (nrow(duplicate_rows) > 0L) {
      msg <- sprintf(
        paste(
          "Anchored results contain duplicate rows for the same",
          "`person_id`, `T0`, and `variable_id`, so wide output is ambiguous."
        )
      )
      logger::log_error(msg)
      base::stop(msg, call. = FALSE)
    }

    # The dcast formula will create columns in the format value_<variable_id> and date_<variable_id> or if cast_window is TRUE, value_<window_name>_<variable_id> and date_<window_name>_<variable_id>
    formula <- as.formula(if(cast_window){
      "person_id + T0 ~ window_name + variable_id"
      }else{
        "person_id + T0 + window_name ~ variable_id"
      }
    )
    wide_anchored <- data.table::dcast(
      anchored_dt,
      formula,
      value.var = if(only_date == FALSE) c("value", "date") else c("date"),
      fill = list(value = NA_character_, date = as.Date(NA))
    )
    
    #Generating all missing variable columns
    missing_variables <- setdiff(unique(metadata$variable_id), 
    unique(anchored_dt$variable_id))
    
    lapply(missing_variables, function(x){
      wide_anchored[, eval(paste0("value_", x)) := NA]
      wide_anchored[, eval(paste0("date_", x)) := NA]
    })
    
    if (!is.null(population)) {
      #Identifying persons that do not have ANY variable
      population <- data.table::fsetdiff(population[, .(person_id, T0)],
                                         unique(wide_anchored[, .(person_id, T0)]))[, tmp := 1]
      metadata[, tmp := 1]
      
      #We will generate a row per missing person per window
      missing_anchored <- data.table::merge.data.table(population, 
                                                       unique(metadata[,.(window_name,tmp)]), 
                                                       by = "tmp", 
                                                       allow.cartesian = TRUE)[
        , tmp := NULL
      ]
      #Doing the rbindlist between wide_anchored and missing_anchored we will 
      # populated the missing column of the dt missing_anchored automatically
      wide_anchored <- data.table::rbindlist(list(wide_anchored, missing_anchored), 
                                             use.names = TRUE, 
                                             fill = TRUE)
    }
    
    if(impute_missing == TRUE){
      wide_anchored <- imputing_missing(wide_anchored, metadata)
    }
      
    return(wide_anchored)
    
  } else {
    msg <- sprintf("`result_shape` must be either 'wide' or 'narrow'!")
    logger::log_error(msg)
    base::stop(msg, call. = FALSE)
  }
}


#' Impute Missing Values in Wide Anchor Output
#'
#' Imputes missing \\code{value_<variable_id>} cells in a wide anchored result
#' using metadata rules for \\code{is_expected_missing} and
#' \\code{variable_type}. For non-expected-missing variables, logical/TF types
#' are imputed as \\code{FALSE} and categorical types as \\code{0}. If required
#' metadata columns are only partially available, a warning is raised and
#' imputation is skipped.
#'
#' @param wide_anchored A wide \\code{data.table} from \\code{get_anchor_result}
#'   with \\code{value_<variable_id>} columns.
#' @param metadata A data frame that should include \\code{variable_id},
#'   \\code{is_expected_missing}, and \\code{variable_type}.
#'
#' @return The updated wide \\code{data.table}. Returns input unchanged when
#'   required metadata columns are missing.
#' @keywords internal
#' 
imputing_missing <- function(wide_anchored, metadata){
  
  #Imputing missing values, we will need metadata for this task
  required_imputation_cols <- c(
    "variable_id",
    "is_expected_missing",
    "variable_type"
  )
  present_imputation_cols <- intersect(required_imputation_cols, names(metadata))
  missing_imputation_cols <- setdiff(required_imputation_cols, names(metadata))
  
  #Checking if any requiered imputation column is missing
  if (length(missing_imputation_cols) > 0L) {
    if (length(present_imputation_cols) > 0L) {
      warning(
        sprintf(
          paste(
            "Metadata is partially missing required imputation columns.",
            "Present: %s.",
            "Missing: %s.",
            "Skipping imputation."
          ),
          paste(present_imputation_cols, collapse = ", "),
          paste(missing_imputation_cols, collapse = ", ")
        )
      )
    }
  }else {
    #Imputing values
    for (i in seq_len(nrow(metadata))) {
      i_variable_id <- metadata$variable_id[[i]]
      i_is_expected_missing <- isTRUE(metadata$is_expected_missing[[i]])
      i_variable_type <- metadata$variable_type[[i]]
      value_col <- paste0("value_", i_variable_id)
      
      if (!value_col %in% names(wide_anchored) || i_is_expected_missing) {
        next
      }
      
      #Decision logic:
      # If variable is an boolean, then value = FALSE. Outcomes or boolean are by default false since the subject never had an diagnostic of that variable.
      # If variables is a categorical, then value = 0 We use 0 as category for missingness
      # If variable is an integer, then ignore
      
      if (i_variable_type %in% c("TF", "BOOL", "BOOLEAN", "LOGICAL")) {
        wide_anchored[is.na(get(value_col)), (value_col) := FALSE]
        wide_anchored[, (value_col) := as.logical(get(value_col))]
      } else if (i_variable_type %in% c("CAT", "FACTOR")) {
        wide_anchored[is.na(get(value_col)), (value_col) := 0]
      }
    }
  }
  wide_anchored
}
