# Clip candidate windows to the project's hard anchor-relative boundary

`anchor_start_offset`/`anchor_end_offset` define a hard boundary,
`[anchor_start_val + anchor_start_offset, anchor_end_val + anchor_end_offset]`,
that every episode-based window must fall inside, regardless of
constructor. Each side is applied independently and only when not `NA`
(the same convention the border-offset pairs use): a set
`anchor_start_offset` raises `window_start` up to at least the
boundary's lower edge; a set `anchor_end_offset` lowers `window_end`
down to at most the boundary's upper edge. A window entirely outside the
boundary comes out with `window_start > window_end`, left for
[`finalize_windows()`](https://umc-utrecht-rwe.github.io/anchoR/reference/finalize_windows.md)
to mark invalid, the same as any other empty window; this function never
drops rows itself.

## Usage

``` r
clip_to_anchor_bounds(
  windows,
  anchor_start_val,
  anchor_start_offset,
  anchor_end_val,
  anchor_end_offset
)
```

## Arguments

- windows:

  A data.table with `window_start`/`window_end` columns.

- anchor_start_val, anchor_end_val:

  The row's own anchor date(s) (single Dates), from
  `anchor_start_col`/`anchor_end_col`.

- anchor_start_offset, anchor_end_offset:

  Single offsets (or `NA`).

## Value

`windows`, with `window_start`/`window_end` clipped in place.
