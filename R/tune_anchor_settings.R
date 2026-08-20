#' Build the grid of `anchor()` settings to benchmark.
#'
#' `by = "whole"` and `by = "selector"` ignore `chunk_size`, `staging_mode`,
#' and `publish`, so each gets exactly one row regardless of what those
#' arguments were set to; `by = "variable"` gets one row per combination of
#' the three.
#'
#' @param by_values Which `by` modes to include.
#' @param chunk_size_values Chunk sizes to cross for `by = "variable"` rows.
#' @param staging_mode_values Staging modes to cross for `by = "variable"`
#'   rows.
#' @param publish_values Publish modes to cross for `by = "variable"` rows.
#' @return A data.table with one row per setting combination to benchmark,
#'   columns `setting_id`, `by`, `chunk_size`, `staging_mode`, `publish`.
#' @keywords internal
#' @noRd
anchor_tuning_grid <- function(
  by_values,
  chunk_size_values,
  staging_mode_values,
  publish_values
) {
  grid <- data.table::rbindlist(lapply(by_values, function(current_by) {
    if (current_by == "variable") {
      data.table::CJ(
        by = "variable",
        chunk_size = chunk_size_values,
        staging_mode = staging_mode_values,
        publish = publish_values,
        sorted = FALSE
      )
    } else {
      data.table::data.table(
        by = current_by,
        chunk_size = NA_integer_,
        staging_mode = NA_character_,
        publish = NA_character_
      )
    }
  }))

  grid[, setting_id := .I]
  grid
}

#' Run one `anchor()` call with one setting combination and time it.
#'
#' Always writes to its own throwaway temporary hive, removed again before
#' returning, so this never touches a real `anchor_hive_path` and repeated
#' calls never see each other's output.
#'
#' @inheritParams anchor
#' @param by,chunk_size,staging_mode,publish One row's worth of settings
#'   from `anchor_tuning_grid()`. `chunk_size`/`staging_mode`/`publish` are
#'   only passed on to `anchor()` when `by == "variable"`.
#' @return A list with `elapsed_secs` (numeric), `success` (logical), and
#'   `error_message` (`NA_character_` on success).
#' @keywords internal
#' @noRd
time_anchor_setting <- function(
  population,
  metadata,
  concepts,
  episodes,
  anchor_col,
  by,
  chunk_size,
  staging_mode,
  publish,
  prepare_con
) {
  hive_path <- tempfile(pattern = "anchor-tune-hive-")
  dir.create(hive_path)
  on.exit(unlink(hive_path, recursive = TRUE, force = TRUE), add = TRUE)

  call_args <- list(
    population = population,
    metadata = metadata,
    concepts = concepts,
    episodes = episodes,
    anchor_col = anchor_col,
    anchor_hive_path = hive_path,
    by = by,
    prepare_con = prepare_con
  )
  if (by == "variable") {
    call_args$chunk_size <- chunk_size
    call_args$staging_mode <- staging_mode
    call_args$publish <- publish
  }

  start_time <- Sys.time()
  outcome <- tryCatch(
    {
      do.call(anchor, call_args)
      list(success = TRUE, error_message = NA_character_)
    },
    error = function(e) {
      list(success = FALSE, error_message = conditionMessage(e))
    }
  )

  c(
    outcome,
    list(
      elapsed_secs = as.numeric(
        difftime(Sys.time(), start_time, units = "secs")
      )
    )
  )
}

#' Benchmark `anchor()` settings to find the fastest combination
#'
#' Runs `anchor()` once (or `repeats` times) for every combination of `by`,
#' `chunk_size`, `staging_mode`, and `publish` requested, against the given
#' `population`/`metadata`/`concepts` (and optional `episodes`), and times
#' each run. There's no single combination that's fastest everywhere, it
#' depends on things specific to a client's own environment: how
#' `anchor_hive_path` is mounted (local disk vs. slow/network storage), how
#' many variables and distinct selectors `metadata` has, and how big
#' `concepts` is. Meant to be run once, up front, against a representative
#' sample of a new client's own data and storage, so that expensive
#' production runs can go straight to whatever settings this found fastest
#' instead of guessing.
#'
#' `by = "whole"` and `by = "selector"` don't use `chunk_size`,
#' `staging_mode`, or `publish` (see [anchor()]), so each is benchmarked
#' once per repeat regardless of what those arguments are set to;
#' `by = "variable"` is benchmarked once per repeat per combination of the
#' three.
#'
#' Every run writes to its own throwaway temporary hive, removed again
#' immediately after, so this never touches a real `anchor_hive_path`. A run
#' that errors (for example, a `staging_mode` a client's storage doesn't
#' support) is recorded as a failure rather than stopping the whole
#' benchmark, so one bad combination doesn't prevent finding out about the
#' rest.
#'
#' @inheritParams anchor
#' @param by_values Which `by` modes to benchmark. Defaults to all three.
#' @param chunk_size_values Chunk sizes to try when `by = "variable"`.
#'   Defaults to `c(5L, 10L, 20L, 50L)`.
#' @param staging_mode_values Staging modes to try when `by = "variable"`.
#'   Defaults to both `"memory"` and `"disk"`.
#' @param publish_values Publish modes to try when `by = "variable"`.
#'   Defaults to both `"once"` and `"per_chunk"`.
#' @param repeats How many times to time each setting combination.
#'   Combinations are ranked by the median of their successful runs; more
#'   repeats give a steadier estimate at the cost of a longer benchmark.
#'   Defaults to `1`.
#'
#' @return A list:
#'   \describe{
#'     \item{`runs`}{One row per individual timed run: the setting
#'       combination, `repeat_index`, `elapsed_secs`, `success`, and
#'       `error_message` (`NA` on success).}
#'     \item{`summary`}{One row per setting combination: the setting
#'       combination, `median_elapsed_secs` (over successful runs only),
#'       `n_success`, `n_failed`; ordered fastest first. A combination that
#'       never succeeded sorts last, with `median_elapsed_secs` `NA`.}
#'     \item{`best`}{The single fastest row of `summary` that succeeded at
#'       least once, or `NULL` if every combination failed.}
#'   }
#' @export
tune_anchor_settings <- function(
  population,
  metadata,
  concepts,
  episodes = NULL,
  anchor_col = "T0",
  by_values = c("whole", "variable", "selector"),
  chunk_size_values = c(5L, 10L, 20L, 50L),
  staging_mode_values = c("memory", "disk"),
  publish_values = c("once", "per_chunk"),
  repeats = 1L,
  prepare_con = NULL
) {
  if (!all(by_values %in% c("whole", "variable", "selector"))) {
    stop_log(
      "`by_values` must only contain \"whole\", \"variable\", \"selector\"."
    )
  }
  if (!all(staging_mode_values %in% c("memory", "disk"))) {
    stop_log("`staging_mode_values` must only contain \"memory\", \"disk\".")
  }
  if (!all(publish_values %in% c("once", "per_chunk"))) {
    stop_log("`publish_values` must only contain \"once\", \"per_chunk\".")
  }
  if (!is.numeric(chunk_size_values) || any(chunk_size_values < 1)) {
    stop_log("`chunk_size_values` must be positive numbers.")
  }
  if (!is.numeric(repeats) || length(repeats) != 1L || repeats < 1) {
    stop_log("`repeats` must be a single positive number.")
  }

  # Fail fast on broken inputs instead of repeating the same validation
  # error across every setting combination below.
  validate_anchor_inputs(
    population = population,
    metadata = metadata,
    concepts = concepts,
    episodes = episodes,
    anchor_col = anchor_col
  )

  grid <- anchor_tuning_grid(
    by_values = by_values,
    chunk_size_values = chunk_size_values,
    staging_mode_values = staging_mode_values,
    publish_values = publish_values
  )

  logger::log_info(
    sprintf(
      paste(
        "tune_anchor_settings(): benchmarking %d setting combination(s),",
        "%d repeat(s) each."
      ),
      nrow(grid), repeats
    )
  )

  describe_setting <- function(setting) {
    sprintf(
      "by = `%s`, chunk_size = %s, staging_mode = %s, publish = %s",
      setting$by,
      ifelse(is.na(setting$chunk_size), "NA", setting$chunk_size),
      ifelse(is.na(setting$staging_mode), "NA", setting$staging_mode),
      ifelse(is.na(setting$publish), "NA", setting$publish)
    )
  }

  combination_indices <- seq_len(nrow(grid))
  time_combination <- function(row_index) {
    setting <- grid[row_index]

    data.table::rbindlist(lapply(seq_len(repeats), function(repeat_index) {
      logger::log_info(
        sprintf(
          "tune_anchor_settings(): combination %d/%d, repeat %d/%d (%s).",
          row_index, nrow(grid), repeat_index, repeats,
          describe_setting(setting)
        )
      )

      timing <- time_anchor_setting(
        population = population,
        metadata = metadata,
        concepts = concepts,
        episodes = episodes,
        anchor_col = anchor_col,
        by = setting$by,
        chunk_size = setting$chunk_size,
        staging_mode = setting$staging_mode,
        publish = setting$publish,
        prepare_con = prepare_con
      )

      if (!timing$success) {
        logger::log_error(
          sprintf(
            "tune_anchor_settings(): %s failed: %s",
            describe_setting(setting), timing$error_message
          )
        )
      }

      data.table::data.table(
        setting_id = setting$setting_id,
        by = setting$by,
        chunk_size = setting$chunk_size,
        staging_mode = setting$staging_mode,
        publish = setting$publish,
        repeat_index = repeat_index,
        elapsed_secs = timing$elapsed_secs,
        success = timing$success,
        error_message = timing$error_message
      )
    }))
  }

  runs <- data.table::rbindlist(lapply(combination_indices, time_combination))

  summary <- runs[
    ,
    .(
      median_elapsed_secs = if (any(success)) {
        stats::median(elapsed_secs[success])
      } else {
        NA_real_
      },
      n_success = sum(success),
      n_failed = sum(!success)
    ),
    by = .(setting_id, by, chunk_size, staging_mode, publish)
  ]
  summary <- summary[
    order(is.na(median_elapsed_secs), median_elapsed_secs)
  ]

  best <- if (any(!is.na(summary$median_elapsed_secs))) {
    summary[!is.na(median_elapsed_secs)][1]
  } else {
    NULL
  }

  if (is.null(best)) {
    logger::log_error(
      "tune_anchor_settings(): every setting combination failed."
    )
  } else {
    logger::log_info(
      sprintf(
        "tune_anchor_settings(): fastest was %s (%.2f secs median).",
        describe_setting(best), best$median_elapsed_secs
      )
    )
  }

  list(runs = runs, summary = summary, best = best)
}
