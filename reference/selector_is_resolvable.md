# Check Whether a Selector Resolves to Something Runnable

Used by `metadata_supported_selectors()` to accept selector names that
aren't bundled with the package but are defined by the caller. Existence
only, deliberately cheap: it doesn't fetch or validate the SQL text.

## Usage

``` r
selector_is_resolvable(selector_name, selector_env)
```

## Arguments

- selector_name:

  Value of the metadata `selector` column.

- selector_env:

  Environment searched for user-defined selectors.

## Value

`TRUE` if a built-in template or a `selector_env` object of class
`anchor_selector` and the expected name exists, `FALSE` otherwise.
