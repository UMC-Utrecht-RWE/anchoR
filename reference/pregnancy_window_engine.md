# Episode-Based Window Engine

Shared engine behind every episode-based constructor. Each `window_dt`
row carries that person's episodes in the `.episodes` list-column (a
data.table with `start_episode`/`end_episode` columns, one row per
episode), added by
[`nest_episodes_onto_population()`](https://umc-utrecht-rwe.github.io/anchoR/reference/nest_episodes_onto_population.md).
One input row can expand into zero, one, or many output rows, one per
candidate window.

## Usage

``` r
pregnancy_window_engine(window_dt, episode_select)
```

## Arguments

- window_dt:

  A data.table produced by `cross_join_population_metadata()`, with
  `.episodes` already nested onto it.

- episode_select:

  One of `"CURRENT"`, `"PRIOR"`, `"CURRENT_AND_PRIOR"`, `"OUTSIDE_ALL"`.

## Value

A data.table with the same columns as `window_dt` plus
`window_start`/`window_end`.

## Details

For `"CURRENT"`/`"PRIOR"`/`"CURRENT_AND_PRIOR"`, episodes are first
classified relative to the anchor (see
[`classify_episodes()`](https://umc-utrecht-rwe.github.io/anchoR/reference/classify_episodes.md)),
then each selected episode independently contributes its own window(s)
via
[`episode_windows()`](https://umc-utrecht-rwe.github.io/anchoR/reference/episode_windows.md),
purely from its own `start_episode`/`end_episode` and the row's four
border offsets. Each of those windows is then optionally capped to the
*selected episode's own bounds*: when `cap_start_to_episode` is `TRUE`,
`window_start` is raised up to at least that episode's `start_episode`;
when `cap_end_to_episode` is `TRUE`, `window_end` is lowered down to at
most that episode's `end_episode`. Both default to `NA`/unset (no change
from the border-offset formula's own result). `"OUTSIDE_ALL"` is
different: it finds the gaps *between all* of a person's episodes inside
`[anchor_start_col + anchor_start_offset, anchor_end_col + anchor_end_offset]`
directly; the border offsets and the two capping flags are not used.
Regardless of `episode_select`, every candidate window is then clipped
to that same
`[anchor_start_col + anchor_start_offset, anchor_end_col + anchor_end_offset]`
boundary via
[`clip_to_anchor_bounds()`](https://umc-utrecht-rwe.github.io/anchoR/reference/clip_to_anchor_bounds.md)
– for `"OUTSIDE_ALL"` this is a no-op (the gaps are already computed
inside that range), for the other three it's what makes
`anchor_start_offset`/ `anchor_end_offset` a hard,
constructor-independent time boundary.
