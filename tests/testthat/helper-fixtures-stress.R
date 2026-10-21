# Synthetic data for the episode window engine stress test
# (test_stress-pregnancy-window.R).

# Each person gets 0-4 ~280 day episodes separated by 60-700 day gaps,
# starting somewhere in 2015-2018.
stress_episodes <- function(n_persons) {
  n_episodes <- sample(0:4, n_persons, replace = TRUE,
                       prob = c(0.1, 0.4, 0.3, 0.15, 0.05))
  person_id <- rep(as.character(seq_len(n_persons)), n_episodes)
  episodes <- data.table::data.table(
    person_id = person_id,
    length = sample(200:300, length(person_id), replace = TRUE),
    gap = sample(60:700, length(person_id), replace = TRUE)
  )
  episodes[, offset := cumsum(data.table::shift(length + gap, fill = 0)),
           by = person_id]
  first_start <- as.Date("2015-01-01") +
    sample(0:1460, n_persons, replace = TRUE)
  episodes[, start_episode := first_start[as.integer(person_id)] + offset]
  episodes[, end_episode := start_episode + length]
  episodes[, .(person_id, start_episode, end_episode)]
}

# T0 drawn across the episode period, so rows land in every situation:
# inside an episode, between episodes, before/after all of them.
stress_population <- function(n_persons) {
  data.table::data.table(
    person_id = as.character(seq_len(n_persons)),
    T0 = as.Date("2016-01-01") + sample(0:2555, n_persons, replace = TRUE)
  )
}

stress_metadata_default <- function(n_variables = 5L) {
  data.table::data.table(
    variable_id = paste0("var_", seq_len(n_variables)),
    anchor_start_col = "T0",
    anchor_end_col = "T0",
    anchor_start_offset = -730,
    anchor_end_offset = 365,
    before_start_episode_offset = -7,
    after_start_episode_offset = 7,
    before_end_episode_offset = -7,
    after_end_episode_offset = 7,
    cap_start_to_episode = TRUE,
    cap_end_to_episode = NA
  )
}

# Build window_dt the way define_window() hands it to a constructor:
# population (with nested .episodes) x metadata, one row per pair.
stress_window_dt <- function(n_persons, metadata) {
  population <- stress_population(n_persons)
  episodes <- stress_episodes(n_persons)
  population <- nest_episodes_onto_population(population, episodes)
  # Person-major cross join, as define_window() produces. Repeating row
  # indices is much faster than `merge()` once `.episodes` is a list column.
  cbind(
    population[rep(seq_len(nrow(population)), each = nrow(metadata))],
    metadata[rep(seq_len(nrow(metadata)), times = nrow(population))]
  )
}
