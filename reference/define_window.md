# Define Anchoring Windows

Cross-joins a population with anchoring metadata and computes one window
per population row and study variable.

## Usage

``` r
define_window(
  population,
  metadata,
  episodes = NULL,
  anchor_col = "T0",
  constructor_env = globalenv()
)
```

## Arguments

- population:

  A data frame containing the study population.

- metadata:

  A data frame describing the variables to anchor.

- episodes:

  Optional data frame with `person_id`, `start_episode`, `end_episode`
  columns. Required when `metadata` uses an episode-based constructor
  (`in_current_pregnancy`, `in_prior_pregnancy`, `in_current_and_prior`,
  `outside_all_pregnancy`); nested onto `population` internally, one
  person's episodes per row, via
  [`nest_episodes_onto_population()`](https://umc-utrecht-rwe.github.io/anchoR/reference/nest_episodes_onto_population.md).

- anchor_col:

  Column to use when metadata does not specify `anchor_start_col` or
  `anchor_end_col`.

- constructor_env:

  Environment to search for user-defined window constructors that are
  not built into anchoR. Defaults to the global environment, so a
  constructor made with
  [`make_constructor()`](https://umc-utrecht-rwe.github.io/anchoR/reference/make_constructor.md)
  and assigned at the top level (e.g.
  `my_window <- make_constructor(...)`) is found automatically. Pass a
  different environment (or a small one built just for the purpose) to
  use a constructor defined elsewhere.

## Value

A `data.table` with one row per population row and metadata row.
