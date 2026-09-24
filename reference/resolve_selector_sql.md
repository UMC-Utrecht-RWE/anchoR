# Resolve a Selector's SQL by Name

Looks up the SQL text for a given `selector` value. Built-in selectors
(e.g. `RANGE_COUNT`) are always resolved from the bundled `inst/sql`
templates. A user-defined selector is found by name
(`<selector>_selector`, lower-cased) in `selector_env`, so anyone can
add one with
[`make_selector()`](https://umc-utrecht-rwe.github.io/anchoR/reference/make_selector.md)
without editing this package, the same pattern
[`resolve_window_constructor()`](https://umc-utrecht-rwe.github.io/anchoR/reference/resolve_window_constructor.md)
uses for window constructors.

## Usage

``` r
resolve_selector_sql(selector_name, selector_env)
```

## Arguments

- selector_name:

  Value of the metadata `selector` column.

- selector_env:

  Environment searched for user-defined selectors.

## Value

SQL text (a single string) for the selector.
