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
#' `data.table(start_episode, end_episode)`, forming a '3D structure' so the.
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

#' Classify a person's episodes relative to the anchor
#'
#' The "current" episode is the one containing `anchor` (assumes a person's
#' episodes don't overlap). "Prior"/"future" are normally relative to that
#' one current episode's own bounds: an episode entirely before the current
#' one's start is "prior", one entirely after the current one's end is
#' "future". If there is no current episode at all, prior/future fall back
#' to being directly relative to `anchor` itself (ended before it / starts
#' after it).
#'
#' Never mutates `episodes`: the input's list-column element may be shared
#' (by reference) across several `window_dt` rows for the same person, so
#' this always returns a freshly built table instead of adding a column to
#' the one it was given.
#'
#' @param episodes A data.table with `start_episode`/`end_episode` columns,
#'   one row per episode for a single person.
#' @param anchor A single Date.
#' @return A new data.table with `start_episode`/`end_episode`/
#'   `episode_class` columns, `episode_class` one of `"current"`,
#'   `"prior"`, `"future"`, or `NA` (an episode that is none of the three,
#'   e.g. one that overlaps the current episode despite the no-overlap
#'   assumption).
#' @keywords internal
classify_episodes <- function(episodes, anchor) {
  is_current <-
    episodes$start_episode <= anchor & anchor <= episodes$end_episode
  current <- episodes[is_current]

  if (nrow(current) > 0L) {
    current_start <- current$start_episode[[1]]
    current_end <- current$end_episode[[1]]
    episode_class <- data.table::fifelse(
      is_current, "current",
      data.table::fifelse(
        episodes$end_episode < current_start, "prior",
        data.table::fifelse(
          episodes$start_episode > current_end, "future", NA_character_
        )
      )
    )
  } else {
    # No current episode: fall back to anchor-relative prior/future.
    episode_class <- data.table::fifelse(
      episodes$end_episode < anchor, "prior",
      data.table::fifelse(
        episodes$start_episode > anchor, "future", NA_character_
      )
    )
  }

  data.table::data.table(
    start_episode = episodes$start_episode,
    end_episode = episodes$end_episode,
    episode_class = episode_class
  )
}

#' Compute the window(s) one episode contributes, from its border offsets
#'
#' Each pair: `before_start_offset`/`after_start_offset` for
#' `start_episode`, `before_end_offset`/`after_end_offset` for `end_episode`.
#' It is read as up to two independent borders relative to that edge:
#' `edge + offset` (`0` means the border sits exactly on the edge; `NA`
#' means that particular border isn't set). A pair with **both** sides set
#' becomes its own self-contained region, `[edge + before_offset,
#' edge + after_offset]` (a single calendar day when both offsets are `0`);
#' `before_offset` must not be later than `after_offset`, or that region
#' would be inverted, which is an error.
#'
#' What happens with the *other* pair depends on whether either pair forms
#' a region:
#' - **Neither pair fully specified**: both edges contribute to one shared
#'   window, an edge with neither side set contributes `edge` itself,
#'   unshifted; one with exactly one side set contributes `edge + that
#'   offset` (whichever side, no ambiguity with only one value).
#' - **Exactly one pair fully specified**: that pair's region is the only
#'   output; the other pair (whether fully unset or only partially set)
#'   contributes nothing.
#' - **Both pairs fully specified**: two regions, one per pair.
#'
#' @param start_episode,end_episode The episode's own bounds (single Dates).
#' @param before_start_offset,after_start_offset Single integer offsets (or
#'   `NA`) for the `start_episode` border.
#' @param before_end_offset,after_end_offset Single integer offsets (or
#'   `NA`) for the `end_episode` border.
#' @return A data.table with one or two rows of `window_start`/`window_end`.
#' @keywords internal
episode_windows <- function(
  start_episode, end_episode,
  before_start_offset, after_start_offset,
  before_end_offset, after_end_offset
) {
  start_both_set <- !is.na(before_start_offset) && !is.na(after_start_offset)
  end_both_set <- !is.na(before_end_offset) && !is.na(after_end_offset)

  if (start_both_set && before_start_offset > after_start_offset) {
    stop_log(
      paste(
        "`before_start_episode_offset` must not be later than",
        "`after_start_episode_offset`."
      )
    )
  }
  if (end_both_set && before_end_offset > after_end_offset) {
    stop_log(
      paste(
        "`before_end_episode_offset` must not be later than",
        "`after_end_episode_offset`."
      )
    )
  }

  if (start_both_set && end_both_set) {
    return(data.table::data.table(
      window_start = as.Date(c(
        start_episode + before_start_offset, end_episode + before_end_offset
      )),
      window_end = as.Date(c(
        start_episode + after_start_offset, end_episode + after_end_offset
      ))
    ))
  }

  if (start_both_set) {
    return(data.table::data.table(
      window_start = as.Date(start_episode + before_start_offset),
      window_end = as.Date(start_episode + after_start_offset)
    ))
  }
  if (end_both_set) {
    return(data.table::data.table(
      window_start = as.Date(end_episode + before_end_offset),
      window_end = as.Date(end_episode + after_end_offset)
    ))
  }

  # Neither pair fully specified: contribute to one shared window.
  start_offset <- if (!is.na(before_start_offset)) {
    before_start_offset
  } else if (!is.na(after_start_offset)) {
    after_start_offset
  } else {
    0
  }
  end_offset <- if (!is.na(before_end_offset)) {
    before_end_offset
  } else if (!is.na(after_end_offset)) {
    after_end_offset
  } else {
    0
  }

  data.table::data.table(
    window_start = as.Date(start_episode + start_offset),
    window_end = as.Date(end_episode + end_offset)
  )
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

#' Clip candidate windows to the project's hard anchor-relative boundary
#'
#' `anchor_start_offset`/`anchor_end_offset` define a hard boundary,
#' `[anchor_start_val + anchor_start_offset, anchor_end_val +
#' anchor_end_offset]`, that every episode-based window must fall inside,
#' regardless of constructor. Each side is applied independently and only
#' when not `NA` (the same convention the border-offset pairs use): a set
#' `anchor_start_offset` raises `window_start` up to at least the
#' boundary's lower edge; a set `anchor_end_offset` lowers `window_end`
#' down to at most the boundary's upper edge. A window entirely outside the
#' boundary comes out with `window_start > window_end`, left for
#' `finalize_windows()` to mark invalid, the same as any other empty
#' window; this function never drops rows itself.
#'
#' @param windows A data.table with `window_start`/`window_end` columns.
#' @param anchor_start_val,anchor_end_val The row's own anchor date(s)
#'   (single Dates), from `anchor_start_col`/`anchor_end_col`.
#' @param anchor_start_offset,anchor_end_offset Single offsets (or `NA`).
#' @return `windows`, with `window_start`/`window_end` clipped in place.
#' @keywords internal
clip_to_anchor_bounds <- function(
  windows, anchor_start_val, anchor_start_offset,
  anchor_end_val, anchor_end_offset
) {
  if (!is.na(anchor_start_offset)) {
    windows[
      , window_start := pmax(
        window_start, anchor_start_val + anchor_start_offset
      )
    ]
  }
  if (!is.na(anchor_end_offset)) {
    windows[
      , window_end := pmin(window_end, anchor_end_val + anchor_end_offset)
    ]
  }
  windows[]
}

#' Episode-Based Window Engine
#'
#' Shared engine behind every episode-based constructor.
#' Each `window_dt` row carries that person's episodes in the `.episodes`
#' list-column (a data.table with `start_episode`/`end_episode` columns,
#' one row per episode), added by `nest_episodes_onto_population()`. One
#' input row can expand into zero, one, or many output rows, one per
#' candidate window.
#'
#' For `"CURRENT"`/`"PRIOR"`/`"CURRENT_AND_PRIOR"`, episodes are first
#' classified relative to the anchor (see `classify_episodes()`), then each
#' selected episode independently contributes its own window(s) via
#' `episode_windows()`, purely from its own `start_episode`/`end_episode`
#' and the row's four border offsets. `"OUTSIDE_ALL"` is different: it
#' finds the gaps *between all* of a person's episodes inside
#' `[anchor_start_col + anchor_start_offset, anchor_end_col +
#' anchor_end_offset]` directly; the border offsets are not used.
#' Regardless of `episode_select`, every candidate window is then clipped
#' to that same `[anchor_start_col + anchor_start_offset, anchor_end_col +
#' anchor_end_offset]` boundary via `clip_to_anchor_bounds()` -- for
#' `"OUTSIDE_ALL"` this is a no-op (the gaps are already computed inside
#' that range), for the other three it's what makes `anchor_start_offset`/
#' `anchor_end_offset` a hard, constructor-independent time boundary.
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
      classified <- classify_episodes(episodes, anchor_start_val)
      current <- classified[episode_class == "current"]
      prior <- classified[episode_class == "prior"]

      selected <- switch(episode_select,
        "CURRENT" = current,
        "PRIOR" = prior,
        "CURRENT_AND_PRIOR" = rbind(current, prior)
      )

      if (nrow(selected) == 0L) {
        next
      }

      windows <- data.table::rbindlist(lapply(
        seq_len(nrow(selected)),
        function(j) {
          episode_windows(
            selected$start_episode[[j]], selected$end_episode[[j]],
            row$before_start_episode_offset, row$after_start_episode_offset,
            row$before_end_episode_offset, row$after_end_episode_offset
          )
        }
      ))
    }

    if (nrow(windows) == 0L) {
      next
    }

    windows <- clip_to_anchor_bounds(
      windows,
      anchor_start_val, row$anchor_start_offset,
      anchor_end_val, row$anchor_end_offset
    )

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
