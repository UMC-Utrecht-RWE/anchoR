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
