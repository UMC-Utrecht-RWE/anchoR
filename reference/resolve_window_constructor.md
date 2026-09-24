# Resolve a Window Constructor by Name

Looks up the function that computes windows for a given `constructor`
value. Built-in constructors (e.g. `generic_window`) are always resolved
from the anchoR package itself. A user-defined constructor is found by
name (`<constructor>_window`, lower-cased) in `constructor_env`, so
anyone can add one with
[`make_constructor()`](https://umc-utrecht-rwe.github.io/anchoR/reference/make_constructor.md)
without editing this package.

## Usage

``` r
resolve_window_constructor(constructor_name, constructor_env)
```

## Arguments

- constructor_name:

  Value of the metadata `constructor` column.

- constructor_env:

  Environment searched for user-defined constructors.

## Value

The constructor function.
