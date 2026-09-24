# Make a window constructor

Create a window-definition function with required-column checks and
optional custom validation.

## Usage

``` r
make_constructor(transform_fn, required_cols = character(), check_fn = NULL)
```

## Arguments

- transform_fn:

  A function applied to `window_dt`.

- required_cols:

  Character vector of required input columns.

- check_fn:

  Optional validation function.

## Value

A `data.table`.
