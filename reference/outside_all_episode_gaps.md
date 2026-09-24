# Compute the "outside all episodes" gap windows

Within `[range_start, range_end]`, returns the parts that do not fall
inside any episode. An episode always fences the gaps around it, even
one that contains the anchor itself.

## Usage

``` r
outside_all_episode_gaps(episodes, range_start, range_end)
```

## Arguments

- episodes:

  A data.table with `start_episode`/`end_episode` columns, one row per
  episode for a single person.

- range_start, range_end:

  The search range bounds (order-independent; the smaller/larger of the
  two is used as the range's lower/upper bound).

## Value

A data.table with `window_start`/`window_end` columns, one row per gap
(possibly zero rows).
