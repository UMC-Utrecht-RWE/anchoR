#' Compute the "outside all events" gap windows
#'
#' Within `[anchor + start_offset, anchor + end_offset]`, returns the parts
#' that do not fall inside any event. An event always fences the gaps
#' around it, even one that contains `anchor` itself.
#'
#' @param events A data.table with `event_start`/`event_end` columns,
#'   one row per event for a single person.
#' @param anchor A single Date.
#' @param start_offset Integer offsets applied to `anchor` to get
#'   the overall search range (order-independent; the smaller of the two
#'   resulting dates is used as the range's lower bound).
#' @param end_offset Integer offsets applied to `anchor` to get
#'   the overall search range (order-independent; the larger of the two
#'   resulting dates is used as the range's upper bound).
#' @return A data.table with `window_start`/`window_end` columns, one row
#'   per gap (possibly zero rows).
#' @keywords internal
outside_all_event_gaps <- function(
  events, anchor, start_offset, end_offset
) {
  search_bounds <- sort(as.Date(c(anchor + start_offset, anchor + end_offset)))
  range_start <- search_bounds[[1]]
  range_end <- search_bounds[[2]]

  overlapping <- events[
    event_end >= range_start & event_start <= range_end
  ]
  data.table::setorder(overlapping, event_start)

  gap_starts <- vector("list", nrow(overlapping) + 1L)
  gap_ends <- vector("list", nrow(overlapping) + 1L)
  cursor <- range_start
  n_gaps <- 0L

  for (j in seq_len(nrow(overlapping))) {
    event_start <- overlapping$event_start[[j]]
    event_end <- overlapping$event_end[[j]]

    if (cursor < event_start) {
      n_gaps <- n_gaps + 1L
      gap_starts[[n_gaps]] <- cursor
      gap_ends[[n_gaps]] <- event_start - 1L
    }
    cursor <- max(cursor, event_end + 1L)
  }

  if (cursor <= range_end) {
    n_gaps <- n_gaps + 1L
    gap_starts[[n_gaps]] <- cursor
    gap_ends[[n_gaps]] <- range_end
  }

  data.table::data.table(
    window_start = as.Date(
      if (n_gaps) unlist(gap_starts[seq_len(n_gaps)]) else numeric(0)
    ),
    window_end = as.Date(
      if (n_gaps) unlist(gap_ends[seq_len(n_gaps)]) else numeric(0)
    )
  )
}

#' event-Based Window Engine
#'
#' Shared engine behind every event-based constructor (`IN_PRIOR_PREG`,
#' `SINCE_START_CURRENT_PREG`, `ANYTIME_CURRENT_PREG`, `OUTSIDE_ALL_PREG`).
#' Each `window_dt` row references, via its `event_col` value, a
#' population list-column holding that person's events (a data.table with
#' `event_start`/`event_end` columns, one row per event). One input
#' row can expand into zero, one, or many output rows -- one per candidate
#' window.
#'
#' @param window_dt A data.table produced by `cross_join_population_metadata()`.
#' @param event_select One of `"PRIOR"`, `"CURRENT"`, `"OUTSIDE_ALL"`.
#' @param end_boundary One of `"event_END"` or `"ANCHOR"`; only used when
#'   `event_select` is `"CURRENT"`.
#' @return A data.table with the same columns as `window_dt` (minus the
#'   `.window_row_id`-preserving columns, which are carried through
#'   unchanged) plus `window_start`/`window_end`.
#' @keywords internal
event_window_engine <- function(
  window_dt,
  event_select,
  end_boundary = "event_END"
) {
  output_rows <- vector("list", nrow(window_dt))

  for (i in seq_len(nrow(window_dt))) {
    row <- window_dt[i]
    anchor <- row[[row$anchor_start_col]]
    event_col <- row$event_col

    if (is.na(event_col) || !event_col %in% names(row)) {
      stop_log(
        sprintf(
          paste(
            "Metadata `event_col` ('%s') for variable_id '%s' does not",
            "name an existing population column."
          ),
          event_col,
          row$variable_id
        )
      )
    }

    events <- data.table::as.data.table(row[[event_col]][[1]])

    if (event_select == "OUTSIDE_ALL") {
      windows <- outside_all_event_gaps(
        events, anchor, row$start_offset, row$end_offset
      )
    } else {
      selected <- if (event_select == "PRIOR") {
        events[event_end < anchor]
      } else {
        events[event_start <= anchor & anchor <= event_end]
      }

      if (nrow(selected) == 0L) {
        next
      }

      window_start <- selected$event_start + row$start_offset
      window_end <- if (end_boundary == "ANCHOR") {
        rep(anchor + row$end_offset, nrow(selected))
      } else {
        selected$event_end + row$end_offset
      }

      if (!is.na(row$end_cap_offset)) {
        window_end <- pmin(
          window_end, selected$event_start + row$end_cap_offset
        )
      }

      if (event_select == "PRIOR") {
        # IN_PRIOR_PREG additionally clips every candidate window to the
        # anchor-relative lookback range [anchor + start_offset, anchor +
        # end_offset] (order-independent, same as OUTSIDE_ALL_PREG's search
        # bounds). A prior episode entirely outside that range yields
        # window_start > window_end, which finalize_windows() already marks
        # invalid and anchor()/anchor_by_variable() already filter out.
        lookback_bounds <- sort(
          as.Date(c(anchor + row$start_offset, anchor + row$end_offset))
        )
        window_start <- pmax(window_start, lookback_bounds[[1]])
        window_end <- pmin(window_end, lookback_bounds[[2]])
      }

      windows <- data.table::data.table(
        window_start = as.Date(window_start), window_end = as.Date(window_end)
      )
    }

    if (nrow(windows) == 0L) {
      next
    }

    output_rows[[i]] <- cbind(row[rep(1L, nrow(windows))], windows)
  }

  non_empty <- Filter(Negate(is.null), output_rows)

  if (length(non_empty) == 0L) {
    return(window_dt[0])
  }

  data.table::rbindlist(non_empty, use.names = TRUE, fill = TRUE)[]
}

# Look for records during (parts) of prior pregnancies,
# defined here only by start and end pregnancy
in_prior_preg_window <- make_constructor(
  transform_fn = function(window_dt) {
    event_window_engine(
      window_dt,
      event_select = "PRIOR", end_boundary = "event_END"
    )
  },
  required_cols = c(
    "event_col", "start_offset", "end_offset", "end_cap_offset",
    "anchor_start_col"
  ),
  check_fn = generic_window_check
)

# Look for records between start pregnancy and the anchor date (T0)
since_start_current_preg_window <- make_constructor( # nolint
  transform_fn = function(window_dt) {
    event_window_engine(
      window_dt,
      event_select = "CURRENT", end_boundary = "ANCHOR"
    )
  },
  required_cols = c(
    "event_col", "start_offset", "end_offset", "anchor_start_col"
  ),
  check_fn = generic_window_check
)

# Look for records between start_pregnancy and end_pregnancy + 30
anytime_current_preg_window <- make_constructor(
  transform_fn = function(window_dt) {
    event_window_engine(
      window_dt,
      event_select = "CURRENT", end_boundary = "event_END"
    )
  },
  required_cols = c(
    "event_col", "start_offset", "end_offset", "anchor_start_col"
  ),
  check_fn = generic_window_check
)

# Look for records outside of start_pregnancy and end_pregnancy dates,
# i.e., between consecutive end_pregnancy + 1 and start_pregnancy - 1
outside_all_preg_window <- make_constructor(
  transform_fn = function(window_dt) {
    event_window_engine(window_dt, event_select = "OUTSIDE_ALL")
  },
  required_cols = c(
    "event_col", "start_offset", "end_offset", "anchor_start_col"
  ),
  check_fn = generic_window_check
)
