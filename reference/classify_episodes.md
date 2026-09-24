# Classify a person's episodes relative to the anchor

The "current" episode is the one containing `anchor` (assumes a person's
episodes don't overlap). "Prior"/"future" are normally relative to that
one current episode's own bounds: an episode entirely before the current
one's start is "prior", one entirely after the current one's end is
"future". If there is no current episode at all, prior/future fall back
to being directly relative to `anchor` itself (ended before it / starts
after it).

## Usage

``` r
classify_episodes(episodes, anchor)
```

## Arguments

- episodes:

  A data.table with `start_episode`/`end_episode` columns, one row per
  episode for a single person.

- anchor:

  A single Date.

## Value

A new data.table with `start_episode`/`end_episode`/ `episode_class`
columns, `episode_class` one of `"current"`, `"prior"`, `"future"`, or
`NA` (an episode that is none of the three, e.g. one that overlaps the
current episode despite the no-overlap assumption).

## Details

Never mutates `episodes`: the input's list-column element may be shared
(by reference) across several `window_dt` rows for the same person, so
this always returns a freshly built table instead of adding a column to
the one it was given.
