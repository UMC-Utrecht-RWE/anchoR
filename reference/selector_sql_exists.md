# Check Whether a Built-in SQL Template Exists for a Selector

Non-throwing counterpart to
[`selector_sql_path()`](https://umc-utrecht-rwe.github.io/anchoR/reference/selector_sql_path.md),
used by
[`resolve_selector_sql()`](https://umc-utrecht-rwe.github.io/anchoR/reference/resolve_selector_sql.md)/[`selector_is_resolvable()`](https://umc-utrecht-rwe.github.io/anchoR/reference/selector_is_resolvable.md)
to check the package templates before falling back to a caller-defined
selector.

## Usage

``` r
selector_sql_exists(selector)
```

## Arguments

- selector:

  Selector name such as `"LATEST"` or `"COUNT"`.

## Value

`TRUE` if a bundled `inst/sql/<selector>.sql` template exists.
