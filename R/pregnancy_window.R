#' Constructor names backed by the episode window engine
#'
#' Used by `define_window()` to decide whether `episodes` must be supplied
#' and nested onto `population` before any constructor runs.
#' @keywords internal
EPISODE_CONSTRUCTORS <- c( # nolint: object_name_linter.
  "in_current_pregnancy",
  "in_prior_pregnancy",
  "in_current_and_prior",
  "outside_all_pregnancy"
)

#' Combine the Episodes table onto Population, one list-column per person
#'
#' Each population row gets its own person's episodes as a small
#' `data.table(start_episode, end_episode)`, forming a 3D structure so the.
#' Persons with no episodes get a zero-row table rather than `NULL`.
#'
#' @param population_dt A data.table with a `person_id` column.
#' @param episodes_dt A data.table with `person_id`, `start_episode`,
#'   `end_episode` columns (already validated).
#' @return `population_dt`, with `.episodes` added.
#' @keywords internal
nest_episodes_onto_population <- function(population_dt, episodes_dt) {
  population_dt[, .episodes := lapply(person_id, function(id) {
    episodes_dt[person_id == id, .(start_episode, end_episode)]
  })]
  population_dt[]
}

#' Compute the "outside all episodes" gap windows
#'
#' Within `[range_start, range_end]`, returns the parts that do not fall
#' inside any episode. An episode always fences the gaps around it, even one
#' that contains the anchor itself.
#'
#' @param episodes A data.table with `start_episode`/`end_episode` columns,
#'   one row per episode for a single person.
#' @param range_start,range_end The search range bounds (order-independent;
#'   the smaller/larger of the two is used as the range's lower/upper bound).
#' @return A data.table with `window_start`/`window_end` columns, one row
#'   per gap (possibly zero rows).
#' @keywords internal
outside_all_episode_gaps <- function(episodes, range_start, range_end) {
  search_bounds <- sort(as.Date(c(range_start, range_end)))
  range_start <- search_bounds[[1]]
  range_end <- search_bounds[[2]]

  overlapping <- episodes[
    end_episode >= range_start & start_episode <= range_end
  ]
  data.table::setorder(overlapping, start_episode)

  gap_starts <- vector("list", nrow(overlapping) + 1L)
  gap_ends <- vector("list", nrow(overlapping) + 1L)
  cursor <- range_start
  n_gaps <- 0L

  for (j in seq_len(nrow(overlapping))) {
    episode_start <- overlapping$start_episode[[j]]
    episode_end <- overlapping$end_episode[[j]]

    if (cursor < episode_start) {
      n_gaps <- n_gaps + 1L
      gap_starts[[n_gaps]] <- cursor
      gap_ends[[n_gaps]] <- episode_start - 1L
    }
    cursor <- max(cursor, episode_end + 1L)
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

#' Clamp a raw window boundary into an optional range around an episode edge
#'
#' `before_offset`/`after_offset` are independent and optional (`NA` means
#' "no clamp on that side"), and both are read the same way, as a signed
#' number of days from `edge`: `before_offset` stops `raw` from being
#' earlier than `edge + before_offset` (a floor), `after_offset` stops it
#' from being later than `edge + after_offset` (a cap). Applied in that
#' order, so if both are set and inconsistent (the floor lands after the
#' cap), the cap wins. `raw` may itself be `NA` (e.g. when the matching
#' `anchor_start_offset`/`anchor_end_offset` was left unset because the
#' window is meant to be derived purely from the episode, with no anchor
#' contribution at all): `pmax`/`pmin` are called with `na.rm = TRUE`, so an
#' `NA` `raw` simply drops out and the active clamp offset(s) alone
#' determine the result.
#'
#' @param raw The anchor-derived boundary before clamping (a Date vector,
#'   may contain `NA`).
#' @param edge The episode's own start or end date (a Date vector, same
#'   length as `raw`).
#' @param before_offset,after_offset Single integer offsets, or `NA` to skip
#'   that side's clamp.
#' @return `raw`, clamped.
#' @keywords internal
clamp_episode_boundary <- function(raw, edge, before_offset, after_offset) {
  out <- raw
  if (!is.na(before_offset)) {
    out <- pmax(out, edge + before_offset, na.rm = TRUE)
  }
  if (!is.na(after_offset)) {
    out <- pmin(out, edge + after_offset, na.rm = TRUE)
  }
  out
}

#' Episode-Based Window Engine
#'
#' Shared engine behind every episode-based constructor (`in_current_pregnancy`,
#' `in_prior_pregnancy`, `in_current_and_prior`, `outside_all_pregnancy`).
#' Each `window_dt` row carries that person's episodes in the `.episodes`
#' list-column (a data.table with `start_episode`/`end_episode` columns,
#' one row per episode), added by `nest_episodes_onto_population()`. One
#' input row can expand into zero, one, or many output rows, one per
#' candidate window.
#'
#' The current episode is the one containing the anchor
#' (`start_episode <= anchor <= end_episode`, where `anchor` is the row's
#' `anchor_start_col` value); this assumes a person's episodes don't
#' overlap. Prior episodes are defined relative to the *current* episode,
#' not directly relative to the anchor: `end_episode < current$start_episode`.
#' If there is no current episode, there are no prior episodes either.
#'
#' For `"CURRENT"`/`"PRIOR"`/`"CURRENT_AND_PRIOR"`, each selected episode's
#' window starts from `anchor_start_col + anchor_start_offset` and ends at
#' `anchor_end_col + anchor_end_offset`, then that raw boundary is clamped
#' into range around the episode's own start/end via
#' `before_start_episode_offset`/`after_start_episode_offset` (window start)
#' and `before_end_episode_offset`/`after_end_episode_offset` (window end);
#' see `clamp_episode_boundary()`. For `"OUTSIDE_ALL"`, it instead finds the
#' gaps *between all* of a person's episodes inside `[anchor_start_col +
#' anchor_start_offset, anchor_end_col + anchor_end_offset]` (the
#' before/after episode offsets are not used).
#'
#' @param window_dt A data.table produced by `cross_join_population_metadata()`,
#'   with `.episodes` already nested onto it.
#' @param episode_select One of `"CURRENT"`, `"PRIOR"`, `"CURRENT_AND_PRIOR"`,
#'   `"OUTSIDE_ALL"`.
#' @return A data.table with the same columns as `window_dt` plus
#'   `window_start`/`window_end`.
#' @keywords internal
pregnancy_window_engine <- function(window_dt, episode_select) {
  output_rows <- vector("list", nrow(window_dt))

  for (i in seq_len(nrow(window_dt))) {
    row <- window_dt[i]
    anchor_start_val <- row[[row$anchor_start_col]]
    anchor_end_val <- row[[row$anchor_end_col]]
    episodes <- data.table::as.data.table(row$.episodes[[1]])

    if (episode_select == "OUTSIDE_ALL") {
      windows <- outside_all_episode_gaps(
        episodes,
        anchor_start_val + row$anchor_start_offset,
        anchor_end_val + row$anchor_end_offset
      )
    } else {
      # Assumes a person's episodes don't overlap: "current" is whichever
      # episode contains the anchor, and "prior" is defined relative to
      # that one episode's own start, not directly relative to the anchor.
      current <- episodes[
        start_episode <= anchor_start_val & anchor_start_val <= end_episode
      ]
      prior <- if (nrow(current) == 0L) {
        episodes[0]
      } else {
        episodes[end_episode < current$start_episode[[1]]]
      }

      selected <- switch(episode_select,
        "CURRENT" = current,
        "PRIOR" = prior,
        "CURRENT_AND_PRIOR" = rbind(current, prior)
      )

      if (nrow(selected) == 0L) {
        next
      }

      window_start_raw <- rep(
        anchor_start_val + row$anchor_start_offset, nrow(selected)
      )
      window_end_raw <- rep(
        anchor_end_val + row$anchor_end_offset, nrow(selected)
      )

      window_start <- clamp_episode_boundary(
        window_start_raw,
        selected$start_episode,
        row$before_start_episode_offset,
        row$after_start_episode_offset
      )
      window_end <- clamp_episode_boundary(
        window_end_raw,
        selected$end_episode,
        row$before_end_episode_offset,
        row$after_end_episode_offset
      )

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
    # Even with no candidate windows at all, the result must still carry
    # window_start/window_end columns (empty), since downstream code (e.g.
    # finalize_windows()) always expects them to exist.
    return(cbind(
      window_dt[0],
      data.table::data.table(
        window_start = as.Date(character()), window_end = as.Date(character())
      )
    ))
  }

  data.table::rbindlist(non_empty, use.names = TRUE, fill = TRUE)[]
}

episode_required_cols <- c(
  "anchor_start_col", "anchor_end_col",
  "anchor_start_offset", "anchor_end_offset",
  "before_start_episode_offset", "after_start_episode_offset",
  "before_end_episode_offset", "after_end_episode_offset"
)

# Look for records in the episode containing the anchor date (T0).
in_current_pregnancy_window <- make_constructor(
  transform_fn = function(window_dt) {
    pregnancy_window_engine(window_dt, episode_select = "CURRENT")
  },
  required_cols = episode_required_cols,
  check_fn = generic_window_check
)

# Look for records in episodes that ended before the current episode began.
in_prior_pregnancy_window <- make_constructor(
  transform_fn = function(window_dt) {
    pregnancy_window_engine(window_dt, episode_select = "PRIOR")
  },
  required_cols = episode_required_cols,
  check_fn = generic_window_check
)

# Union of in_current_pregnancy_window and in_prior_pregnancy_window.
in_current_and_prior_window <- make_constructor(
  transform_fn = function(window_dt) {
    pregnancy_window_engine(window_dt, episode_select = "CURRENT_AND_PRIOR")
  },
  required_cols = episode_required_cols,
  check_fn = generic_window_check
)

# Look for records outside of every episode, i.e. in the gaps between them.
outside_all_pregnancy_window <- make_constructor(
  transform_fn = function(window_dt) {
    pregnancy_window_engine(window_dt, episode_select = "OUTSIDE_ALL")
  },
  required_cols = c(
    "anchor_start_col", "anchor_end_col",
    "anchor_start_offset", "anchor_end_offset"
  ),
  check_fn = generic_window_check
)
