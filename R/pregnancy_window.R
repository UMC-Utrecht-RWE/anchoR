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
