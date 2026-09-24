# Finalize a Window Frame

Restores the pre-cross-join row order, marks which rows ended up with a
usable window, and assigns a stable per-row id for the downstream SQL
layer.

## Usage

``` r
finalize_windows(window_dt)
```

## Arguments

- window_dt:

  A data.table with `.window_row_id`, `window_start`, and `window_end`
  already populated.

## Value

`window_dt`, reordered, with `.window_row_id` removed and `window_valid`
/ `anchor_row_id` columns added.
