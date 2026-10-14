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
#' @param start_episode,end_episode The episode's own bounds (single Dates).
#' @param before_start_offset,after_start_offset Single integer offsets (or
#'   `NA`) for the `start_episode` border.
#' @param before_end_offset,after_end_offset Single integer offsets (or
#'   `NA`) for the `end_episode` border.
#' @return A data.table with one or more rows of `window_start`/`window_end`.
#' @keywords internal
episode_windows <- function(
  start_episode, end_episode,
  before_start_offset, after_start_offset,
  before_end_offset, after_end_offset
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
#' @param window_dt A data.table produced by `cross_join_population_metadata()`,
#'   with `.episodes` already nested onto it.
#' @param episode_select One of `"CURRENT"`, `"PRIOR"`, `"CURRENT_AND_PRIOR"`,
#'   `"OUTSIDE_ALL"`.
#' @return A data.table with the same columns as `window_dt` plus
#'   `window_start`/`window_end`.
#' @keywords internal
pregnancy_window_engine <- function(window_dt, episode_select) {
  # Vectorized: instead of looping over `window_dt` one row at a time, every
  # row's episodes are stacked into one long table (one row per window_dt
  # row x episode, keyed by `.row`), and classification, window building,
  # capping and clipping all run as column operations on it.
  anchor_start_val <- episode_anchor_values(window_dt, "anchor_start_col")
  anchor_end_val <- episode_anchor_values(window_dt, "anchor_end_col")
  anchor_start_offset <- as.numeric(window_dt$anchor_start_offset)
  anchor_end_offset <- as.numeric(window_dt$anchor_end_offset)

  episodes <- stack_episodes(window_dt$.episodes)

  windows <- if (episode_select == "OUTSIDE_ALL") {
    outside_all_gaps_vectorized(
      episodes,
      anchor_start_val + anchor_start_offset,
      anchor_end_val + anchor_end_offset
    )
  } else {
    selected <- select_episodes_vectorized(
      episodes, anchor_start_val, episode_select
    )
    episode_windows_vectorized(selected, window_dt)
  }

  if (nrow(windows) == 0L) {
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

  # Hard anchor-relative boundary: each side only applies where its offset
  # is set.
  row_id <- windows$.row
  window_start <- windows$window_start
  window_end <- windows$window_end
  clip_start <- !is.na(anchor_start_offset[row_id])
  clip_end <- !is.na(anchor_end_offset[row_id])
  window_start[clip_start] <- pmax(
    window_start[clip_start],
    (anchor_start_val + anchor_start_offset)[row_id][clip_start]
  )
  window_end[clip_end] <- pmin(
    window_end[clip_end],
    (anchor_end_val + anchor_end_offset)[row_id][clip_end]
  )

  out <- window_dt[row_id]
  out[, `:=`(
    window_start = as.Date(window_start, origin = "1970-01-01"),
    window_end = as.Date(window_end, origin = "1970-01-01")
  )]
  out[]
}

#' Look up each row's anchor date from the column its metadata names
#'
#' @param window_dt A data.table with the column named by `col_col`.
#' @param col_col `"anchor_start_col"` or `"anchor_end_col"`.
#' @return A numeric vector (days since epoch), one value per row.
#' @keywords internal
episode_anchor_values <- function(window_dt, col_col) {
  anchor_cols <- window_dt[[col_col]]
  values <- rep(NA_real_, nrow(window_dt))
  for (col in unique(anchor_cols)) {
    idx <- which(anchor_cols == col)
    values[idx] <- as.numeric(window_dt[[col]][idx])
  }
  values
}

#' Stack every row's nested episodes into one long table
#'
#' @param episode_list The `.episodes` list-column of `window_dt`.
#' @return A data.table with `.row` (the `window_dt` row it came from), and
#'   numeric `start_episode`/`end_episode`, in the original episode order.
#' @keywords internal
stack_episodes <- function(episode_list) {
  # Pulling the two date vectors out and unlisting them is much cheaper than
  # `rbindlist()` over one small data.table per row.
  starts <- lapply(episode_list, `[[`, "start_episode")
  ends <- lapply(episode_list, `[[`, "end_episode")
  data.table::data.table(
    .row = rep.int(seq_along(episode_list), lengths(starts)),
    start_episode = as.numeric(unlist(starts, use.names = FALSE)),
    end_episode = as.numeric(unlist(ends, use.names = FALSE))
  )
}

#' Classify and select episodes for every row at once
#'
#' Vectorized `classify_episodes()` + the `episode_select` switch: an
#' episode is "current" when it contains the anchor; prior/future
#' are relative to the row's first current episode, or to the anchor when
#' the row has none.
#'
#' @param episodes Output of `stack_episodes()`.
#' @param anchor Numeric anchor per `window_dt` row.
#' @param episode_select `"CURRENT"`, `"PRIOR"` or `"CURRENT_AND_PRIOR"`.
#' @return The selected episodes, ordered by row, then current before prior,
#'   then original episode order.
#' @keywords internal
select_episodes_vectorized <- function(episodes, anchor, episode_select) {
  episode_anchor <- anchor[episodes$.row]
  start_episode <- episodes$start_episode
  end_episode <- episodes$end_episode
  is_current <- start_episode <= episode_anchor &
    episode_anchor <= end_episode

  # Each row's first current episode (in episode order) sets the reference
  # bounds for prior/future, as `classify_episodes()` does.
  current_idx <- which(is_current)
  first_current <- current_idx[!duplicated(episodes$.row[current_idx])]
  current_start <- rep(NA_real_, length(anchor))
  current_end <- rep(NA_real_, length(anchor))
  current_start[episodes$.row[first_current]] <- start_episode[first_current]
  current_end[episodes$.row[first_current]] <- end_episode[first_current]
  current_start <- current_start[episodes$.row]
  current_end <- current_end[episodes$.row]

  episode_class <- data.table::fifelse(
    is_current, "current",
    data.table::fifelse(
      !is.na(current_start),
      data.table::fifelse(
        end_episode < current_start, "prior",
        data.table::fifelse(
          start_episode > current_end, "future", NA_character_
        )
      ),
      data.table::fifelse(
        end_episode < episode_anchor, "prior",
        data.table::fifelse(
          start_episode > episode_anchor, "future", NA_character_
        )
      )
    )
  )

  select_rank <- switch(episode_select,
    "CURRENT" = c(current = 1L),
    "PRIOR" = c(prior = 1L),
    "CURRENT_AND_PRIOR" = c(current = 1L, prior = 2L)
  )
  rank <- unname(select_rank[episode_class])
  keep <- which(!is.na(rank))

  selected <- episodes[keep]
  selected[, .rank := rank[keep]]
  # Stable sort: keeps original episode order within the same row and rank.
  data.table::setorder(selected, .row, .rank)
  selected[, .rank := NULL]
  selected[]
}

#' Build border-offset windows for every selected episode at once
#'
#' Vectorized `episode_windows()` (same rules, same errors) plus the
#' `cap_start_to_episode`/`cap_end_to_episode` caps.
#'
#' @param selected Output of `select_episodes_vectorized()`.
#' @param window_dt The engine's input, for the per-row offsets and caps.
#' @return A data.table with `.row`, `window_start`, `window_end` (numeric),
#'   ordered by row, then selected episode, then region (start, end, shared).
#' @keywords internal
episode_windows_vectorized <- function(selected, window_dt) {
  row_id <- selected$.row
  start_episode <- selected$start_episode
  end_episode <- selected$end_episode

  before_start <- as.numeric(window_dt$before_start_episode_offset)[row_id]
  after_start <- as.numeric(window_dt$after_start_episode_offset)[row_id]
  before_end <- as.numeric(window_dt$before_end_episode_offset)[row_id]
  after_end <- as.numeric(window_dt$after_end_episode_offset)[row_id]

  start_has_before <- !is.na(before_start)
  start_has_after <- !is.na(after_start)
  end_has_before <- !is.na(before_end)
  end_has_after <- !is.na(after_end)
  start_full <- start_has_before & start_has_after
  end_full <- end_has_before & end_has_after
  start_empty <- !start_has_before & !start_has_after
  end_empty <- !end_has_before & !end_has_after
  shared_mode <- (start_has_before & !start_full) |
    (end_has_after & !end_full)
  start_inner_only <- !start_full & !start_empty & !shared_mode
  end_inner_only <- !end_full & !end_empty & !shared_mode

  # Same checks, in the same order, as `episode_windows()`.
  bad_start_full <- start_full & before_start > after_start
  bad_end_full <- end_full & before_end > after_end
  bad_start_inner <- start_inner_only & after_start < 0
  bad_end_inner <- end_inner_only & before_end > 0
  bad <- which(bad_start_full | bad_end_full | bad_start_inner | bad_end_inner)
  if (length(bad) > 0L) {
    first <- bad[[1]]
    if (bad_start_full[first] ||
          (!bad_end_full[first] && bad_start_inner[first])) {
      stop_log(
        paste(
          "`before_start_episode_offset` must not be later than",
          "`after_start_episode_offset`."
        )
      )
    }
    stop_log(
      paste(
        "`before_end_episode_offset` must not be later than",
        "`after_end_episode_offset`."
      )
    )
  }

  # Region 1: the start border; region 2: the end border; region 3: the
  # shared window (also used for "nothing set": the unshifted episode span).
  in_start <- start_full | start_inner_only
  in_end <- end_full | end_inner_only
  in_shared <- shared_mode | (start_empty & end_empty)

  start_point <- data.table::fifelse(
    !start_full & start_has_before, before_start,
    data.table::fifelse(!start_full & start_has_after, after_start, 0)
  )
  end_point <- data.table::fifelse(
    !end_full & end_has_after, after_end,
    data.table::fifelse(!end_full & end_has_before, before_end, 0)
  )

  episode_seq <- seq_along(row_id)
  region_dt <- function(keep, region, window_start, window_end) {
    data.table::data.table(
      .row = row_id[keep], .episode = episode_seq[keep], .region = region,
      window_start = window_start[keep], window_end = window_end[keep]
    )
  }
  windows <- data.table::rbindlist(list(
    region_dt(
      in_start, 1L,
      start_episode + data.table::fifelse(start_full, before_start, 0),
      start_episode + after_start
    ),
    region_dt(
      in_end, 2L,
      end_episode + before_end,
      end_episode + data.table::fifelse(end_full, after_end, 0)
    ),
    region_dt(
      in_shared, 3L,
      start_episode + start_point,
      end_episode + end_point
    )
  ))
  data.table::setorder(windows, .episode, .region)

  cap_flag <- function(x) {
    if (is.logical(x)) x %in% TRUE else rep(FALSE, nrow(window_dt))
  }
  cap_start <- cap_flag(window_dt$cap_start_to_episode)[windows$.row]
  cap_end <- cap_flag(window_dt$cap_end_to_episode)[windows$.row]
  windows[
    cap_start,
    window_start := pmax(window_start, start_episode[.episode])
  ]
  windows[
    cap_end,
    window_end := pmin(window_end, end_episode[.episode])
  ]

  windows[, c(".episode", ".region") := NULL]
  windows[]
}

#' Compute the "outside all episodes" gaps for every row at once
#'
#' Within each row's search range, returns the parts not covered by any of
#' that row's episodes. An episode always fences the gaps around it, even
#' one that contains the anchor itself.
#'
#' @param episodes Output of `stack_episodes()`.
#' @param range_a,range_b Numeric search range bounds per `window_dt` row
#'   (order-independent).
#' @return A data.table with `.row`, `window_start`, `window_end` (numeric),
#'   ordered by row, then gap position.
#' @keywords internal
outside_all_gaps_vectorized <- function(episodes, range_a, range_b) {
  range_start <- pmin(range_a, range_b)
  range_end <- pmax(range_a, range_b)

  overlapping <- episodes[which(
    episodes$end_episode >= range_start[episodes$.row] &
      episodes$start_episode <= range_end[episodes$.row]
  )]
  data.table::setorder(overlapping, .row, start_episode)

  # `covered_until` = day after the latest episode end seen so far in the
  # row; `cursor` = first day not yet covered before each episode (the range
  # start, or the previous episode's `covered_until`).
  row_id <- overlapping$.row
  covered_until <- cummax_by_row(overlapping$end_episode + 1, row_id)
  first_in_row <- !duplicated(row_id)
  previous_covered <- c(-Inf, covered_until[-length(covered_until)])
  previous_covered[first_in_row] <- -Inf
  cursor <- pmax(range_start[row_id], previous_covered)

  has_gap <- which(cursor < overlapping$start_episode)
  inner <- data.table::data.table(
    .row = row_id[has_gap],
    .gap = has_gap,
    window_start = cursor[has_gap],
    window_end = overlapping$start_episode[has_gap] - 1
  )

  # Trailing gap: from after the last covered day (or the range start, when
  # no episode overlaps) up to the range end.
  final_cursor <- range_start
  last_in_row <- which(!duplicated(row_id, fromLast = TRUE))
  final_cursor[row_id[last_in_row]] <- pmax(
    range_start[row_id[last_in_row]], covered_until[last_in_row]
  )
  trailing_rows <- which(
    !is.na(final_cursor) & !is.na(range_end) & final_cursor <= range_end
  )
  trailing <- data.table::data.table(
    .row = trailing_rows,
    .gap = Inf,
    window_start = final_cursor[trailing_rows],
    window_end = range_end[trailing_rows]
  )

  gaps <- data.table::rbindlist(list(inner, trailing))
  data.table::setorder(gaps, .row, .gap)
  gaps[, .gap := NULL]
  gaps[]
}

#' Running maximum that restarts at each new row id
#'
#' Equivalent to `ave(x, row_id, FUN = cummax)` for `row_id` sorted
#' ascending, without grouping: each value is lifted by `row_id * span`, so
#' one global `cummax()` can never carry a value over from an earlier row.
#' That is exact only for whole numbers, so fractional input (episode dates
#' shifted by fractional offsets) falls back to a grouped `cummax()`.
#'
#' @param x Numeric vector.
#' @param row_id Integer row ids, sorted ascending, same length as `x`.
#' @return Numeric vector, the running max of `x` within each row id.
#' @keywords internal
cummax_by_row <- function(x, row_id) {
  if (length(x) == 0L) {
    return(numeric(0))
  }
  if (any(x != floor(x))) {
    return(stats::ave(x, row_id, FUN = cummax))
  }
  low <- min(x)
  span <- max(x) - low + 1
  lift <- row_id * span
  cummax(x - low + lift) - lift + low
}

episode_required_cols <- c(
  "anchor_start_col", "anchor_end_col",
  "anchor_start_offset", "anchor_end_offset",
  "before_start_episode_offset", "after_start_episode_offset",
  "before_end_episode_offset", "after_end_episode_offset",
  "cap_start_to_episode", "cap_end_to_episode"
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
