# Make a Selector SQL Template

Wraps a SQL `SELECT` statement as a selector definable outside the
anchoR package, this is the SQL-template equivalent of
[`make_constructor()`](https://umc-utrecht-rwe.github.io/anchoR/reference/make_constructor.md).

## Usage

``` r
make_selector(selector_query)
```

## Arguments

- selector_query:

  A single SQL `SELECT` statement (a length-1 character string).

## Value

An object of class `anchor_selector` wrapping the SQL text.

## Details

Unlike a constructor (a plain R function over a `data.table`), a
selector runs as SQL directly inside the DuckDB connection
[`anchor()`](https://umc-utrecht-rwe.github.io/anchoR/reference/anchor.md)
opens, where `population_windows` and `concepts` are already loaded.
