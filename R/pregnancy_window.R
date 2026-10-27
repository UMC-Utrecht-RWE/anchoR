#' Constructor names backed by the episode window engine
#'
#' Used by `define_window()` to decide whether `episodes` must be supplied
#' and nested onto `population` before any constructor runs.
#' @keywords internal
# nolint next
EPISODE_CONSTRUCTORS <- c(
  "in_current_pregnancy",
  "in_prior_pregnancy",
  "in_current_and_prior",
  "outside_all_pregnancy"
)


#' Combine the Episodes table onto Population, one list-column per person
#'
#' Each population row gets its own person's episodes as a small
#' `data.table(start_episode, end_episode)`, in their original order.
#' Persons with no episodes get a zero-row table rather than `NULL`. Rows of
#' the same person share one table, so nothing downstream may modify it in
#' place.
#'
#' @param population_dt A data.table with a `person_id` column.
#' @param episodes_dt A data.table with `person_id`, `start_episode`,
#'   `end_episode` columns (already validated).
#' @return `population_dt`, with `.episodes` added.
#' @keywords internal
nest_episodes_onto_population <- function(population_dt, episodes_dt) {
  # One split() of the row indices, then a lookup per person: subsetting
  # `episodes_dt` once per person costs ~0.5 ms each. Each table is built
  # as a plain classed list: setDT() would reserve ~1000 spare column slots
  # (~8 KB) per person, which adds up to GBs on a full study. The tables are
  # only read, never modified with `:=`.
  starts <- episodes_dt$start_episode
  ends <- episodes_dt$end_episode
  by_person <- lapply(
    split(seq_len(nrow(episodes_dt)), as.character(episodes_dt$person_id)),
    function(i) {
      structure(
        list(start_episode = starts[i], end_episode = ends[i]),
        row.names = c(NA_integer_, -length(i)),
        class = c("data.table", "data.frame")
      )
    }
  )
  no_episodes <- episodes_dt[0L, .(start_episode, end_episode)]
  person_idx <- match(as.character(population_dt$person_id), names(by_person))
  population_dt[,
    .episodes := lapply(person_idx, function(i) {
      if (is.na(i)) no_episodes else by_person[[i]]
    })
  ]
  population_dt[]
}

#' Classify episodes relative to the anchor
#'
#' The "current" episode is the one containing `anchor` (assumes a person's
#' episodes don't overlap). "Prior"/"future" are normally relative to that
#' one current episode's own bounds: an episode entirely before the current
#' one's start is "prior", one entirely after the current one's end is
#' "future". If there is no current episode at all, prior/future fall back
#' to being directly relative to `anchor` itself (ended before it / starts
#' after it). When several episodes contain the anchor, the first one sets
#' the reference bounds.
#'
#' Works on one person's episodes or, with a `.row` column, on the stacked
#' episodes of many `window_dt` rows at once (see `stack_episodes()`), each
#' classified against its own row's anchor.
#'
#' @param episodes A data.table with `start_episode`/`end_episode` columns,
#'   one row per episode, and optionally `.row`.
#' @param anchor The anchor Date: a single value, or one per `.row`.
#' @return A copy of `episodes` with an `episode_class` column, one of
#'   `"current"`, `"prior"`, `"future"`, or `NA` (an episode that is none
#'   of the three, e.g. one that overlaps the current episode despite the
#'   no-overlap assumption).
#' @keywords internal
classify_episodes <- function(episodes, anchor) {
  row_id <- if (".row" %in% names(episodes)) {
    episodes$.row
  } else {
    rep(1L, nrow(episodes))
  }
  start_episode <- episodes$start_episode
  end_episode <- episodes$end_episode
  episode_anchor <- anchor[row_id]
  is_current <- start_episode <= episode_anchor &
    episode_anchor <= end_episode

  # Reference bounds per row: its first current episode, or the anchor
  # itself when it has none.
  ref_start <- anchor
  ref_end <- anchor
  current_idx <- which(is_current)
  first_current <- current_idx[!duplicated(row_id[current_idx])]
  ref_start[row_id[first_current]] <- start_episode[first_current]
  ref_end[row_id[first_current]] <- end_episode[first_current]

  classified <- data.table::copy(episodes)
  classified[,
    episode_class := data.table::fifelse(
      is_current %in% TRUE,
      "current",
      data.table::fifelse(
        end_episode < ref_start[row_id],
        "prior",
        data.table::fifelse(
          start_episode > ref_end[row_id],
          "future",
          NA_character_
        )
      )
    )
  ]
  classified[]
}

#' Compute the window(s) one episode contributes, from its border offsets
#'
#' Each pair: `before_start_offset`/`after_start_offset` for
#' `start_episode`, `before_end_offset`/`after_end_offset` for `end_episode`.
#' `before_start_offset` and `after_end_offset` are the *outer* sides (they
#' point away from the episode); `after_start_offset` and
#' `before_end_offset` are the *inner* sides (they point into it).
#'
#' Each pair's own contribution is decided independently:
#' - **Both sides set** ("full"): always its own self-contained region,
#'   `[edge + before_offset, edge + after_offset]`, regardless of what the
#'   other pair does. `before_offset` must not be later than
#'   `after_offset`, or the region would be inverted, which is an error.
#' - **Only its outer side set** (and not full): this pair wants to join a
#'   *shared window* instead of forming its own region -- see below.
#' - **Only its inner side set** (and not full): its own region, missing
#'   side defaulting to `0` -- *unless* the other pair's outer side is set
#'   (and that other pair isn't full either), in which case shared-window
#'   mode is active and this pair's single value is used as a plain point
#'   in that shared window instead of forming its own region.
#' - **Nothing set**: contributes nothing of its own; if shared-window mode
#'   is active, it contributes the unshifted edge as that window's point.
#'
#' Shared-window mode triggers whenever *either* pair's only set side is
#' its outer one (and that pair isn't full); when it triggers, every
#' non-full pair contributes a single point to one shared window (its own
#' set side if it has exactly one, or the unshifted edge if it has none) --
#' this is the only way one pair's value and the other pair's value
#' combine into a single window. A full pair never joins the shared
#' window; it always keeps its own separate region alongside it.
#'
#' If neither pair has anything set at all, the result is one shared
#' window: the episode's own unshifted span, `[start_episode,
#' end_episode]`.
#'
#' @param start_episode,end_episode The episode's own bounds: Dates, one
#'   value per episode. Several episodes can be passed at once when they
#'   share the same offsets.
#' @param before_start_offset,after_start_offset Single integer offsets (or
#'   `NA`) for the `start_episode` border.
#' @param before_end_offset,after_end_offset Single integer offsets (or
#'   `NA`) for the `end_episode` border.
#' @return A data.table of `window_start`/`window_end`: one block of rows
#'   per region (start border, end border, shared window, in that order, each
#'   only when it applies), with one row per episode in each block.
#' @keywords internal
episode_windows <- function(
  start_episode,
  end_episode,
  before_start_offset,
  after_start_offset,
  before_end_offset,
  after_end_offset
) {
  start_has_before <- !is.na(before_start_offset)
  start_has_after <- !is.na(after_start_offset)
  end_has_before <- !is.na(before_end_offset)
  end_has_after <- !is.na(after_end_offset)

  start_full <- start_has_before && start_has_after
  end_full <- end_has_before && end_has_after
  start_empty <- !start_has_before && !start_has_after
  end_empty <- !end_has_before && !end_has_after

  if (start_full && before_start_offset > after_start_offset) {
    stop_log(
      paste(
        "`before_start_episode_offset` must not be later than",
        "`after_start_episode_offset`."
      )
    )
  }
  if (end_full && before_end_offset > after_end_offset) {
    stop_log(
      paste(
        "`before_end_episode_offset` must not be later than",
        "`after_end_episode_offset`."
      )
    )
  }

  if (start_empty && end_empty) {
    # Neither pair has anything set: whole unshifted episode span.
    return(data.table::data.table(
      window_start = as.Date(start_episode),
      window_end = as.Date(end_episode)
    ))
  }

  # A non-full pair's outer side, set alone, pulls the whole computation
  # into shared-window mode; a full pair never triggers it (it already has
  # its own region).
  start_triggers_shared <- start_has_before && !start_full
  end_triggers_shared <- end_has_after && !end_full
  shared_mode <- start_triggers_shared || end_triggers_shared

  regions <- vector("list", 3L)

  if (start_full) {
    regions[[1]] <- data.table::data.table(
      window_start = as.Date(start_episode + before_start_offset),
      window_end = as.Date(start_episode + after_start_offset)
    )
  } else if (!start_empty && !shared_mode) {
    # Inner side alone (after_start_offset), shared mode not active: its
    # own region, missing (outer) side defaulting to 0.
    before <- 0
    after <- after_start_offset
    if (before > after) {
      stop_log(
        paste(
          "`before_start_episode_offset` must not be later than",
          "`after_start_episode_offset`."
        )
      )
    }
    regions[[1]] <- data.table::data.table(
      window_start = as.Date(start_episode + before),
      window_end = as.Date(start_episode + after)
    )
  }

  if (end_full) {
    regions[[2]] <- data.table::data.table(
      window_start = as.Date(end_episode + before_end_offset),
      window_end = as.Date(end_episode + after_end_offset)
    )
  } else if (!end_empty && !shared_mode) {
    # Inner side alone (before_end_offset), shared mode not active: its
    # own region, missing (outer) side defaulting to 0.
    before <- before_end_offset
    after <- 0
    if (before > after) {
      stop_log(
        paste(
          "`before_end_episode_offset` must not be later than",
          "`after_end_episode_offset`."
        )
      )
    }
    regions[[2]] <- data.table::data.table(
      window_start = as.Date(end_episode + before),
      window_end = as.Date(end_episode + after)
    )
  }

  if (shared_mode) {
    # Only non-full pairs participate: their one set side (or the
    # unshifted edge, if empty) becomes the shared window's point. A full
    # pair already got its own region above and sits this out.
    start_point <- if (start_full) {
      NA_real_
    } else if (start_has_before) {
      before_start_offset
    } else if (start_has_after) {
      after_start_offset
    } else {
      0
    }
    end_point <- if (end_full) {
      NA_real_
    } else if (end_has_after) {
      after_end_offset
    } else if (end_has_before) {
      before_end_offset
    } else {
      0
    }
    regions[[3]] <- data.table::data.table(
      window_start = as.Date(
        start_episode + (if (is.na(start_point)) 0 else start_point)
      ),
      window_end = as.Date(
        end_episode + (if (is.na(end_point)) 0 else end_point)
      )
    )
  }

  data.table::rbindlist(Filter(Negate(is.null), regions))
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
#' and the row's four border offsets. Each of those windows is then
#' optionally capped to the *selected episode's own bounds*: when
#' `cap_start_to_episode` is `TRUE`, `window_start` is raised up to at
#' least that episode's `start_episode`; when `cap_end_to_episode` is
#' `TRUE`, `window_end` is lowered down to at most that episode's
#' `end_episode`. Both default to `NA`/unset (no change from the
#' border-offset formula's own result). `"OUTSIDE_ALL"` is different: it
#' finds the gaps *between all* of a person's episodes inside
#' `[anchor_start_col + anchor_start_offset, anchor_end_col +
#' anchor_end_offset]` directly; the border offsets and the two capping
#' flags are not used.
#' Regardless of `episode_select`, every candidate window is then clipped
#' to that same `[anchor_start_col + anchor_start_offset, anchor_end_col +
#' anchor_end_offset]` boundary -- for `"OUTSIDE_ALL"` this is a no-op (the
#' gaps are already computed inside that range), for the other three it's
#' what makes `anchor_start_offset`/`anchor_end_offset` a hard,
#' constructor-independent time boundary. Each side only applies when its
#' offset is not `NA`; a window entirely outside the boundary comes out with
#' `window_start > window_end`, left for `finalize_windows()` to mark
#' invalid.
#'
#' Output rows follow `window_dt`'s row order; within a row, current
#' episodes come before prior ones, then episodes in their original order,
#' then regions in `episode_windows()` order.
#'
#' @param window_dt A data.table produced by `cross_join_population_metadata()`,
#'   with `.episodes` already nested onto it.
#' @param episode_select One of `"CURRENT"`, `"PRIOR"`, `"CURRENT_AND_PRIOR"`,
#'   `"OUTSIDE_ALL"`.
#' @return A data.table with the same columns as `window_dt` plus
#'   `window_start`/`window_end`.
#' @keywords internal
pregnancy_window_engine <- function(window_dt, episode_select) {
  # Every row's episodes are stacked into one long table keyed by `.row`, so
  # the work runs on whole columns instead of one `window_dt` row at a time.
  anchor_start_val <- episode_anchor_values(window_dt, "anchor_start_col")
  anchor_end_val <- episode_anchor_values(window_dt, "anchor_end_col")
  anchor_start_offset <- window_dt$anchor_start_offset
  anchor_end_offset <- window_dt$anchor_end_offset
  range_start <- anchor_start_val + anchor_start_offset
  range_end <- anchor_end_val + anchor_end_offset

  episodes <- stack_episodes(window_dt$.episodes)

  windows <- if (episode_select == "OUTSIDE_ALL") {
    outside_all_gaps(episodes, range_start, range_end)
  } else {
    selected <- select_episodes(episodes, anchor_start_val, episode_select)
    border_offset_windows(selected, window_dt)
  }

  # Hard anchor-relative boundary: each side only applies where its offset
  # is set.
  row_id <- windows$.row
  clip_start <- !is.na(anchor_start_offset[row_id])
  clip_end <- !is.na(anchor_end_offset[row_id])
  windows[clip_start, window_start := pmax(window_start, range_start[.row])]
  windows[clip_end, window_end := pmin(window_end, range_end[.row])]

  # Even with no candidate windows at all, the result still carries empty
  # window_start/window_end columns, since downstream code (e.g.
  # finalize_windows()) always expects them to exist.
  out <- window_dt[row_id]
  out[, `:=`(
    window_start = as.Date(windows$window_start),
    window_end = as.Date(windows$window_end)
  )]
  out[]
}

#' Look up each row's anchor date from the column its metadata names
#'
#' @param window_dt A data.table with the column named by `col_col`.
#' @param col_col `"anchor_start_col"` or `"anchor_end_col"`.
#' @return A Date vector, one value per row.
#' @keywords internal
episode_anchor_values <- function(window_dt, col_col) {
  anchor_cols <- window_dt[[col_col]]
  values <- rep(as.Date(NA), nrow(window_dt))
  for (col in unique(anchor_cols)) {
    idx <- which(anchor_cols == col)
    values[idx] <- as.Date(window_dt[[col]][idx])
  }
  values
}

#' Stack every row's nested episodes into one long table
#'
#' @param episode_list The `.episodes` list-column of `window_dt`.
#' @return A data.table with `.row` (the `window_dt` row it came from) and
#'   `start_episode`/`end_episode` Dates, in the original episode order.
#' @keywords internal
stack_episodes <- function(episode_list) {
  # Pulling the two date vectors out and unlisting them is much cheaper than
  # `rbindlist()` over one small data.table per row.
  starts <- lapply(episode_list, .subset2, "start_episode")
  ends <- lapply(episode_list, .subset2, "end_episode")
  data.table::data.table(
    .row = rep.int(seq_along(episode_list), lengths(starts)),
    start_episode = as.Date(unlist(starts, use.names = FALSE)),
    end_episode = as.Date(unlist(ends, use.names = FALSE))
  )
}

#' Keep the episodes `episode_select` asks for
#'
#' @param episodes Output of `stack_episodes()`.
#' @param anchor Anchor Date per `window_dt` row.
#' @param episode_select `"CURRENT"`, `"PRIOR"` or `"CURRENT_AND_PRIOR"`.
#' @return The selected episodes, ordered by row, then current before prior,
#'   then original episode order.
#' @keywords internal
select_episodes <- function(episodes, anchor, episode_select) {
  select_rank <- switch(
    episode_select,
    "CURRENT" = c(current = 1L),
    "PRIOR" = c(prior = 1L),
    "CURRENT_AND_PRIOR" = c(current = 1L, prior = 2L)
  )
  selected <- classify_episodes(episodes, anchor)
  selected[, .rank := unname(select_rank[episode_class])]
  selected <- selected[!is.na(.rank)]
  # Stable sort: keeps original episode order within the same row and rank.
  data.table::setorder(selected, .row, .rank)
  selected[, c(".rank", "episode_class") := NULL]
  selected[]
}

#' Build the border-offset windows of every selected episode
#'
#' The offsets and caps come from metadata, so all persons of one variable
#' share them. Each distinct setting is handled in one `episode_windows()`
#' call over all of its episodes, then capped.
#'
#' @param selected Output of `select_episodes()`.
#' @param window_dt The engine's input, for the per-row offsets and caps.
#' @return A data.table with `.row`, `window_start`, `window_end`, ordered
#'   by selected episode, then region.
#' @keywords internal
border_offset_windows <- function(selected, window_dt) {
  setting_cols <- c(
    "before_start_episode_offset",
    "after_start_episode_offset",
    "before_end_episode_offset",
    "after_end_episode_offset",
    "cap_start_to_episode",
    "cap_end_to_episode"
  )
  settings <- window_dt[selected$.row, setting_cols, with = FALSE]
  # Groups in order of first appearance, so an inverted-offset error is
  # raised for the earliest row that has one.
  settings[, .grp := .GRP, by = setting_cols]
  groups <- split(seq_len(nrow(selected)), settings$.grp)

  windows <- lapply(groups, function(idx) {
    setting <- settings[idx[[1]]]
    start_episode <- selected$start_episode[idx]
    end_episode <- selected$end_episode[idx]
    w <- episode_windows(
      start_episode,
      end_episode,
      setting$before_start_episode_offset,
      setting$after_start_episode_offset,
      setting$before_end_episode_offset,
      setting$after_end_episode_offset
    )
    # Each region block holds one row per episode, in `idx` order.
    n_regions <- nrow(w) %/% length(idx)
    w[, .episode := rep(idx, n_regions)]
    if (isTRUE(setting$cap_start_to_episode)) {
      w[, window_start := pmax(window_start, rep(start_episode, n_regions))]
    }
    if (isTRUE(setting$cap_end_to_episode)) {
      w[, window_end := pmin(window_end, rep(end_episode, n_regions))]
    }
    w
  })

  windows <- data.table::rbindlist(
    c(list(empty_windows()), unname(windows)),
    use.names = TRUE
  )
  # Stable sort: regions keep their episode_windows() order per episode.
  data.table::setorder(windows, .episode)
  windows[, .row := selected$.row[.episode]]
  windows[, .episode := NULL]
  windows[]
}

#' Find the "outside all episodes" gaps of every row
#'
#' Within each row's search range, returns the parts not covered by any of
#' that row's episodes. An episode always fences the gaps around it, even
#' one that contains the anchor itself.
#'
#' @param episodes Output of `stack_episodes()`.
#' @param range_a,range_b Search range bounds per `window_dt` row
#'   (order-independent).
#' @return A data.table with `.row`, `window_start`, `window_end`, ordered
#'   by row, then gap position.
#' @keywords internal
outside_all_gaps <- function(episodes, range_a, range_b) {
  range_start <- pmin(range_a, range_b)
  range_end <- pmax(range_a, range_b)

  overlapping <- episodes[
    end_episode >= range_start[.row] & start_episode <= range_end[.row]
  ]
  data.table::setorder(overlapping, .row, start_episode)
  # Walking each row's episodes in start order: `covered_until` is the day
  # after the latest end so far, `cursor` the first day not yet covered
  # before this episode.
  # Plain-column calls, so data.table runs the grouped cummax()/shift() in C.
  overlapping[, covered_until := as.numeric(end_episode) + 1]
  overlapping[, covered_until := cummax(covered_until), by = .row]
  overlapping[, cursor := data.table::shift(covered_until), by = .row]
  overlapping[,
    cursor := pmax(
      as.numeric(range_start[.row]),
      cursor,
      na.rm = TRUE
    )
  ]

  inner <- overlapping[
    cursor < start_episode,
    .(
      .row,
      .gap = .I,
      window_start = cursor,
      window_end = as.numeric(start_episode) - 1
    )
  ]

  # Trailing gap: after the last covered day (or from the range start, when
  # no episode overlaps) up to the range end.
  last <- overlapping[, .(covered_until = covered_until[.N]), by = .row]
  final_cursor <- as.numeric(range_start)
  final_cursor[last$.row] <- pmax(final_cursor[last$.row], last$covered_until)
  trailing_rows <- which(final_cursor <= range_end)
  trailing <- data.table::data.table(
    .row = trailing_rows,
    .gap = Inf,
    window_start = final_cursor[trailing_rows],
    window_end = as.numeric(range_end[trailing_rows])
  )

  gaps <- data.table::rbindlist(list(inner, trailing))
  data.table::setorder(gaps, .row, .gap)
  gaps[, .gap := NULL]
  gaps[, `:=`(
    window_start = as.Date(window_start, origin = "1970-01-01"),
    window_end = as.Date(window_end, origin = "1970-01-01")
  )]
  gaps[]
}

#' Zero-row windows table, typed like the engine's internal windows
#' @keywords internal
empty_windows <- function() {
  data.table::data.table(
    window_start = as.Date(character()),
    window_end = as.Date(character()),
    .episode = integer()
  )
}

episode_required_cols <- c(
  "anchor_start_col",
  "anchor_end_col",
  "anchor_start_offset",
  "anchor_end_offset",
  "before_start_episode_offset",
  "after_start_episode_offset",
  "before_end_episode_offset",
  "after_end_episode_offset",
  "cap_start_to_episode",
  "cap_end_to_episode"
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
    "anchor_start_col",
    "anchor_end_col",
    "anchor_start_offset",
    "anchor_end_offset"
  ),
  check_fn = generic_window_check
)
