# Compute the window(s) one episode contributes, from its border offsets

Each pair: `before_start_offset`/`after_start_offset` for
`start_episode`, `before_end_offset`/`after_end_offset` for
`end_episode`. `before_start_offset` and `after_end_offset` are the
*outer* sides (they point away from the episode); `after_start_offset`
and `before_end_offset` are the *inner* sides (they point into it).

## Usage

``` r
episode_windows(
  start_episode,
  end_episode,
  before_start_offset,
  after_start_offset,
  before_end_offset,
  after_end_offset
)
```

## Arguments

- start_episode, end_episode:

  The episode's own bounds (single Dates).

- before_start_offset, after_start_offset:

  Single integer offsets (or `NA`) for the `start_episode` border.

- before_end_offset, after_end_offset:

  Single integer offsets (or `NA`) for the `end_episode` border.

## Value

A data.table with one or more rows of `window_start`/`window_end`.

## Details

Each pair's own contribution is decided independently:

- **Both sides set** ("full"): always its own self-contained region,
  `[edge + before_offset, edge + after_offset]`, regardless of what the
  other pair does. `before_offset` must not be later than
  `after_offset`, or the region would be inverted, which is an error.

- **Only its outer side set** (and not full): this pair wants to join a
  *shared window* instead of forming its own region – see below.

- **Only its inner side set** (and not full): its own region, missing
  side defaulting to `0` – *unless* the other pair's outer side is set
  (and that other pair isn't full either), in which case shared-window
  mode is active and this pair's single value is used as a plain point
  in that shared window instead of forming its own region.

- **Nothing set**: contributes nothing of its own; if shared-window mode
  is active, it contributes the unshifted edge as that window's point.

Shared-window mode triggers whenever *either* pair's only set side is
its outer one (and that pair isn't full); when it triggers, every
non-full pair contributes a single point to one shared window (its own
set side if it has exactly one, or the unshifted edge if it has none) –
this is the only way one pair's value and the other pair's value combine
into a single window. A full pair never joins the shared window; it
always keeps its own separate region alongside it.

If neither pair has anything set at all, the result is one shared
window: the episode's own unshifted span,
`[start_episode, end_episode]`.
