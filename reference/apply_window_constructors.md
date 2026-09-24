# Apply Window Constructors to a Cross-Joined Frame

Runs one constructor per unique `constructor` value in `window_dt` and
combines their outputs. A constructor may return a different number of
rows than it was given, an event-based constructor (see
`R/pregnancy_window.R`) turns one input row into zero, one, or many
candidate windows, so outputs are combined by row-binding rather than
assigned back into fixed row positions.

## Usage

``` r
apply_window_constructors(window_dt, constructor_env)
```

## Arguments

- window_dt:

  A data.table with a `constructor` column, such as one produced by
  `cross_join_population_metadata()`.

- constructor_env:

  Environment used to resolve user-defined constructors. See
  [`resolve_window_constructor()`](https://umc-utrecht-rwe.github.io/anchoR/reference/resolve_window_constructor.md).

## Value

A new data.table combining every constructor's output, each row carrying
`window_start`/`window_end`.
