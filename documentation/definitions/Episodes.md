> The optional long input table of repeatable start/end periods (e.g. pregnancies) that episode-based [constructors](Constructor.md) build windows from: one row per episode.

Required columns: `person_id`, `start_episode`, `end_episode` (Date, or character in `YYYY-mm-dd` format). Unlike [Population](Population.md), which is one row per person (or per `person_id x T0`), `episodes` is long: a person with three pregnancies has three rows.

Passed as the `episodes` argument to `define_window()`/`anchor()`/`anchor_by_variable()`/`anchor_by_selector()`, alongside `population` and `metadata`. It's only required when `metadata` uses an episode-based constructor (`in_current_pregnancy`, `in_prior_pregnancy`, `in_current_and_prior`, `outside_all_pregnancy`); calling with none of those constructors and no `episodes` is unaffected. When required, anchoR nests it onto `population` internally, one person's own episodes per row, via `nest_episodes_onto_population()`, before applying any constructor, so the reshaping is not something a caller needs to do by hand:

```r
population[, .episodes := lapply(person_id, function(id) {
  episodes[person_id == id, .(start_episode, end_episode)]
})]
```

See [Episode-Based Window Engine](<Episode-Based Window Engine.md>) for how a person's episodes are used to build windows.
